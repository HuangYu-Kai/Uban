#!/bin/bash

# --- 0. Cleanup Previous Sessions ---
echo "[*] Cleaning up previous sessions..."
pkill -f "flutter run" 2>/dev/null
sleep 1

# --- 1. Connection Mode Selection ---
clear
echo "========================================"
echo "    Uban System Launch Menu (macOS)"
echo "========================================"
echo "[1] Tailscale Funnel (Remote FastAPI)"
echo "[2] Custom Server URL"
echo "========================================"
read -p "Please select a connection mode [1-2]: " choice

if [ "$choice" == "2" ]; then
    read -p "Enter your Server URL: " serverURL
    echo "[!] Using custom Server URL: $serverURL"
else
    serverURL="localhost-0.tail5abf5e.ts.net"
    echo "[*] Using Tailscale Funnel: $serverURL"
fi

# --- 2. Local Python Environment Setup ---
echo "[*] Checking local Python environment (for test scripts)..."
if [ ! -d "venv" ] && [ ! -d ".venv" ]; then
    echo "[!] Virtual environment not found. Creating venv..."

    if ! command -v python3 &> /dev/null; then
        echo "Error: python3 is required but not found. Please install it."
        exit 1
    fi

    python3 -m venv venv
    echo "Installing dependencies from server/requirements.txt..."
    ./venv/bin/pip install -r server/requirements.txt
    echo "✅ Virtual environment setup complete!"
else
    echo "✅ Virtual environment found (venv or .venv)"
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

# --- 5. Check Remote Backend Connection ---
echo "[*] Checking remote FastAPI backend connection..."
retryCount=0
backendReady=false
while [ $retryCount -lt 5 ]; do
    status=$(curl -s -k https://$serverURL/)
    if echo "$status" | grep -q "Uban API"; then
        backendReady=true
        break
    fi
    sleep 1
    ((retryCount++))
done

if [ "$backendReady" == false ]; then
    echo "⚠️  Warning: Cannot reach remote backend at https://$serverURL"
    echo "    Please ensure Tailscale Funnel is running on the server."
    read -p "Continue anyway? [y/N]: " continue_choice
    if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
        exit 1
    fi
else
    echo "✅ Remote backend is reachable at https://$serverURL"
fi

# --- 6. Start Flutter Frontend ---
echo "[*] Launching Frontend App (Flutter) with Server URL: $serverURL"

osascript -e "tell application \"Terminal\" to do script \"cd '$(pwd)/mobile_app'; flutter run --dart-define=SERVER_IP=$serverURL\""

echo ""
echo "========================================"
echo "✅ Uban Frontend is launching!"
echo "📡 Backend: https://$serverURL"
echo "========================================"
echo "Happy coding!"