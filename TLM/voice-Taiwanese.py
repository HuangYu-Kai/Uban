import requests
import json
import os
from flask import Flask, send_file, request, Response

app = Flask(__name__)

class GPTSoVITSClient:
    def __init__(self, api_url="http://127.0.0.1:9880"):
        self.api_url = api_url
        
        # 【重要】這裡設定一個預設的「溫柔長輩模式」參考音訊
        # 建議您錄製一段約 5 秒的聲音，語氣要親切、稍慢
        # 例如："你好，我是你的健康小幫手，今天覺得如何呢？"
        self.default_ref_audio_path = "assets/gentle_voice_sample.wav" 
        self.default_ref_text = "你好，我是你的健康小幫手，今天覺得如何呢？"
        self.default_ref_lang = "zh"

    def generate_speech(self, text, speed=0.8):
        """
        呼叫 GPT-SoVITS API 生成語音
        :param text: 要轉語音的文字
        :param speed: 語速，預設 0.8 (適合長輩)
        :return: 音訊二進位數據 (bytes)
        """
        url = f"{self.api_url}/"
        
        # GPT-SoVITS 的 API 參數結構 (根據官方 api.py)
        # 注意：不同版本的 API 參數名稱可能略有不同，這是最通用的 GET/POST 結構
        payload = {
            "text": text,
            "text_language": "zh",
            # 參考音訊設定 (Zero-shot 關鍵)
            "ref_audio_path": self.default_ref_audio_path,
            "prompt_text": self.default_ref_text,
            "prompt_language": self.default_ref_lang,
            # 參數調整
            "speed": speed,          # 語速：0.8 為慢速
            "top_k": 5,             # 控制語氣隨機性，越小越穩定
            "top_p": 1,
            "temperature": 1        # 溫度，越高語氣越豐富
        }

        try:
            # 發送請求 (預設 api.py 支援 GET 或 POST，這裡用 POST 處理長文本較安全)
            # 若官方 API 僅支援 GET，則需改用 params=payload
            response = requests.post(url, json=payload) 
            
            # 如果是 GET 模式 (視您的 api.py 版本而定)
            # response = requests.get(url, params=payload)

            if response.status_code == 200:
                return response.content
            else:
                print(f"TTS Error: {response.text}")
                return None
        except Exception as e:
            print(f"Connection Error: {e}")
            return None

# 初始化 TTS 服務
tts_client = GPTSoVITSClient()

# ================= FLASK 路由範例 =================

@app.route('/api/speak', methods=['POST'])
def speak():
    data = request.json
    text = data.get('text', '')
    
    # 允許前端微調語速，若無則使用預設長輩語速 0.8
    speed = float(data.get('speed', 0.8))

    if not text:
        return {"error": "No text provided"}, 400

    print(f"正在為長輩生成語音: {text[:20]}... (語速: {speed})")
    
    audio_data = tts_client.generate_speech(text, speed=speed)

    if audio_data:
        # 直接回傳音訊串流給前端 (Flutter)
        return Response(audio_data, mimetype="audio/wav")
    else:
        return {"error": "TTS Generation failed"}, 500

if __name__ == '__main__':
    # 確保您的 Flask 跑在不同的 port，避免與 GPT-SoVITS (9880) 衝突
    app.run(host='0.0.0.0', port=5000, debug=True)