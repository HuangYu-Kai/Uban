import urllib.request
import urllib.error
import json

data = json.dumps({
    "family_id": 1,
    "code": "5726",
    "elder_name": "周宇璿",
    "gender": "M",
    "age": 86
}).encode('utf-8')

req = urllib.request.Request('http://127.0.0.1:8000/api/pairing/confirm', data=data, headers={"Content-Type": "application/json"})

try:
    with urllib.request.urlopen(req) as response:
        print("Success:", response.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print("Error:", e.code)
    try:
        print(e.read().decode('utf-8'))
    except Exception as inner_e:
        print("Could not read response body:", inner_e)
except Exception as e:
    print("Other error:", e)
