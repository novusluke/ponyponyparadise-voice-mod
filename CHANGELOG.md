# Changes

## 1.0.3

- Fix Apply voices rejecting the current official Windows game download. The installer now selects a verified patch set for either the older supported export or the October 2026 export, instead of comparing every game against one older build.
- Preserve the newer game's history panel, save validation, language options and calendar features, including voice replay when selecting a story line.
- Recognize reviewed source scripts with either Windows or Unix line endings. Verify the engine and active resource remaps, and continue refusing unknown or modified scripts before installation changes any game files.
- Report compatibility mismatches with the detected engine, number of matching scripts and guidance for reporting an unsupported build.

All bundled opening and Quick Start voices remain at 64 steps.
