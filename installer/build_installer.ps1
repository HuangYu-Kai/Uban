# Uban 安裝程式一鍵重建
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File build_installer.ps1 [-SkipApk]
param([switch]$SkipApk)
$ErrorActionPreference = 'Stop'

$here   = $PSScriptRoot
$app    = Join-Path $here '..\mobile_app'
$app    = (Resolve-Path $app).Path
$apkSrc = Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk'

# (a) 編譯 APK
if (-not $SkipApk) {
    Write-Host '== 編譯 release APK ==' -ForegroundColor Cyan
    Push-Location $app
    try {
        & flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw 'flutter build apk 失敗' }
    } finally { Pop-Location }
}
if (-not (Test-Path $apkSrc)) { throw "找不到 APK：$apkSrc" }

# (b) 準備 payload
Write-Host '== 準備 payload ==' -ForegroundColor Cyan
$payload = Join-Path $here 'payload'
if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
$ptDst = Join-Path $payload 'platform-tools'
New-Item -ItemType Directory -Path $ptDst -Force | Out-Null
Copy-Item $apkSrc (Join-Path $payload 'Uban.apk')

$sdk = $null
$lp = Join-Path $app 'android\local.properties'
if (Test-Path $lp) {
    $line = Get-Content $lp | Where-Object { $_ -match '^\s*sdk\.dir\s*=' } | Select-Object -First 1
    if ($line) { $sdk = ($line -replace '^\s*sdk\.dir\s*=', '').Trim() -replace '\\', '\' -replace '\:', ':' }
}
if (-not $sdk -or -not (Test-Path $sdk)) { $sdk = Join-Path $env:LOCALAPPDATA 'Android\sdk' }
$pt = Join-Path $sdk 'platform-tools'
if (-not (Test-Path (Join-Path $pt 'adb.exe'))) { throw "找不到 adb.exe：$pt" }
foreach ($f in 'adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll','libwinpthread-1.dll','NOTICE.txt') {
    $p = Join-Path $pt $f
    if (Test-Path $p) { Copy-Item $p $ptDst } elseif ($f -in 'adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll') { throw "缺少 $f" }
}

# (c) 編譯安裝程式
Write-Host '== 編譯 Inno Setup ==' -ForegroundColor Cyan
$iscc = $null
$cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($cmd) { $iscc = $cmd.Source }
if (-not $iscc) {
    foreach ($d in (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6'), (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6')) {
        $c = Join-Path $d 'ISCC.exe'
        if (Test-Path $c) { $iscc = $c; break }
    }
}
if (-not $iscc) { throw '找不到 ISCC.exe，請先安裝 Inno Setup 6' }
Push-Location $here
try {
    & $iscc 'Uban_Setup.iss'
    if ($LASTEXITCODE -ne 0) { throw 'ISCC 編譯失敗' }
} finally { Pop-Location }

# (d) 結果
$out = Get-ChildItem (Join-Path $here 'Output') -Filter 'Uban_Setup_*.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host ''
Write-Host ("產物：{0}" -f $out.FullName) -ForegroundColor Green
Write-Host ("大小：{0:N1} MB" -f ($out.Length / 1MB))
