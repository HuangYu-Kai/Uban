import os
from supabase import create_client, Client
from dotenv import load_dotenv

# 載入 .env 檔案
load_dotenv()

# ==========================================
# 1. 初始化 Supabase 客戶端
# ==========================================
# 請將這裡的 URL 和 KEY 替換為你在 Supabase 專案設定中取得的資料
# 通常會在設定 (Settings) -> API 裡面找到
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("❌ 錯誤：找不到 SUPABASE_URL 或 SUPABASE_KEY，請確認 .env 檔案設定是否正確。")
    exit(1)

try:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    print("✅ 成功初始化 Supabase 客戶端")
except Exception as e:
    print(f"❌ 初始化 Supabase 客戶端失敗: {e}")
    exit(1)


def run_crud_test():
    """
    執行完整的 CRUD 測試。
    測試前，請確保 Supabase 中有一個名為 'test_users' 的資料表，並包含以下欄位：
    - id (整數或 UUID, Primary Key, 如果是整數請設定為 identity/auto-increment)
    - name (字串)
    - email (字串)
    """
    table_name = 'test_users'
    test_email = "test@example.com"
    
    print("\n--- 開始 Supabase CRUD 測試 ---")

    # ==========================================
    # C - Create (新增)
    # ==========================================
    print("\n[1. Create] 嘗試新增一筆資料...")
    try:
        # 執行插入，Supabase python 客戶端預設會回傳插入的資料
        new_user = {"name": "Test User", "email": test_email}
        response = supabase.table(table_name).insert(new_user).execute()
        
        # 取得剛新增的資料內容 (包含自動產生的 id)
        created_data = response.data[0]
        user_id = created_data['id']
        print(f"✅ 新增成功！資料: {created_data}")
    except Exception as e:
        print(f"❌ 新增失敗，請檢查資料表是否存在或欄位是否正確: {e}")
        return

    # ==========================================
    # R - Read (查詢)
    # ==========================================
    print("\n[2. Read] 嘗試查詢剛剛新增的資料...")
    try:
        # 使用 eq 進行條件查詢
        response = supabase.table(table_name).select("*").eq("id", user_id).execute()
        print(f"✅ 查詢成功！查詢結果: {response.data}")
    except Exception as e:
        print(f"❌ 查詢失敗: {e}")

    # ==========================================
    # U - Update (修改)
    # ==========================================
    print("\n[3. Update] 嘗試修改該筆資料的名稱...")
    try:
        # 執行更新並透過 eq 指定條件
        updated_user = {"name": "Updated Test User"}
        response = supabase.table(table_name).update(updated_user).eq("id", user_id).execute()
        print(f"✅ 修改成功！新資料: {response.data[0]}")
    except Exception as e:
        print(f"❌ 修改失敗: {e}")

    # ==========================================
    # D - Delete (刪除)
    # ==========================================
    print("\n[4. Delete] 嘗試刪除該筆測試資料...")
    try:
        # 執行刪除並透過 eq 指定條件
        response = supabase.table(table_name).delete().eq("id", user_id).execute()
        print(f"✅ 刪除成功！被刪除的資料: {response.data[0]}")
    except Exception as e:
        print(f"❌ 刪除失敗: {e}")

    # 再次查詢確認是否真的刪除
    print("\n[5. Verify] 確認資料是否已刪除...")
    verify_response = supabase.table(table_name).select("*").eq("id", user_id).execute()
    if not verify_response.data:
        print("✅ 完美！測試資料已徹底清除。")
    else:
        print(f"⚠️ 警告：資料似乎還在: {verify_response.data}")

if __name__ == "__main__":
    print("提示：在執行測試前，請確保已在資料庫建立 'test_users' 資料表。")
    print("如果要正式執行，請將環境變數設定好：")
    
    # 這裡直接執行測試，但如果有缺變數通常會死在前面
    run_crud_test()
