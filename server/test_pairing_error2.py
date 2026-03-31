import urllib.request
import urllib.error
import urllib.parse
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

data = json.dumps({
    "family_id": 1,
    "code": "5726",
    "elder_name": "周宇璿",
    "gender": "M",
    "age": 86
}).encode('utf-8')

req = urllib.request.Request('https://localhost-0.tail5abf5e.ts.net/api/pairing/confirm', data=data, headers={"Content-Type": "application/json"})

try:
    with urllib.request.urlopen(req, context=ctx) as response:
        print("Success:", response.read().decode('utf-8'))
except urllib.error.HTTPError as e:
    print("Error:", e.code)
    try:
        print(e.read().decode('utf-8'))
    except Exception as inner_e:
        print("Could not read response body:", inner_e)
except Exception as e:
    print("Other error:", e)
