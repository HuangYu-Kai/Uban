// 語音助理「辨識結果需人工確認才送出」回歸測試（第五十三輪）。
//
// 背景（使用者原話）：「長輩在語音輸入完後，因語音輸入的偵測精度仍然過低
// （連年輕人使用幾乎偵測也會 100% 完全出錯，更別提老年人），若是語音輸入
// 偵測錯誤還是會自動發送出去」。根因在
// lib/widgets/google_assistant_overlay.dart：辨識出 finalResult 後直接呼叫
// _processUserQuery() 送給 AI，長輩完全沒有機會看到、更沒機會修正。
//
// ⚠️ 深入 speech_to_text 7.3.0 原始碼後發現：舊版程式碼其實有「兩條」各自
// 獨立的自動送出路徑——onResult 的 finalResult 分支，以及 _initSpeech() 的
// onStatus('done'/'notListening') 分支（引擎自行判定聆聽結束時觸發，例如
// pauseFor 逾時）。只堵住其中一條無法真正修好這個 bug。本測試刻意模擬
// 「finalResult 到達」與「引擎回報 done」兩個真實平台事件（對照
// speech_to_text_platform_interface 的 MethodChannel 協定），同時覆蓋兩條
// 路徑，而不是只測試表面行為。
//
// 測試手法：不去碰 _GoogleAssistantOverlayState 的任何私有成員（Dart 的
// library-private 在不同檔案間本來就存取不到），而是直接對
// speech_to_text／flutter_tts 兩個套件實際使用的 MethodChannel 送出跟真機
// 一致的訊息（channel 名稱、method 名稱、參數形狀皆取自套件原始碼），讓
// GoogleAssistantOverlay 內部真正註冊給這兩個套件的 onResult／onStatus／
// completionHandler 被觸發，再透過公開的 Widget 樹（find.text／
// TextField.controller）斷言可觀察到的畫面行為。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_application_1/widgets/google_assistant_overlay.dart';

const MethodChannel _sttChannel = MethodChannel('plugin.csdcorp.com/speech_to_text');
const MethodChannel _ttsChannel = MethodChannel('flutter_tts');
const StandardMethodCodec _codec = StandardMethodCodec();

/// 安裝 speech_to_text 的假平台實作：initialize／listen 一律成功，
/// locales 回空清單（讓 pickChineseSttLocale 安全退回 null），
/// stop／cancel 都是無害的 no-op。
void _installSttMock(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_sttChannel, (call) async {
    switch (call.method) {
      case 'initialize':
        return true;
      case 'listen':
        return true;
      case 'locales':
        return <String>[];
      case 'has_permission':
        return true;
      default:
        return null; // stop／cancel 等等，回傳值不影響本檔測試流程
    }
  });
}

/// 安裝 flutter_tts 的假平台實作：任何呼叫都安全成功返回，不模擬真的
/// 語音播放（TTS 完成事件由 _completeTtsSpeech() 手動觸發）。
void _installTtsMock(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_ttsChannel, (call) async => 1);
}

void _clearMocks(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_sttChannel, null);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_ttsChannel, null);
}

/// 模擬 speech_to_text 原生端主動呼叫 Dart 端（見
/// speech_to_text_platform_interface 2.3.0 的 MethodChannelSpeechToText：
/// textRecognitionMethod='textRecognition'、notifyStatusMethod='notifyStatus'）。
Future<void> _sendStt(WidgetTester tester, String method, dynamic arguments) async {
  final ByteData data = _codec.encodeMethodCall(MethodCall(method, arguments)) as ByteData;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _sttChannel.name,
    data,
    (_) {},
  );
}

/// 模擬 flutter_tts 原生端回報「這句話念完了」（見 flutter_tts 4.2.5 的
/// platformCallHandler：case "speak.onComplete"），讓 _speakAndWait() 的
/// completer 立刻 resolve，不必真的等待 8 秒逾時兜底。
Future<void> _completeTtsSpeech(WidgetTester tester) async {
  final ByteData data = _codec.encodeMethodCall(const MethodCall('speak.onComplete')) as ByteData;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _ttsChannel.name,
    data,
    (_) {},
  );
}

/// 對照 speech_recognition_result.dart 的 SpeechRecognitionResult.fromJson
/// 格式（alternates + finalResult）手刻一份 textRecognition 事件的 JSON 字串。
String _recognitionResultJson(String words, {required bool finalResult}) {
  return jsonEncode({
    'alternates': [
      {'recognizedWords': words, 'recognizedPhrases': null, 'confidence': 0.85},
    ],
    'finalResult': finalResult,
  });
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump();
  }
}

/// 把 GoogleAssistantOverlay 推進到「正在聆聽」狀態，模擬長輩喚醒小嘎後
/// 的自動流程：_initSpeech() → _initTtsAndGreeting() → _speakAndWait(問候語)
/// → 念完後自動 _startListening()。
///
/// ⚠️ 刻意呼叫 _completeTtsSpeech() 讓問候語立刻「念完」，而不是靠
/// FakeAsync 空等 8 秒逾時兜底——後者除了較慢，也會讓
/// _speakAndWait 內部的 8 秒 Timer 一路帶到測試結束才被取消，增加
/// 「測試結束時仍有 pending Timer」的風險。
Future<void> _pumpListeningOverlay(WidgetTester tester) async {
  _installSttMock(tester);
  _installTtsMock(tester);

  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: GoogleAssistantOverlay(
          userName: '測試長輩',
          aiName: '小嘎',
          userId: 1,
        ),
      ),
    ),
  );
  await _pumpFrames(tester, 10); // 讓 _initSpeech()/setLanguage 等一串 await 落地

  await _completeTtsSpeech(tester); // 問候語「念完」，觸發自動 _startListening()
  await _pumpFrames(tester, 10);

  expect(
    find.byIcon(Icons.mic),
    findsOneWidget,
    reason: '前置流程應該已經自動進入聆聽狀態（顯示聆聽中的實心麥克風圖示），'
        '後續測試才能模擬語音辨識事件',
  );
}

/// 每個測試收尾都推進幾秒鐘的假時間，讓 speech_to_text 內部可能殘留的
/// _notifyFinalTimer（stop() 後 2 秒的兜底計時器）與測試環境攔截回 400
/// 的 HTTP 呼叫落地，避免測試結束時留下 pending Timer 或 Future。
///
/// ⚠️ aifix53b 修正：原本只在這裡累積 pump 時間是不夠的——
/// `GoogleAssistantOverlay.dispose()` 會「無條件」再呼叫一次
/// `_speechToText.stop()`，而 speech_to_text 7.3.0 的 `_stop()` 每次被呼叫
/// 都會重新排一個新的 2 秒 `_notifyFinalTimer`（見套件原始碼
/// `speech_to_text.dart::_stop()`：`_shutdownListener()` 先取消舊計時器，
/// 再無條件排一個新的），不會因為測試本體已經呼叫過一次 `stop()` 就略過。
/// 若放任 `testWidgets` 收尾時才自動觸發這次 dispose，測試函式早已返回、
/// 沒有機會再 pump，那個「dispose 自己排出來的」計時器就會殘留，觸發
/// flutter_test 的收尾檢查（`!timersPending`）並丟出
/// "A Timer is still pending even after the widget tree was disposed"。
/// 修法：先照原本邏輯排空測試本體裡呼叫 stop() 產生的計時器，接著主動把
/// widget 換成空白樹以觸發 dispose（自己承接這次呼叫排出的新計時器），
/// 再補一輪 pump 讓它落地——而不是留給框架收尾時措手不及。
Future<void> _drainPendingWork(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  // 主動觸發 dispose，讓它排出的第二個 _notifyFinalTimer 在測試本體還能
  // 掌控 pump 節奏的時候就被排空，不要等框架收尾時才措手不及。
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void main() {
  setUpAll(() {
    // google_fonts 在測試環境找不到本地字型資產時會嘗試打網路抓取，關掉
    // runtime fetching 讓它退回系統 fallback 字型（沿用專案既有慣例，見
    // elder_home_tab_news_visibility_test.dart）。
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sttChannel, null);
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ttsChannel, null);
  });

  testWidgets('語音辨識出最終結果後不會自動送出，需長輩按「送出」才會問 AI', (tester) async {
    await _pumpListeningOverlay(tester);

    // 刻意用一句「聽起來很像正常句子、但其實答非所問」的文字，模擬使用者
    // 抱怨的「偵測精度低、辨識錯誤」情境——重點不是文字本身合不合理，而是
    // 辨識完成後不該不經確認就送出。
    const recognized = '今天天氣真的好嗎';

    // 先送 textRecognition(finalResult:true)：對應 onResult 分支。
    await _sendStt(tester, 'textRecognition', _recognitionResultJson(recognized, finalResult: true));
    await _pumpFrames(tester, 5);
    // 再送 notifyStatus('done')：對應 onStatus 分支（引擎自行回報聆聽結束）。
    await _sendStt(tester, 'notifyStatus', 'done');
    await _pumpFrames(tester, 5);

    // 確認區塊應該出現，AI 還沒有被呼叫（沒有「思考中」）。
    expect(find.text('送出'), findsOneWidget, reason: '辨識完成後應該顯示確認區塊');
    expect(find.text('重新說一次'), findsOneWidget);
    expect(find.textContaining('思考中'), findsNothing, reason: '確認前不該自動問 AI');

    final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(
      controller.text,
      recognized,
      reason: '辨識文字應該停留在輸入框等待確認，而不是已經被送出清空',
    );

    // 長輩看過文字覺得沒問題，按下「送出」才真的問 AI。
    await tester.tap(find.text('送出'));
    await _pumpFrames(tester, 3);

    expect(find.text('送出'), findsNothing, reason: '送出後確認區塊應該收起');
    expect(controller.text, isEmpty, reason: '送出後輸入框應該被清空');
    expect(find.text(recognized), findsOneWidget, reason: '辨識文字現在應該變成一則使用者訊息泡泡');

    await _drainPendingWork(tester);
  });

  testWidgets('確認區塊「重新說一次」會清空文字並重新聆聽，不會送出', (tester) async {
    await _pumpListeningOverlay(tester);

    const recognized = '明天記得吃藥吧也許';
    await _sendStt(tester, 'textRecognition', _recognitionResultJson(recognized, finalResult: true));
    await _pumpFrames(tester, 5);
    await _sendStt(tester, 'notifyStatus', 'done');
    await _pumpFrames(tester, 5);

    expect(find.text('重新說一次'), findsOneWidget);

    await tester.tap(find.text('重新說一次'));
    await _pumpFrames(tester, 5);

    // 文字被清空，且沒有被當成使用者訊息送出。
    expect(find.text(recognized), findsNothing, reason: '重新說一次不應該送出剛才的辨識文字');
    expect(find.textContaining('思考中'), findsNothing);
    expect(find.text('送出'), findsNothing, reason: '重新聆聽時確認區塊應該收起');

    // 重新開始聆聽（麥克風圖示應變回聆聽中的實心樣式）。
    expect(
      find.byIcon(Icons.mic),
      findsOneWidget,
      reason: '「重新說一次」應該讓麥克風重新開始聆聽',
    );

    await _drainPendingWork(tester);
  });

  testWidgets('聆聽中手動點擊麥克風鈕提前停止，同樣進入確認區塊而不直接送出', (tester) async {
    await _pumpListeningOverlay(tester);

    // 模擬「部分結果」（尚未 finalResult）：只更新輸入框文字，不觸發確認流程。
    const partialWords = '今天';
    await _sendStt(tester, 'textRecognition', _recognitionResultJson(partialWords, finalResult: false));
    await _pumpFrames(tester, 3);

    expect(find.text('送出'), findsNothing, reason: '部分結果不應該提前顯示確認區塊');

    // 長輩手動點擊（此時顯示聆聽中實心麥克風圖示的）按鈕提前停止聆聽——
    // 這是 _stopListeningForConfirm() 的另一個進入點（先前叫
    // _stopListeningAndSend()，一樣會自動送出），不是只有 onResult 一條路。
    await tester.tap(find.byIcon(Icons.mic));
    await _pumpFrames(tester, 5);

    expect(find.text('送出'), findsOneWidget, reason: '手動停止聆聽也應該進入確認區塊');
    expect(find.text('重新說一次'), findsOneWidget);
    expect(find.textContaining('思考中'), findsNothing, reason: '手動停止不該直接送出給 AI');

    final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(controller.text, partialWords);

    await _drainPendingWork(tester);
  });
}
