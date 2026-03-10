import socket
import requests

def check_port(ip, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2)
    try:
        s.connect((ip, port))
        return True
    except:
        return False
    finally:
        s.close()

def get_ips():
    return socket.gethostbyname_ex(socket.gethostname())[2]

if __name__ == "__main__":
    port = 5001
    print(f"--- Uban Backend Diagnostic ---")
    print(f"Checking port {port} on all local interfaces...\n")
    
    found_any = False
    for ip in get_ips():
        status = "OPEN" if check_port(ip, port) else "CLOSED"
        print(f"Interface IP: {ip:<15} | Status: {status}")
        if status == "OPEN":
            found_any = True
            try:
                r = requests.get(f"http://{ip}:{port}/api/health", timeout=2)
                print(f"  -> Health Check: {r.status_code} {r.json()}")
            except Exception as e:
                print(f"  -> Health Check: FAILED ({e})")
    
    print("\nNext Steps:")
    if not found_any:
        print("1. Your backend server might not be running. Run .\\run.ps1 first.")
    else:
        print("1. Your backend is running locally.")
        print("2. Check if your router's Port Forwarding (5001) points to the correct 'Interface IP' above.")
        print("3. Ensure Windows Firewall allows 'Inbound' traffic on TCP 5001.")
