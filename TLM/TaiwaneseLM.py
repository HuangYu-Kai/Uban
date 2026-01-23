import os
import shutil
import time
import requests
import urllib3
from openai import OpenAI
from gradio_client import Client, handle_file

# ==========================================
# 1. 設定區
# ==========================================

# ⚠️ 請填入您的 NVIDIA API Key
NVIDIA_API_KEY = "nvapi----------------------------------------------------" 

# TTS 服務網址
TTS_APP_URL = "https://tts.ivoice.tw:5003/"

# 官方參考音檔 (直接寫死，不依賴伺服器回傳)
FALLBACK_AUDIO_URL = "https://tts.ivoice.tw:5003/gradio_api/file=/home/tianyi/tts_taigi/gradio_cache/169345990328661d3035ba3c7e69d5ffb04bb34947acf44c22416982989c8bdc/文化相放伴_ep080_085_測試集.wav"
FALLBACK_TEXT = "ai3 tsu3- i3 an1- tsuan5 --ooh4 , a1- kong1 tshue1 tian7- hong1 , lin2 u7 oh8 --khi2- lai5 ah8 bo5 ?"
LOCAL_REF_AUDIO = "reference_audio.wav"

# 分隔符號
SEPARATOR = "###TL###"

# 全域變數
GLOBAL_CLIENT = None

# 忽略 SSL 警告
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ==========================================
# 2. 初始化與下載 (最穩健的寫法)
# ==========================================

def download_reference_file():
    """ 強制下載參考音檔 (Bypass SSL) """
    print("📥 正在檢查參考音檔...")
    
    # 如果檔案已經存在，就不用重新下載
    if os.path.exists(LOCAL_REF_AUDIO):
        print("✅ 參考音檔已存在 (本地快取)")
        return True

    print("☁️ 正在從網路下載參考音檔...")
    try:
        response = requests.get(FALLBACK_AUDIO_URL, verify=False, timeout=30)
        with open(LOCAL_REF_AUDIO, 'wb') as f:
            f.write(response.content)
        print("✅ 下載完成！")
        return True
    except Exception as e:
        print(f"❌ 參考音檔下載失敗: {e}")
        return False

def init_tts_system():
    """ 系統啟動時執行：下載檔案 + 建立 Client """
    global GLOBAL_CLIENT
    
    # 1. 先確保有檔案
    if not download_reference_file():
        return False

    # 2. 建立 Gradio Client (只做連線，不依賴 change_model 回傳的檔案)
    print("⚙️ 正在連線至意傳 TTS 伺服器...")
    try:
        GLOBAL_CLIENT = Client(TTS_APP_URL, ssl_verify=False)
        
        # 試著切換模型喚醒伺服器 (但我們不依賴它的回傳值)
        try:
            GLOBAL_CLIENT.predict(
                model_path="pretrained_For_Selection/台語模型",
                api_name="/change_model"
            )
            print("✅ 伺服器連線與模型切換成功！")
        except:
            print("⚠️ 模型切換回傳異常，但將嘗試繼續使用...")
        
        return True

    except Exception as e:
        print(f"❌ 無法連線至 TTS 伺服器: {e}")
        return False

# ==========================================
# 3. 語音合成
# ==========================================

def speak_taigi(text_romanized):
    """ 接收羅馬拼音並合成語音 """
    if not text_romanized or not text_romanized.strip():
        return

    if not GLOBAL_CLIENT or not os.path.exists(LOCAL_REF_AUDIO):
        print("⚠️ TTS 系統未就緒 (缺檔案或未連線)，略過合成。")
        return

    # print(f"DEBUG: 拼音輸入: {text_romanized}")
    
    try:
        # 直接使用我們自己下載好的 LOCAL_REF_AUDIO
        result_path = GLOBAL_CLIENT.predict(
            tts_text=text_romanized,
            mode_checkbox_group="3s極速覆刻",
            prompt_text=FALLBACK_TEXT,         # 使用我們寫死的文本
            prompt_wav_upload=handle_file(LOCAL_REF_AUDIO), # 使用我們下載好的檔案
            prompt_wav_record=None,
            instruct_text="Speak very slowly",
            seed=0,
            speed=1.0,
            enable_translation=False, # 關閉翻譯，唸拼音
            api_name="/generate"
        )

        final_filename = "ai_response.wav"
        
        # 解析回傳
        if isinstance(result_path, dict):
            result_path = result_path.get('path') or result_path.get('url')

        if result_path and os.path.exists(result_path):
            if os.path.exists(final_filename):
                try: os.remove(final_filename)
                except: pass 

            shutil.copy(result_path, final_filename)
            os.startfile(final_filename)
        else:
            print("❌ TTS 合成無回應")

    except Exception as e:
        print(f"❌ TTS 執行錯誤: {e}")
        # 如果連線斷了，嘗試重連一次 (簡易重試機制)
        # init_tts_system() 

# ==========================================
# 4. 主程式
# ==========================================

def main():
    client = OpenAI(
        base_url = "https://integrate.api.nvidia.com/v1",
        api_key = NVIDIA_API_KEY
    )

    system_prompt = f"""
    你是一個精通「臺灣閩南語（台語）」的 AI 助理。
    
    【回答規則】
    1. 必須使用「全漢字」或「漢羅混寫」回答。
    2. 回答結束後，加上 "{SEPARATOR}" 符號。
    3. 符號後方提供對應的「臺羅拼音 (Tâi-lô)」，聲調用數字標示。
    
    範例：
    這是你的雨傘。{SEPARATOR}Tse7 si7 li2 e5 hoo7-suann3.
    """

    conversation_history = [{"role": "system", "content": system_prompt}]

    print("=== 台語 AI 聊天室 (Robust 版) ===")
    
    # 🔥 啟動初始化
    if init_tts_system():
        print("✅ 系統準備就緒！請開始對話。\n")
    else:
        print("⚠️ 警告：語音系統故障，將只有文字回應。\n")

    while True:
        try:
            user_input = input("\n你：")
            if user_input.lower() in ["exit", "quit", "離開"]:
                print("AI：多謝，再會！")
                speak_taigi("To-sia7, tsai3-hue7!")
                time.sleep(3)
                break
            
            conversation_history.append({"role": "user", "content": user_input})

            completion = client.chat.completions.create(
                model="yentinglin/llama-3-taiwan-70b-instruct",
                messages=conversation_history,
                temperature=0.4,
                top_p=1,
                max_tokens=1024,
                stream=True
            )

            print("AI：", end="")
            full_response = ""
            is_printing = True

            for chunk in completion:
                if chunk.choices[0].delta.content is not None:
                    content = chunk.choices[0].delta.content
                    full_response += content
                    
                    if is_printing:
                        if SEPARATOR not in full_response:
                            print(content, end="", flush=True)
                        else:
                            if SEPARATOR in content:
                                print(content.split(SEPARATOR)[0], end="", flush=True)
                            is_printing = False

            print()

            conversation_history.append({"role": "assistant", "content": full_response})
            
            if SEPARATOR in full_response:
                parts = full_response.split(SEPARATOR)
                roman_part = parts[1].strip()
                if roman_part:
                    speak_taigi(roman_part)
            else:
                speak_taigi(full_response)
        
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"錯誤: {e}")

if __name__ == "__main__":
    main()