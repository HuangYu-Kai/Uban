from funasr import AutoModel
import os

def main():
    model_dir = "FunAudioLLM/Fun-ASR-Nano-2512"
    device = "cpu" # 強制使用 CPU 進行穩定測試
    
    print(f"--- 正在載入模型: {model_dir} ---")
    model = AutoModel(
        model=model_dir,
        trust_remote_code=True,
        remote_code="./model.py",
        device=device,
        hub="ms"
    )
    
    # 使用 model 物件自帶的路徑
    wav_path = os.path.join(model.model_path, "example", "zh.mp3")
    
    print(f"--- 測試音檔路徑: {wav_path} ---")
    if not os.path.exists(wav_path):
        print("錯誤: 找不到音檔!")
        return

    print("--- 開始執行語音辨識 ---")
    try:
        res = model.generate(
            input=[wav_path],
            language="中文",
            itn=True,
        )
        print("--- 辨識結果 ---")
        print(res[0]["text"])
    except Exception as e:
        print(f"執行出錯: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
