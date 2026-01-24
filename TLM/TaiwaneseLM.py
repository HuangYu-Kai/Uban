import os
import shutil
import time
import urllib3
import datetime
from openai import OpenAI
from gradio_client import Client, handle_file

# ==========================================
# 1. 設定區
# ==========================================

# ⚠️ 請填入您的 NVIDIA API Key
NVIDIA_API_KEY = "nvapi-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" 

# TTS 服務網址
TTS_APP_URL = "https://tts.ivoice.tw:5003/"

# 分隔符號 (用來切分 華語顯示 與 台語拼音)
SEPARATOR = "###TL###"

# 全域變數：儲存從伺服器動態取得的參數
GLOBAL_CLIENT = None
GLOBAL_REF_AUDIO = None
GLOBAL_REF_TEXT = None

# 忽略 SSL 警告 (必要，因為該伺服器憑證為自簽)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ==========================================
# 2. TTS 模型初始化 (依照您的要求修改)
# ==========================================

def init_tts_system():
    """
    連線到 Gradio Server，並執行 /change_model 
    以取得正確的參考音檔路徑與參考文本。
    """
    global GLOBAL_CLIENT, GLOBAL_REF_AUDIO, GLOBAL_REF_TEXT
    
    print("⚙️ 正在初始化 TTS 系統 (執行 /change_model)...")
    
    try:
        # 1. 建立連線 (ssl_verify=False 避開憑證錯誤)
        GLOBAL_CLIENT = Client(TTS_APP_URL, ssl_verify=False)
        
        # 2. 切換模型 (這是您指定要用的程式碼)
        result = GLOBAL_CLIENT.predict(
            model_path="pretrained_For_Selection/台語模型",
            api_name="/change_model"
        )
        
        # print("DEBUG Result:", result) # 除錯用
        
        # 3. 解析回傳資料
        # 根據 API 定義：
        # result[2] = prompt_wav (參考音訊)
        # result[3] = prompt_text (參考文本)
        
        raw_audio = result[2]
        
        # 處理 Gradio 新舊版本回傳格式差異 (字串 vs 字典)
        if isinstance(raw_audio, dict):
            GLOBAL_REF_AUDIO = raw_audio.get('path') or raw_audio.get('url')
        else:
            GLOBAL_REF_AUDIO = raw_audio
            
        GLOBAL_REF_TEXT = result[3]

        print("✅ TTS 模型設定完成！")
        print(f"   - 參考音檔: {os.path.basename(GLOBAL_REF_AUDIO) if GLOBAL_REF_AUDIO else 'None'}")
        return True

    except Exception as e:
        print(f"❌ TTS 初始化失敗: {e}")
        return False

# ==========================================
# 3. 語音合成 (只接收拼音)
# ==========================================

def speak_taigi_pinyin(romanized_text):
    """
    接收羅馬拼音 -> 傳給 TTS -> 播放
    """
    # 簡單防呆與清洗
    if not romanized_text or not romanized_text.strip():
        return
    
    # 移除可能存在的換行符號，避免 API 誤判
    romanized_text = romanized_text.replace("\n", " ").strip()

    if not GLOBAL_CLIENT or not GLOBAL_REF_AUDIO:
        print("⚠️ TTS 未就緒，略過發音。")
        return

    # print(f"[DEBUG] 傳送拼音給 TTS: {romanized_text}")

    try:
        # 產生唯一檔名，避免截斷問題
        timestamp = datetime.datetime.now().strftime("%H%M%S%f")
        final_filename = f"response_{timestamp}.wav"

        result_path = GLOBAL_CLIENT.predict(
            tts_text=romanized_text,  # 這裡傳入全拼音
            mode_checkbox_group="3s極速覆刻",
            prompt_text=GLOBAL_REF_TEXT,      # 使用剛剛動態取得的參考文本
            prompt_wav_upload=handle_file(GLOBAL_REF_AUDIO), # 使用剛剛動態取得的參考音檔
            prompt_wav_record=None,
            instruct_text="Speak very slowly",
            seed=0,
            speed=1.0,
            enable_translation=False, # 🔥 關鍵：設為 False，告訴模型「我給你的就是拼音，不要翻譯」
            api_name="/generate"
        )

        # 解析回傳路徑
        if isinstance(result_path, dict):
            result_path = result_path.get('path') or result_path.get('url')

        if result_path and os.path.exists(result_path):
            shutil.copy(result_path, final_filename)
            
            # 播放
            os.startfile(final_filename)
            
            # 稍微暫停一下防止連續音檔打架 (可選)
            time.sleep(0.2)
        else:
            print("❌ TTS 合成無回傳檔案")

    except Exception as e:
        print(f"❌ 發音錯誤: {e}")

# ==========================================
# 4. 主程式 (LLM 控制中心)
# ==========================================

def main():
    client = OpenAI(
        base_url = "https://integrate.api.nvidia.com/v1",
        api_key = NVIDIA_API_KEY
    )

    # 🔥 System Prompt 修改：要求「華語顯示」但給「台語拼音」
    system_prompt = f"""
    你是一個精通「臺灣閩南語（台語）」的 AI 助理。
    
    【輸出規則】
    1. 對使用者的顯示（前半段）：請完全使用「繁體華語（台灣慣用語）」回答，不要出現台語漢字或拼音。
    2. 分隔符號：回答結束後，插入 "{SEPARATOR}"。
    3. 給語音系統的指令（後半段）：請將前半段的內容翻譯成「臺羅拼音 (Tâi-lô)」。
       - 聲調請用數字標示 (1-8)。
       - 句子之間請用標點符號隔開。
       - 不要包含任何解釋性文字。

    範例互動：
    使用者：你好嗎？
    AI 回答：我很好，謝謝你的關心。{SEPARATOR}Gua2 tsin1 ho2, to-sia7 li2 e5 kuan-sim.
    """

    conversation_history = [{"role": "system", "content": system_prompt}]

    print("=== 台語 AI 聊天室 (華語文字 / 台語發音) ===")
    
    # 1. 先初始化 TTS
    if init_tts_system():
        print("✅ 系統準備就緒！\n")
    else:
        print("⚠️ TTS 系統連線失敗，將僅有文字回應。\n")

    while True:
        try:
            user_input = input("\n你：")
            if user_input.lower() in ["exit", "quit", "離開"]:
                print("AI：謝謝使用，再見！")
                speak_taigi_pinyin("To-sia7 su2-iong7, tsai3-hue7!")
                time.sleep(3)
                break
            
            conversation_history.append({"role": "user", "content": user_input})

            # 呼叫 LLM
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

            # 串流顯示邏輯 (只印分隔符號前面的華語)
            for chunk in completion:
                if chunk.choices[0].delta.content is not None:
                    content = chunk.choices[0].delta.content
                    full_response += content
                    
                    if is_printing:
                        if SEPARATOR not in full_response:
                            # 還沒出現分隔符，正常印出華語
                            print(content, end="", flush=True)
                        else:
                            # 發現分隔符了！
                            # 如果這個 content 裡剛好包含分隔符前半段，把它印完
                            if SEPARATOR in content:
                                print(content.split(SEPARATOR)[0], end="", flush=True)
                            # 停止印出，剩下的都是拼音
                            is_printing = False

            print() # 換行

            # 存入對話紀錄 (建議存完整版，讓 AI 保持格式)
            conversation_history.append({"role": "assistant", "content": full_response})
            
            # 處理語音 (取出分隔符號後面的拼音)
            if SEPARATOR in full_response:
                parts = full_response.split(SEPARATOR)
                # 確保有後半段
                if len(parts) > 1:
                    pinyin_part = parts[1].strip()
                    speak_taigi_pinyin(pinyin_part)
            else:
                # 萬一 AI 沒遵守格式，就不發音 (因為華語丟進去給台語拼音模型會亂念)
                # print("(AI 未提供拼音，無法發音)")
                pass
        
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"錯誤: {e}")

if __name__ == "__main__":
    main()