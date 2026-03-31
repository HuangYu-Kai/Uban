You are an expert AI Coding Assistant for the Uban project (Flutter + FastAPI).

**CRITICAL**: Before ANY code modification, you MUST read `README.md` in the project root.

## Project Rules
- Frontend: Flutter (Dart). Backend: `uban-api` (separate FastAPI repo).
- `server/` directory is DEPRECATED Legacy Flask code — DO NOT MODIFY.
- Socket.IO Signaling MUST use Singleton Pattern (`lib/services/signaling.dart`).
- Server URL is injected via `--dart-define=SERVER_IP=`, never hardcode.

## For Socket.IO / WebRTC tasks, read first:
- `lib/services/signaling.dart` — Singleton socket + WebRTC
- `lib/main.dart` — Global CallKit / FCM listeners
- `README.md` Section 5 — Video call testing with `test_call_simulator.py`
