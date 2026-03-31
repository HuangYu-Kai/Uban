<# 
==============================================================================
Uban 開發啟動腳本 (Windows PowerShell)

┌─────────────────────────────────────────────────────────────────────────────┐
│  📌 啟動方式 (How to Run)                                                   │
│                                                                             │
│  ═══════════════════════════════════════════════════════════════════════   │
│  🪟 Windows (PowerShell)                                                    │
│  ═══════════════════════════════════════════════════════════════════════   │
│                                                                             │
│  方法一：在 PowerShell 中 cd 到 Uban 目錄後執行                              │
│    cd C:\你的路徑\Uban                                                      │
│    .\run.ps1                                                                │
│                                                                             │
│  方法二：若出現權限錯誤，先執行                                              │
│    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser     │
│    .\run.ps1                                                                │
│                                                                             │
│  快速啟動參數：                                                             │
│    .\run.ps1 -Start         # 一鍵啟動                                      │
│    .\run.ps1 -Check         # 檢查後端                                      │
│    .\run.ps1 -Clean         # 清理程序                                      │
│                                                                             │
│  ═══════════════════════════════════════════════════════════════════════   │
│  🍎 macOS / 🐧 Linux                                                        │
│  ═══════════════════════════════════════════════════════════════════════   │
│                                                                             │
│  請改用 run.sh：                                                            │
│    chmod +x run.sh                                                          │
│    ./run.sh                                                                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

架構說明：
  - FastAPI 後端：部署在遠端伺服器，透過 Tailscale Funnel 暴露
  - Flutter 前端：本地開發，連接遠端 FastAPI

功能：
  [1] 一鍵啟動 - 自動檢測模擬器、安裝依賴、啟動 App
  [2] 熱重啟   - 快速重啟已運行的 Flutter App
  [3] 僅檢查   - 檢查後端連線狀態
  [4] 清理程序 - 停止所有 Flutter 進程

最後更新：2026-03-31
==============================================================================
#>

param(
    [switch]$Start,
    [switch]$Check,
    [switch]$Clean,
    [string]$ServerUrl
)

# --- 配置區 ---
$DEFAULT_SERVER_URL = "localhost-0.tail5abf5e.ts.net"
$root = $PSScriptRoot
$mobileAppDir = "$root\mobile_app"

# --- 輔助函數 ---
function Write-Success { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "ℹ️  $msg" -ForegroundColor Cyan }

function Test-Backend {
    param($serverUrl)
    Write-Host "[*] 檢查遠端 FastAPI 連線... " -NoNewline
    try {
        $response = Invoke-WebRequest -Uri "https://$serverUrl/" -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.Content -like "*Uban API*") {
            Write-Success "後端在線 (https://$serverUrl)"
            return $true
        }
    } catch {}
    Write-Warning "無法連線至 https://$serverUrl"
    return $false
}

function Get-Emulator {
    $devices = flutter devices 2>&1 | Out-String
    if ($devices -match "emulator|android") {
        $deviceLine = ($devices -split "`n" | Where-Object { $_ -match "emulator|android" } | Select-Object -First 1)
        if ($deviceLine -match "•\s*(\S+)\s*•") {
            return $matches[1]
        }
    }
    return $null
}

function Start-Emulator {
    Write-Info "未偵測到 Android 模擬器，正在啟動..."
    
    $emulators = flutter emulators 2>&1 | Out-String
    $emulatorId = ($emulators -split "`n" | Where-Object { $_ -match "android" } | ForEach-Object { ($_ -split "\s+")[0] } | Select-Object -First 1)
    
    if (-not $emulatorId) {
        Write-Error "找不到任何 Android 模擬器！請先在 Android Studio 中建立模擬器"
        exit 1
    }
    
    Write-Info "啟動模擬器: $emulatorId"
    Start-Process flutter -ArgumentList "emulators", "--launch", $emulatorId -WindowStyle Hidden
    
    Write-Host "    等待模擬器開機 (最多 90 秒)" -NoNewline
    for ($i = 1; $i -le 45; $i++) {
        Start-Sleep -Seconds 2
        $device = Get-Emulator
        if ($device) {
            Write-Host ""
            Write-Success "模擬器已就緒"
            Start-Sleep -Seconds 3
            return
        }
        Write-Host "." -NoNewline
    }
    Write-Host ""
    Write-Error "模擬器啟動超時"
    exit 1
}

function Install-Dependencies {
    Write-Info "安裝 Flutter 依賴..."
    Set-Location $mobileAppDir
    flutter pub get 2>&1 | Out-Null
    Set-Location $root
    Write-Success "依賴已更新"
}

# --- 核心功能 ---

function Start-QuickLaunch {
    param($serverUrl)
    
    if (-not $serverUrl) { $serverUrl = $DEFAULT_SERVER_URL }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "         🚀 一鍵啟動模式" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host ""
    
    # 1. 檢查後端
    if (-not (Test-Backend $serverUrl)) {
        $continue = Read-Host "    是否繼續？[y/N]"
        if ($continue -ne "y" -and $continue -ne "Y") { exit }
    }
    
    # 2. 檢查/啟動模擬器
    $deviceId = Get-Emulator
    if ($deviceId) {
        Write-Success "偵測到模擬器: $deviceId"
    } else {
        Start-Emulator
        $deviceId = Get-Emulator
    }
    
    # 3. 安裝依賴
    Install-Dependencies
    
    # 4. 啟動 Flutter
    Write-Host ""
    Write-Info "正在啟動 Flutter App..."
    Write-Info "伺服器: https://$serverUrl"
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "    Flutter 熱鍵提示："
    Write-Host "    r = 熱重載 (Hot Reload)  🔥"
    Write-Host "    R = 熱重啟 (Hot Restart) 🔄"
    Write-Host "    q = 退出"
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host ""
    
    Set-Location $mobileAppDir
    if ($deviceId) {
        flutter run --dart-define=SERVER_IP=$serverUrl -d $deviceId
    } else {
        flutter run --dart-define=SERVER_IP=$serverUrl
    }
}

function Start-HealthCheck {
    param($serverUrl)
    if (-not $serverUrl) { $serverUrl = $DEFAULT_SERVER_URL }
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "         🔍 後端健康檢查" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Host "[*] 測試連線: https://$serverUrl"
    Write-Host ""
    
    try {
        $response = Invoke-WebRequest -Uri "https://$serverUrl/" -TimeoutSec 10 -UseBasicParsing
        if ($response.Content -like "*Uban API*") {
            Write-Success "FastAPI 後端運作正常！"
            Write-Host ""
            Write-Host "    回應內容："
            Write-Host ($response.Content | Select-Object -First 200)
        }
    } catch {
        Write-Error "無法連線至後端"
        Write-Host ""
        Write-Host "    可能原因："
        Write-Host "    1. Server 未運行 (檢查 uvicorn 或 podman)"
        Write-Host "    2. Tailscale Funnel 未啟用 (執行: tailscale funnel 8000)"
        Write-Host "    3. 網路問題"
    }
}

function Start-Cleanup {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "         🧹 清理 Flutter 進程" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host ""
    
    $procs = Get-Process -Name "*flutter*", "*dart*" -ErrorAction SilentlyContinue
    
    if (-not $procs) {
        Write-Info "沒有找到 Flutter 相關進程"
        return
    }
    
    Write-Host "[*] 找到以下進程："
    $procs | Format-Table Id, ProcessName, CPU -AutoSize
    
    $confirm = Read-Host "    確定要終止這些進程嗎？[y/N]"
    if ($confirm -eq "y" -or $confirm -eq "Y") {
        $procs | Stop-Process -Force
        Write-Success "清理完成"
    } else {
        Write-Info "已取消"
    }
}

# --- 主選單 ---
function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           🏠 Uban 跨世代感知照護系統 - 開發工具            ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] 🚀 一鍵啟動 (自動檢測環境並啟動 App)"
    Write-Host "  [2] 🔍 檢查後端連線狀態"
    Write-Host "  [3] 🧹 清理 Flutter 進程"
    Write-Host "  [4] ⚙️  自訂伺服器網址"
    Write-Host "  [q] 退出"
    Write-Host ""
    Write-Host "  當前後端: https://$DEFAULT_SERVER_URL" -ForegroundColor Cyan
    Write-Host ""
    
    $choice = Read-Host "請選擇 [1-4/q]"
    
    switch ($choice) {
        "1" { Start-QuickLaunch }
        "2" { Start-HealthCheck }
        "3" { Start-Cleanup }
        "4" {
            $customUrl = Read-Host "輸入伺服器網址"
            Start-QuickLaunch $customUrl
        }
        "q" { Write-Host "Bye! 👋"; exit 0 }
        "Q" { Write-Host "Bye! 👋"; exit 0 }
        default { Write-Error "無效選項"; Start-Sleep -Seconds 1; Show-Menu }
    }
}

# --- 入口點 ---
if ($Start) {
    Start-QuickLaunch $ServerUrl
} elseif ($Check) {
    Start-HealthCheck $ServerUrl
} elseif ($Clean) {
    Start-Cleanup
} else {
    Show-Menu
}
