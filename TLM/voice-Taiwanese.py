import torch
from transformers import VitsModel, AutoTokenizer
import scipy.io.wavfile
from taibun import Converter

# === 設定區 ===
# 1. 載入 Meta 的台語 TTS 模型 (第一次執行會下載)
print("正在載入 TTS 模型...")
tts_model = VitsModel.from_pretrained("facebook/mms-tts-nan")
tokenizer = AutoTokenizer.from_pretrained("facebook/mms-tts-nan")

# 2. 設定漢字轉拼音工具 (這是讓發音準確的關鍵！)
# system="Tailo" (臺羅拼音)
t_convert = Converter(system="Tailo", dialect="south") 

def text_to_speech_taigi(text_hanji):
    """
    將台語漢字轉成語音 wav
    """
    # 步驟 A: 漢字 -> 臺羅拼音 (解決破音字與變調問題)
    # 雖然 MMS 宣稱支援漢字，但在地化拼音通常唸得比較準
    try:
        # 這裡做簡單轉換，實際應用可能需要更強的斷詞庫
        text_tailo = t_convert.get(text_hanji)
        print(f"拼音轉換: {text_hanji} -> {text_tailo}")
    except:
        text_tailo = text_hanji # 如果轉換失敗就直接用漢字衝衝看

    # 步驟 B: 轉成模型看得懂的 tokens
    inputs = tokenizer(text_tailo, return_tensors="pt")

    # 步驟 C: 生成波形
    with torch.no_grad():
        output = tts_model(**inputs).waveform

    # 步驟 D: 存檔或播放
    # 這裡示範存成檔案 output.wav
    scipy.io.wavfile.write("output.wav", rate=tts_model.config.sampling_rate, data=output.float().numpy().T)
    print("✅ 語音已生成: output.wav")

# === 測試整合 ===
# 假設這是剛剛 Llama-3-70B 的回答
ai_response = "這幾工雨落甲真濟，出門愛記得帶雨傘。"

text_to_speech_taigi(ai_response)