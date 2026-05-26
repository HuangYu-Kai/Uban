#!/bin/bash
# ==============================================================================
# Uban 開發啟動腳本
# 
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │  📌 啟動方式 (How to Run)                                                   │
# │                                                                             │
# │  ═══════════════════════════════════════════════════════════════════════   │
# │  🍎 macOS / 🐧 Linux                                                        │
# │  ═══════════════════════════════════════════════════════════════════════   │
# │                                                                             │
# │  方法一：在終端機中 cd 到 Uban 目錄後執行                                    │
# │    cd /你的路徑/Uban                                                        │
# │    chmod +x run.sh    # 首次需要，賦予執行權限                               │
# │    ./run.sh                                                                 │
# │                                                                             │
# │  方法二：直接用完整路徑執行                                                  │
# │    bash /你的路徑/Uban/run.sh                                               │
# │                                                                             │
# │  方法三：快速啟動 (跳過選單)                                                 │
# │    ./run.sh -s        # 一鍵啟動                                            │
# │    ./run.sh -r        # 熱重啟                                              │
# │    ./run.sh -c        # 檢查後端                                            │
# │                                                                             │
# │  ═══════════════════════════════════════════════════════════════════════   │
# │  🪟 Windows (PowerShell)                                                    │
# │  ═══════════════════════════════════════════════════════════════════════   │
# │                                                                             │
# │  方法一：在 PowerShell 中 cd 到 Uban 目錄後執行                              │
# │    cd C:\你的路徑\Uban                                                      │
# │    .\run.ps1                                                                │
# │                                                                             │
# │  方法二：若出現權限錯誤，先執行                                              │
# │    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser     │
# │    .\run.ps1                                                                │
# │                                                                             │
# └─────────────────────────────────────────────────────────────────────────────┘
# 
# 架構說明：
#   - FastAPI 後端：部署在遠端伺服器，透過 Tailscale Funnel 暴露
#   - Flutter 前端：本地開發，連接遠端 FastAPI
#
# 功能：
#   [1] 一鍵啟動 - 自動檢測模擬器、安裝依賴、啟動 App
#   [2] 熱重啟   - 快速重啟已運行的 Flutter App (不重新編譯)
#   [3] 僅檢查   - 檢查後端連線狀態
#   [4] 清理程序 - 停止所有 Flutter 進程
#
# 最後更新：2026-03-31
# ==============================================================================

set -e  # 遇到錯誤立即停止

# --- 配置區 ---
DEFAULT_SERVER_URL="localhost-0.tail5abf5e.ts.net"
DEFAULT_OLLAMA_URL="boyo-desktop.tail531c8a.ts.net"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOBILE_APP_DIR="$SCRIPT_DIR/mobile_app"
FLUTTER_DEVICE_TIMEOUT=120

# --- 顏色定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 輔助函數 ---
print_header() {
    clear
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║           🏠 Uban 跨世代感知照護系統 - 開發工具            ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }

is_macos() {
    [ "$(uname -s)" = "Darwin" ]
}

ADB_BIN=""
EMULATOR_BIN=""

# 自動設定 ANDROID_HOME（如果未設定）
if [ -z "$ANDROID_HOME" ]; then
    if [ -d ~/Library/Android/sdk ]; then
        export ANDROID_HOME=~/Library/Android/sdk
    elif [ -d ~/.android ]; then
        export ANDROID_HOME=~/.android
    fi
fi

resolve_adb() {
    # 優先使用 SDK 版本
    if [ -n "$ANDROID_HOME" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ]; then
        echo "$ANDROID_HOME/platform-tools/adb"
        return 0
    fi
    if [ -n "$ANDROID_SDK_ROOT" ] && [ -x "$ANDROID_SDK_ROOT/platform-tools/adb" ]; then
        echo "$ANDROID_SDK_ROOT/platform-tools/adb"
        return 0
    fi
    # 不要用 PATH 的版本，避免混用不同 adb
    return 1
}

resolve_emulator() {
    # 優先使用 SDK 版本
    if [ -n "$ANDROID_HOME" ] && [ -x "$ANDROID_HOME/emulator/emulator" ]; then
        echo "$ANDROID_HOME/emulator/emulator"
        return 0
    fi
    if [ -n "$ANDROID_SDK_ROOT" ] && [ -x "$ANDROID_SDK_ROOT/emulator/emulator" ]; then
        echo "$ANDROID_SDK_ROOT/emulator/emulator"
        return 0
    fi
    # 不要用 PATH 的版本
    return 1
}

init_adb() {
    if [ -z "$ADB_BIN" ]; then
        ADB_BIN="$(resolve_adb || true)"
    fi
}

init_emulator() {
    if [ -z "$EMULATOR_BIN" ]; then
        EMULATOR_BIN="$(resolve_emulator || true)"
    fi
}

has_adb() {
    init_adb
    [ -n "$ADB_BIN" ]
}

has_emulator() {
    init_emulator
    [ -n "$EMULATOR_BIN" ]
}

get_android_emulator_any_id() {
    if ! has_adb; then
        return 1
    fi
    "$ADB_BIN" devices 2>/dev/null | awk 'NR>1 && $1 ~ /^emulator-/' | head -1 | awk '{print $1}'
}

get_android_emulator_state() {
    if ! has_adb; then
        return 1
    fi
    "$ADB_BIN" devices 2>/dev/null | awk 'NR>1 && $1 ~ /^emulator-/' | head -1 | awk '{print $2}'
}

print_android_tooling_error() {
    print_error "找不到 adb (Android SDK Platform-Tools)"
    echo "    請先安裝並加入 PATH"
    echo "    macOS (Homebrew): brew install android-platform-tools"
    echo "    或設定 ANDROID_HOME/ANDROID_SDK_ROOT，並將 \$ANDROID_HOME/platform-tools 加入 PATH"
}

get_android_emulator_id() {
    if ! has_adb; then
        return 1
    fi
    "$ADB_BIN" devices 2>/dev/null | awk 'NR>1 && $2=="device" && $1 ~ /^emulator-/' | head -1
}

is_android_emulator_booted() {
    local device_id="$1"
    if [ -z "$device_id" ] || ! has_adb; then
        return 1
    fi
    local boot_completed
    boot_completed=$("$ADB_BIN" -s "$device_id" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    [ "$boot_completed" = "1" ]
}

wait_for_android_emulator_boot() {
    local timeout_seconds="${1:-120}"
    local elapsed=0
    local warned_offline=false
    local warned_no_device=false

    while [ "$elapsed" -lt "$timeout_seconds" ]; do
        local emulator_id state
        emulator_id=$(get_android_emulator_any_id)
        state=$(get_android_emulator_state)

        if [ -z "$emulator_id" ]; then
            if [ "$warned_no_device" = false ]; then
                print_warning "adb 尚未偵測到模擬器，等待中..."
                warned_no_device=true
            fi
        else
            if [ "$state" = "device" ]; then
                if is_android_emulator_booted "$emulator_id"; then
                    return 0
                fi
            elif [ "$state" = "offline" ]; then
                if [ "$warned_offline" = false ]; then
                    print_warning "Android 模擬器處於 offline，嘗試重啟 adb..."
                    warned_offline=true
                fi
                "$ADB_BIN" kill-server >/dev/null 2>&1
                "$ADB_BIN" start-server >/dev/null 2>&1
            elif [ "$state" = "unauthorized" ]; then
                print_error "Android 模擬器未授權 (unauthorized)"
                return 1
            fi
        fi

        echo -n "."
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

check_backend() {
    local serverURL="$1"
    echo -n "[*] 檢查遠端 FastAPI 連線... "
    local status
    status=$(curl -s -k --connect-timeout 5 "https://$serverURL/" 2>/dev/null || echo "")
    if echo "$status" | grep -q "Uban API"; then
        print_success "後端在線 (https://$serverURL)"
        return 0
    else
        print_warning "無法連線至 https://$serverURL"
        return 1
    fi
}

check_ollama() {
    local ollamaURL="$1"
    echo -n "[*] 檢查遠端 Ollama 連線... "
    local status
    status=$(curl -s -k --connect-timeout 5 "https://$ollamaURL/api/tags" 2>/dev/null || echo "")
    if echo "$status" | grep -q "models"; then
        print_success "Ollama 在線 (https://$ollamaURL)"
        # 顯示可用模型
        local models
        models=$(echo "$status" | grep -o '"name":"[^"]*"' | head -3 | sed 's/"name":"//g' | sed 's/"//g' | tr '\n' ', ' | sed 's/,$//')
        if [ -n "$models" ]; then
            echo "    可用模型: $models"
        fi
        return 0
    else
        print_warning "無法連線至 Ollama (https://$ollamaURL)"
        return 1
    fi
}

# 取得所有已連接的設備 (實體設備 + 模擬器)
get_connected_devices() {
    # 返回格式: device_id|device_name|device_type (每行一個)
    flutter devices 2>/dev/null | grep -E "•.*•.*•" | grep -vi "macos\|linux\|windows\|chrome\|web" | while read -r line; do
        local name id type
        name=$(echo "$line" | sed 's/•.*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        id=$(echo "$line" | awk -F'•' '{print $2}' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        if echo "$line" | grep -qi "emulator\|simulator"; then
            type="emulator"
        else
            type="physical"
        fi
        if [ -n "$id" ]; then
            echo "$id|$name|$type"
        fi
    done
}

# 檢查是否有實體設備
check_physical_device() {
    local devices
    devices=$(get_connected_devices)
    echo "$devices" | grep -q "|physical$"
    return $?
}

# 檢查是否有模擬器
check_emulator_running() {
    local devices
    devices=$(get_connected_devices)
    if echo "$devices" | grep -q "|emulator$"; then
        return 0
    fi
    local adb_emulator_id
    adb_emulator_id=$(get_android_emulator_id)
    if [ -z "$adb_emulator_id" ]; then
        return 1
    fi
    if is_android_emulator_booted "$adb_emulator_id"; then
        return 0
    fi
    return 1
}

# 取得模擬器 ID
get_emulator_id() {
    local adb_emulator_id
    adb_emulator_id=$(get_android_emulator_id)
    if [ -n "$adb_emulator_id" ]; then
        echo "$adb_emulator_id"
        return 0
    fi
    get_connected_devices | grep "|emulator$" | head -1 | cut -d'|' -f1
}

# 取得實體設備 ID
get_physical_device_id() {
    get_connected_devices | grep "|physical$" | head -1 | cut -d'|' -f1
}

start_emulator() {
    print_info "正在啟動模擬器..."
    local launched=false
    local android_launched=false
    local emulator_id=""
    local emulator_adb_id=""
    
    # 先確保 adb daemon 已啟動（模擬器需要它）
    if has_adb; then
        "$ADB_BIN" start-server > /dev/null 2>&1 || true
        sleep 1
    fi
    
    emulator_id=$(flutter emulators 2>/dev/null | grep -i "android" | awk '{print $1}' | head -1)
    if [ -z "$emulator_id" ] && has_emulator; then
        emulator_id=$("$EMULATOR_BIN" -list-avds 2>/dev/null | head -n 1)
    fi

    if [ -n "$emulator_id" ]; then
        print_info "啟動 Android 模擬器: $emulator_id"
        flutter emulators --launch "$emulator_id" > /dev/null 2>&1 &
        launched=true
        android_launched=true
    fi

    if [ "$launched" = false ] && is_macos; then
        local ios_emulator_id
        ios_emulator_id=$(flutter emulators 2>/dev/null | awk -F'•' '{print $1}' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | grep -i "ios" | head -1)
        if [ -n "$ios_emulator_id" ]; then
            print_info "啟動 iOS 模擬器: $ios_emulator_id"
            flutter emulators --launch "$ios_emulator_id" > /dev/null 2>&1 &
            launched=true
        else
            if command -v open >/dev/null 2>&1; then
                print_info "啟動 iOS Simulator..."
                open -a Simulator > /dev/null 2>&1 &
                launched=true
            fi
        fi
    fi

    if [ "$android_launched" = true ] && ! has_adb; then
        print_android_tooling_error
        return 1
    fi

    if [ "$launched" = false ]; then
        print_error "找不到任何可用的模擬器！"
        echo "    macOS: 請先安裝 Xcode 並啟動 iOS Simulator"
        echo "    Android: 請先在 Android Studio 中建立模擬器"
        echo "    或執行: flutter emulators --create --name my_emulator"
        return 1
    fi

    echo ""
    echo -n "    等待模擬器開機 (最多 30 秒)"

    # 等待 adb 能偵測到設備並且 online
    for i in $(seq 1 30); do
        if has_adb; then
            local device_state
            device_state=$("$ADB_BIN" devices -l 2>/dev/null | grep "emulator-5554" | awk '{print $2}')
            if [ "$device_state" = "device" ]; then
                echo ""
                print_success "模擬器已就緒 (online)"
                return 0
            fi
        fi
        echo -n "."
        sleep 1
    done

    echo ""
    print_warning "模擬器已啟動但尚未就緒，flutter 會繼續等待..."
    
    # 寫入 adb ID 供後續使用
    echo "emulator-5554" > /tmp/uban_emulator_id.txt
    return 0
}

flutter_pub_get() {
    print_info "安裝 Flutter 依賴..."
    cd "$MOBILE_APP_DIR"
    flutter pub get > /dev/null 2>&1
    cd "$SCRIPT_DIR"
    print_success "依賴已更新"
}

# --- 核心功能 ---

# 儲存運行中的 Flutter 進程資訊
FLUTTER_PIDS_FILE="/tmp/uban_flutter_pids.txt"

# 一鍵啟動
do_quick_start() {
    local serverURL="${1:-$DEFAULT_SERVER_URL}"
    
    echo ""
    echo "=========================================="
    echo "         🚀 一鍵啟動模式"
    echo "=========================================="
    echo ""
    
    # 1. 檢查後端
    local backend_ok=true
    local ollama_ok=true
    
    if ! check_backend "$serverURL"; then
        backend_ok=false
    fi
    
    # 2. 檢查 Ollama
    if ! check_ollama "$DEFAULT_OLLAMA_URL"; then
        ollama_ok=false
    fi
    
    # 如果有任一服務無法連線，詢問是否繼續
    if [ "$backend_ok" = false ] || [ "$ollama_ok" = false ]; then
        echo ""
        read -p "    是否繼續？[y/N]: " continue_choice
        if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
            exit 1
        fi
    fi
    
    # 2. 檢測設備狀態
    echo ""
    print_info "檢測連接設備..."
    
    local has_physical=false
    local has_emulator=false
    local physical_id=""
    local emulator_id=""
    
    if check_physical_device; then
        has_physical=true
        physical_id=$(get_physical_device_id)
        print_success "偵測到實體設備: $physical_id"
    fi
    
    if check_emulator_running; then
        has_emulator=true
        emulator_id=$(get_emulator_id)
        print_success "偵測到模擬器: $emulator_id"
    fi
    
    # 3. 如果沒有模擬器，啟動一個
    if [ "$has_emulator" = false ]; then
        start_emulator
        # start_emulator 會把 adb ID 寫到 /tmp/uban_emulator_id.txt
        if [ -f /tmp/uban_emulator_id.txt ]; then
            emulator_id=$(cat /tmp/uban_emulator_id.txt)
            has_emulator=true
            print_warning "模擬器已啟動: $emulator_id"
        fi
    fi
    
    # 4. 安裝依賴
    flutter_pub_get
    
    # 5. 決定啟動模式
    echo ""
    
    # 清空舊的 PID 檔案
    > "$FLUTTER_PIDS_FILE"
    
    if [ "$has_physical" = true ] && [ "$has_emulator" = true ]; then
        # 雙設備模式
        print_info "🎯 雙設備模式：同時在實體設備和模擬器上啟動"
        echo ""
        
        print_info "伺服器: https://$serverURL"
        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════"
        echo "    雙設備模式熱鍵提示："
        echo "    模擬器視窗：r/R = 熱重載/熱重啟"
        echo "    實體設備：使用選單 [6] 熱重啟實體設備"
        echo "    q = 退出當前視窗"
        echo -e "═══════════════════════════════════════════════════════════${NC}"
        echo ""
        
        cd "$MOBILE_APP_DIR"
        
        # 在背景啟動實體設備
        print_info "啟動實體設備 ($physical_id)..."
        flutter run --dart-define=SERVER_IP="$serverURL" --device-timeout="$FLUTTER_DEVICE_TIMEOUT" -d "$physical_id" &
        echo "$!|physical|$physical_id" >> "$FLUTTER_PIDS_FILE"
        sleep 3
        
        # 前台啟動模擬器
        print_info "啟動模擬器 ($emulator_id)..."
        flutter run --dart-define=SERVER_IP="$serverURL" --device-timeout="$FLUTTER_DEVICE_TIMEOUT" -d "$emulator_id" &
        echo "$!|emulator|$emulator_id" >> "$FLUTTER_PIDS_FILE"
        
        echo ""
        print_success "雙設備已啟動！使用 ./run.sh 選擇 [6] 來熱重啟實體設備"
        echo ""
        
        # 等待任一進程結束
        wait
        
    else
        # 單設備模式
        local target_device=""
        local device_type=""
        
        if [ "$has_emulator" = true ]; then
            target_device="$emulator_id"
            device_type="模擬器"
        elif [ "$has_physical" = true ]; then
            target_device="$physical_id"
            device_type="實體設備"
        fi
        
        print_info "🎯 單設備模式：在${device_type}上啟動"
        print_info "伺服器: https://$serverURL"
        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════"
        echo "    Flutter 熱鍵提示："
        echo "    r = 熱重載 (Hot Reload)  🔥"
        echo "    R = 熱重啟 (Hot Restart) 🔄"
        echo "    q = 退出"
        echo -e "═══════════════════════════════════════════════════════════${NC}"
        echo ""
        
        cd "$MOBILE_APP_DIR"
        
        if [ -n "$target_device" ]; then
            flutter run --dart-define=SERVER_IP="$serverURL" --device-timeout="$FLUTTER_DEVICE_TIMEOUT" -d "$target_device"
        else
            flutter run --dart-define=SERVER_IP="$serverURL"
        fi
    fi
}

# 熱重啟實體設備
do_hot_restart_physical() {
    if [ ! -f "$FLUTTER_PIDS_FILE" ]; then
        print_error "沒有找到運行中的雙設備進程"
        echo "    請先使用選項 [1] 啟動 App"
        return 1
    fi
    
    local physical_line
    physical_line=$(grep "|physical|" "$FLUTTER_PIDS_FILE" 2>/dev/null)
    
    if [ -z "$physical_line" ]; then
        print_error "沒有找到運行中的實體設備進程"
        return 1
    fi
    
    local pid device_id
    pid=$(echo "$physical_line" | cut -d'|' -f1)
    device_id=$(echo "$physical_line" | cut -d'|' -f3)
    
    if ! kill -0 "$pid" 2>/dev/null; then
        print_error "實體設備進程 (PID: $pid) 已停止"
        return 1
    fi
    
    print_info "正在熱重啟實體設備 ($device_id)..."
    
    # 發送 SIGUSR1 或透過 stdin 發送 R
    # 由於 Flutter 在背景，我們需要重新啟動
    kill "$pid" 2>/dev/null
    sleep 2
    
    cd "$MOBILE_APP_DIR"
    flutter run --dart-define=SERVER_IP="$DEFAULT_SERVER_URL" --device-timeout="$FLUTTER_DEVICE_TIMEOUT" -d "$device_id" &
    local new_pid=$!
    
    # 更新 PID 檔案
    grep -v "|physical|" "$FLUTTER_PIDS_FILE" > "${FLUTTER_PIDS_FILE}.tmp"
    echo "$new_pid|physical|$device_id" >> "${FLUTTER_PIDS_FILE}.tmp"
    mv "${FLUTTER_PIDS_FILE}.tmp" "$FLUTTER_PIDS_FILE"
    
    print_success "實體設備已重新啟動 (新 PID: $new_pid)"
}

# 熱重啟 (發送 R 到現有 flutter run 進程)
do_hot_restart() {
    local flutter_pid
    flutter_pid=$(pgrep -f "flutter_tools.*run" 2>/dev/null | head -1)
    
    if [ -z "$flutter_pid" ]; then
        print_error "未找到正在運行的 Flutter 進程"
        echo "    請先使用選項 [1] 啟動 App"
        return 1
    fi
    
    print_info "正在觸發熱重啟 (PID: $flutter_pid)..."
    
    # 嘗試透過 /dev/pts 發送 R
    local pts
    pts=$(ls -la /proc/$flutter_pid/fd/0 2>/dev/null | awk '{print $NF}')
    
    if [ -n "$pts" ] && [ -e "$pts" ]; then
        echo "R" > "$pts" 2>/dev/null && print_success "已發送熱重啟指令" && return 0
    fi
    
    # 備用方案：使用 osascript 發送鍵盤事件
    osascript -e 'tell application "System Events" to keystroke "R"' 2>/dev/null
    print_success "已發送熱重啟指令 (透過系統事件)"
}

# 僅檢查後端
do_health_check() {
    local serverURL="${1:-$DEFAULT_SERVER_URL}"
    echo ""
    echo "=========================================="
    echo "         🔍 後端健康檢查"
    echo "=========================================="
    echo ""
    
    echo "[*] 測試連線: https://$serverURL"
    echo ""
    
    local response
    response=$(curl -s -k --connect-timeout 10 "https://$serverURL/" 2>/dev/null)
    
    if echo "$response" | grep -q "Uban API"; then
        print_success "FastAPI 後端運作正常！"
        echo ""
        echo "    回應內容："
        echo "$response" | head -5
    else
        print_error "無法連線至後端"
        echo ""
        echo "    可能原因："
        echo "    1. Server 未運行 (檢查 uvicorn 或 podman)"
        echo "    2. Tailscale Funnel 未啟用 (執行: tailscale funnel 8000)"
        echo "    3. 網路問題"
    fi
    
    echo ""
    check_ollama "$DEFAULT_OLLAMA_URL"
}

# 清理進程
do_cleanup() {
    echo ""
    echo "=========================================="
    echo "         🧹 清理 Flutter 進程"
    echo "=========================================="
    echo ""
    
    local pids
    pids=$(pgrep -f "flutter" 2>/dev/null || echo "")
    
    if [ -z "$pids" ]; then
        print_info "沒有找到 Flutter 相關進程"
        return 0
    fi
    
    echo "[*] 找到以下進程："
    ps aux | grep -E "flutter" | grep -v grep
    echo ""
    
    read -p "    確定要終止這些進程嗎？[y/N]: " confirm
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        for pid in $pids; do
            kill "$pid" 2>/dev/null && echo "    已終止 PID: $pid"
        done
        print_success "清理完成"
    else
        print_info "已取消"
    fi
}

# --- 主選單 ---
main() {
    print_header
    
    echo "  [1] 🚀 一鍵啟動 (自動檢測環境並啟動 App)"
    echo "  [2] 🔄 熱重啟 (重啟已運行的 App，不重新編譯)"
    echo "  [3] 🔍 檢查後端連線狀態"
    echo "  [4] 🧹 清理 Flutter 進程"
    echo "  [5] ⚙️  自訂伺服器網址"
    echo "  [6] 📱 熱重啟實體設備 (雙設備模式)"
    echo "  [q] 退出"
    echo ""
    echo -e "${BLUE}  當前後端: https://$DEFAULT_SERVER_URL${NC}"
    echo -e "${BLUE}  當前 Ollama: https://$DEFAULT_OLLAMA_URL${NC}"
    echo ""
    
    read -p "請選擇 [1-6/q]: " choice
    
    case $choice in
        1) do_quick_start ;;
        2) do_hot_restart ;;
        3) do_health_check ;;
        4) do_cleanup ;;
        5)
            read -p "輸入伺服器網址: " custom_url
            do_quick_start "$custom_url"
            ;;
        6) do_hot_restart_physical ;;
        q|Q) echo "Bye! 👋"; exit 0 ;;
        *) print_error "無效選項"; sleep 1; main ;;
    esac
}

# 支援命令行參數直接執行
if [ "$1" == "--start" ] || [ "$1" == "-s" ]; then
    do_quick_start "${2:-$DEFAULT_SERVER_URL}"
elif [ "$1" == "--restart" ] || [ "$1" == "-r" ]; then
    do_hot_restart
elif [ "$1" == "--restart-physical" ] || [ "$1" == "-rp" ]; then
    do_hot_restart_physical
elif [ "$1" == "--check" ] || [ "$1" == "-c" ]; then
    do_health_check "${2:-$DEFAULT_SERVER_URL}"
elif [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Uban 開發腳本"
    echo ""
    echo "用法: ./run.sh [選項]"
    echo ""
    echo "選項:"
    echo "  -s, --start [URL]       一鍵啟動 (可選指定伺服器)"
    echo "  -r, --restart           熱重啟"
    echo "  -rp, --restart-physical 熱重啟實體設備 (雙設備模式)"
    echo "  -c, --check [URL]       檢查後端連線"
    echo "  -h, --help              顯示幫助"
    echo ""
    echo "無參數時進入互動式選單"
else
    main
fi