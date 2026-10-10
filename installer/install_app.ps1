# Uban App 手機安裝程式
# 由 Uban_Setup.exe 安裝完成後呼叫，也可從「開始」選單的「安裝 Uban 到手機」再次執行。
# 透過 adb 把 Uban.apk 裝進以 USB 連接（已開啟 USB 偵錯）的 Android 手機或正在執行的 Android 模擬器。

$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'Uban 手機安裝程式'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root    = $PSScriptRoot
$adb     = Join-Path $root 'platform-tools\adb.exe'
$apk     = Join-Path $root 'Uban.apk'
$package = 'com.example.flutter_application_1'

function Pause-Exit([int]$code) {
    Write-Host ''
    Read-Host '按 Enter 鍵關閉視窗' | Out-Null
    exit $code
}

function Show-ManualGuide {
    Write-Host ''
    Write-Host '──── 改用手動安裝 ────' -ForegroundColor Yellow
    Write-Host '1. 將下列檔案傳到手機（USB 複製、雲端硬碟、LINE 傳給自己皆可）：'
    Write-Host "   $apk"
    Write-Host '2. 在手機上點開 Uban.apk，若出現「禁止安裝不明來源應用程式」，'
    Write-Host '   請依畫面指示允許該來源後再安裝。'
    Start-Process explorer.exe "/select,`"$apk`""
}

Write-Host '========================================'
Write-Host '        Uban 手機安裝程式'
Write-Host '========================================'
Write-Host ''

if (-not (Test-Path $apk) -or -not (Test-Path $adb)) {
    Write-Host '找不到 Uban.apk 或 adb，請重新執行 Uban_Setup.exe。' -ForegroundColor Red
    Pause-Exit 1
}

Write-Host '請確認：'
Write-Host '  ・手機已用 USB 線連接電腦，並在「開發人員選項」開啟「USB 偵錯」'
Write-Host '  ・或已啟動 Android 模擬器'
Write-Host ''

& $adb start-server 2>&1 | Out-Null

while ($true) {
    $lines   = & $adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match '\S' }
    $ready   = @($lines | Where-Object { $_ -match '\tdevice$' }       | ForEach-Object { ($_ -split '\t')[0] })
    $unauth  = @($lines | Where-Object { $_ -match '\tunauthorized$' } | ForEach-Object { ($_ -split '\t')[0] })

    if ($ready.Count -gt 0) { break }

    if ($unauth.Count -gt 0) {
        Write-Host '已偵測到手機，但尚未授權此電腦。' -ForegroundColor Yellow
        Write-Host '請在手機上出現的「允許 USB 偵錯嗎？」視窗按「允許」。'
    } else {
        Write-Host '沒有偵測到任何手機或模擬器。' -ForegroundColor Yellow
    }
    $ans = Read-Host '處理完後按 Enter 重新偵測；輸入 M 改用手動安裝'
    if ($ans -match '^[Mm]$') {
        Show-ManualGuide
        Pause-Exit 0
    }
}

$failed = 0
foreach ($serial in $ready) {
    $model = (& $adb -s $serial shell getprop ro.product.model 2>$null | Out-String).Trim()
    Write-Host ''
    Write-Host "正在安裝到 $model（$serial），約需 30 秒…"
    $out = (& $adb -s $serial install -r $apk 2>&1 | Out-String)

    if ($out -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
        # 手機上已有用其他電腦簽章編譯的 Uban（例如組員的開發版），簽章不同無法直接覆蓋
        Write-Host '手機上已裝有簽章不同的舊版 Uban，必須先移除才能安裝。' -ForegroundColor Yellow
        Write-Host '（移除後手機上的 Uban 登入狀態會清除，伺服器上的帳號與資料不受影響）'
        $ans = Read-Host '要移除舊版並重新安裝嗎？(Y/N)'
        if ($ans -match '^[Yy]$') {
            & $adb -s $serial uninstall $package 2>&1 | Out-Null
            $out = (& $adb -s $serial install -r $apk 2>&1 | Out-String)
        }
    }

    if ($out -match 'Success') {
        Write-Host "安裝成功：$model" -ForegroundColor Green
        & $adb -s $serial shell monkey -p $package -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
    } else {
        $failed++
        Write-Host "安裝失敗：$model" -ForegroundColor Red
        Write-Host $out.Trim()
    }
}

if ($failed -gt 0) {
    Show-ManualGuide
    Pause-Exit 1
}

Write-Host ''
Write-Host 'Uban 已安裝並開啟，請在手機上依畫面完成註冊或登入。' -ForegroundColor Green
Pause-Exit 0
