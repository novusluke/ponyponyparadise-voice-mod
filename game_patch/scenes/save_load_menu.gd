extends CanvasLayer



signal closed
signal game_loaded

const SaveSlotScene = preload("res://scenes/save_slot.tscn")
const ScenarioMissingDialogScene = preload("res://scenes/scenario_missing_dialog.tscn")

const TouchScrollGesture: = preload("res://scripts/ui/touch_scroll_gesture.gd")
const TOTAL_SLOTS = 108
const GRID_COLUMNS = 3
const TALL_GRID_ROWS = 3
const COMPACT_GRID_ROWS = 2
const MIN_HEIGHT_FOR_TALL_GRID = 860.0


const PANEL_MAX_SIZE = Vector2(1400, 1040)
const VIEWPORT_INSET = 32.0
const PAGE_LABELS_INFO_KEY: = "ppp_manual_save_page_labels"
const SLOT_LABELS_INFO_KEY: = "ppp_manual_save_slot_labels"
const MAX_LABEL_LENGTH: = 40
const LIBRARY_INTRO_TIMELINE: = "library_scene"
const LIBRARY_INTRO_POST_AI_LABEL: = "after_twilight_intro_ai"
const LIBRARY_BACKGROUND_PATH: = "locations/core/Ponyville/golden_oak_library/background.png"
const LIBRARY_MUSIC_PATH: = "locations/core/Ponyville/golden_oak_library/bgm.mp3"
enum MenuMode{SAVE, LOAD, AUTOSAVE, AI_REPLIES}

@onready var title_label: Label = %TitleLabel
@onready var slots_grid: GridContainer = %SlotsGrid
@onready var page_buttons_container: HBoxContainer = %PageButtons
@onready var prev_button: Button = %PrevButton
@onready var next_button: Button = %NextButton
@onready var close_button: Button = %CloseButton
@onready var save_tab: Button = %SaveTab
@onready var load_tab: Button = %LoadTab
@onready var autosave_tab: Button = %AutosaveTab
@onready var ai_replies_tab: Button = %AIRepliesTab
@onready var sort_toggle: CheckButton = %SortToggle
@onready var slot_counter: Label = %SlotCounter
@onready var page_title_label: Label = %PageTitleLabel
@onready var rename_page_button: Button = %RenamePageButton
@onready var input_blocker: Control = $InputBlocker
@onready var panel: PanelContainer = $Panel


const TAB_ACTIVE_COLOR: = Color(UIPalette.MENU_ACCENT, 0.35)
const TAB_INACTIVE_COLOR: = Color(0.13, 0.13, 0.16, 1.0)

var current_page: int = 0
var _last_manual_page: int = 0
var _last_autosave_page: int = 0
var _last_ai_replies_page: int = 0
var _current_mode: int = MenuMode.SAVE
var total_pages: int = 1
var slots_per_page: int = GRID_COLUMNS * TALL_GRID_ROWS
var _ordered_slot_names: Array[String] = []
var _sort_load_by_date: bool = false
var _rename_overlay: Control = null
var _operation_in_progress: bool = false
var _refresh_generation: int = 0
var _slots_refreshing: = false


func _ready() -> void :
	TouchScrollGesture.install_scroll( %SlotsScroll, false, true)
	close_button.pressed.connect(_on_close_pressed)
	prev_button.pressed.connect(_on_prev_pressed)
	next_button.pressed.connect(_on_next_pressed)
	save_tab.pressed.connect(_on_save_tab_pressed)
	load_tab.pressed.connect(_on_load_tab_pressed)
	autosave_tab.pressed.connect(_on_autosave_tab_pressed)
	ai_replies_tab.pressed.connect(_on_ai_replies_tab_pressed)
	sort_toggle.toggled.connect(_on_sort_toggle_toggled)
	rename_page_button.pressed.connect(_on_rename_page_pressed)
	get_viewport().size_changed.connect(_on_viewport_size_changed)


	for btn in [prev_button, next_button]:
		_style_pagination_button(btn)


	var close_style: = StyleBoxFlat.new()
	close_style.bg_color = Color(0.2, 0.18, 0.25, 0.6)
	close_style.set_corner_radius_all(6)
	close_button.add_theme_stylebox_override("normal", close_style)
	var close_hover: = close_style.duplicate() as StyleBoxFlat
	close_hover.bg_color = Color(0.5, 0.15, 0.15, 0.8)
	close_button.add_theme_stylebox_override("hover", close_hover)
	close_button.add_theme_stylebox_override("pressed", close_hover)

	_apply_responsive_layout()
	hide()


func open(save_mode: bool = true) -> void :
	if _operation_in_progress:
		return
	Dialogic.Save.clear_slot_display_cache(true)
	_close_rename_dialog()
	_set_mode(MenuMode.SAVE if save_mode else MenuMode.LOAD)
	_apply_responsive_layout()
	current_page = clampi(_get_remembered_page(), 0, total_pages - 1)
	_update_tabs()
	_refresh_slots()

	Dialogic.paused = true
	DialogicUtil.autoload().paused = true
	input_blocker.show()
	show()


func open_save_menu() -> void :
	open(true)


func open_load_menu() -> void :
	open(false)


func _update_tabs() -> void :
	_set_tab_style(ai_replies_tab, _current_mode == MenuMode.AI_REPLIES)
	if _current_mode == MenuMode.SAVE:
		title_label.text = "Save Game"
		_set_tab_style(save_tab, true)
		_set_tab_style(load_tab, false)
		_set_tab_style(autosave_tab, false)
		sort_toggle.hide()
	elif _current_mode == MenuMode.LOAD:
		title_label.text = "Load Game"
		_set_tab_style(save_tab, false)
		_set_tab_style(load_tab, true)
		_set_tab_style(autosave_tab, false)
		sort_toggle.show()
		sort_toggle.set_pressed_no_signal(_sort_load_by_date)
		sort_toggle.text = "Newest First"
	else:
		title_label.text = "AI Replies" if _current_mode == MenuMode.AI_REPLIES else "Checkpoints"
		_set_tab_style(save_tab, false)
		_set_tab_style(load_tab, false)
		_set_tab_style(autosave_tab, _current_mode == MenuMode.AUTOSAVE)
		sort_toggle.hide()


func _set_tab_style(tab: Button, active: bool) -> void :
	var style: = StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	var hover: = style.duplicate() as StyleBoxFlat
	if active:
		style.bg_color = TAB_ACTIVE_COLOR
		hover.bg_color = Color(0.72, 0.36, 0.78, 0.48)
		tab.add_theme_color_override("font_color", Color(0.95, 0.7, 1.0))
		tab.add_theme_color_override("font_hover_color", Color(1.0, 0.8, 1.0))
	else:
		style.bg_color = TAB_INACTIVE_COLOR
		hover.bg_color = Color(0.2, 0.2, 0.26, 1.0)
		tab.add_theme_color_override("font_color", Color(0.55, 0.5, 0.6))
		tab.add_theme_color_override("font_hover_color", Color(0.75, 0.65, 0.8))
	tab.add_theme_stylebox_override("normal", style)
	tab.add_theme_stylebox_override("hover", hover)
	tab.add_theme_stylebox_override("pressed", hover)


func _refresh_slots() -> void :
	_set_slots_refreshing(true)
	%SlotsScroll.scroll_vertical = 0
	_refresh_generation += 1
	var refresh_generation: = _refresh_generation

	await get_tree().process_frame
	if refresh_generation != _refresh_generation or not is_inside_tree():
		return

	_ordered_slot_names = _build_ordered_slot_names()

	_update_pagination()
	_update_slot_counter()
	_update_page_title()

	var start_index: = current_page * slots_per_page
	var end_index: = mini(start_index + slots_per_page, _ordered_slot_names.size())

	var needed: = end_index - start_index
	while slots_grid.get_child_count() > needed:
		var removed: = slots_grid.get_child(slots_grid.get_child_count() - 1)
		slots_grid.remove_child(removed)
		removed.queue_free()
	for i in range(needed):
		var sn: = _ordered_slot_names[start_index + i]
		var slot_ui: Control
		if i < slots_grid.get_child_count():
			slot_ui = slots_grid.get_child(i)
		else:
			slot_ui = SaveSlotScene.instantiate()
			slots_grid.add_child(slot_ui)
			slot_ui.save_requested.connect(_on_save_requested)
			slot_ui.load_requested.connect(_on_load_requested)
			slot_ui.delete_requested.connect(_on_delete_requested)
			slot_ui.rename_requested.connect(_on_rename_slot_requested)
		slot_ui.set_interaction_blocked(true)
		slot_ui.setup(sn, _current_mode == MenuMode.SAVE, _get_slot_label(sn))
		if OS.has_feature("android"):
			await get_tree().process_frame
			if refresh_generation != _refresh_generation or not is_inside_tree() or not visible:
				return
	_set_slots_refreshing(false)


func _set_slots_refreshing(active: bool) -> void :
	_slots_refreshing = active
	for card in slots_grid.get_children():
		card.set_interaction_blocked(active or _operation_in_progress)


func _accepts_slot_action(slot_name: String) -> bool:
	if _slots_refreshing or _operation_in_progress or not visible: return false
	var start: = current_page * slots_per_page
	return slot_name in _ordered_slot_names.slice(start, start + slots_per_page)


func _update_pagination() -> void :
	prev_button.disabled = current_page <= 0
	next_button.disabled = current_page >= total_pages - 1
	_build_page_buttons()


func _build_page_buttons() -> void :
	for child in page_buttons_container.get_children():
		child.queue_free()

	for p in range(total_pages):
		var btn: = Button.new()
		btn.text = _get_page_button_text(p)
		btn.tooltip_text = _get_page_button_tooltip(p)
		btn.custom_minimum_size = Vector2(42, 30)
		btn.add_theme_font_size_override("font_size", 14)

		if p == current_page:
			_style_page_button(btn, true)
		else:
			_style_page_button(btn, false)
			btn.pressed.connect(_go_to_page.bind(p))
		if _operation_in_progress:
			btn.disabled = true

		page_buttons_container.add_child(btn)


func _style_page_button(btn: Button, active: bool) -> void :
	var style: = StyleBoxFlat.new()
	style.set_corner_radius_all(5)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0

	if active:
		style.bg_color = Color(UIPalette.MENU_ACCENT, 0.8)
		style.border_width_bottom = 2
		style.border_color = Color(0.8, 0.5, 0.9, 0.6)
		btn.add_theme_color_override("font_color", Color(1.0, 0.95, 1.0))
		btn.disabled = true
		btn.add_theme_color_override("font_disabled_color", Color(1.0, 0.95, 1.0))
		btn.add_theme_stylebox_override("disabled", style)
	else:
		style.bg_color = Color(0.18, 0.16, 0.24, 0.7)
		btn.add_theme_color_override("font_color", Color(0.75, 0.7, 0.85))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 1.0))
		btn.add_theme_stylebox_override("normal", style)
		var hover: = style.duplicate() as StyleBoxFlat
		hover.bg_color = Color(UIPalette.MENU_ACCENT, 0.5)
		btn.add_theme_stylebox_override("hover", hover)


func _get_page_button_text(page_index: int) -> String:
	if _current_mode in [MenuMode.AUTOSAVE, MenuMode.AI_REPLIES]:
		return str(page_index + 1)
	var title: = _get_page_label(page_index) if _uses_manual_page_labels() else ""
	return "%d*" % (page_index + 1) if not title.is_empty() else str(page_index + 1)


func _get_page_button_tooltip(page_index: int) -> String:
	var base: = "Page %d" % (page_index + 1)
	if _current_mode in [MenuMode.AUTOSAVE, MenuMode.AI_REPLIES]:
		return "%s · %s" % [base, _get_autosave_page_range(page_index)]
	var title: = _get_page_label(page_index) if _uses_manual_page_labels() else ""
	return "%s - %s" % [base, title] if not title.is_empty() else base


func _go_to_page(page: int) -> void :
	if _operation_in_progress:
		return
	if page != current_page and page >= 0 and page < total_pages:
		current_page = page
		_remember_page()
		_refresh_slots()


func _get_autosave_page_range(page_index: int) -> String:
	var count: = AutosaveManager.AI_REPLY_SLOT_COUNT if _current_mode == MenuMode.AI_REPLIES else AutosaveManager.AUTOSAVE_SLOT_COUNT
	var first: = page_index * slots_per_page + 1
	if first > count:
		return "Legacy autosave"
	var label: = "Slots %d–%d" % [first, mini(first + slots_per_page - 1, count)]
	if _current_mode == MenuMode.AUTOSAVE and first + slots_per_page - 1 > count and _get_total_slot_count() > count:
		label += " + legacy autosave"
	return label


func _update_page_title() -> void :
	if _current_mode in [MenuMode.AUTOSAVE, MenuMode.AI_REPLIES]:
		page_title_label.text = "Page %d · %s" % [current_page + 1, _get_autosave_page_range(current_page)]
		rename_page_button.hide()
		return
	if not _uses_manual_page_labels():
		page_title_label.text = "Newest First"
		rename_page_button.hide()
		return
	rename_page_button.show()
	var page_title: = _get_page_label(current_page)
	var base: = "Page %d" % (current_page + 1)
	page_title_label.text = "%s - %s" % [base, page_title] if not page_title.is_empty() else base


func _uses_manual_page_labels() -> bool:
	return _current_mode not in [MenuMode.AUTOSAVE, MenuMode.AI_REPLIES] and not (_current_mode == MenuMode.LOAD and _sort_load_by_date)


func _apply_responsive_layout() -> void :
	var vp: = get_viewport().get_visible_rect().size

	var w: = minf(PANEL_MAX_SIZE.x, vp.x - VIEWPORT_INSET)
	var h: = minf(PANEL_MAX_SIZE.y, vp.y - VIEWPORT_INSET)
	var half: = Vector2(w * 0.5, h * 0.5)
	panel.offset_left = - half.x
	panel.offset_top = - half.y
	panel.offset_right = half.x
	panel.offset_bottom = half.y

	var grid_rows: = TALL_GRID_ROWS if vp.y >= MIN_HEIGHT_FOR_TALL_GRID else COMPACT_GRID_ROWS
	slots_grid.columns = GRID_COLUMNS

	slots_per_page = GRID_COLUMNS * grid_rows
	total_pages = maxi(1, ceili(float(_get_total_slot_count()) / slots_per_page))
	current_page = clampi(current_page, 0, total_pages - 1)


func _style_pagination_button(btn: Button) -> void :
	var normal: = StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.16, 0.24, 0.6)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 6.0
	normal.content_margin_right = 6.0
	normal.content_margin_top = 2.0
	normal.content_margin_bottom = 2.0
	btn.add_theme_stylebox_override("normal", normal)

	var hover: = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(UIPalette.MENU_ACCENT, 0.45)
	btn.add_theme_stylebox_override("hover", hover)

	var disabled: = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.1, 0.1, 0.13, 0.4)
	btn.add_theme_stylebox_override("disabled", disabled)

	btn.add_theme_color_override("font_color", Color(0.75, 0.7, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.33, 0.4))


func _update_slot_counter() -> void :
	if _current_mode == MenuMode.AI_REPLIES:
		var used: = 0
		for slot in AutosaveManager.get_ai_reply_slot_names():
			if Dialogic.Save.has_slot(slot):
				used += 1
		slot_counter.text = "%d / %d AI reply saves used" % [used, AutosaveManager.AI_REPLY_SLOT_COUNT]
		return
	if _current_mode == MenuMode.AUTOSAVE:
		var autosave_used: = 0
		for slot_name in AutosaveManager.get_autosave_slot_names(false):
			if Dialogic.Save.has_slot(slot_name):
				autosave_used += 1
		var legacy_suffix: = ""
		if Dialogic.Save.has_slot(AutosaveManager.AUTOSAVE_SLOT_NAME):
			legacy_suffix = " + legacy"
		slot_counter.text = "%d / %d checkpoints used%s" % [
			autosave_used, 
			AutosaveManager.AUTOSAVE_SLOT_COUNT, 
			legacy_suffix, 
		]
		return

	var used: = _count_manual_slots_used()
	slot_counter.text = "%d / %d slots used" % [used, TOTAL_SLOTS]


func _on_save_tab_pressed() -> void :
	if _operation_in_progress:
		return
	if _current_mode != MenuMode.SAVE:
		_set_mode(MenuMode.SAVE)
		_apply_responsive_layout()
		current_page = clampi(_last_manual_page, 0, total_pages - 1)
		_update_tabs()
		_refresh_slots()


func _on_load_tab_pressed() -> void :
	if _operation_in_progress:
		return
	if _current_mode != MenuMode.LOAD:
		_set_mode(MenuMode.LOAD)
		_apply_responsive_layout()
		current_page = clampi(_last_manual_page, 0, total_pages - 1)
		_update_tabs()
		_refresh_slots()


func _on_autosave_tab_pressed() -> void :
	if _operation_in_progress:
		return
	if _current_mode != MenuMode.AUTOSAVE:
		_set_mode(MenuMode.AUTOSAVE)
		_apply_responsive_layout()
		current_page = clampi(_last_autosave_page, 0, total_pages - 1)
		_update_tabs()
		_refresh_slots()


func _on_ai_replies_tab_pressed() -> void :
	if _operation_in_progress or _current_mode == MenuMode.AI_REPLIES:
		return
	_set_mode(MenuMode.AI_REPLIES)
	_apply_responsive_layout()
	current_page = clampi(_last_ai_replies_page, 0, total_pages - 1)
	_update_tabs()
	_refresh_slots()


func _on_sort_toggle_toggled(button_pressed: bool) -> void :
	if _operation_in_progress:
		return
	_sort_load_by_date = button_pressed
	if _current_mode == MenuMode.LOAD:
		current_page = 0
		_remember_page()
		_update_tabs()
		_refresh_slots()


func _on_prev_pressed() -> void :
	if _operation_in_progress:
		return
	if current_page > 0:
		_go_to_page(current_page - 1)


func _on_next_pressed() -> void :
	if _operation_in_progress:
		return
	if current_page < total_pages - 1:
		_go_to_page(current_page + 1)


func _remember_page() -> void :
	match _current_mode:
		MenuMode.SAVE:
			_last_manual_page = current_page
		MenuMode.LOAD:
			_last_manual_page = current_page
		MenuMode.AUTOSAVE:
			_last_autosave_page = current_page
		MenuMode.AI_REPLIES:
			_last_ai_replies_page = current_page


func _on_viewport_size_changed() -> void :
	_apply_responsive_layout()
	if visible and not _operation_in_progress:
		_refresh_slots()


func _on_save_requested(slot_name: String) -> void :
	if _current_mode != MenuMode.SAVE: return
	if not _accepts_slot_action(slot_name): return
	if _operation_in_progress:
		return
	_set_operation_in_progress(true)
	var error = AutosaveManager.save_manual_slot(slot_name)
	_set_operation_in_progress(false)

	if error == OK:
		Log.d("SaveLoadMenu", "Saved to: " + slot_name)
		UISettingsManager.apply_runtime_settings()
		_refresh_slots()
	else:
		push_error("[SaveLoadMenu] Failed to save: ", error)


func _on_load_requested(slot_name: String) -> void :
	if _current_mode == MenuMode.SAVE: return
	if not _accepts_slot_action(slot_name): return
	if _operation_in_progress or not Dialogic.Save.has_slot(slot_name):
		return
	_set_operation_in_progress(true)
	await _perform_load(slot_name)
	_set_operation_in_progress(false)


func _perform_load(slot_name: String) -> void :
	if not Dialogic.Save.has_slot(slot_name):
		return





	var pre_check_slot_info: Dictionary = Dialogic.Save.get_slot_info(slot_name)
	if pre_check_slot_info.has("game_state"):
		var compat: Dictionary = GameState.check_save_compatibility(pre_check_slot_info["game_state"])
		if not bool(compat.get("ok", false)):
			var reason: String = str(compat.get("reason", "Save incompatible with current content."))
			var blocked_id: String = str(compat.get("scenario_id", ""))
			Log.warn("SaveLoadMenu", "Load refused for '%s': %s" % [slot_name, reason])



			var dialog: CanvasLayer = ScenarioMissingDialogScene.instantiate()
			dialog.configure(blocked_id, reason)
			add_child(dialog)
			return

	Log.d("SaveLoadMenu", "Loading: " + slot_name)


	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.stop_all_channels(0.0)


	var loading_from_map: = MapManager.is_map_open()



	MapManager.prepare_for_load()



	var main_scene: = get_tree().current_scene
	if main_scene and main_scene.has_method("disconnect_intro_chain_hook"):
		main_scene.disconnect_intro_chain_hook()


	AIStateCoordinator.reset()


	if MapManager.is_map_open():
		MapManager.close_map()


	if loading_from_map:
		if Dialogic.current_timeline != null:
			Dialogic.end_timeline()
		await get_tree().process_frame


	var slot_info = Dialogic.Save.get_slot_info(slot_name)




	if slot_info.has("game_state"):
		if not GameState.load_state(slot_info["game_state"]):
			Log.warn("SaveLoadMenu", "GameState.load_state refused '%s' after pre-check; aborting load" % slot_name)
			MapManager.clear_sandbox_night_ai_restore()
			MapManager.finalize_after_load()
			return
	else:
		GameState.reset()


	if slot_info.has("ai_state"):
		AIStateCoordinator.restore_from_save(slot_info["ai_state"])
		if AIStateCoordinator.is_active() and not AIStateCoordinator.has_restorable_state():
			Log.d("SaveLoadMenu", "Discarding stale AI restore state with no resumable payload")
			AIStateCoordinator.end_session()


	var loading_into_ai_scene: = AIStateCoordinator.is_active()
	var recover_empty_sandbox_ai_save: = _should_recover_empty_sandbox_ai_save(slot_info)
	var resume_sleep_choice_checkpoint: = _should_resume_sandbox_sleep_choice_checkpoint(slot_info)
	var restore_sandbox_night_ai: = _should_restore_sandbox_night_ai_after_load(slot_info)
	if restore_sandbox_night_ai:
		MapManager.arm_sandbox_night_ai_restore()


	if loading_from_map and not loading_into_ai_scene and not GameState.was_map_open:
		await _ensure_dialogic_layout()




	var saved_dialogic_state: Dictionary = Dialogic.Save.load_file(slot_name, "state.txt", {})
	var dialogic_state: Dictionary = preload("res://scripts/voice_mod/voice_save_repair.gd").recover(saved_dialogic_state, slot_info)
	var recover_library_intro_handoff: = _should_recover_library_intro_handoff(slot_info, dialogic_state)
	var requires_prepared_dialogic_load: = _prepare_runtime_timeline_for_dialogic_state(dialogic_state) or dialogic_state != saved_dialogic_state
	var _timeline_driven_ai: = loading_into_ai_scene and (
		AIStateCoordinator.get_location_id().is_empty() or AIStateCoordinator.get_location_id() == "_timeline_driven"
	)
	if _timeline_driven_ai:
		MapManager.capture_timeline_restore_resume_state_from_dialogic_state(dialogic_state)
		Log.d("SaveLoadMenu", "Setting skip flag for timeline-driven AI restore")
		Dialogic.set_meta("_skip_call_event_execution", true)
		Dialogic.set_meta("_block_call_event", true)

	var error = _load_dialogic_slot(slot_name, dialogic_state, requires_prepared_dialogic_load)
	UISettingsManager.apply_runtime_settings()

	if error == OK:

		RollbackManager.clear_snapshots()
		await get_tree().process_frame
		if loading_into_ai_scene and AIStateCoordinator.has_pending_rollback_state():
			RollbackManager.restore_active_ai_session_save_state(AIStateCoordinator.get_pending_rollback_state())
			AIStateCoordinator.clear_pending_rollback_state()


		if loading_into_ai_scene:
			await get_tree().process_frame
			MapManager.restore_ai_scene_visuals()
		elif GameState.was_map_open:
			await get_tree().process_frame
			await get_tree().process_frame
			_cleanup_dialogic_for_map_restore()
			MapManager.open_map()
		elif recover_empty_sandbox_ai_save:
			await get_tree().process_frame
			await get_tree().process_frame
			_cleanup_dialogic_for_map_restore()
			MapManager.open_map()
			Log.d("SaveLoadMenu", "Recovered empty sandbox AI save by returning to the map")
		elif resume_sleep_choice_checkpoint:
			await get_tree().process_frame
			await get_tree().process_frame
			await _cleanup_dialogic_for_map_restore()
		elif recover_library_intro_handoff:
			await _recover_library_intro_handoff()
		else:
			if Dialogic.current_timeline != null:
				await get_tree().process_frame
				await get_tree().process_frame
				await _restore_regular_timeline_visuals()

		hide()
		Dialogic.paused = false
		DialogicUtil.autoload().paused = false
		input_blocker.hide()
		MapManager.finalize_after_load()
		game_loaded.emit()
		if resume_sleep_choice_checkpoint:
			MapManager.resume_sandbox_sleep_choice_checkpoint()
		UISettingsManager.apply_runtime_settings()
		Log.d("SaveLoadMenu", "Loaded: " + slot_name)
	else:
		MapManager.clear_sandbox_night_ai_restore()
		MapManager.finalize_after_load()
		push_error("[SaveLoadMenu] Failed to load: ", error)


func _should_recover_empty_sandbox_ai_save(slot_info: Dictionary) -> bool:
	if GameState.current_mode != GameState.Mode.SANDBOX or GameState.was_map_open:
		return false
	if not slot_info.has("ai_state"):
		return false

	var ai_state: Variant = slot_info.get("ai_state", {})
	if ai_state is Dictionary and not (ai_state as Dictionary).is_empty():
		return false

	var game_state: Dictionary = slot_info.get("game_state", {})
	var sleepover_state: Dictionary = game_state.get("sleepover_state", {})
	var qa_location: = str(sleepover_state.get("qa_session_start_location_id", "")).strip_edges()
	return not qa_location.is_empty()


func _should_resume_sandbox_sleep_choice_checkpoint(slot_info: Dictionary) -> bool:
	if GameState.current_mode != GameState.Mode.SANDBOX or GameState.was_map_open:
		return false
	if AIStateCoordinator.is_active():
		return false


	if bool(slot_info.get("night_checkpoint", false)):
		return true
	return str(slot_info.get("autosave_reason", "")).strip_edges() == "sleep_choice"


func _should_restore_sandbox_night_ai_after_load(slot_info: Dictionary) -> bool:
	if GameState.current_mode != GameState.Mode.SANDBOX or GameState.was_map_open:
		return false
	if not bool(slot_info.get("night_checkpoint", false)):
		return false
	if not AIStateCoordinator.is_active():
		return false
	return AIStateCoordinator.get_location_id().strip_edges() == "dream_realm"


func _should_recover_library_intro_handoff(slot_info: Dictionary, dialogic_state: Dictionary) -> bool:
	if not slot_info.has("game_state"):
		return false
	var game_state: Dictionary = slot_info.get("game_state", {})
	if int(game_state.get("mode", GameState.Mode.STORY)) != GameState.Mode.STORY:
		return false
	if bool(game_state.get("was_map_open", false)):
		return false

	var ai_state: Variant = slot_info.get("ai_state", {})
	if ai_state is Dictionary and not (ai_state as Dictionary).is_empty():
		return false

	var saved_timeline: = str(dialogic_state.get("current_timeline", "")).strip_edges()
	if not saved_timeline.is_empty() and saved_timeline != "<null>":
		return false

	var saved_background: = str(dialogic_state.get("background_argument", "")).strip_edges()
	if saved_background != LIBRARY_BACKGROUND_PATH:
		return false

	var saved_speaker: = str(dialogic_state.get("speaker", "")).strip_edges()
	return saved_speaker.is_empty() or saved_speaker == "player"


func _recover_library_intro_handoff() -> void :
	await get_tree().process_frame
	await get_tree().process_frame

	Dialogic.set_meta("_block_call_event", false)
	if Dialogic.has_meta("_skip_call_event_execution"):
		Dialogic.remove_meta("_skip_call_event_execution")

	await _ensure_dialogic_layout()
	if Dialogic.has_subsystem("Backgrounds"):
		Dialogic.Backgrounds.update_background("", LIBRARY_BACKGROUND_PATH, 0.0)
	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.update_audio("music", LIBRARY_MUSIC_PATH, {"loop": true})
	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.update_name_label(null)
		Dialogic.Text.update_dialog_text("", true)

	Dialogic.start(LIBRARY_INTRO_TIMELINE, LIBRARY_INTRO_POST_AI_LABEL)
	Log.d("SaveLoadMenu", "Recovered broken library intro Q&A handoff by resuming post-AI label")


func _load_dialogic_slot(slot_name: String, dialogic_state: Dictionary, use_prepared_state: bool = false) -> Error:
	if use_prepared_state or _repair_missing_runtime_timeline_state(dialogic_state):
		var latest_error: = Dialogic.Save.set_latest_slot(slot_name)
		if latest_error != OK:
			push_error("[SaveLoadMenu] Failed to update latest save slot: ", latest_error)
		Dialogic.load_full_state(dialogic_state)
		return OK if not dialogic_state.is_empty() else FAILED
	return Dialogic.Save.load(slot_name)


func _prepare_runtime_timeline_for_dialogic_state(dialogic_state: Dictionary) -> bool:
	if dialogic_state.is_empty():
		return false
	var repaired: = _repair_missing_runtime_timeline_state(dialogic_state)
	var saved_timeline: = str(dialogic_state.get("current_timeline", "")).strip_edges()
	if not saved_timeline.is_empty():
		_prepare_saved_runtime_timeline_identifier(saved_timeline)
	return repaired


func _prepare_saved_runtime_timeline_identifier(saved_timeline: String) -> bool:
	if GameState.current_mode != GameState.Mode.STORY:
		return false
	if ScenarioManager == null or ScenarioManager.is_base_active():
		return false
	if ScenarioManager.prepare_active_runtime_timeline_identifier(saved_timeline):
		Log.d("SaveLoadMenu", "Prepared runtime timeline '%s' for save restore" % saved_timeline)
		return true
	Log.warn("SaveLoadMenu", "Could not prepare runtime timeline '%s' for save restore" % saved_timeline)
	return false


func _repair_missing_runtime_timeline_state(dialogic_state: Dictionary) -> bool:
	if dialogic_state.is_empty():
		return false
	var saved_timeline: = str(dialogic_state.get("current_timeline", "")).strip_edges()
	if not saved_timeline.is_empty():
		return false
	if GameState.current_mode != GameState.Mode.STORY:
		return false
	if ScenarioManager == null or ScenarioManager.is_base_active():
		return false

	var identifier: = _infer_runtime_timeline_identifier_from_history(dialogic_state)
	if identifier.is_empty():
		return false
	dialogic_state["current_timeline"] = identifier
	Log.warn("SaveLoadMenu", "Repaired missing runtime timeline identifier as '%s'" % identifier)
	return true


func _infer_runtime_timeline_identifier_from_history(dialogic_state: Dictionary) -> String:
	var history_full: Array = dialogic_state.get("history_full", [])
	var history_text: = "\n".join(history_full)
	if history_text.contains("Quick Start"):
		return ScenarioManager.prepare_active_quick_start_timeline()
	if history_text.contains("Normal Start"):
		return ScenarioManager.prepare_active_start_timeline()
	return ""


func _on_delete_requested(slot_name: String) -> void :
	if not _accepts_slot_action(slot_name): return
	if _operation_in_progress:
		return
	if Dialogic.Save.has_slot(slot_name):
		Dialogic.Save.delete_slot(slot_name)
		_set_slot_label(slot_name, "")
		_refresh_slots()


func _on_rename_page_pressed() -> void :
	if _operation_in_progress:
		return
	if not _uses_manual_page_labels():
		return
	var page_index: = current_page
	_show_rename_dialog(
		"Rename Page", 
		_get_page_label(page_index), 
		"Page %d" % (page_index + 1), 
		func(new_label: String) -> void :
			_set_page_label(page_index, new_label)
			_refresh_slots()
	)


func _on_rename_slot_requested(slot_name: String) -> void :
	if not _accepts_slot_action(slot_name): return
	if _operation_in_progress:
		return
	if AutosaveManager.is_autosave_slot(slot_name):
		return
	_show_rename_dialog(
		"Name Save Slot", 
		_get_slot_label(slot_name), 
		slot_name, 
		func(new_label: String) -> void :
			_set_slot_label(slot_name, new_label)
			_refresh_slots()
	)


func _show_rename_dialog(title: String, current_label: String, placeholder: String, confirm_callback: Callable) -> void :
	_close_rename_dialog()

	_rename_overlay = Control.new()
	_rename_overlay.name = "RenameOverlay"
	_rename_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rename_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rename_overlay)

	var dimmer: = ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.45)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_rename_overlay.add_child(dimmer)

	var dialog: = PanelContainer.new()
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.offset_left = -190
	dialog.offset_top = -78
	dialog.offset_right = 190
	dialog.offset_bottom = 78
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	var style: = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.055, 0.085, 0.98)
	style.border_color = Color(UIPalette.MENU_ACCENT, 0.65)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	dialog.add_theme_stylebox_override("panel", style)
	_rename_overlay.add_child(dialog)

	var box: = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)

	var label: = Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.94, 0.86, 1.0))
	box.add_child(label)

	var edit: = LineEdit.new()
	edit.text = current_label.strip_edges()
	edit.placeholder_text = placeholder
	edit.max_length = MAX_LABEL_LENGTH
	edit.select_all()
	box.add_child(edit)

	var buttons: = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)

	var clear_button: = Button.new()
	clear_button.text = "Clear"
	clear_button.custom_minimum_size = Vector2(72, 30)
	buttons.add_child(clear_button)

	var cancel_button: = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(78, 30)
	buttons.add_child(cancel_button)

	var save_button: = Button.new()
	save_button.text = "Save"
	save_button.custom_minimum_size = Vector2(72, 30)
	buttons.add_child(save_button)

	clear_button.pressed.connect( func() -> void :
		confirm_callback.call("")
		_close_rename_dialog()
	)
	cancel_button.pressed.connect(_close_rename_dialog)
	save_button.pressed.connect( func() -> void :
		confirm_callback.call(edit.text)
		_close_rename_dialog()
	)
	edit.text_submitted.connect( func(text: String) -> void :
		confirm_callback.call(text)
		_close_rename_dialog()
	)
	edit.call_deferred("grab_focus")


func _close_rename_dialog() -> void :
	if _rename_overlay != null and is_instance_valid(_rename_overlay):
		_rename_overlay.queue_free()
	_rename_overlay = null


func _get_page_label(page_index: int) -> String:
	var labels: = _get_global_label_dict(PAGE_LABELS_INFO_KEY)
	return str(labels.get(str(page_index), "")).strip_edges()


func _set_page_label(page_index: int, label: String) -> void :
	var labels: = _get_global_label_dict(PAGE_LABELS_INFO_KEY)
	var key: = str(page_index)
	var clean: = _sanitize_label(label)
	if clean.is_empty():
		labels.erase(key)
	else:
		labels[key] = clean
	_store_global_label_dict(PAGE_LABELS_INFO_KEY, labels)


func _get_slot_label(slot_name: String) -> String:
	if AutosaveManager.is_autosave_slot(slot_name):
		return ""
	var labels: = _get_global_label_dict(SLOT_LABELS_INFO_KEY)
	return str(labels.get(slot_name, "")).strip_edges()


func _set_slot_label(slot_name: String, label: String) -> void :
	if AutosaveManager.is_autosave_slot(slot_name):
		return
	var labels: = _get_global_label_dict(SLOT_LABELS_INFO_KEY)
	var clean: = _sanitize_label(label)
	if clean.is_empty():
		labels.erase(slot_name)
	else:
		labels[slot_name] = clean
	_store_global_label_dict(SLOT_LABELS_INFO_KEY, labels)


func _get_global_label_dict(key: String) -> Dictionary:
	var raw = Dialogic.Save.get_global_info(key, {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


func _store_global_label_dict(key: String, labels: Dictionary) -> void :
	var error: = Dialogic.Save.set_global_info(key, labels)
	if error != OK:
		push_warning("[SaveLoadMenu] Failed to store save labels '%s': %s" % [key, error_string(error)])


func _sanitize_label(label: String) -> String:
	var clean: = label.strip_edges().replace("\r", " ").replace("\n", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	if clean.length() > MAX_LABEL_LENGTH:
		clean = clean.substr(0, MAX_LABEL_LENGTH).strip_edges()
	return clean


func _build_ordered_slot_names() -> Array[String]:
	var slot_names: Array[String] = []
	for i in range(1, TOTAL_SLOTS + 1):
		slot_names.append("Slot %02d" % i)

	if _current_mode == MenuMode.SAVE:
		return slot_names

	if _current_mode == MenuMode.AI_REPLIES:
		return AutosaveManager.get_ai_reply_slot_names()
	if _current_mode == MenuMode.AUTOSAVE:
		return AutosaveManager.get_autosave_slot_names(true)

	if not _sort_load_by_date:
		return slot_names

	var populated_slots: Array[Dictionary] = []
	var empty_slots: Array[String] = []

	for slot_name in slot_names:
		if Dialogic.Save.has_slot(slot_name):
			populated_slots.append({
				"slot_name": slot_name, 
				"timestamp": _get_slot_timestamp(slot_name), 
				"slot_number": _extract_slot_number(slot_name), 
			})
		else:
			empty_slots.append(slot_name)

	populated_slots.sort_custom( func(a: Dictionary, b: Dictionary) -> bool:
		var time_a: = int(a.get("timestamp", 0))
		var time_b: = int(b.get("timestamp", 0))
		if time_a == time_b:
			return int(a.get("slot_number", 0)) < int(b.get("slot_number", 0))
		return time_a > time_b
	)

	var ordered: Array[String] = []
	for entry in populated_slots:
		ordered.append(str(entry.get("slot_name", "")))
	ordered.append_array(empty_slots)
	return ordered


func _get_total_slot_count() -> int:
	if _current_mode == MenuMode.AI_REPLIES:
		return AutosaveManager.AI_REPLY_SLOT_COUNT
	if _current_mode == MenuMode.AUTOSAVE:
		return AutosaveManager.get_autosave_slot_names(true).size()
	return TOTAL_SLOTS


func _set_mode(mode: int) -> void :
	_current_mode = mode


func _get_remembered_page() -> int:
	match _current_mode:
		MenuMode.SAVE:
			return _last_manual_page
		MenuMode.LOAD:
			return _last_manual_page
		MenuMode.AUTOSAVE:
			return _last_autosave_page
		MenuMode.AI_REPLIES:
			return _last_ai_replies_page
	return 0


func _count_manual_slots_used() -> int:
	var used: = 0
	for i in range(1, TOTAL_SLOTS + 1):
		if Dialogic.Save.has_slot("Slot %02d" % i):
			used += 1
	return used


func _get_slot_timestamp(slot_name: String) -> int:
	var info: = Dialogic.Save.get_slot_summary(slot_name)
	if info.has("timestamp_usec"):
		return int(info["timestamp_usec"])
	if info.has("timestamp"):
		return int(info.get("timestamp", 0)) * 1000000

	var datetime_str: = str(info.get("datetime", "")).strip_edges()
	if datetime_str.is_empty():
		return 0

	var parts: = datetime_str.split(" ", false)
	if parts.size() < 2:
		return 0

	var date_parts: = parts[0].split("-")
	var time_parts: = parts[-1].split(":")
	if date_parts.size() != 3 or time_parts.size() < 2:
		return 0

	var datetime_dict: = {
		"year": int(date_parts[0]), 
		"month": int(date_parts[1]), 
		"day": int(date_parts[2]), 
		"hour": int(time_parts[0]), 
		"minute": int(time_parts[1]), 
		"second": 0, 
	}
	return int(Time.get_unix_time_from_datetime_dict(datetime_dict)) * 1000000


func _extract_slot_number(slot_name: String) -> int:
	var parts: = slot_name.split(" ", false)
	if parts.is_empty():
		return 0
	return int(parts[-1])


func _set_operation_in_progress(active: bool) -> void :
	_operation_in_progress = active
	if not is_node_ready():
		return
	_set_slots_refreshing(_slots_refreshing)
	close_button.disabled = active
	save_tab.disabled = active
	load_tab.disabled = active
	autosave_tab.disabled = active
	ai_replies_tab.disabled = active
	sort_toggle.disabled = active
	rename_page_button.disabled = active
	prev_button.disabled = active or current_page <= 0
	next_button.disabled = active or current_page >= total_pages - 1
	for child in page_buttons_container.get_children():
		if child is Button:
			(child as Button).disabled = active or (child as Button).text == _get_page_button_text(current_page)


func _on_close_pressed() -> void :
	if _operation_in_progress:
		return
	_close_rename_dialog()
	hide()
	Dialogic.paused = false
	DialogicUtil.autoload().paused = false
	input_blocker.hide()
	closed.emit()


func _ensure_dialogic_layout() -> void :
	if not Dialogic.has_subsystem("Styles"):
		return
	if not Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.load_style()
		await get_tree().process_frame
	else:
		Dialogic.Styles.get_layout_node().show()
	UISettingsManager.apply_runtime_settings()


func _restore_regular_timeline_visuals() -> void :
	await _ensure_dialogic_layout()

	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().show()

	for tn in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if "textbox_root" in tn:
			var tbr = tn.textbox_root
			var p = tbr.get_parent()
			while p:
				if p.name == "AnimationParent" and p is CanvasItem:
					if p.modulate.a < 1.0:
						p.modulate.a = 1.0
					if p.position != Vector2.ZERO:
						p.position = Vector2.ZERO
					if p.rotation != 0.0:
						p.rotation = 0.0
					if p.scale != Vector2.ONE:
						p.scale = Vector2.ONE
					break
				p = p.get_parent()

	if Dialogic.has_subsystem("Backgrounds"):
		var saved_background_scene: String = Dialogic.current_state_info.get("background_scene", "")
		var saved_background_argument: String = Dialogic.current_state_info.get("background_argument", "")
		if not saved_background_scene.is_empty() or not saved_background_argument.is_empty():
			Dialogic.Backgrounds.update_background(
				saved_background_scene, 
				saved_background_argument, 
				0.0, 
				Dialogic.Backgrounds.default_transition, 
				true
			)

	await get_tree().process_frame

	var saved_text: String = Dialogic.current_state_info.get("text", "")
	if Dialogic.has_subsystem("Text") and not saved_text.is_empty():
		Dialogic.Text.show_textbox()
		Dialogic.Text.update_dialog_text(saved_text, true)

	for tn in get_tree().get_nodes_in_group("dialogic_dialog_text"):
		if tn.visible_characters >= 0 and tn.visible_characters < tn.text.length():
			tn.visible_characters = -1


func _cleanup_dialogic_for_map_restore() -> void :
	if Dialogic.current_timeline != null:
		Dialogic.end_timeline()

	if Dialogic.has_subsystem("Text"):
		Dialogic.Text.hide_textbox()
	if Dialogic.has_subsystem("Portraits"):
		await Dialogic.Portraits.leave_all_characters("", 0.0, false)
	if Dialogic.has_subsystem("Backgrounds") and Dialogic.Backgrounds.has_background():
		Dialogic.Backgrounds.update_background("", "", 0.0)
	if Dialogic.has_subsystem("Audio"):
		Dialogic.Audio.stop_all_channels(0.0)
	if Dialogic.has_subsystem("Styles") and Dialogic.Styles.has_active_layout_node():
		Dialogic.Styles.get_layout_node().hide()


func _input(event: InputEvent) -> void :
	if not visible:
		return
	if _operation_in_progress:
		if event.is_action_pressed("ui_cancel")\
		or event.is_action_pressed("ui_left")\
		or event.is_action_pressed("ui_right"):
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_on_prev_pressed()
	elif event.is_action_pressed("ui_right"):
		_on_next_pressed()
