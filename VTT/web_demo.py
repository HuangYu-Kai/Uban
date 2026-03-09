import os
import sys
import json
import tempfile
import traceback
from flask import Flask, render_template_string, request, jsonify

import torch
from funasr import AutoModel

# --- Model Loading ---
MODEL_DIR = "FunAudioLLM/Fun-ASR-Nano-2512"

print(f"Loading model from {MODEL_DIR}...")

device = (
    "cuda:0"
    if torch.cuda.is_available()
    else "mps"
    if torch.backends.mps.is_available()
    else "cpu"
)

try:
    model = AutoModel(
        model=MODEL_DIR,
        trust_remote_code=True,
        remote_code="./model.py",
        device=device,
        hub="ms"
    )
    print("Model loaded successfully.")
except Exception as e:
    print(f"Error loading model: {e}")
    model = None

# --- Flask App ---
app = Flask(__name__)

HTML_PAGE = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>FunASR Nano 语音识别</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', sans-serif;
            background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
            min-height: 100vh;
            color: #e0e0e0;
            display: flex;
            justify-content: center;
            align-items: flex-start;
            padding: 40px 20px;
        }
        .container {
            max-width: 800px;
            width: 100%;
            background: rgba(255, 255, 255, 0.06);
            border-radius: 20px;
            padding: 40px;
            backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            box-shadow: 0 25px 60px rgba(0, 0, 0, 0.5);
        }
        h1 {
            text-align: center;
            font-size: 28px;
            font-weight: 700;
            margin-bottom: 8px;
            background: linear-gradient(90deg, #a78bfa, #60a5fa, #34d399);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .subtitle {
            text-align: center;
            color: #9ca3af;
            font-size: 14px;
            margin-bottom: 32px;
        }
        .section {
            margin-bottom: 24px;
        }
        label {
            display: block;
            font-size: 14px;
            font-weight: 500;
            color: #c4b5fd;
            margin-bottom: 8px;
        }
        .upload-area {
            border: 2px dashed rgba(139, 92, 246, 0.4);
            border-radius: 12px;
            padding: 40px;
            text-align: center;
            cursor: pointer;
            transition: all 0.3s ease;
            background: rgba(139, 92, 246, 0.05);
        }
        .upload-area:hover {
            border-color: rgba(139, 92, 246, 0.8);
            background: rgba(139, 92, 246, 0.1);
        }
        .upload-area.has-file {
            border-color: #34d399;
            background: rgba(52, 211, 153, 0.1);
        }
        .upload-icon { font-size: 36px; margin-bottom: 8px; }
        .upload-text { color: #9ca3af; font-size: 14px; }
        .file-name { color: #34d399; font-size: 14px; font-weight: 500; margin-top: 8px; }
        input[type="file"] { display: none; }
        
        .row {
            display: flex;
            gap: 16px;
        }
        .row .section { flex: 1; }
        
        select, input[type="text"] {
            width: 100%;
            padding: 10px 14px;
            border-radius: 10px;
            border: 1px solid rgba(255, 255, 255, 0.12);
            background: rgba(255, 255, 255, 0.06);
            color: #e0e0e0;
            font-size: 14px;
            outline: none;
            transition: border-color 0.3s;
        }
        select:focus, input[type="text"]:focus {
            border-color: #a78bfa;
        }
        select option { background: #1e1b4b; color: #e0e0e0; }
        
        .btn {
            width: 100%;
            padding: 14px;
            border: none;
            border-radius: 12px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            background: linear-gradient(135deg, #7c3aed, #6366f1);
            color: white;
            margin-top: 8px;
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 25px rgba(124, 58, 237, 0.4);
        }
        .btn:active { transform: translateY(0); }
        .btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
            transform: none;
            box-shadow: none;
        }
        
        .result-box {
            background: rgba(0, 0, 0, 0.3);
            border: 1px solid rgba(255, 255, 255, 0.08);
            border-radius: 12px;
            padding: 20px;
            min-height: 120px;
            font-size: 15px;
            line-height: 1.8;
            white-space: pre-wrap;
            word-break: break-all;
            color: #d1d5db;
        }
        .result-box.error { color: #f87171; }
        
        .spinner {
            display: inline-block;
            width: 18px;
            height: 18px;
            border: 2px solid rgba(255,255,255,0.3);
            border-radius: 50%;
            border-top-color: #fff;
            animation: spin 0.7s linear infinite;
            vertical-align: middle;
            margin-right: 8px;
        }
        @keyframes spin { to { transform: rotate(360deg); } }

        audio { width: 100%; margin-top: 12px; border-radius: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎙️ FunASR Nano 语音识别</h1>
        <p class="subtitle">上传音频文件，快速识别语音内容</p>

        <div class="section">
            <label>上传音频文件（支持 mp3 / wav / flac 等）</label>
            <div class="upload-area" id="uploadArea" onclick="document.getElementById('audioFile').click()">
                <div class="upload-icon">📁</div>
                <div class="upload-text">点击此处选择音频文件</div>
                <div class="file-name" id="fileName"></div>
            </div>
            <input type="file" id="audioFile" accept="audio/*" onchange="onFileSelected(this)">
            <audio id="audioPlayer" controls style="display:none;"></audio>
        </div>

        <div class="row">
            <div class="section">
                <label>Language</label>
                <select id="language">
                    <option value="中文" selected>中文</option>
                    <option value="英文">English</option>
                    <option value="粤语">粤语</option>
                    <option value="日文">日本語</option>
                    <option value="韩文">한국어</option>
                </select>
            </div>
            <div class="section">
                <label>Hotwords（可选）</label>
                <input type="text" id="hotwords" placeholder="e.g. 阿里巴巴, 语音识别">
            </div>
        </div>

        <div class="section">
            <button class="btn" id="recognizeBtn" onclick="recognize()">🚀 开始识别</button>
        </div>

        <div class="section">
            <label>识别结果</label>
            <div class="result-box" id="resultBox">等待上传音频...</div>
        </div>
    </div>

    <script>
        let selectedFile = null;

        function onFileSelected(input) {
            if (input.files && input.files[0]) {
                selectedFile = input.files[0];
                document.getElementById('fileName').textContent = '✅ ' + selectedFile.name;
                document.getElementById('uploadArea').classList.add('has-file');
                // show audio player
                const player = document.getElementById('audioPlayer');
                player.src = URL.createObjectURL(selectedFile);
                player.style.display = 'block';
                document.getElementById('resultBox').textContent = '文件已选择，点击"开始识别"';
                document.getElementById('resultBox').classList.remove('error');
            }
        }

        async function recognize() {
            if (!selectedFile) {
                document.getElementById('resultBox').textContent = '⚠️ 请先选择一个音频文件';
                document.getElementById('resultBox').classList.add('error');
                return;
            }

            const btn = document.getElementById('recognizeBtn');
            const resultBox = document.getElementById('resultBox');
            btn.disabled = true;
            btn.innerHTML = '<span class="spinner"></span>识别中...';
            resultBox.textContent = '正在识别，请稍候...';
            resultBox.classList.remove('error');

            const formData = new FormData();
            formData.append('audio', selectedFile);
            formData.append('language', document.getElementById('language').value);
            formData.append('hotwords', document.getElementById('hotwords').value);

            try {
                const resp = await fetch('/recognize', {
                    method: 'POST',
                    body: formData
                });
                const data = await resp.json();
                if (data.success) {
                    resultBox.textContent = data.text;
                    resultBox.classList.remove('error');
                } else {
                    resultBox.textContent = '❌ ' + data.error;
                    resultBox.classList.add('error');
                }
            } catch (e) {
                resultBox.textContent = '❌ 请求失败: ' + e.message;
                resultBox.classList.add('error');
            } finally {
                btn.disabled = false;
                btn.innerHTML = '🚀 开始识别';
            }
        }
    </script>
</body>
</html>
"""

@app.route("/")
def index():
    return render_template_string(HTML_PAGE)

@app.route("/recognize", methods=["POST"])
def recognize():
    if model is None:
        return jsonify({"success": False, "error": "Model not loaded."})

    audio_file = request.files.get("audio")
    if not audio_file:
        return jsonify({"success": False, "error": "No audio file uploaded."})

    language = request.form.get("language", "中文")
    hotwords_str = request.form.get("hotwords", "")
    hotwords = [w.strip() for w in hotwords_str.split(",") if w.strip()]

    # Save uploaded file to a temp path
    suffix = os.path.splitext(audio_file.filename)[1] or ".wav"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    audio_file.save(tmp.name)
    tmp.close()

    try:
        res = model.generate(
            input=[tmp.name],
            cache={},
            batch_size=1,
            hotwords=hotwords,
            language=language,
            itn=True,
        )
        text = res[0]["text"]
        return jsonify({"success": True, "text": text})
    except Exception as e:
        traceback.print_exc()
        return jsonify({"success": False, "error": str(e)})
    finally:
        os.unlink(tmp.name)

if __name__ == "__main__":
    print("* Running on local URL:  http://127.0.0.1:7860")
    app.run(host="127.0.0.1", port=7860, debug=False)
