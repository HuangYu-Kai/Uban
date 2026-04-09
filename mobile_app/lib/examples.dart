// 📱 UI 增強功能使用示例

/// 示例 1: 在 Dashboard 中使用健康儀表板
void exampleHealthDashboard() {
  // family_dashboard_view.dart 已自動集成
  // 組件會在首屏自動顯示
  // 顯示長者的實時健康數據
}

/// 示例 2: 使用增強的聊天屏幕替換原始聊天
void exampleReplaceChatScreen() {
  // 原始代碼：
  // Navigator.push(context, MaterialPageRoute(
  //   builder: (context) => FamilyAiChatScreen(),
  // ));

  // 改為增強版本：
  // Navigator.push(context, MaterialPageRoute(
  //   builder: (context) => EnhancedFamilyAiChatScreen(
  //     elderName: '媽媽',
  //     aiPersona: '親切的老年陪伴員',
  //     elderId: 123,
  //   ),
  // ));
}

/// 示例 3: 自定義健康儀表板
void exampleCustomHealthDashboard() {
  /*
  HealthDashboardCard(
    elderName: '李奶奶',
    healthData: {
      'heart_rate': 68,        // 心率
      'steps': 5320,           // 今日步數
      'calories': 450,         // 卡路里消耗
      'sleep_quality': 88,     // 睡眠品質百分比
    },
    onRefresh: () async {
      // 刷新數據的邏輯
      final data = await ApiService.getHealthData(elderId);
      // 更新 UI
    },
  )
  */
}

/// 示例 4: 集成 AI 聊天消息流
void exampleChatMessageFlow() {
  /*
  List<Map<String, dynamic>> messages = [
    {
      'isUser': false,
      'text': '您好！我是您的智慧照護助理。',
      'duration': const Duration(milliseconds: 1500),
    },
    {
      'isUser': true,
      'text': '媽媽今天好嗎？',
    },
    {
      'isUser': false,
      'text': '根據今天的監測，您的媽媽心率穩定在 70-75 BPM，步數達到 5000 步...',
      'duration': const Duration(milliseconds: 2000),
    },
  ];

  ChatListView(
    messages: messages,
    aiPersona: '親切的老年陪伴員',
    scrollController: _scrollController,
  );
  */
}

/// 示例 5: 自定義 AI 性格
void exampleCustomAiPersona() {
  // AI 性格會影響：
  // 1. 聊天氣泡的顏色
  // 2. AppBar 中的指示燈顏色
  // 3. 思考指示器的顏色

  // 支持的性格類型包括親切、嚴謹、活潑、溫柔等。
}

/// 示例 6: 連接真實的 API
void exampleRealApiIntegration() {
  /*
  // 在 enhanced_family_ai_chat_screen.dart 中修改 _sendMessage()
  
  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final userText = _controller.text.trim();
    setState(() {
      _messages.add({'isUser': true, 'text': userText});
      _isThinking = true;
      _controller.clear();
    });

    try {
      // 調用 API 獲取 AI 回應
      final response = await ApiService.sendChatMessage(
        elder_id: widget.elderId,
        message: userText,
        persona: _aiPersona,
      );

      setState(() {
        _isThinking = false;
        _messages.add({
          'isUser': false,
          'text': response['reply'],
          'duration': Duration(
            milliseconds: response['reply'].length * 25,
          ),
        });
      });
    } catch (e) {
      setState(() => _isThinking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('錯誤: $e')),
      );
    }
  }
  */
}

/// 示例 7: 動態主題切換
void exampleDynamicThemeByPersona() {
  /*
  void _updateAccentColorFromPersona() {
    final persona = _aiPersona?.toLowerCase() ?? '';
    
    if (persona.contains('親切')) {
      _accentColor = const Color(0xFFF59E0B); // 暖色調
    } else if (persona.contains('嚴謹')) {
      _accentColor = const Color(0xFF3B82F6); // 冷色調
    } else if (persona.contains('活潑')) {
      _accentColor = const Color(0xFFEC4899); // 活力色
    } else if (persona.contains('溫柔')) {
      _accentColor = const Color(0xFF8B5CF6); // 柔和色
    }
    
    setState(() {}); // 觸發 UI 更新
  }
  */
}

/// 示例 8: 語音輸入整合
void exampleVoiceInput() {
  /*
  // ChatInputBar 中的語音功能
  
  void _onVoiceStart() {
    // 開始錄音
    _speechToText.listen(
      onResult: (result) {
        setState(() => _controller.text = result.recognizedWords);
      },
    );
  }

  void _onVoiceEnd() {
    // 停止錄音並發送
    _speechToText.stop();
    _sendMessage();
  }
  */
}

/// 示例 9: 自定義打字機速度
void exampleTypewriterSpeed() {
  /*
  // 快速打字（技術性回應）
  AnimatedChatBubble(
    text: '您的媽媽最近 7 天平均步數: 4,250 步/天',
    isUser: false,
    aiPersona: '嚴謹的健康顧問',
    typewriterDuration: const Duration(milliseconds: 1000), // 快速
  );

  // 慢速打字（溫暖回應）
  AnimatedChatBubble(
    text: '希望您和媽媽這個週末能一起出去散步...',
    isUser: false,
    aiPersona: '親切的老年陪伴員',
    typewriterDuration: const Duration(milliseconds: 3000), // 緩慢
  );
  */
}

/// 示例 10: 離線數據快取
void exampleOfflineCache() {
  /*
  // 使用 SharedPreferences 快取健康數據
  
  Future<void> _cacheHealthData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cached_health_data',
      jsonEncode(data),
    );
  }

  Future<Map<String, dynamic>?> _getCachedHealthData() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_health_data');
    if (cached != null) {
      return jsonDecode(cached) as Map<String, dynamic>;
    }
    return null;
  }
  */
}

/// 示例 11: 比賽演示建議
void demoSuggestionForContest() {
  /*
  在比賽時展示這些特點：
  
  ✅ 打開 Dashboard
    - 展示健康儀表板卡片的脈搏動畫
    - 指出實時數據的可視化
    - 展示 7 天趨勢圖
  
  ✅ 進入聊天
    - 展示 AI 性格化色彩系統
    - 演示打字機效果
    - 發送幾條消息看 AI 智能回應
    - 顯示不同性格的色彩差異
  
  ✅ 強調的技術點
    - 動畫流暢度（使用 flutter_animate）
    - 響應式設計
    - 實時數據更新
    - 現代 UI/UX 範式
    - 無縫的用戶體驗
  */
}

/// 示例 12: 故障排除
void troubleshooting() {
  /*
  問題 1: 聊天氣泡沒有出現打字機效果
  解決: 確保 isUser = false 且 isLastMessage = true
  
  問題 2: 顏色沒有根據 AI 性格改變
  解決: 檢查 aiPersona 是否正確傳遞，並包含關鍵詞（親切/嚴謹/活潑/溫柔）
  
  問題 3: 健康卡片不顯示
  解決: 確保導入了 health_dashboard_card.dart，並檢查 healthData 不為 null
  
  問題 4: 動畫卡頓
  解決: 減少同時動畫數量，或降低動畫幀率
  */
}
