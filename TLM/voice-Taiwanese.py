import requests
import os
import shutil
import urllib3
from gradio_client import Client, handle_file

# === 設定區 ===
APP_URL = "https://tts.ivoice.tw:5003/" 
USER_INPUT = "最近天氣真冷啊，出門要注意保暖，衣服要多穿一點。"

# 官方文件提供的參考音檔與對應文本
REF_AUDIO_URL = "https://tts.ivoice.tw:5003/gradio_api/file=/home/tianyi/tts_taigi/gradio_cache/169345990328661d3035ba3c7e69d5ffb04bb34947acf44c22416982989c8bdc/文化相放伴_ep080_085_測試集.wav"
REF_TEXT = "ai3 tsu3- i3 an1- tsuan5 --ooh4 , a1- kong1 tshue1 tian7- hong1 , lin2 u7 oh8 --khi2- lai5 ah8 bo5 ?"

# 忽略 SSL 警告 (讓畫面乾淨點)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def download_reference_file(url, filename):
    """ 強制忽略 SSL 下載參考音檔 """
    print(f"📥 正在下載參考音檔 (Bypass SSL)...")
    try:
        response = requests.get(url, verify=False, timeout=30)
        with open(filename, 'wb') as f:
            f.write(response.content)
        print(f"✅ 參考音檔已下載至: {filename}")
        return True
    except Exception as e:
        print(f"❌ 下載失敗: {e}")
        return False

def speak_taigi_gradio(text_hanji):
    # 1. 先把參考音檔抓下來 (這是繞過錯誤的關鍵！)
    local_ref_audio = "temp_reference.wav"
    if not download_reference_file(REF_AUDIO_URL, local_ref_audio):
        return

    print("🚀 正在連線至意傳科技 Gradio API ...")
    
    try:
        # 2. 建立連線 (ssl_verify=False)
        client = Client(APP_URL, ssl_verify=False)
        
        print(f"📝 準備合成：{text_hanji}")

        # 3. 開始合成
        # 這裡我們上傳「本地檔案」(local_ref_audio)，而不是網址
        # 這樣 Client 就不需要自己去連線下載，避開 SSL 錯誤
        result_path = client.predict(
            tts_text=text_hanji,
            mode_checkbox_group="3s極速覆刻",
            prompt_text=REF_TEXT,
            prompt_wav_upload=handle_file(local_ref_audio), # 👈 關鍵修改：傳本地檔
            prompt_wav_record=None,
            instruct_text="Speak very slowly",
            seed=0,
            speed=1.0,
            enable_translation=True, 
            api_name="/generate"
        )

        # 4. 處理結果
        final_filename = "taigi_gradio_output.wav"
        
        # 處理回傳字典
        if isinstance(result_path, dict):
            result_path = result_path.get('path') or result_path.get('url')

        if result_path and os.path.exists(result_path):
            # 清理舊檔
            if os.path.exists(final_filename):
                try: os.remove(final_filename)
                except: pass 

            shutil.copy(result_path, final_filename)
            print(f"✅ 合成成功！檔案已儲存：{os.path.abspath(final_filename)}")
            
            print("🎵 正在啟動播放器...")
            os.startfile(final_filename)
        else:
            print("❌ 找不到回傳的檔案。")
            print(f"回傳內容: {result_path}")

    except Exception as e:
        print(f"❌ 發生錯誤: {e}")
        # 如果還是失敗，我們可以試著切換到 http (如果不強制 https)
        # APP_URL = "http://tts.ivoice.tw:5003/"

    finally:
        # 清理暫存的參考音檔
        if os.path.exists(local_ref_audio):
            try: os.remove(local_ref_audio)
            except: pass

if __name__ == "__main__":
    speak_taigi_gradio(USER_INPUT)