"""The public Windows installer. Personal state is stored outside the repository."""
from __future__ import annotations

import argparse
import copy
import json
import os
import subprocess
import sys
import traceback
from pathlib import Path

from PySide6.QtCore import Qt, QThread, Signal, QTimer, QUrl
from PySide6.QtGui import QColor, QDesktopServices, QFont, QFontDatabase, QIcon, QLinearGradient, QPainter, QPixmap
from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer
from PySide6.QtWidgets import (QApplication, QCheckBox, QComboBox, QFileDialog, QFrame,
                              QHBoxLayout, QLabel, QLineEdit, QMainWindow, QMessageBox,
                              QPlainTextEdit, QProgressBar, QPushButton, QScrollArea,
                              QSlider, QVBoxLayout, QWidget)

import script as backend
from voice_mod import installer_service as service
from voice_mod.settings import state_directory


STYLE = """
QWidget { color: #f5f0ff; font-family: 'Segoe UI'; font-size: 14px; }
QFrame#panel { background: rgba(23,22,44,245); border: 1px solid rgba(121,113,163,96); border-radius: 22px; }
QFrame#card { background: rgba(255,255,255,9); border: 1px solid rgba(166,156,194,48); border-radius: 12px; }
QLabel { background: transparent; }
QLabel#eyebrow { color: #c7b9fa; font-size: 12px; font-weight: 700; letter-spacing: 2px; }
QLabel#title { font-size: 29px; font-weight: 700; }
QLabel#muted { color: #bcb6d0; }
QLabel#status { color: #d3c9ec; padding: 12px; background: #24223b; border-radius: 10px; }
QLabel#status[error="true"] { color: #ffd3df; background: #482839; }
QLabel#status[success="true"] { color: #bef5e3; background: #203b3a; }
QPushButton { background: #302d4d; border: 1px solid rgba(101,92,136,96); border-radius: 9px;
              padding: 8px 15px; font-weight: 600; }
QPushButton:hover { background: #484064; border: 1px solid #c8b5ff; }
QPushButton:pressed { background: #615181; }
QPushButton:disabled { color: #817991; background: #262339; border-color: #383247; }
QPushButton#primary { background: #bfa0f3; color: #221832; border: none; }
QPushButton#primary:hover { background: #d4bdff; }
QPushButton#primary:disabled { background: #625376; color: #bfb0d0; }
QPushButton#update { background: #237c53; color: #ffffff; border: 1px solid #66daa1; }
QPushButton#update:hover { background: #329967; }
QPushButton#launch { background: #c5b4f2;
                    color: #221b3c; border: 1px solid #eee1ff; border-radius: 13px;
                    padding: 15px 18px; font-size: 17px; font-weight: 700; }
QPushButton#launch:hover { background: #dfd4ff; border: 1px solid #ffffff; }
QPushButton#launch:pressed { background: #b39bdd; }
QSlider::groove:horizontal { height: 5px; border-radius: 2px; background: #4c4069; }
QSlider::sub-page:horizontal { background: #c9adf5; border-radius: 2px; }
QSlider::handle:horizontal { width: 13px; margin: -4px 0; border-radius: 6px; background: #f5eaff; }
QPushButton#choice { text-align: left; padding: 13px; background: #27243e; }
QPushButton#choice:checked { background: #57406e; border: 1px solid #d4b6ff; }
QPushButton#nav { text-align: left; background: rgba(21,17,40,160); border: 1px solid rgba(255,255,255,32);
                  padding: 14px 17px; font-size: 15px; }
QPushButton#nav:checked { background: #cdb0f3; color: #251735; border: none; }
QLineEdit, QComboBox { background: #100f20; border: 1px solid #655c88; border-radius: 8px;
                       padding: 9px; selection-background-color: #79599a; }
QLineEdit:focus, QComboBox:focus { border: 1px solid #d5b7ff; }
QComboBox::drop-down { border: none; width: 25px; }
QComboBox QAbstractItemView { background: #27233d; selection-background-color: #57406e; }
QPlainTextEdit { background: #100f20; color: #c8c2d8; border: 1px solid #4a405f; border-radius: 8px;
                 font-family: 'Consolas'; font-size: 11px; }
QProgressBar { background: #302b45; border: none; border-radius: 3px; height: 5px; }
QProgressBar::chunk { background: #c6a7f2; border-radius: 3px; }
QToolTip { background: #211a30; color: white; border: 1px solid #b69adc; padding: 7px; }
"""


def label(text, name=None, wrap=True):
    item = QLabel(text)
    item.setWordWrap(wrap)
    if name:
        item.setObjectName(name)
    return item


def button(text, callback, name=None):
    item = QPushButton(text.replace("&", "&&"))
    if name:
        item.setObjectName(name)
    item.clicked.connect(callback)
    item.setCursor(Qt.CursorShape.PointingHandCursor)
    return item


class Background(QWidget):
    def __init__(self):
        super().__init__()
        self.art = QPixmap(str(backend.ROOT / "assets/installer-background.png"))

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor("#17162c"))
        if not self.art.isNull():
            scaled = self.art.scaled(self.size(), Qt.AspectRatioMode.KeepAspectRatioByExpanding,
                                     Qt.TransformationMode.SmoothTransformation)
            painter.drawPixmap((self.width() - scaled.width()) // 2,
                               (self.height() - scaled.height()) // 2, scaled)
        gradient = QLinearGradient(0, 0, 0, self.height())
        gradient.setColorAt(0, QColor(14, 10, 30, 190))
        gradient.setColorAt(.50, QColor(14, 10, 30, 50))
        gradient.setColorAt(1, QColor(14, 10, 30, 10))
        painter.fillRect(self.rect(), gradient)


class Job(QThread):
    succeeded = Signal(object)
    failed = Signal(str)
    activity = Signal(str)

    def __init__(self, task, parent):
        super().__init__(parent)
        self.task = task

    def run(self):
        try:
            result = self.task(self.activity.emit)
            self.succeeded.emit(result)
        except Exception as error:
            write_private_log(traceback.format_exc())
            self.failed.emit(str(error) or "The operation failed. See the private installer log.")


def write_private_log(text):
    try:
        path = state_directory() / "logs/installer.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        # Bound the diagnostic file; no diagnostics are written beside the executable.
        if path.exists() and path.stat().st_size > 2_000_000:
            path.write_text("", encoding="utf-8")
        with path.open("a", encoding="utf-8") as stream:
            stream.write(text + "\n")
    except OSError:
        pass


class Installer(QMainWindow):
    def __init__(self, preview=False):
        super().__init__()
        self.preview = preview
        self.metadata = service.release_metadata()
        self.config = copy.deepcopy(backend.DEFAULTS) if preview else service.load_preferences()
        self.config["github_repository"] = self.metadata.get("github_repository", "") or backend.DEFAULTS["github_repository"]
        self.config["language"] = "en"
        self.job = None
        self.environment = None
        self.latest = None
        self.setWindowTitle("PonyPonyParadise · Voice setup")
        self.setWindowIcon(QIcon(str(backend.ROOT / "assets/installer-icon.svg")))
        self.resize(1220, 940)
        self.setMinimumSize(1040, 760)
        self.setStyleSheet(STYLE)
        self.background = Background()
        self.setCentralWidget(self.background)
        layout = QHBoxLayout(self.background)
        layout.setContentsMargins(36, 32, 32, 32)
        layout.setSpacing(34)
        hero = QVBoxLayout()
        hero.setSpacing(14)
        hero.addWidget(label("A LITTLE MAGIC. EVERY VOICE.", "eyebrow"))
        brand = label("PonyPonyParadise", wrap=False)
        brand.setStyleSheet("font-size: 28px; font-weight: 700;")
        hero.addWidget(brand)
        hero.addWidget(label("Voice setup", "title"))
        hero.addWidget(label("Bring Equestria’s conversations to life.", "muted"))
        hero.addSpacing(18)
        hero.addWidget(label("Your game. Your voices.", "eyebrow"))
        hero.addWidget(label("Choose the game and voice engine, then apply when you’re ready.", "muted"))
        hero.addStretch(1)
        music_card, music = self.card("SETUP MUSIC")
        self.music_muted = QCheckBox("Mute background music")
        self.music_muted.setChecked(bool(self.config.get("setup_music", {}).get("muted", False)))
        music.addWidget(self.music_muted)
        self.music_volume = QSlider(Qt.Orientation.Horizontal)
        self.music_volume.setRange(0, 100)
        self.music_volume.setValue(int(self.config.get("setup_music", {}).get("volume", 25)))
        self.music_volume.setAccessibleName("Background music volume")
        self.music_level = label(f"Volume · {self.music_volume.value()}%", "muted")
        music.addWidget(self.music_level)
        music.addWidget(self.music_volume)
        hero.addWidget(music_card)
        self.music_output = QAudioOutput(self)
        self.music_player = QMediaPlayer(self)
        self.music_player.setAudioOutput(self.music_output)
        self.music_player.setLoops(QMediaPlayer.Loops.Infinite)
        self.music_player.setSource(QUrl.fromLocalFile(str(backend.ROOT / "assets/setup-music.mp3")))
        self.music_muted.toggled.connect(self.update_music)
        self.music_volume.valueChanged.connect(self.update_music)
        self.update_music()
        if not preview:
            self.music_player.play()
        hero_widget = QWidget()
        hero_widget.setLayout(hero)
        hero_widget.setFixedWidth(300)
        layout.addWidget(hero_widget)
        panel = QFrame()
        panel.setObjectName("panel")
        content = QVBoxLayout(panel)
        content.setContentsMargins(23, 20, 23, 18)
        content.setSpacing(10)
        self.controls = QWidget()
        form = QVBoxLayout(self.controls)
        form.setContentsMargins(0, 0, 6, 0)
        form.setSpacing(13)
        form.addWidget(label("Make room for a little magic", "title"))
        game_card, game = self.card("GAME INSTALLATION")
        row = QHBoxLayout()
        self.game_folder = QLineEdit("" if preview else str(service.default_game_folder()))
        from voice_mod.settings import application_directory
        if not preview and not (application_directory() / "PonyPonyParadise.pck").is_file() and self.config.get("game_path") and Path(self.config["game_path"]).is_absolute():
            self.game_folder.setText(self.config["game_path"])
        self.game_folder.setPlaceholderText("PonyPonyParadise game folder…")
        self.game_folder.textChanged.connect(self.refresh_game_update)
        row.addWidget(self.game_folder, 1)
        self.browse_game = button("Browse…", self.browse_game_folder)
        row.addWidget(self.browse_game)
        self.detect_game_button = button("Detect", self.detect_game)
        row.addWidget(self.detect_game_button)
        game.addLayout(row)
        self.game_version = label("Select a game folder to install or update the mod.", "muted")
        row = QHBoxLayout()
        row.addWidget(self.game_version, 1)
        self.uninstall_button = button("Uninstall voice mod", self.uninstall_mod)
        self.uninstall_button.setEnabled(False)
        row.addWidget(self.uninstall_button)
        game.addLayout(row)
        form.addWidget(game_card)
        engine_card, engine = self.card("VOICE ENGINE")
        engine.addWidget(label("Local OmniVoice · your GPU", "muted"))
        self.local_card = QWidget()
        local = QVBoxLayout(self.local_card)
        local.setContentsMargins(0, 0, 0, 0)
        local.setSpacing(8)
        local.addWidget(label("OmniVoice folder · accepts the project, .venv or venv", "muted"))
        row = QHBoxLayout()
        self.omni_folder = QLineEdit("" if preview else self.config["omnivoice"].get("install_path", ""))
        self.omni_folder.setPlaceholderText("Use an existing installation or download OmniVoice below…")
        self.omni_folder.textEdited.connect(self.invalidate_environment)
        row.addWidget(self.omni_folder, 1)
        self.browse_omni = button("Use existing…", self.browse_environment)
        row.addWidget(self.browse_omni)
        local.addLayout(row)
        row = QHBoxLayout()
        self.detect_button = button("Detect OmniVoice", self.detect)
        self.install_button = button("Download & install OmniVoice…", self.install_new)
        self.repair_button = button("Repair environment", self.repair_environment)
        self.repair_button.hide()
        row.addWidget(self.detect_button)
        row.addWidget(self.install_button)
        row.addWidget(self.repair_button)
        local.addLayout(row)
        local.addWidget(label("Choose an install location. Setup creates an OmniVoice folder and downloads Python and the voice engine automatically.", "muted"))
        engine.addWidget(self.local_card)
        row = QHBoxLayout()
        row.addWidget(label("Voice language", "muted"))
        self.language = QComboBox()
        self.language.addItem("English", "en")
        row.addWidget(self.language)
        row.addStretch()
        engine.addLayout(row)
        count = len(list((backend.ROOT / "reference_audios/en").glob("*.mp3")))
        engine.addWidget(label(f"{count} English voices included", "muted"))
        row = QHBoxLayout()
        self.apply_button = button("Apply voices", self.apply_from_engine, "primary")
        row.addWidget(self.apply_button, 1)
        engine.addLayout(row)
        self.launch_button = button("Launch PonyPonyParadise", self.launch_game, "launch")
        self.launch_button.setMinimumHeight(58)
        engine.addWidget(self.launch_button)
        form.addWidget(engine_card)
        release_card, release = self.card("RELEASE UPDATES")
        row = QHBoxLayout()
        self.check_button = button("Check for updates", self.check_updates)
        self.release_button = button("Release page", self.open_releases)
        self.update_button = button("Update available", self.update_game, "update")
        self.update_button.hide()
        row.addWidget(self.check_button)
        row.addWidget(self.release_button)
        row.addWidget(self.update_button)
        release.addLayout(row)
        form.addWidget(release_card)
        form.addStretch(1)
        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.scroll.setFrameShape(QFrame.Shape.NoFrame)
        self.scroll.setStyleSheet("QScrollArea, QScrollArea > QWidget > QWidget { background: transparent; }")
        self.scroll.setWidget(self.controls)
        content.addWidget(self.scroll, 1)
        self.status = label("Select your game and engine, then click Apply voices.", "status")
        self.status.setMinimumHeight(50)
        content.addWidget(self.status)
        self.progress = QProgressBar()
        self.progress.setTextVisible(False)
        self.progress.setRange(0, 1)
        self.progress.hide()
        content.addWidget(self.progress)
        footer = QHBoxLayout()
        self.details = button("Show activity", self.toggle_details)
        self.details.setFlat(True)
        footer.addWidget(self.details)
        footer.addStretch()
        footer.addWidget(label("v" + self.metadata["version"], "muted", False))
        content.addLayout(footer)
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(500)
        self.log.setFixedHeight(100)
        self.log.hide()
        content.addWidget(self.log)
        layout.addWidget(panel, 1)
        self.config["execution_mode"] = "local"
        self.refresh_game_update()

    def card(self, title):
        card = QFrame()
        card.setObjectName("card")
        layout = QVBoxLayout(card)
        layout.setContentsMargins(13, 11, 13, 11)
        layout.setSpacing(8)
        layout.addWidget(label(title, "eyebrow"))
        return card, layout

    def detect_game(self):
        candidates = [Path(self.game_folder.text()), service.default_game_folder()]
        if self.config.get("game_path"):
            candidates.append(Path(self.config["game_path"]))
        for folder in candidates:
            if (folder / "PonyPonyParadise.pck").is_file():
                self.game_folder.setText(str(folder.resolve()))
                self.refresh_game_update()
                self.set_status("PonyPonyParadise detected. Click Apply voices when ready.", success=True)
                return
        self.set_status("Game not found nearby. Use Browse to select its folder.", error=True)

    def refresh_game_update(self):
        if not hasattr(self, "update_button"):
            return
        self.bundled_update = False
        value = self.game_folder.text().strip()
        if value and (Path(value) / "PonyPonyParadise.pck").is_file():
            state = Path(value) / "data/voice_mod/install_state.json"
            try:
                installed = json.loads(state.read_text(encoding="utf-8")) if state.is_file() else {}
                self.uninstall_button.setEnabled(bool(installed) and ((Path(value) / "PonyPonyParadise.pck.voice-mod-original").is_file() or installed.get("status") in ("cleanup_pending", "uninstalled")))
                if installed.get("status") in ("cleanup_pending", "uninstalled"):
                    self.game_version.setText("Original game restored · Uninstall can retry unfinished cleanup")
                elif installed:
                    version = installed.get("mod_version", "earlier release")
                    fingerprint = service.patch_fingerprint()
                    self.bundled_update = installed.get("patch_fingerprint") != fingerprint
                    if installed.get("mod_version"):
                        shipped, previous = service.version_tuple(self.metadata["version"]), service.version_tuple(installed["mod_version"])
                        self.bundled_update = shipped > previous or (shipped == previous and self.bundled_update)
                    self.game_version.setText(f"Game detected · voice mod {version}" + (" · update ready to apply" if self.bundled_update else ""))
                else:
                    self.game_version.setText("Game detected · ready to install voices")
            except (OSError, ValueError):
                self.uninstall_button.setEnabled(False)
                self.game_version.setText("Game detected · installation metadata needs checking")
        else:
            self.uninstall_button.setEnabled(False)
            self.game_version.setText("Select a game folder to install or update the mod.")
        remote = self.latest is not None and self.latest.get("kind") == "available"
        self.update_button.setVisible(self.bundled_update or remote)
        self.update_button.setToolTip("Download the newer release" if remote else "Apply this setup’s update to the selected game")

    def update_game(self):
        if self.latest and self.latest.get("kind") == "available":
            QDesktopServices.openUrl(QUrl(self.latest.get("download") or self.latest["url"]))
            self.set_status("Download the newer setup, then choose Apply voices to update your game.")
        elif self.bundled_update:
            self.apply_from_engine()

    def set_status(self, message, error=False, success=False):
        self.status.setText(message)
        self.status.setProperty("error", error)
        self.status.setProperty("success", success)
        self.status.style().unpolish(self.status)
        self.status.style().polish(self.status)

    def update_music(self):
        self.music_output.setMuted(self.music_muted.isChecked())
        self.music_output.setVolume(self.music_volume.value() / 100.0)
        self.music_level.setText(f"Volume · {self.music_volume.value()}%")
        self.config["setup_music"] = {"muted": self.music_muted.isChecked(), "volume": self.music_volume.value()}
        self.persist()

    def invalidate_environment(self):
        self.environment = None
        self.config["omnivoice"]["python_path"] = ""
        self.repair_button.hide()

    def browse_environment(self):
        folder = QFileDialog.getExistingDirectory(self, "Select an existing OmniVoice installation", self.omni_folder.text())
        if folder:
            self.omni_folder.setText(folder)
            self.invalidate_environment()
            self.detect(selected_only=True)

    def browse_game_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Select PonyPonyParadise game folder", self.game_folder.text())
        if folder:
            self.game_folder.setText(folder)

    def start_job(self, task, message, success):
        if self.job is not None and self.job.isRunning():
            return
        self.set_status(message)
        self.progress.setRange(0, 0)
        self.progress.show()
        for widget in (self.controls,):
            widget.setEnabled(False)
        job = Job(task, self)
        self.job = job
        job.activity.connect(self.add_activity)
        job.succeeded.connect(success)
        job.failed.connect(lambda message: self.set_status(message, error=True))
        job.finished.connect(self.finish_job)
        job.start()

    def finish_job(self):
        self.progress.setRange(0, 1)
        self.progress.setValue(1)
        self.progress.hide()
        for widget in (self.controls,):
            widget.setEnabled(True)

    def add_activity(self, message):
        self.log.appendPlainText(message)
        if not self.preview:
            write_private_log(message)

    def toggle_details(self):
        self.log.setVisible(not self.log.isVisible())
        self.details.setText("Hide activity" if self.log.isVisible() else "Show activity")

    def detected(self, result):
        self.environment = result if result["ok"] else None
        self.repair_button.setVisible(bool(result.get("repairable")))
        self.set_status(result["message"], error=not result["ok"], success=result["ok"])
        if result["ok"]:
            self.config["omnivoice"]["python_path"] = result["python_path"]
            selected = self.omni_folder.text().strip()
            self.config["omnivoice"]["install_path"] = selected if selected and Path(selected).exists() else str(Path(result["python_path"]).parent.parent)
            self.omni_folder.setText(self.config["omnivoice"]["install_path"])
            self.persist()

    def detect(self, selected_only=False):
        selected = self.omni_folder.text().strip()
        if selected_only or (selected and Path(selected).exists()):
            task = lambda log: service.inspect_environment(Path(selected))
        else:
            # A missing default folder must not stop automatic detection. An
            # explicitly browsed existing folder reports its own probe result.
            task = lambda log: service.detect_environment(self.config, Path(selected) if selected else None)
        self.start_job(task, "Checking OmniVoice…", self.detected)

    def install_new(self):
        parent = QFileDialog.getExistingDirectory(self, "Choose where to download and install OmniVoice", str(Path.home()))
        if parent:
            try:
                folder = service.new_installation_folder(Path(parent))
            except (OSError, ValueError) as error:
                self.set_status(str(error), error=True)
                return
            self.omni_folder.setText(str(folder))
            self.invalidate_environment()
            self.log.show()
            self.details.setText("Hide activity")
            self.start_job(lambda log: service.install_local(folder, copy.deepcopy(self.config["omnivoice"]), log),
                           "Installing OmniVoice. Keep this window open…", self.detected)

    def repair_environment(self):
        selected = self.omni_folder.text().strip()
        if selected:
            self.start_job(lambda log: service.repair_environment(Path(selected), log),
                           "Restoring the environment’s compatible Python…", self.detected)

    def persist(self):
        if not self.preview:
            service.save_preferences(self.config)

    def apply_from_engine(self):
        if not (Path(self.game_folder.text()) / "PonyPonyParadise.pck").is_file():
            folder = QFileDialog.getExistingDirectory(self, "Select PonyPonyParadise game folder", self.game_folder.text())
            if not folder:
                return
            self.game_folder.setText(folder)
        self.apply()

    def selected_game(self):
        value = self.game_folder.text().strip()
        if not value or not (Path(value) / "PonyPonyParadise.pck").is_file():
            raise ValueError("Select the game folder containing PonyPonyParadise.pck.")
        game = Path(value).resolve()
        service.require_private_destination(game)
        return game

    def apply(self):
        try:
            game = self.selected_game()
            self.config["language"] = self.language.currentData()
            self.config["github_repository"] = self.configured_repository()
            config = copy.deepcopy(self.config)
            selected = self.omni_folder.text().strip()
            def operation(log):
                if config["execution_mode"] == "local":
                    result = service.inspect_environment(Path(selected)) if selected else service.detect_environment(config)
                    if not result["ok"]:
                        raise ValueError(result["message"])
                    config["omnivoice"]["install_path"] = selected
                    config["omnivoice"]["python_path"] = result["python_path"]
                return service.apply_voices(game, config, log, save_config=not self.preview)
            self.start_job(operation, "Applying voices…", self.applied)
        except Exception as error:
            self.set_status(str(error), error=True)

    def applied(self, result):
        self.config["game_path"] = self.game_folder.text()
        self.refresh_game_update()
        self.set_status(result["message"], success=True)

    def launch_game(self):
        try:
            game = self.selected_game()
            exe = game / "PonyPonyParadise.exe"
            if not exe.is_file():
                raise ValueError("PonyPonyParadise.exe was not found in the selected game folder.")
            subprocess.Popen([str(exe)], cwd=game, env=service.clean_subprocess_environment(),
                             creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            self.close()
        except Exception as error:
            self.set_status(str(error), error=True)

    def uninstall_mod(self):
        try:
            game = self.selected_game()
            answer = QMessageBox.question(self, "Uninstall voice mod",
                f"Uninstall the voice mod from:\n{game}\n\n"
                "The original game will be restored and the mod's audio and cache removed. "
                "Your saves and OmniVoice installation will be kept.",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No)
            if answer != QMessageBox.StandardButton.Yes:
                return
            self.start_job(lambda log: service.uninstall_voices(game, log), "Uninstalling the voice mod…", self.uninstalled)
        except Exception as error:
            self.set_status(str(error), error=True)

    def uninstalled(self, result):
        self.refresh_game_update()
        message = "Voice mod uninstalled. Original game restored; saves and OmniVoice kept."
        if result.get("retained"):
            message += " Edited resources were preserved."
        if result.get("recovery_directory"):
            message += " Additional files saved to " + result["recovery_directory"]
        self.set_status(message, success=True)

    def configured_repository(self):
        return backend.repository_name(self.metadata.get("github_repository", "") or backend.DEFAULTS["github_repository"])

    def check_updates(self):
        try:
            repo = self.configured_repository()
            self.start_job(lambda log: service.check_updates(repo, self.metadata["version"]), "Checking GitHub releases…", self.checked_update)
        except Exception as error:
            self.set_status(str(error), error=True)

    def checked_update(self, result):
        self.latest = result
        self.refresh_game_update()
        self.set_status(result["message"], success=result["kind"] == "current")

    def open_releases(self):
        try:
            QDesktopServices.openUrl(QUrl(f"https://github.com/{self.configured_repository()}/releases"))
        except Exception as error:
            self.set_status(str(error), error=True)

    def closeEvent(self, event):
        if self.job is not None and self.job.isRunning():
            self.set_status("An operation is running. Please wait for it to finish before closing.")
            event.ignore()
        else:
            self.music_player.stop()
            event.accept()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", action="store_true", help="Preview with generic empty fields and no preferences saved.")
    parser.add_argument("--screenshot", type=Path, help="Save a generic GUI preview for verification.")
    parser.add_argument("--probe", type=Path, help="Check a selected environment in the GUI.")
    parser.add_argument("--report", type=Path, help="Write a private smoke-test report and exit.")
    args = parser.parse_args(argv)
    app = QApplication([sys.argv[0]])
    if sys.platform == "win32":
        # Explicitly register the OS fonts so native and headless rendering use
        # the same readable typeface. No Windows fonts are redistributed.
        for font in ("segoeui.ttf", "segoeuib.ttf", "seguisym.ttf"):
            path = Path(os.environ.get("WINDIR", "")) / "Fonts" / font
            if path.is_file():
                QFontDatabase.addApplicationFont(str(path))
    # PyInstaller injects a DLL search directory which can break an external venv.
    if getattr(sys, "frozen", False) and sys.platform == "win32":
        import ctypes
        ctypes.windll.kernel32.SetDllDirectoryW(None)
    app.setApplicationName("PonyPonyParadise Voice Setup")
    app.setFont(QFont("Segoe UI", 10))
    try:
        window = Installer(preview=args.preview or bool(args.screenshot) or bool(args.report))
    except Exception as error:
        write_private_log(traceback.format_exc())
        QMessageBox.critical(None, "Voice setup", f"Unable to load private preferences: {error}\nThe public mod files have not been changed.")
        return 1
    def uncaught(kind, error, tb):
        write_private_log("".join(traceback.format_exception(kind, error, tb)))
        window.set_status(str(error), error=True)
    sys.excepthook = uncaught
    window.show()
    if args.probe:
        window.omni_folder.setText(str(args.probe))
        QTimer.singleShot(100, lambda: window.detect(selected_only=True))
    if args.screenshot or args.report:
        timer = QTimer(window)
        def finish_preview():
            if window.job is not None and window.job.isRunning():
                return
            timer.stop()
            if args.screenshot:
                args.screenshot.parent.mkdir(parents=True, exist_ok=True)
                window.grab().save(str(args.screenshot))
            if args.report:
                args.report.parent.mkdir(parents=True, exist_ok=True)
                args.report.write_text(json.dumps({"visible": window.isVisible(), "single_view": True, "apply_buttons": 1,
                                                  "status": window.status.text(), "environment_ok": bool(window.environment),
                                                  "version": window.metadata["version"],
                                                  "bundled_references": len(list((backend.ROOT / "reference_audios").rglob("*.mp3"))),
                                                  "bundled_opening": len(list((backend.ROOT / "data/voices").rglob("*.mp3"))),
                                                  "game_detected": (Path(window.game_folder.text()) / "PonyPonyParadise.pck").is_file(),
                                                  "idle_progress_visible": window.progress.isVisible()}, indent=2), encoding="utf-8")
            app.quit()
        timer.timeout.connect(finish_preview)
        timer.start(1200)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
