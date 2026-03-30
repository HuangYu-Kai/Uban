import requests
import time

BASE_URL = "http://127.0.0.1:5000"

def test_check_reset():
    print("Testing /api/game/check_reset with force=True")
    try:
        response = requests.post(f"{BASE_URL}/api/game/check_reset", json={"force": True})
        print(f"Status: {response.status_code}")
        print(f"Response: {response.json()}")
    except requests.exceptions.RequestException as e:
        print(f"Request failed: {e}")

if __name__ == "__main__":
    test_check_reset()
