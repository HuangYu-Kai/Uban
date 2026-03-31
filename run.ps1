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

# ADB 路徑
$script:AdbPath = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

# 用 ADB 檢測已連接的設備（更可靠）
function Get-AdbDevices {
    if (-not (Test-Path $script:AdbPath)) {
        return @{ Physical = @(); Emulator = @() }
    }
    
    $result = @{
        Physical = @()
        Emulator = @()
    }
    
    $output = & $script:AdbPath devices 2>&1 | Out-String
    $lines = $output -split "`n" | Where-Object { $_ -match "device$" -and $_ -notmatch "List of devices" }
    
    foreach ($line in $lines) {
        if ($line -match "^(\S+)\s+device") {
            $deviceId = $matches[1]
            if ($deviceId -match "emulator") {
                $result.Emulator += $deviceId
            } else {
                $result.Physical += $deviceId
            }
        }
    }
    
    return $result
}

# 取得所有已連接的設備 (結合 flutter devices 和 adb devices)
function Get-ConnectedDevices {
    # 優先用 ADB 檢測（更快更可靠）
    $adbDevices = Get-AdbDevices
    if ($adbDevices.Physical.Count -gt 0 -or $adbDevices.Emulator.Count -gt 0) {
        return $adbDevices
    }
    
    # 備用: flutter devices
    $devices = flutter devices 2>&1 | Out-String
    $result = @{
        Physical = @()
        Emulator = @()
    }
    
    # 匹配格式: "設備名稱 (類型) • 設備ID • 平台 • 版本資訊"
    # 排除 desktop 和 web 設備
    $lines = $devices -split "`n" | Where-Object { 
        $_ -match "•.*•.*•" -and 
        $_ -notmatch "\(desktop\)" -and 
        $_ -notmatch "\(web\)" -and
        $_ -notmatch "windows|chrome|edge|macos|linux"
    }
    
    foreach ($line in $lines) {
        # 提取設備 ID（第一個 • 後面的內容）
        if ($line -match "•\s*([^\s•]+)\s*•") {
            $deviceId = $matches[1]
            if ($line -match "\(emulator\)") {
                $result.Emulator += $deviceId
            } else {
                $result.Physical += $deviceId
            }
        }
    }
    
    return $result
}

# 檢查模擬器視窗是否已開啟（透過進程名稱）
function Test-EmulatorRunning {
    $qemuProc = Get-Process -Name "qemu-system-x86_64" -ErrorAction SilentlyContinue
    $emulatorProc = Get-Process -Name "emulator*" -ErrorAction SilentlyContinue
    return ($null -ne $qemuProc -or $null -ne $emulatorProc)
}

function Start-EmulatorDevice {
    Write-Info "正在啟動 Android 模擬器..."
    
    $emulators = flutter emulators 2>&1 | Out-String
    $emulatorId = ($emulators -split "`n" | Where-Object { $_ -match "android" } | ForEach-Object { ($_ -split "\s+")[0] } | Select-Object -First 1)
    
    if (-not $emulatorId) {
        Write-Error "找不到任何 Android 模擬器！請先在 Android Studio 中建立模擬器"
        return $false
    }
    
    Write-Info "啟動模擬器: $emulatorId"
    Start-Process flutter -ArgumentList "emulators", "--launch", $emulatorId -WindowStyle Hidden
    
    # 只等 10 秒，讓 flutter run 自己處理等待
    Write-Host "    等待模擬器... " -NoNewline
    for ($i = 1; $i -le 5; $i++) {
        Start-Sleep -Seconds 2
        $devices = Get-ConnectedDevices
        if ($devices.Emulator.Count -gt 0) {
            Write-Host ""
            Write-Success "模擬器已就緒"
            return $true
        }
        Write-Host "." -NoNewline
    }
    Write-Host ""
    Write-Warning "模擬器可能還在啟動中，繼續執行..."
    return $false
}

function Install-Dependencies {
    Write-Info "安裝 Flutter 依賴..."
    Set-Location $mobileAppDir
    flutter pub get 2>&1 | Out-Null
    Set-Location $root
    Write-Success "依賴已更新"
}

# --- 核心功能 ---

# 儲存運行中的 Flutter 進程資訊
$script:FlutterPidsFile = "$env:TEMP\uban_flutter_pids.txt"

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
    
    # 2. 檢測設備狀態
    Write-Host ""
    Write-Info "檢測連接設備..."
    
    $devices = Get-ConnectedDevices
    $hasPhysical = $devices.Physical.Count -gt 0
    $hasEmulator = $devices.Emulator.Count -gt 0
    $physicalId = if ($hasPhysical) { $devices.Physical[0] } else { $null }
    $emulatorId = if ($hasEmulator) { $devices.Emulator[0] } else { $null }
    
    if ($hasPhysical) {
        Write-Success "偵測到實體設備: $physicalId"
    }
    if ($hasEmulator) {
        Write-Success "偵測到模擬器: $emulatorId"
    }
    
    # 3. 如果沒有模擬器，啟動一個
    if (-not $hasEmulator) {
        if (Start-EmulatorDevice) {
            $devices = Get-ConnectedDevices
            $hasEmulator = $devices.Emulator.Count -gt 0
            $emulatorId = if ($hasEmulator) { $devices.Emulator[0] } else { $null }
        }
    }
    
    # 4. 安裝依賴
    Install-Dependencies
    
    # 5. 決定啟動模式
    Write-Host ""
    
    # 清空舊的 PID 檔案
    "" | Out-File $script:FlutterPidsFile -Force
    
    if ($hasPhysical -and $hasEmulator) {
        # 雙設備模式
        Write-Info "🎯 雙設備模式：同時在實體設備和模擬器上啟動"
        Write-Host ""
        
        Write-Info "伺服器: https://$serverUrl"
        Write-Host ""
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host "    雙設備模式熱鍵提示："
        Write-Host "    模擬器視窗：r/R = 熱重載/熱重啟"
        Write-Host "    實體設備：使用選單 [6] 熱重啟實體設備"
        Write-Host "    q = 退出當前視窗"
        Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host ""
        
        Set-Location $mobileAppDir
        
        # 在新視窗啟動實體設備
        Write-Info "啟動實體設備 ($physicalId)..."
        $physicalProcess = Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$mobileAppDir'; flutter run --dart-define=SERVER_IP=$serverUrl -d $physicalId" -PassThru
        "physical|$($physicalProcess.Id)|$physicalId" | Out-File $script:FlutterPidsFile -Append
        Start-Sleep -Seconds 3
        
        # 在新視窗啟動模擬器
        Write-Info "啟動模擬器 ($emulatorId)..."
        $emulatorProcess = Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$mobileAppDir'; flutter run --dart-define=SERVER_IP=$serverUrl -d $emulatorId" -PassThru
        "emulator|$($emulatorProcess.Id)|$emulatorId" | Out-File $script:FlutterPidsFile -Append
        
        Write-Host ""
        Write-Success "雙設備已啟動！使用 .\run.ps1 選擇 [6] 來熱重啟實體設備"
        Write-Host ""
        
    } else {
        # 單設備模式
        $targetDevice = $null
        $deviceType = ""
        
        if ($hasEmulator) {
            $targetDevice = $emulatorId
            $deviceType = "模擬器"
        } elseif ($hasPhysical) {
            $targetDevice = $physicalId
            $deviceType = "實體設備"
        }
        
        Write-Info "🎯 單設備模式：在${deviceType}上啟動"
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
        
        if ($targetDevice) {
            flutter run --dart-define=SERVER_IP=$serverUrl -d $targetDevice
        } else {
            flutter run --dart-define=SERVER_IP=$serverUrl
        }
    }
}

function Start-HotRestartPhysical {
    if (-not (Test-Path $script:FlutterPidsFile)) {
        Write-Error "沒有找到運行中的雙設備進程"
        Write-Host "    請先使用選項 [1] 啟動 App"
        return
    }
    
    $physicalLine = Get-Content $script:FlutterPidsFile | Where-Object { $_ -match "^physical\|" } | Select-Object -First 1
    
    if (-not $physicalLine) {
        Write-Error "沒有找到運行中的實體設備進程"
        return
    }
    
    $parts = $physicalLine -split "\|"
    $pid = $parts[1]
    $deviceId = $parts[2]
    
    $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if (-not $process) {
        Write-Error "實體設備進程 (PID: $pid) 已停止"
        return
    }
    
    Write-Info "正在熱重啟實體設備 ($deviceId)..."
    
    Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    Set-Location $mobileAppDir
    $newProcess = Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$mobileAppDir'; flutter run --dart-define=SERVER_IP=$DEFAULT_SERVER_URL -d $deviceId" -PassThru
    
    # 更新 PID 檔案
    $otherLines = Get-Content $script:FlutterPidsFile | Where-Object { $_ -notmatch "^physical\|" }
    $otherLines | Out-File $script:FlutterPidsFile -Force
    "physical|$($newProcess.Id)|$deviceId" | Out-File $script:FlutterPidsFile -Append
    
    Write-Success "實體設備已重新啟動 (新 PID: $($newProcess.Id))"
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
    Write-Host "  [5] 📱 熱重啟實體設備 (雙設備模式)"
    Write-Host "  [q] 退出"
    Write-Host ""
    Write-Host "  當前後端: https://$DEFAULT_SERVER_URL" -ForegroundColor Cyan
    Write-Host ""
    
    $choice = Read-Host "請選擇 [1-5/q]"
    
    switch ($choice) {
        "1" { Start-QuickLaunch }
        "2" { Start-HealthCheck }
        "3" { Start-Cleanup }
        "4" {
            $customUrl = Read-Host "輸入伺服器網址"
            Start-QuickLaunch $customUrl
        }
        "5" { Start-HotRestartPhysical }
        "q" { Write-Host "Bye! 👋"; exit 0 }
        "Q" { Write-Host "Bye! 👋"; exit 0 }
        default { Write-Error "無效選項"; Start-Sleep -Seconds 1; Show-Menu }
    }
}

# --- 入口點 ---
# param 部分已在檔案開頭定義

if ($Start) {
    Start-QuickLaunch $ServerUrl
} elseif ($Check) {
    Start-HealthCheck $ServerUrl
} elseif ($Clean) {
    Start-Cleanup
} else {
    Show-Menu
}
