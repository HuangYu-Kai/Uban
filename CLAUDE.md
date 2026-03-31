# Claude 專案開發最高指導原則 (System Directive)

## ⚠️ CRITICAL RULE ⚠️
You are an expert AI Coding Assistant specialized in Flutter, WebRTC, and Socket.IO.
Before retrieving context, answering user questions, or executing any edits or refactoring within the `Uban` project, you **MUST** first completely read and ingest the `README.md` located in the root directory.

The `README.md` contains:
1. Project architecture overview (Flutter + FastAPI backend).
2. Build & launch instructions (`run.sh` / `run.ps1`).
3. Video call testing workflow using `test_call_simulator.py`.

## Architecture Constraints
- **Frontend**: Flutter (Dart), Signaling uses Singleton Pattern (`lib/services/signaling.dart`).
- **Backend**: `uban-api` (separate FastAPI repo). The `server/` directory is **DEPRECATED Legacy Flask code — DO NOT MODIFY**.
- **Communication**: Socket.IO + Firebase FCM dual-track relay for WebRTC video calls.
- **Server URL**: Injected via `--dart-define=SERVER_IP=`, never hardcode.

## If Your Task Involves Socket.IO or WebRTC:
You are strictly forbidden from writing code without first reviewing:
- `lib/services/signaling.dart` — Singleton socket + WebRTC handlers
- `lib/main.dart` — Global CallKit / FCM listeners and incoming call dialog
- `lib/globals.dart` — Shared state (`pendingAcceptedCall`, `appRole`)

Follow the constraints: Global Call Listener, Singleton connection, FCM token forwarding.

## Key File Index
| File | Purpose |
|------|---------|
| `lib/services/signaling.dart` | Socket.IO + WebRTC signaling |
| `lib/services/api_service.dart` | REST API client |
| `lib/main.dart` | App entry + Global call listeners |
| `lib/globals.dart` | Global state variables |
| `test_call_simulator.py` | Video call signaling test script |
