$root = $PSScriptRoot

# --- 0. Cleanup Previous Sessions ---
Write-Host "[*] Cleaning up previous sessions..." -ForegroundColor Gray
Stop-Process -Name "python", "ngrok" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# --- 1. Connection Mode Selection ---
Clear-Host
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "    Uban System Launch Menu" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "[1] Local Development (Auto Detect 192.168.*)"
Write-Host "[2] External Access (Manual Public IP)"
Write-Host "[3] Remote Tunnel (Auto ngrok)"
Write-Host "========================================" -ForegroundColor Yellow
$choice = Read-Host "Please select a connection mode [1-3]"

if ($choice -eq "2") {
    $localIP = Read-Host "Enter your Public IP"
    Write-Host "[!] Using manual Server IP: $localIP" -ForegroundColor Yellow
} 
elseif ($choice -eq "3") {
    Write-Host "[*] Starting ngrok tunnel on port 5001..." -ForegroundColor Gray
    Start-Process ngrok -ArgumentList "http 5001" -WindowStyle Minimized
    
    Write-Host "[*] Waiting for ngrok to initialize (5s)..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
    
    # Extract ngrok URL from local API
    try {
        $ngrokData = Invoke-RestMethod -Uri "http://localhost:4040/api/tunnels"
        $localIP = $ngrokData.tunnels[0].public_url.Replace("https://", "").Replace("http://", "")
        Write-Host "Detected ngrok URL: $localIP" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to get ngrok URL. Is ngrok running?"
        exit
    }
}
else {
    Write-Host "[*] Detecting Local IP..." -ForegroundColor Gray
    $allIPs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
        $_.InterfaceAlias -notlike "*Loopback*" -and 
        $_.InterfaceAlias -notlike "*VirtualBox*" -and 
        $_.InterfaceAlias -notlike "*VMware*" -and
        $_.IPAddress -notlike "169.254.*" -and
        $_.IPAddress -notlike "26.*" 
    }
    
    $localIP = ($allIPs | Where-Object { $_.IPAddress -like "192.168.*" -or $_.IPAddress -like "10.*" } | Select-Object -ExpandProperty IPAddress -First 1)
    if (-not $localIP) { $localIP = $allIPs[0].IPAddress }
    if (-not $localIP) { $localIP = "10.0.2.2" }
    
    Write-Host "Detected Server IP: $localIP" -ForegroundColor Cyan
}

# ------------------------------------

# --- 2. Auto Setup Check ---
if (-not (Test-Path "$root\venv")) {
    Write-Host "[!] Virtual environment (venv) not found. Starting auto-setup..." -ForegroundColor Magenta
    
    # Check if Python 3.12 is available
    $pyCheck = py --list | Select-String "3.12"
    if (-not $pyCheck) {
        Write-Error "Python 3.12 is required but not found on your system. Please install it first."
        exit
    }

    Write-Host "Creating venv using Python 3.12..." -ForegroundColor Gray
    py -3.12 -m venv venv
    
    Write-Host "Installing dependencies from server\requirements.txt..." -ForegroundColor Gray
    .\venv\Scripts\python.exe -m pip install -r "$root\server\requirements.txt"
    
    Write-Host "Setup complete!`n" -ForegroundColor Green
}

# --- 3. Flutter Dependencies Check ---
Write-Host "[*] Checking Flutter dependencies (flutter pub get)..." -ForegroundColor Gray
Set-Location "$root\mobile_app"
flutter pub get
Set-Location "$root"

# --- 4. Start Flask Backend ---
Write-Host "[1/2] Launching Backend Server (Flask)..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$root'; .\venv\Scripts\python.exe server\app.py"

# --- 5. Start Flutter Frontend ---
Write-Host "[2/2] Launching Frontend App (Flutter) with Server IP: $localIP" -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$root\mobile_app'; flutter run --dart-define=SERVER_IP=$localIP"

Write-Host "`nUban is starting in separate windows!" -ForegroundColor Yellow
Write-Host "Happy coding!" -ForegroundColor Gray
