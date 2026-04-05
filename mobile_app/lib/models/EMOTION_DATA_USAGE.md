# 情緒數據存儲系統使用指南

## 概述

情緒數據存儲系統提供了完整的情緒數據管理功能，包括數據模型定義、本地存儲、查詢和統計等功能。

## 核心組件

### 1. EmotionData 模型 (`lib/models/emotion_data.dart`)

情緒數據的核心模型，包含以下字段：

- `id`: 唯一標識符
- `elderId`: 長者ID
- `timestamp`: 記錄時間
- `emotionType`: 情緒類型（快樂、平靜、焦慮、悲傷、生氣）
- `confidenceScore`: 置信度分數（0.0-1.0）
- `audioSnippetRef`: 音頻片段引用（可選）
- `metadata`: 額外元數據（可選）

#### 情緒類型

```dart
enum EmotionType {
  happy,    // 快樂
  calm,     // 平靜
  anxious,  // 焦慮
  sad,      // 悲傷
  angry,    // 生氣
}
```

#### 使用範例

```dart
import 'package:flutter_application_1/models/emotion_data.dart';

// 創建情緒數據
final emotion = EmotionData(
  id: 'emotion-001',
  elderId: 1,
  timestamp: DateTime.now(),
  emotionType: EmotionType.happy,
  confidenceScore: 0.85,
  audioSnippetRef: '/audio/snippet_001.mp3',
  metadata: {
    'speechRate': 120.5,
    'pitchVariance': 0.8,
    'volumeLevel': 0.6,
  },
);

// JSON 序列化
final json = emotion.toJson();

// JSON 反序列化
final restoredEmotion = EmotionData.fromJson(json);

// 檢查是否為異常情緒
if (emotion.isAbnormal()) {
  print('檢測到異常情緒：${emotion.emotionType.displayName}');
}

// 檢查是否為高置信度
if (emotion.isHighConfidence()) {
  print('高置信度記錄');
}

// 複製並修改
final updatedEmotion = emotion.copyWith(
  confidenceScore: 0.90,
);
```

### 2. EmotionStorageService 服務 (`lib/services/emotion_storage_service.dart`)

提供完整的情緒數據存儲和查詢功能。

#### 初始化服務

```dart
import 'package:flutter_application_1/services/emotion_storage_service.dart';

final storageService = EmotionStorageService();
await storageService.initialize();
```

#### 儲存情緒數據

```dart
// 儲存單筆數據
final emotion = EmotionData(
  id: 'emotion-001',
  elderId: 1,
  timestamp: DateTime.now(),
  emotionType: EmotionType.happy,
  confidenceScore: 0.85,
);

final success = await storageService.saveEmotion(emotion);
if (success) {
  print('儲存成功');
}

// 批量儲存
final emotions = [emotion1, emotion2, emotion3];
final count = await storageService.saveEmotions(emotions);
print('成功儲存 $count 筆記錄');
```

#### 查詢情緒數據

```dart
// 獲取某日的情緒數據
final today = DateTime.now();
final todayEmotions = await storageService.getEmotionsByDate(
  today,
  elderId: 1, // 可選：過濾特定長者
);

// 獲取日期範圍內的數據
final startDate = DateTime.now().subtract(Duration(days: 7));
final endDate = DateTime.now();
final weekEmotions = await storageService.getEmotionsByDateRange(
  startDate,
  endDate,
  elderId: 1,
);

// 獲取異常情緒記錄
final abnormalEmotions = await storageService.getAbnormalEmotions(
  elderId: 1,
  startDate: startDate,
  endDate: endDate,
  confidenceThreshold: 0.6, // 置信度閾值
  limit: 100, // 返回數量限制
);
```

#### 統計功能

```dart
// 獲取情緒統計
final statistics = await storageService.getEmotionStatistics(
  startDate,
  endDate,
  elderId: 1,
);

print('快樂: ${statistics[EmotionType.happy]}');
print('平靜: ${statistics[EmotionType.calm]}');
print('焦慮: ${statistics[EmotionType.anxious]}');
print('悲傷: ${statistics[EmotionType.sad]}');
print('生氣: ${statistics[EmotionType.angry]}');
```

#### 數據導入/導出

```dart
// 導出為 JSON
final jsonString = await storageService.exportEmotionsAsJson(
  startDate: startDate,
  endDate: endDate,
  elderId: 1,
);

// 保存到文件或發送到服務器
// ...

// 從 JSON 導入
final count = await storageService.importEmotionsFromJson(
  jsonString,
  mergeWithExisting: true, // true: 合併，false: 替換
);
print('成功導入 $count 筆記錄');
```

#### 刪除數據

```dart
// 刪除單筆記錄
final deleted = await storageService.deleteEmotion('emotion-001');

// 清空所有數據（謹慎使用！）
final cleared = await storageService.clearAllEmotions();
```

## 設計理念

### 1. 數據結構設計

- **時序性**: 每個情緒記錄都有準確的時間戳，支持歷史追蹤和趨勢分析
- **置信度**: 記錄 AI 識別的信心程度，用於過濾低質量數據
- **可追溯性**: 通過 audioSnippetRef 可以回溯到原始音頻片段
- **擴展性**: metadata 支持存儲額外的分析數據
- **關聯性**: 通過 elderId 關聯到特定長者，支持多用戶場景

### 2. 存儲策略

- **本地優先**: 使用 SharedPreferences 進行本地存儲，支持離線訪問
- **雲端同步**: 預留 Firebase Firestore 接口（未來實現）
- **數據分層**: 熱數據本地緩存，冷數據雲端存儲
- **定期清理**: 建議定期歸檔超過 3 個月的歷史數據

### 3. 查詢優化

- **按需加載**: 避免一次性載入大量歷史記錄
- **智能過濾**: 支持按日期、長者ID、情緒類型等多維度過濾
- **置信度閾值**: 可自定義置信度閾值，過濾低質量數據

## 完整使用示例

```dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/models/emotion_data.dart';
import 'package:flutter_application_1/services/emotion_storage_service.dart';

class EmotionTrackingExample extends StatefulWidget {
  @override
  _EmotionTrackingExampleState createState() => _EmotionTrackingExampleState();
}

class _EmotionTrackingExampleState extends State<EmotionTrackingExample> {
  final EmotionStorageService _storageService = EmotionStorageService();
  List<EmotionData> _todayEmotions = [];
  List<EmotionData> _abnormalEmotions = [];

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _storageService.initialize();
    await _loadData();
  }

  Future<void> _loadData() async {
    // 加載今天的情緒數據
    final todayEmotions = await _storageService.getEmotionsByDate(
      DateTime.now(),
      elderId: 1,
    );

    // 加載異常情緒記錄
    final abnormalEmotions = await _storageService.getAbnormalEmotions(
      elderId: 1,
      limit: 10,
    );

    setState(() {
      _todayEmotions = todayEmotions;
      _abnormalEmotions = abnormalEmotions;
    });
  }

  Future<void> _saveEmotion(EmotionType type, double confidence) async {
    final emotion = EmotionData(
      id: 'emotion-${DateTime.now().millisecondsSinceEpoch}',
      elderId: 1,
      timestamp: DateTime.now(),
      emotionType: type,
      confidenceScore: confidence,
    );

    final success = await _storageService.saveEmotion(emotion);
    if (success) {
      await _loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('情緒記錄已儲存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('情緒追蹤')),
      body: Column(
        children: [
          // 今日情緒列表
          Expanded(
            child: ListView.builder(
              itemCount: _todayEmotions.length,
              itemBuilder: (context, index) {
                final emotion = _todayEmotions[index];
                return ListTile(
                  title: Text(emotion.emotionType.displayName),
                  subtitle: Text(
                    '置信度: ${(emotion.confidenceScore * 100).toStringAsFixed(0)}%',
                  ),
                  trailing: Text(
                    '${emotion.timestamp.hour}:${emotion.timestamp.minute}',
                  ),
                );
              },
            ),
          ),
          
          // 異常情緒警報
          if (_abnormalEmotions.isNotEmpty)
            Container(
              color: Colors.red.shade100,
              padding: EdgeInsets.all(16),
              child: Text(
                '檢測到 ${_abnormalEmotions.length} 個異常情緒記錄',
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),
        ],
      ),
    );
  }
}
```

## 測試

運行單元測試：

```bash
# 測試 EmotionData 模型
flutter test test/models/emotion_data_test.dart

# 測試 EmotionStorageService 服務
flutter test test/services/emotion_storage_service_test.dart

# 運行所有測試
flutter test
```

## 依賴項

在 `pubspec.yaml` 中添加以下依賴：

```yaml
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.2.2

dev_dependencies:
  flutter_test:
    sdk: flutter
```

## 未來擴展

### Firebase Firestore 整合

```dart
// 啟用雲端同步
final storageService = EmotionStorageService(enableCloudSync: true);
await storageService.initialize();

// 自動同步到 Firestore
await storageService.saveEmotion(emotion); // 會自動上傳到雲端

// 從雲端同步數據
await storageService.syncFromCloud(elderId: 1);
```

### Hive 高性能存儲

未來可以替換 SharedPreferences 為 Hive，以獲得更好的性能：

```dart
// 使用 Hive 適配器
@HiveType(typeId: 0)
class EmotionData extends HiveObject {
  // ...
}
```

## 注意事項

1. **數據隱私**: 情緒數據屬於敏感信息，務必確保數據安全
2. **存儲限制**: SharedPreferences 有大小限制，建議定期清理舊數據
3. **並發安全**: 當前實現不支持多線程並發寫入，需要在應用層控制
4. **數據備份**: 建議定期導出數據進行備份

## 支援

如有問題或建議，請聯繫開發團隊。
