import asyncio
import edge_tts
import os
import pygame
import time

# === 設定區 ===
# 這裡不需要 Key，也不用選地區，直接指定聲音名稱即可
# 女聲：nan-TW-HsiaoYuNeural
# 男聲：nan-TW-YunJheNeural
VOICE = "nan-TW-HsiaoYuNeural"

async def speak_taigi_edge(text_hanji):
    print(f"正在合成台語 (使用 Edge 引擎)：{text_hanji} ...")
    
    output_file = "taigi_edge.mp3"
    
    # 1. 建立溝通物件
    communicate = edge_tts.Communicate(text_hanji, VOICE)
    
    # 2. 存檔
    await communicate.save(output_file)
    
    print(f"✅ 合成成功！檔案已儲存：{os.path.abspath(output_file)}")
    
    # 3. 播放聲音 (使用 pygame 比較穩定)
    play_audio(output_file)

def play_audio(file_path):
    print("🎵 正在播放...")
    try:
        pygame.mixer.init()
        pygame.mixer.music.load(file_path)
        pygame.mixer.music.play()
        
        # 等待播放完畢
        while pygame.mixer.music.get_busy():
            time.sleep(0.1)
            
        pygame.mixer.quit() # 釋放資源
        
        # 播放完刪除檔案 (可選)
        # os.remove(file_path) 
        
    except Exception as e:
        print(f"播放失敗，請手動開啟檔案: {e}")
        # 如果 pygame 失敗，嘗試用系統預設播放器
        os.startfile(file_path)

# === 測試區 ===
# 這是 Llama-3 的台語回答
ai_response = "這幾工雨落甲真濟，出門愛記得帶雨傘，無者會淋甲落湯雞。"

if __name__ == "__main__":
    # 因為 edge-tts 是非同步的 (async)，所以要用這行來執行
    asyncio.run(speak_taigi_edge(ai_response))