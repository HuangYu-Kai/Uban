from openai import OpenAI

# 建立客戶端連線
client = OpenAI(
  base_url = "https://integrate.api.nvidia.com/v1",
  api_key = "nvapi--" # 請記得填回您的 NVIDIA API Key
)

# 1. 初始化對話紀錄 (加入 System Prompt 設定人設)
# 這樣它才知道要講台語，而不是講華語
conversation_history = [
    {
        "role": "system", 
        "content": "你是一個精通「臺灣閩南語（台語）」的 AI 助理。請優先使用「全漢字」或「漢羅混寫」回答使用者的問題。用語要道地、自然，避免直接將華語字面翻譯。"
    }
]

print("=== 台語 AI 聊天室 (輸入 'exit' 或 '離開' 可結束) ===")

# 2. 進入無限迴圈，直到使用者說要離開
while True:
    # 接收使用者輸入
    user_input = input("\n你：")
    
    # 設定離開條件
    if user_input.lower() in ["exit", "quit", "離開"]:
        print("AI：多謝你的使用，再會！")
        break
    
    # 將使用者的問題加入對話紀錄
    conversation_history.append({"role": "user", "content": user_input})

    # 呼叫 API
    completion = client.chat.completions.create(
      model="yentinglin/llama-3-taiwan-70b-instruct",
      messages=conversation_history, # 傳送完整的對話紀錄
      temperature=0.5,
      top_p=1,
      max_tokens=1024,
      stream=True
    )

    print("AI：", end="")
    
    # 建立一個變數來收集完整的回答 (為了存入記憶)
    full_response = ""

    # 串流輸出 (打字機效果)
    for chunk in completion:
        if chunk.choices[0].delta.content is not None:
            content = chunk.choices[0].delta.content
            print(content, end="", flush=True) # 即時印出
            full_response += content # 收集內容

    print() # 換行
    
    # 3. 將 AI 的回答也加入對話紀錄 (這樣它才會有記憶)
    conversation_history.append({"role": "assistant", "content": full_response})