import os
import shutil
import time
import requests
import urllib3
import datetime
from openai import OpenAI
from gradio_client import Client, handle_file

# ==========================================
# 1. 設定區
# ==========================================

# ⚠️ 請填入您的 NVIDIA API Key
NVIDIA_API_KEY = "-----" 

# TTS 服務網址與備用檔案
TTS_APP_URL = "https://tts.ivoice.tw:5003/"
FALLBACK_AUDIO_URL = "https://tts.ivoice.tw:5003/gradio_api/file=/home/tianyi/tts_taigi/gradio_cache/169345990328661d3035ba3c7e69d5ffb04bb34947acf44c22416982989c8bdc/文化相放伴_ep080_085_測試集.wav"
FALLBACK_TEXT = "ai3 tsu3- i3 an1- tsuan5 --ooh4 , a1- kong1 tshue1 tian7- hong1 , lin2 u7 oh8 --khi2- lai5 ah8 bo5 ?"
LOCAL_REF_AUDIO = "reference_audio.wav"

# 分隔符號
SEPARATOR = "###TL###"

# 全域變數
GLOBAL_CLIENT = None
GLOBAL_REF_AUDIO = None
GLOBAL_REF_TEXT = None

# 忽略 SSL 警告
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ==========================================
# 2. 系統初始化 (雙重保險機制)
# ==========================================

def download_fallback_file():
    """ 強制下載官方音檔到本地 """
    if os.path.exists(LOCAL_REF_AUDIO):
        return True
    print("📥 正在下載備用參考音檔...")
    try:
        response = requests.get(FALLBACK_AUDIO_URL, verify=False, timeout=30)
        with open(LOCAL_REF_AUDIO, 'wb') as f:
            f.write(response.content)
        return True
    except Exception as e:
        print(f"❌ 下載失敗: {e}")
        return False

def init_tts_system():
    global GLOBAL_CLIENT, GLOBAL_REF_AUDIO, GLOBAL_REF_TEXT
    
    # 1. 先把備用檔案準備好 (保命符)
    download_fallback_file()
    
    print("⚙️ 正在連線 TTS 系統...")
    try:
        GLOBAL_CLIENT = Client(TTS_APP_URL, ssl_verify=False)
        
        # 2. 嘗試動態切換模型
        try:
            result = GLOBAL_CLIENT.predict(
                model_path="pretrained_For_Selection/台語模型",
                api_name="/change_model"
            )
            # 嘗試抓取伺服器回傳的音檔
            raw_audio = result[2]
            if isinstance(raw_audio, dict):
                server_audio = raw_audio.get('path') or raw_audio.get('url')
            else:
                server_audio = raw_audio
            
            # 3. 判斷：如果伺服器給的檔案有效，就用伺服器的；否則用本地備份
            if server_audio:
                GLOBAL_REF_AUDIO = server_audio
                print("✅ 使用伺服器提供的參考音檔")
            else:
                raise ValueError("伺服器回傳空值")
                
            GLOBAL_REF_TEXT = result[3]

        except Exception as e:
            print(f"⚠️ 動態取得參考音檔失敗 ({e})，切換至本地備用方案...")
            # === 備用方案啟動 ===
            GLOBAL_REF_AUDIO = LOCAL_REF_AUDIO
            GLOBAL_REF_TEXT = FALLBACK_TEXT
            print(f"✅ 已切換使用本地音檔: {LOCAL_REF_AUDIO}")

        return True

    except Exception as e:
        print(f"❌ TTS 系統連線徹底失敗: {e}")
        return False

# ==========================================
# 3. 語音合成
# ==========================================

def speak_taigi_pinyin(romanized_text):
    if not romanized_text or not romanized_text.strip(): return
    romanized_text = romanized_text.replace("\n", " ").strip()

    # 再次檢查音檔是否存在
    final_ref_audio = GLOBAL_REF_AUDIO
    # 如果是用本地檔案，要確保路徑正確傳入
    if final_ref_audio == LOCAL_REF_AUDIO:
        if not os.path.exists(LOCAL_REF_AUDIO):
            print("❌ 找不到本地參考音檔，無法發音")
            return
    
    if not GLOBAL_CLIENT:
        print("⚠️ TTS Client 未連線")
        return

    try:
        timestamp = datetime.datetime.now().strftime("%H%M%S%f")
        final_filename = f"response_{timestamp}.wav"

        # print(f"[DEBUG] 發音內容: {romanized_text}")
        
        result_path = GLOBAL_CLIENT.predict(
            tts_text=romanized_text,
            mode_checkbox_group="3s極速覆刻",
            prompt_text=GLOBAL_REF_TEXT,
            # 這裡 handle_file 會自動處理網址或本地路徑
            prompt_wav_upload=handle_file(final_ref_audio), 
            prompt_wav_record=None,
            instruct_text="Speak very slowly",
            seed=0,
            speed=1.0,
            enable_translation=False, # 關閉翻譯，唸拼音
            api_name="/generate"
        )

        if isinstance(result_path, dict):
            result_path = result_path.get('path') or result_path.get('url')

        if result_path and os.path.exists(result_path):
            shutil.copy(result_path, final_filename)
            os.startfile(final_filename)
            time.sleep(0.2)
        else:
            print("❌ TTS 合成無檔案")

    except Exception as e:
        print(f"❌ 發音錯誤: {e}")

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
    
    【規則】
    1. 前半段：請用「繁體華語」回答，不要出現拼音。
    2. 分隔符：回答結束後，必須換行並加上 "{SEPARATOR}"，再換行。
    3. 後半段：將前半段翻譯成「臺羅拼音 (Tâi-lô)」。
       - 只要給拼音就好，不要加任何解釋文字。
       - 聲調用數字 (1-8)。
    
    範例：
    你好，很高興認識你。
    {SEPARATOR}
    Li2 ho2, tsin1 huan-hi2 jin7-bat4 li2.
    """

    conversation_history = [{"role": "system", "content": system_prompt}]

    print("=== 台語 AI 聊天室 (Hybrid Final) ===")
    
    if init_tts_system():
        print("✅ 語音系統就緒！\n")
    else:
        print("⚠️ 語音系統故障。\n")

    while True:
        try:
            user_input = input("\n你：")
            if user_input.lower() in ["exit", "quit", "離開"]:
                speak_taigi_pinyin("To-sia7, tsai3-hue7!")
                time.sleep(3)
                break
            
            conversation_history.append({"role": "user", "content": user_input})

            completion = client.chat.completions.create(
                model="yentinglin/llama-3-taiwan-70b-instruct",
                messages=conversation_history,
                temperature=0.3, # 溫度調低，格式較穩
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
                # 使用 split，並確保有取到後半段
                parts = full_response.split(SEPARATOR)
                if len(parts) > 1:
                    pinyin_part = parts[1].strip()
                    speak_taigi_pinyin(pinyin_part)
                else:
                    print("(AI 未產生完整拼音)")
            else:
                pass 
                # print("(未偵測到分隔符號)")
        
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"錯誤: {e}")

if __name__ == "__main__":
    main()