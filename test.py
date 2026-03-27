import asyncio
import websockets
from websockets.exceptions import InvalidStatus
import json
import uuid
import time

async def connect_to_openclaw():
    uri = "ws://127.0.0.1:18789"
    gateway_token = "e2a569c53ccf8c16ad08aa757982b804d419ac8e483f6ebf"
    
    # 補上 Origin 與 User-Agent，偽裝成從本地端 Web UI 發起的正常瀏覽器連線
    headers = {
        "Authorization": f"Bearer {gateway_token}",
        "Origin": "http://127.0.0.1:18789",  
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }

    print(f"🔄 嘗試連線至 {uri} ...")
    try:
        async with websockets.connect(uri, additional_headers=headers) as websocket:
            print("✅ WebSocket 底層連線成功，準備進行安全握手 (Handshake)...")

            # === [階段一：攔截 Challenge 並完成安全握手] ===
            # 1. 等待並接收伺服器的 challenge
            challenge_msg = await websocket.recv()
            challenge_data = json.loads(challenge_msg)
            
            if challenge_data.get("event") == "connect.challenge":
                nonce = challenge_data["payload"]["nonce"]
                print(f"🔐 收到安全挑戰 (Nonce): {nonce}")
                
                # 2. 構造符合 JSON-RPC 風格的回覆
                handshake_reply = {
                    "id": str(uuid.uuid4()),  # 加上唯一請求 ID
                    "type": "req",
                    "action": "connect",
                    "ts": int(time.time() * 1000), # 加上毫秒級時間戳記
                    "payload": {
                        "nonce": nonce
                    }
                }
                await websocket.send(json.dumps(handshake_reply))
                print("📤 已回覆 Challenge，等待伺服器解鎖通道...")

                # 3. 接收伺服器確認 (預期會收到 hello-ok 相關事件)
                ok_msg = await websocket.recv()
                print(f"✅ 通道解鎖成功！伺服器回應: {ok_msg}\n")
            else:
                print(f"⚠️ 收到未預期的初始訊息，握手失敗: {challenge_data}")
                return

            # === [階段二：發送實際 AI 任務] ===
            # 注意：這裡的格式也改為符合 JSON-RPC 風格 (type, action, payload)
            task_payload = {
                "type": "req",
                "action": "sendMessage",
                "payload": {
                    "message": "你好，請幫我總結今天的系統日誌",
                    "stream": True
                }
            }
            
            await websocket.send(json.dumps(task_payload))
            print(f"📤 已發送任務: 你好，請幫我總結今天的系統日誌\n")

            # === [階段三：持續監聽回覆] ===
            print("📥 正在等待 Agent 回覆...")
            while True:
                response = await websocket.recv()
                data = json.loads(response)
                
                # 印出所有的回傳資料，方便你觀察 OpenClaw 實際的資料結構
                print(f"💬 收到訊息: {data}")
                
                # 若收到最終結果，則結束迴圈
                if data.get("type") == "res" and data.get("status") in ["completed", "error"]:
                    print(f"\n🎉 任務結束！")
                    break

    except websockets.exceptions.ConnectionClosedError as e:
        print(f"❌ 連線被強制中斷 (狀態碼 {e.code}): {e.reason}")
    except Exception as e:
        print(f"⚠️ 發生未預期錯誤: {e}")

if __name__ == "__main__":
    asyncio.run(connect_to_openclaw())