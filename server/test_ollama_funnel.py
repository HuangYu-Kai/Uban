#!/usr/bin/env python3
"""
test_ollama_funnel.py - 測試 Ollama function calling
使用方式：
  python test_ollama_funnel.py                    # 使用預設 Tailscale 地址
  python test_ollama_funnel.py --local            # 使用 localhost
  OLLAMA_HOST=http://xxx python test_ollama_funnel.py  # 自訂地址
"""

import os
import sys
import argparse

# 解析命令列參數
parser = argparse.ArgumentParser(description='測試 Ollama Function Calling')
parser.add_argument('--local', action='store_true', help='使用 localhost:11434')
parser.add_argument('--host', type=str, help='自訂 Ollama 地址')
parser.add_argument('--model', type=str, default='qwen2.5:14b', help='模型名稱 (預設: qwen2.5:14b)')
args = parser.parse_args()

# 設定 Ollama 地址
if args.local:
    OLLAMA_HOST = "http://localhost:11434"
elif args.host:
    OLLAMA_HOST = args.host
else:
    OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "https://boyo-t.tail531c8a.ts.net")

os.environ["OLLAMA_HOST"] = OLLAMA_HOST

import ollama

print(f"🔗 連接 Ollama: {OLLAMA_HOST}")
print(f"📦 使用模型: {args.model}")

# 定義測試工具 (與 ollama_service.py 相同格式)
test_tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather_info",
            "description": "獲取指定地區的即時天氣資訊。包含氣溫與天氣概況。",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "城市或地區名稱 (例如：'台北', '台中', '高雄')"
                    }
                },
                "required": ["location"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_youtube_video",
            "description": "搜尋 YouTube 上的影片或音樂。當長輩想聽歌、看影片或學習新事物時使用。",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "搜尋關鍵字 (例如：'江蕙 家後', '足球比賽集錦', '如何做紅燒肉')"
                    }
                },
                "required": ["query"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "save_elder_memory",
            "description": "主動記錄關於長輩的重要生活事實、回憶、家人關係或健康狀況。",
            "parameters": {
                "type": "object",
                "properties": {
                    "fact": {
                        "type": "string",
                        "description": "要記錄的事實描述"
                    },
                    "category": {
                        "type": "string",
                        "description": "資訊分類：'重要事件', '情感偏好與習慣', '家人與關係', '健康與用藥'"
                    }
                },
                "required": ["fact"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_current_time",
            "description": "獲取現在的真實時間 (台灣)。",
            "parameters": {
                "type": "object",
                "properties": {},
                "required": []
            }
        }
    }
]


def test_connection():
    """測試與 Ollama 的連線"""
    print("\n" + "=" * 60)
    print("📡 測試連線...")
    print("=" * 60)
    
    try:
        models = ollama.list()
        print(f"✅ 連線成功！")
        print(f"可用模型：")
        model_names = []
        for m in models.get('models', []):
            name = m.get('name', m.get('model', 'unknown'))
            model_names.append(name)
            print(f"   - {name}")
        
        if args.model not in model_names and not any(args.model in n for n in model_names):
            print(f"\n⚠️  警告: 模型 '{args.model}' 可能不存在")
            print(f"   可用模型: {', '.join(model_names)}")
        
        return True
    except Exception as e:
        print(f"❌ 連線失敗: {e}")
        print("\n請確認：")
        print("  1. Ollama 服務是否運行中")
        print("  2. OLLAMA_HOST 地址是否正確")
        print("  3. 網路是否暢通 (若使用 Tailscale)")
        return False


def test_function_calling():
    """測試 Ollama 是否正確觸發 function calling"""
    
    # 測試案例：(用戶輸入, 預期工具, 預期參數關鍵字)
    test_cases = [
        {
            "name": "🎵 音樂搜尋",
            "prompt": "我想聽周杰倫的稻香",
            "expect_tool": "search_youtube_video",
            "expect_arg_contains": "稻香"
        },
        {
            "name": "🌤️ 天氣查詢",
            "prompt": "台北今天天氣怎麼樣？",
            "expect_tool": "get_weather_info",
            "expect_arg_contains": "台北"
        },
        {
            "name": "⏰ 時間查詢",
            "prompt": "現在幾點了？",
            "expect_tool": "get_current_time",
            "expect_arg_contains": None
        },
        {
            "name": "📝 記憶觸發",
            "prompt": "我兒子住在美國洛杉磯",
            "expect_tool": "save_elder_memory",
            "expect_arg_contains": "美國"
        },
        {
            "name": "💬 一般對話",
            "prompt": "你好，今天過得怎麼樣？",
            "expect_tool": None,
            "expect_arg_contains": None
        },
    ]
    
    print(f"\n" + "=" * 60)
    print(f"🧪 開始測試 Function Calling")
    print(f"   模型: {args.model}")
    print("=" * 60)
    
    results = []
    
    for case in test_cases:
        print(f"\n--- {case['name']} ---")
        print(f"📝 輸入: {case['prompt']}")
        print(f"   預期: {case['expect_tool'] or '(不呼叫工具)'}")
        
        try:
            response = ollama.chat(
                model=args.model,
                messages=[
                    {"role": "system", "content": "你是一位親切的陪伴助手。當需要時請使用工具。"},
                    {"role": "user", "content": case['prompt']}
                ],
                tools=test_tools,
                stream=False
            )
            
            message = response.get('message', {})
            tool_calls = message.get('tool_calls', [])
            
            passed = False
            
            if tool_calls:
                for tc in tool_calls:
                    func_name = tc['function']['name']
                    func_args = tc['function'].get('arguments', {})
                    print(f"   🔧 呼叫工具: {func_name}")
                    print(f"      參數: {func_args}")
                    
                    # 檢查是否符合預期
                    if case['expect_tool'] == func_name:
                        # 檢查參數
                        args_str = str(func_args)
                        if case['expect_arg_contains'] is None or case['expect_arg_contains'] in args_str:
                            print(f"   ✅ PASS")
                            passed = True
                        else:
                            print(f"   ⚠️  參數不包含預期關鍵字 '{case['expect_arg_contains']}'")
                    elif case['expect_tool'] is None:
                        print(f"   ❌ FAIL - 不應該呼叫工具但呼叫了 {func_name}")
                    else:
                        print(f"   ❌ FAIL - 呼叫了錯誤工具 (預期: {case['expect_tool']})")
            else:
                content = message.get('content', '')[:80]
                print(f"   💬 回應: {content}...")
                
                if case['expect_tool'] is None:
                    print(f"   ✅ PASS - 正確沒有呼叫工具")
                    passed = True
                else:
                    print(f"   ❌ FAIL - 應該呼叫 {case['expect_tool']} 但沒有")
            
            results.append({"name": case['name'], "passed": passed})
                    
        except Exception as e:
            print(f"   ❌ 錯誤: {e}")
            results.append({"name": case['name'], "passed": False, "error": str(e)})
    
    # 總結
    print("\n" + "=" * 60)
    print("📊 測試總結")
    print("=" * 60)
    
    passed_count = sum(1 for r in results if r['passed'])
    total_count = len(results)
    
    for r in results:
        status = "✅ PASS" if r['passed'] else "❌ FAIL"
        print(f"  {status} {r['name']}")
    
    print(f"\n總計: {passed_count}/{total_count} 通過")
    
    if passed_count == total_count:
        print("🎉 所有測試通過！Function Calling 運作正常。")
    else:
        print("⚠️  部分測試失敗，請檢查模型是否支援 tool calling。")
    
    return passed_count == total_count


if __name__ == "__main__":
    print("\n" + "🔬 Ollama Function Calling 測試工具 ".center(60, "="))
    
    if test_connection():
        test_function_calling()
    else:
        sys.exit(1)
