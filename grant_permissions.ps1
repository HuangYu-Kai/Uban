# ============================================================================
# grant_permissions.ps1 — 一次授權 Uban App 在模擬器/實機上的所有權限
# ----------------------------------------------------------------------------
# 為什麼需要：Android 的「危險權限」在【全新安裝 / 清除資料(pm clear) / 模擬器 wipe】
#   後會被重置，導致每次都要手動一個個點同意。此腳本用 adb 一次全部預先授權。
#   （註：一般的增量 flutter run，只要沒有重裝、簽章沒變，權限本來就會保留。）
#
# 用法：
#   .\grant_permissions.ps1                      # 用目前唯一連線的裝置
#   .\grant_permissions.ps1 -DeviceId emulator-5554
# ============================================================================
param(
    [string]$DeviceId = "",
    [string]$Package  = "com.example.flutter_application_1"
)

# --- 尋找 adb ---
$adb = $null
foreach ($cand in @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe")) {
    if ($cand -and (Test-Path $cand)) { $adb = $cand; break }
}
if (-not $adb) { $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source }
if (-not $adb) {
    Write-Host "找不到 adb，請確認已安裝 Android SDK platform-tools" -ForegroundColor Red
    exit 1
}

$target = @()
if ($DeviceId) { $target = @("-s", $DeviceId) }
function Adb { & $adb @target @args 2>$null }

Write-Host "對 $Package 進行權限授權..." -ForegroundColor Cyan

# 1) runtime（危險）權限 — 用 pm grant
$runtime = @(
    "CAMERA", "RECORD_AUDIO",
    "ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION", "ACCESS_BACKGROUND_LOCATION",
    "POST_NOTIFICATIONS", "ACTIVITY_RECOGNITION"
)
foreach ($p in $runtime) {
    Adb shell pm grant $Package "android.permission.$p"
    if ($LASTEXITCODE -eq 0) { Write-Host "  [OK]   $p" -ForegroundColor Green }
    else { Write-Host "  [skip] $p (此 API 不適用或已授權)" -ForegroundColor DarkGray }
}

# 2) 特殊 appops 權限 — 懸浮視窗 / 精確鬧鐘 / 全螢幕來電
$appops = @("SYSTEM_ALERT_WINDOW", "SCHEDULE_EXACT_ALARM", "USE_FULL_SCREEN_INTENT")
foreach ($op in $appops) {
    Adb shell appops set $Package $op allow
    if ($LASTEXITCODE -eq 0) { Write-Host "  [OK]   $op (appop)" -ForegroundColor Green }
    else { Write-Host "  [skip] $op" -ForegroundColor DarkGray }
}

# 3) 電池最佳化白名單（避免背景服務被殺）
Adb shell dumpsys deviceidle whitelist "+$Package"
if ($LASTEXITCODE -eq 0) { Write-Host "  [OK]   電池最佳化白名單" -ForegroundColor Green }

Write-Host "完成 — App 不會再逐一跳權限對話框。" -ForegroundColor Cyan
