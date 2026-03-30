#!/usr/bin/env python3
"""
Uban 視訊通話模擬撥話腳本 (Fake Caller)
========================================
用途：模擬「家屬端」撥打視訊電話給模擬器上的 App。
      App 端會收到來電彈窗，你可以測試接聽/拒接流程。

用法：
    python3 test_call_simulator.py [ROOM_ID]

    ROOM_ID = 長輩的 user_id（配對後的數字 ID）
    若不指定，預設為互動式輸入。

環境：
    pip install python-socketio[asyncio_client] websockets
"""

import asyncio
import sys
import socketio

# ======================== 設定區 ========================
# 後端伺服器 URL（改成你的 uban-api 位址）
SERVER_URL = "https://localhost-0.tail5abf5e.ts.net"

# 模擬的撥話者資訊
CALLER_ROLE = "family"
CALLER_DEVICE_NAME = "TestCaller_PC"
CALLER_USER_ID = 9999  # 假的 user_id
# ========================================================

sio = socketio.AsyncClient(
    reconnection=False,
    logger=False,
    engineio_logger=False,
    ssl_verify=False,
)


@sio.event
async def connect():
    print(f"✅ 已連線到伺服器 (SID: {sio.sid})")


@sio.event
async def connect_error(data):
    print(f"❌ 連線失敗: {data}")


@sio.event
async def disconnect():
    print("⚠️ 已斷開連線")


@sio.on("call-accept")
async def on_call_accept(data):
    accepter_id = data.get("accepterId")
    call_id = data.get("callId")
    print(f"\n🎉🎉🎉 對方已接聽！ (AccepterId: {accepter_id}, CallId: {call_id})")
    print("    ✅ call-accept 信令通過！")
    print("    （模擬端不會建立 WebRTC，所以通話不會有影像）")
    print("    按 Ctrl+C 結束測試\n")


@sio.on("call-busy")
async def on_call_busy(data):
    print(f"\n🚫 對方拒接或忙線中 (data: {data})")
    print("    ✅ call-busy 信令通過！")
    await sio.disconnect()


@sio.on("end-call")
async def on_end_call(data):
    print(f"\n📴 對方已掛斷 (data: {data})")
    print("    ✅ end-call 信令通過！")
    await sio.disconnect()


@sio.on("elder-devices-update")
async def on_elder_devices_update(data):
    print(f"\n📡 收到長輩設備列表更新 (共 {len(data)} 台設備):")
    for dev in data:
        status = "🟢 在線" if dev.get("isOnline") else "⚪ 離線"
        mode = dev.get("deviceMode", "comm")
        print(f"    {status} {dev.get('deviceName', 'Unknown')} ({mode}) [id: {dev.get('id', '?')}]")


@sio.on("user-joined")
async def on_user_joined(data):
    print(f"👤 有人加入房間: {data.get('deviceName')} ({data.get('role')})")


async def main():
    # 取得 Room ID
    if len(sys.argv) > 1:
        room_id = sys.argv[1]
    else:
        room_id = input("請輸入房間 ID (= 長輩的 user_id): ").strip()
        if not room_id:
            print("❌ 需要提供房間 ID")
            return

    print(f"\n{'='*50}")
    print(f"  Uban 視訊通話模擬器")
    print(f"  伺服器: {SERVER_URL}")
    print(f"  房間: {room_id}")
    print(f"  角色: {CALLER_ROLE} (模擬家屬)")
    print(f"{'='*50}\n")

    # 1. 連線
    print("🔌 正在連線到伺服器...")
    try:
        await sio.connect(SERVER_URL, transports=["websocket"])
    except Exception as e:
        print(f"❌ 無法連線: {e}")
        print("   請確認 uban-api 後端是否已啟動，且 URL 正確")
        return

    # 2. 加入房間
    print(f"📢 加入房間 {room_id}...")
    await sio.emit("join", {
        "room": room_id,
        "role": CALLER_ROLE,
        "deviceName": CALLER_DEVICE_NAME,
        "deviceMode": "comm",
        "userId": CALLER_USER_ID,
        "fcmToken": None,
    })
    await asyncio.sleep(2)  # 等待 join 完成 + 收設備列表

    # 3. 互動選單
    while sio.connected:
        print("\n" + "─" * 40)
        print("  [1] 📞 發送 call-request（一般通話）")
        print("  [2] 🚨 發送 emergency-call（緊急通話）")
        print("  [3] 🔕 發送 cancel-call（取消呼叫）")
        print("  [4] 📡 查詢長輩設備列表")
        print("  [5] 📴 掛斷 (end-call)")
        print("  [q] 離開")
        print("─" * 40)

        try:
            choice = await asyncio.get_event_loop().run_in_executor(
                None, lambda: input("選擇操作 > ").strip()
            )
        except (EOFError, KeyboardInterrupt):
            break

        if choice == "1":
            print("📞 發送 call-request...")
            await sio.emit("call-request", {
                "room": room_id,
                "role": CALLER_ROLE,
                "callerUserId": CALLER_USER_ID,
            })
            print("   ✅ 已發送！等待對方回應...")

        elif choice == "2":
            print("🚨 發送 emergency-call...")
            await sio.emit("emergency-call", {
                "room": room_id,
                "role": CALLER_ROLE,
            })
            print("   ✅ 已發送緊急通話！")

        elif choice == "3":
            print("🔕 發送 cancel-call...")
            await sio.emit("cancel-call", {
                "room": room_id,
                "role": CALLER_ROLE,
            })
            print("   ✅ 已取消呼叫")

        elif choice == "4":
            print("📡 查詢設備列表...")
            await sio.emit("get-elder-devices", room_id)
            await asyncio.sleep(1)

        elif choice == "5":
            print("📴 發送 end-call...")
            await sio.emit("end-call", {
                "room": room_id,
            })
            print("   ✅ 已掛斷")

        elif choice.lower() == "q":
            break

    # 清理
    if sio.connected:
        await sio.disconnect()
    print("\n👋 測試結束")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n👋 已手動中斷")
