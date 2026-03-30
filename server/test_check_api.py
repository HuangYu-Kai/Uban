import urllib.request
import json
import ssl

def check_update_steps():
    data = {"elder_id": "AAAA", "delta_steps": 10}
    req = urllib.request.Request("http://127.0.0.1:5000/api/game/elder/update_steps", data=json.dumps(data).encode('utf-8'), headers={'Content-Type': 'application/json'})
    try:
        response = urllib.request.urlopen(req)
        print("update_steps response:", response.read().decode())
        
        req2 = urllib.request.Request("http://127.0.0.1:5000/api/game/elder_status/AAAA")
        resp2 = urllib.request.urlopen(req2)
        print("elder_status response:", resp2.read().decode())
    except Exception as e:
        print("Error:", e)

if __name__ == "__main__":
    check_update_steps()
