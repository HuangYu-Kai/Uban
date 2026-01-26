import asyncio
import edge_tts

async def generate_elder_speech(text, output_file, voice="zh-TW-HsiaoChenNeural"):
    # rate="-30%" 代表減慢 30% 語速，非常適合長輩
    # pitch="+0Hz" 維持原音高
    communicate = edge_tts.Communicate(text, voice, rate="-30%")
    await communicate.save(output_file)
    print(f"語音已存檔: {output_file}")

# --- 測試中文 ---
text_zh = "張伯伯您好，今天天氣變冷了，記得多穿一件外套，藥記得吃喔。"
asyncio.run(generate_elder_speech(text_zh, "elder_zh.mp3", voice="zh-TW-HsiaoChenNeural"))