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
