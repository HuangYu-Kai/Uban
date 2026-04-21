# 專案大掃除與整理報告

我已經完成了資料夾的整理與大掃除，並成功啟動了 Flutter App。

## 1. App 啟動狀態
- **裝置**：Android (23113RKC6G)
- **狀態**：成功啟動 (PID: 11496)
- **修正**：修復了 `HeartbeatOverlay` 中的動畫曲線名稱錯誤 (`backOut` -> `easeOutBack`)。

## 2. 檔案整理成果

### Uban (前端專案)
- **建立 `docs/` 資料夾**：收納了原本散落在根目錄的文件。
  - `feedgawa_intro.md` -> `docs/`
  - `proposal.md` -> `docs/`
  - `TEST_CALL_SIMULATOR_GUIDE.md` -> `docs/`
  - `walkthrough.md` -> `docs/archive_walkthrough.md`
- **刪除過時檔案**：
  - `test_call_simulator.py`
  - `webrtc_test.html`
  - `run.ps1` / `run.sh` (清理啟動腳本)

### uban-api (後端專案)
- **建立 `docs/` 資料夾**：
  - `DATABASE.md` -> `docs/`
  - `walkthrough.md` -> `docs/archive_walkthrough.md`
  - 建立 `docs/html_tools/`：收納 `kobe_cutter.html`、`tts_tester.html` 等網頁工具。
- **整理測試腳本**：
  - 將所有 `test_*.py` 與 `check_*.py` 移至 `tests/` 資料夾，保持根目錄純淨。
  - 移除了 `error.log` 等暫存檔。

## 目前根目錄狀態
現在根目錄僅保留核心程式碼 (`main.py`, `database.py` 等) 與必要說明文件 (`README.md`, `CLAUDE.md`)，開發環境變得非常清爽！
