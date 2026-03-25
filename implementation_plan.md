# Appearance and Leaderboard UI Update Plan

This plan details the implementation of the new Admin and Elder specific interfaces, along with step-tracking integration concepts.

## User Review Required
> [!IMPORTANT]
> **Auto-Distribution Time**: To implement automatic distribution when the time is up, we will need a background scheduler (like `APScheduler`) running on the Flask server. Please confirm this addition.
> **Pedometer (Step Tracking)**: To track real steps from walking, we will need to integrate the Flutter `pedometer` or `health` package, which requires native OS permissions (Android `ACTIVITY_RECOGNITION`, iOS `NSMotionUsageDescription`). I will include the conceptual code for this, but actual native setup might need device-level testing.

## Proposed Changes

### [Database & Models]
- **`gawa_appearance` table**: Ensure the `bonus` column exists (DOUBLE, DEFAULT 0).
- **Global Settings table (or file)**: Add a simple table or JSON file to store the scheduled "Next Distribution Time".

### [Backend APIs (Flask)]
#### [MODIFY] [routes/game_logic.py](file:///E:/114Project/UniFlow/server/routes/game_logic.py)
- **Leaderboard API**: Update `/leaderboard/<elder_id>` to return the Top 10 friends, PLUS the requested `elder_id`'s rank directly beneath them (if not already in the Top 10).
- **Admin APIs**:
  - `POST /api/game/admin/set_distribution_time`: Set the global time for the next automatic random distribution.
  - `POST /api/game/admin/assign_appearance`: Manually assign a specific `gawa_id` to a specific `elder_id`.
  - `GET /api/game/admin/elder_info/<elder_id>`: Fetch a specific elder's step count, owned appearances, and total bonus percentage.
- **Elder APIs**:
  - `GET /api/game/elder/collection/<elder_id>`: Fetch the current elder's owned appearances and calculated total bonus.
- **Background Task**: Introduce a background scheduler (e.g., `BackgroundScheduler` from `apscheduler`) in `app.py` or a dedicated module to check the scheduled time and trigger the global distribution automatically.

### [Frontend UI (Flutter)]
#### [MODIFY] [lib/screens/leaderboard_screen.dart](file:///E:/114Project/UniFlow/mobile_app/lib/screens/leaderboard_screen.dart)
- Note: This screen will likely be refactored into or replaced by the Elder Dashboard. If kept independent, update the name display from `長輩 ${entry['elder_id']}` to use `entry['elder_name']`.

#### [NEW] [lib/screens/admin_appearance_screen.dart](file:///E:/114Project/UniFlow/mobile_app/lib/screens/admin_appearance_screen.dart)
- Build a new interface exclusively for admins:
  1. Date/Time picker to set the global auto-distribution schedule.
  2. Form to directly assign a `gawa_id` to an `elder_id`.
  3. Search field to view any elder's step count, appearance collection, and bonus details.

#### [NEW] [lib/screens/elder_dashboard_screen.dart](file:///E:/114Project/UniFlow/mobile_app/lib/screens/elder_dashboard_screen.dart)
- A consolidated user dashboard that:
  1. Displays the Leaderboard (Top 10 + current user).
  2. Displays a section for "My Collection" (Owned appearances + bonus %).

#### [MODIFY] [lib/services/game_service.dart](file:///E:/114Project/UniFlow/mobile_app/lib/services/game_service.dart)
- Add new HTTP methods to interface with the new Admin and Elder endpoints.

### [Documentation]
#### [NEW] [feedgawa_intro.md](file:///C:/Users/OuO/.gemini/antigravity/brain/b2cd0dd5-7daa-47a1-8c5a-7982a2042f60/feedgawa_intro.md)
- Detail all frontend and backend components related to the Appearance Distribution feature, fulfilling the user's request for mapping the related files.

## Verification Plan

### Automated Tests
- Test the new Admin endpoints using direct Python web requests.
- Verify the auto-distribution triggers correctly when the scheduled time is reached.

### Manual Verification
- Render the new UI components in Flutter to ensure they accurately display the Top 10 leaderboard logic and collection details.

## Phase 4: Pedometer (Step Tracking) Integration

### [Native Configurations]
- **Android**: Add `ACTIVITY_RECOGNITION` permission to `AndroidManifest.xml`.
- **iOS**: Add `NSMotionUsageDescription` to `Info.plist`.
- **Dependencies**: Add `pedometer` to `pubspec.yaml` (since `permission_handler` and `shared_preferences` are already present).

### [Backend API]
- **`POST /api/game/elder/update_steps`**: Add a new endpoint in `game_logic.py` that accepts `elder_id` and `delta_steps`. It will increment the `step_total` in the Database by `delta_steps` to accurately handle continuous counting.

### [Frontend Integration]
- **`game_service.dart`**: Implement `updateSteps(String elderId, int deltaSteps)`.
- **`leaderboard_screen.dart`**: 
  1. Request `Permission.activityRecognition` on screen load.
  2. Implement `Pedometer.stepCountStream`.
  3. Keep a cache of the last recorded hardware step count using `SharedPreferences`.
  4. Calculate the delta (`current - cached`) and buffer it.
  5. Sync the buffered steps to the backend in batches (e.g., every 10 steps or periodically) to avoid API spam. Update the local UI optimistically.

## Phase 5: OS Health API (Apple Health / Google Fit) Integration

### [Native Configurations]
- **Dependencies**: Replace `pedometer` usage with the `health` package (`flutter pub add health`).
- **Android**:
  - Add `Health Connect` specific permissions (`android.permission.health.READ_STEPS`).
  - Add `AndroidManifest.xml` intent filters to explicitly support Health Connect bindings.
- **iOS**:
  - Add `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` to `Info.plist`.

### [Frontend Testing Screen]
- **`pedometer_test_screen.dart`**: 
  1. Revamp this sandbox to utilize `health` package APIs.
  2. Implement an authorization flow (`Health().requestAuthorization([HealthDataType.STEPS])`).
  3. Formulate a daily step query (`Health().getTotalStepsInInterval(midnight, now)`).
  4. Build a UI to display authoritative daily steps fetched directly from the OS database.
