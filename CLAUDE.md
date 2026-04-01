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
- **Backend**: `uban-api` (separate FastAPI repo). The `server/` directory is **Legacy Flask code for AI features only**.
- **AI Engine**: Ollama (`qwen2.5:1.5b`) via Tailscale Funnel. Fallback: Gemini API.
- **Communication**: Socket.IO + Firebase FCM dual-track relay for WebRTC video calls.
- **Server URL**: Injected via `--dart-define=SERVER_IP=`, never hardcode.

## Key File Index

### Core Application
| File | Purpose |
|------|---------|
| `lib/services/signaling.dart` | Socket.IO + WebRTC signaling |
| `lib/services/api_service.dart` | REST API client |
| `lib/main.dart` | App entry + Global call listeners |
| `lib/globals.dart` | Global state variables |
| `test_call_simulator.py` | Video call signaling test script |

### AI & Agent System (`server/`)
| File | Purpose |
|------|---------|
| `server/services/ollama_service.py` | Ollama integration + Tool Calling |
| `server/services/heartbeat_manager.py` | Proactive care engine (20-min interval) |
| `server/skills/*.py` | 12 AI skills (weather, music, memory, etc.) |
| `server/agent/SOUL.md` | AI personality core (language, tone, boundaries) |
| `server/agent/IDENTITY.md` | Character profile (name: 小優 Uni) |
| `server/agent/MEMORY.md` | Long-term memory storage |
| `server/agent/USER.md` | Elder profile information |
| `server/agent/HEARTBEAT.md` | Proactive task checklist |
| `server/agent/AGENTS.md` | Operational workflow |

## If Your Task Involves Socket.IO or WebRTC:
You are strictly forbidden from writing code without first reviewing:
- `lib/services/signaling.dart` — Singleton socket + WebRTC handlers
- `lib/main.dart` — Global CallKit / FCM listeners and incoming call dialog
- `lib/globals.dart` — Shared state (`pendingAcceptedCall`, `appRole`)

Follow the constraints: Global Call Listener, Singleton connection, FCM token forwarding.

## If Your Task Involves AI Features:
Review these files first:
- `server/services/ollama_service.py` — Tool schema generation, streaming response
- `server/skills/__init__.py` — ALL_SKILLS list (12 functions)
- `server/agent/*.md` — Personality and memory configuration
