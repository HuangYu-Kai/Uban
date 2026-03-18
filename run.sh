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
    
    # Extract ngrok URL from local API
    ngrok_url=$(curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*' | head -n 1 | sed 's/https:\/\///')
    if [ -z "$ngrok_url" ]; then
        echo "Error: Failed to get ngrok URL. Is ngrok running?"
        exit 1
    fi
    localIP=$ngrok_url
    echo "Detected ngrok URL: $localIP"
else
    echo "[*] Detecting Local IP..."
    # macOS typical IP detection for 192.168.* or 10.*
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
if [ ! -d ".venv" ]; then
    echo "[!] Virtual environment (venv) not found. Starting auto-setup..."
    
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        echo "Error: python3 is required but not found. Please install it."
        exit 1
    fi

    echo "Creating .venv using python3..."
    python3 -m .venv venv
    
    echo "Installing dependencies..."
    ./.venv/bin/pip install -r server/requirements.txt
    echo "Setup complete!"
fi

# --- 3. Flutter Dependencies Check ---
echo "[*] Checking Flutter dependencies (flutter pub get)..."
cd mobile_app
flutter pub get
cd ..

# --- 4. Start Flask Backend ---
echo "[1/2] Launching Backend Server (Flask)..."
# Kill any existing process on port 5001
oldProc=$(lsof -ti :5001)
if [ ! -z "$oldProc" ]; then
    kill -9 $oldProc
fi

# Launch backend in a new Terminal window (macOS specific)
osascript -e "tell application \"Terminal\" to do script \"cd '$(pwd)'; ./venv/bin/python server/app.py\""

# Wait for backend to be ready
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

# --- 5. Start Flutter Frontend ---
echo "[2/2] Launching Frontend App (Flutter) with Server IP: $localIP"
if [[ $localIP == 169.254.* ]] || [[ $localIP == "127.0.0.1" ]]; then
    echo "[!] WARNING: Detected IP ($localIP) may not be reachable from mobile devices."
fi

# Launch flutter in a new Terminal window
osascript -e "tell application \"Terminal\" to do script \"cd '$(pwd)/mobile_app'; flutter run --dart-define=SERVER_IP=$localIP\""

echo "Uban is starting in separate windows!"
echo "Happy coding!"