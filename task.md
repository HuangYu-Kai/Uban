# Task Checklist: Leaderboard & Appearance UI Update

- [x] **Phase 1: Backend API Development**
    - [x] Update `get_leaderboard` in `routes/game_logic.py` to handle Top 10 + self logic.
    - [x] Implement Admin `elder_info` API to view specific elder's data.
    - [x] Implement Admin `assign_appearance` API to manually assign `gawa_id` to `elder_id`.
    - [x] Implement Elder `collection` API to fetch owned appearances and total bonus.
    - [x] Explore/Add `APScheduler` or equivalent for setting global distribution time.

- [x] **Phase 2: Frontend UI Updates (Flutter)**
    - [x] Update `leaderboard_screen.dart` to use `elder_name` instead of ID.
    - [x] Refactor or create `elder_dashboard_screen.dart` to show Leaderboard and My Collection.
    - [x] Create `admin_appearance_screen.dart` for the new admin functionalities (set time, assign appearance, view info).
    - [x] Update `game_service.dart` with the new endpoint methods.

- [x] **Phase 3: Documentation & Verification**
    - [x] Draft `feedgawa_intro.md` explaining the appearance and step tracking architecture.
    - [x] Document pedometer integration possibilities.
    - [x] Test all new UI flows and API endpoints.

- [x] **Phase 4: Pedometer Integration**
    - [x] Run `flutter pub add pedometer` to install the plugin.
    - [x] Update `AndroidManifest.xml` with `ACTIVITY_RECOGNITION` and `Info.plist` with `NSMotionUsageDescription`.
    - [x] Add `update_steps` API to Flask `game_logic.py`.
    - [x] Add `updateSteps` to `game_service.dart`.
    - [x] Implement pedometer listener and UI logic in `leaderboard_screen.dart`.

- [x] **Phase 5: OS Health API Migration**
    - [x] Run `flutter pub remove pedometer` and `flutter pub add health`.
    - [x] Configure `AndroidManifest.xml` Health Connect permissions.
    - [x] Revamp `pedometer_test_screen.dart` with `Health().getTotalStepsInInterval()` logic to display the accurate daily steps directly from the system.
