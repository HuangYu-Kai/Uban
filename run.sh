#!/bin/bash

# --- 0. Cleanup Previous Sessions ---
echo "[*] Cleaning up previous sessions..."
pkill -f "python server/app.py" 2>/dev/null
pkill -f "flutter run" 2>/dev/null
sleep 1

# --- 1. Connection Mode Selection ---
clear
echo "========================================"
echo "    Uban System Launch Menu (macOS)"
echo "========================================"
echo "[1] Local Development (Auto Detect 192.168.*)"
echo "[2] External Access (Manual Public IP)"
echo "[3] Remote Tunnel (Auto ngrok)"
echo "========================================"
read -p "Please select a connection mode [1-3]: " choice

if [ "$choice" == "2" ]; then
    read -p "Enter your Public IP: " localIP
    echo "[!] Using manual Server IP: $localIP"
elif [ "$choice" == "3" ]; then
    echo "[*] Starting ngrok tunnel on port 5001..."
    ngrok http 5001 > /dev/null &
    echo "[*] Waiting for ngrok to initialize (5s)..."
    sleep 5
    
    ngrok_url=$(curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*' | head -n 1 | sed 's/https:\/\///')
    if [ -z "$ngrok_url" ]; then
        echo "Error: Failed to get ngrok URL. Is ngrok running?"
        exit 1
    fi
    localIP=$ngrok_url
    echo "Detected ngrok URL: $localIP"
else
    echo "[*] Detecting Local IP..."
    localIP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | grep -E '^(192\.168\.|10\.)' | head -n 1)
    
    if [ -z "$localIP" ]; then
        localIP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)
    fi
    
    if [ -z "$localIP" ]; then
        localIP="10.0.2.2"
    fi
    echo "Detected Server IP: $localIP"
fi

# --- 2. Auto Setup Check ---
if [ ! -d "venv" ]; then
    echo "[!] Virtual environment (venv) not found. Starting auto-setup..."
    
    if ! command -v python3 &> /dev/null; then
        echo "Error: python3 is required but not found. Please install it."
        exit 1
    fi

    echo "Creating venv using python3..."
    python3 -m venv venv
    
    echo "Installing dependencies..."
    ./venv/bin/pip install -r server/requirements.txt
    echo "Setup complete!"
fi

# --- 3. Flutter Dependencies Check ---
echo "[*] Checking Flutter dependencies (flutter pub get)..."
cd mobile_app
flutter pub get
cd ..

# --- 4. Start Android Emulator ---
echo "[*] Checking Android Emulator..."
emulator_running=$(flutter devices 2>/dev/null | grep -i "emulator")

if [ -z "$emulator_running" ]; then
    echo "[*] No Android emulator detected. Starting one..."
    avd_name=$(emulator -list-avds | head -n 1)
    if [ -z "$avd_name" ]; then
        echo "Error: No AVD found. Please create one in Android Studio."
        exit 1
    fi
    echo "[*] Booting emulator: $avd_name"
    emulator -avd "$avd_name" -no-snapshot-load > /dev/null 2>&1 &

    echo "[*] Waiting for emulator to fully boot..."
    booted=false
    for i in $(seq 1 30); do
        boot_status=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
        if [ "$boot_status" == "1" ]; then
            booted=true
            break
        fi
        echo "    ... waiting ($i/30)"
        sleep 3
    done

    if [ "$booted" == false ]; then
        echo "Error: Emulator failed to boot in time."
        exit 1
    fi
    echo "✅ Emulator is ready."
else
    echo "✅ Emulator already running."
fi

# --- 5. Start Flask Backend ---
echo "[1/2] Launching Backend Server (Flask)..."
oldProc=$(lsof -ti :5001)
if [ ! -z "$oldProc" ]; then
    kill -9 $oldProc
fi

osascript -e "tell application \"Terminal\" to do script \"cd '$(pwd)'; ./venv/bin/python server/app.py\""

echo "[*] Waiting for backend to be ready..."
retryCount=0
backendReady=false
while [ $retryCount -lt 10 ]; do
    status=$(curl -s http://localhost:5001/api/health)
    if echo "$status" | grep -q "ok"; then
        backendReady=true
        break
    fi
    sleep 1
    ((retryCount++))
done

if [ "$backendReady" == false ]; then
    echo "Error: Backend failed to start properly. Please check the backend window."
    exit 1
fi
echo "✅ Backend is UP and running."

# --- 6. Start Flutter Frontend ---
echo "[2/2] Launching Frontend App (Flutter) with Server IP: $localIP"
if [[ $localIP == 169.254.* ]] || [[ $localIP == "127.0.0.1" ]]; then
    echo "[!] WARNING: Detected IP ($localIP) may not be reachable from mobile devices."
fi

osascript -e "tell application \"Terminal\" to do script \"cd '$(pwd)/mobile_app'; flutter run --dart-define=SERVER_IP=$localIP\""

echo "Uban is starting in separate windows!"
echo "Happy coding!"