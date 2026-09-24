// AI 串流 SSE 解析回歸測試（第五十三輪）。
//
// 背景：長輩使用語音助理（google_assistant_overlay.dart）時，AI 回覆的畫面
// 會出現 `{"chunk": "..."}`、`{"audio_ready": true}` 等原始 JSON 文字。根因是
// 舊版 `AiChatApi.aiChatStream()` 誤以為後端每一行 `data:` 送的是「裸字串」
// （`jsonDecode(payload) as String`），但 `uban-api/routers/ai.py::
// ai_chat_stream()` 實際上一律送 JSON **物件**
// （見該檔第 716/735/787 行的三個 `yield f"data: {json.dumps({...})}\n\n"`：
// `{"chunk": ...}` / `{"audio_ready": true}` / `{"done": true}`）。物件轉型別
// String 必定拋例外，落到 catch 又把整段 JSON 原文 yield 出去，使用者因此在
// 畫面上看到程式碼片段。同一顆函式也被 elder_chat_screen.dart 使用，故此
// 修正一併解掉那個畫面的相同問題。
//
// 本檔測試「抽出來的可測解析函式」`AiChatApi.parseChatStreamBytes()`
// （見 lib/services/api/ai_chat_api.dart），直接餵入後端會實際產生的 SSE
// 位元組串，不需要真的打 HTTP。
//
// ⚠️ 鐵律：驗證必須「有可能失敗」。除了驗證修正後的行為，本檔另外內嵌一份
// 「修正前的舊解析邏輯」（_legacyParseChatStreamBytes，逐字照抄舊版
// aiChatStream() 的行內解析），對同一份輸入斷言它「會」吐出原始 JSON 文字
// ——證明這份測試真的抓得到問題，不是只驗證新版程式碼恆真。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/api/ai_chat_api.dart';

/// 把字串片段個別 utf8 編碼成獨立的 Stream chunk，模擬 http 套件收到的
/// TCP 封包串——刻意不合併，貼近真實網路情境下一個 SSE frame 可能跨多個
/// chunk 才送達完整的狀況。切割點一律落在 ASCII 字元上，避免切斷多位元組
/// UTF-8 字元（那是另一個與本輪修正無關的既有限制，不在此測試範圍內）。
Stream<List<int>> _byteStream(List<String> pieces) async* {
  for (final piece in pieces) {
    yield utf8.encode(piece);
  }
}

/// 修正前的舊版解析邏輯——逐字照抄 aiChatStream() 原本的行內實作，只用來
/// 當 canary：證明「輸入沒變，新舊邏輯的輸出不一樣」，不是這份測試本身沒有
/// 鑑別力。ai_chat_api.dart 本體已經不再有這段程式碼。
Stream<String> _legacyParseChatStreamBytes(Stream<List<int>> byteStream) async* {
  final StringBuffer lineBuf = StringBuffer();
  await for (final chunk in byteStream) {
    final decoded = utf8.decode(chunk, allowMalformed: true);
    for (int i = 0; i < decoded.length; i++) {
      final ch = decoded[i];
      if (ch == '\n') {
        final line = lineBuf.toString().trimRight();
        lineBuf.clear();
        if (line.startsWith('data: ')) {
          final payload = line.substring(6).trim();
          if (payload == '[DONE]') {
            return;
          }
          if (payload.startsWith('[ERROR]')) {
            yield payload;
            return;
          }
          try {
            final token = jsonDecode(payload) as String;
            if (token.isNotEmpty) yield token;
          } catch (_) {
            if (payload.isNotEmpty) yield payload;
          }
        }
      } else {
        lineBuf.write(ch);
      }
    }
  }
}

void main() {
  // 後端實際會送出的 SSE 訊框，逐字比照 uban-api/routers/ai.py 的
  // json.dumps 輸出（ensure_ascii=False，故中文不會被跳脫成 \uXXXX）。
  const sseLines = [
    'data: {"chunk": "黑棗是非常棒的養生食物喔！"}\n\n',
    'data: {"chunk": "它富含膳食纖維"}\n\n',
    'data: {"audio_ready": true}\n\n',
    'data: {"chunk": "，對腸胃很好。"}\n\n',
    'data: {"done": true}\n\n',
  ];

  group('AiChatApi.parseChatStreamBytes（修正後）', () {
    test('只 yield 乾淨的 chunk 文字，audio_ready／done 不會變成畫面文字', () async {
      final tokens = await AiChatApi.parseChatStreamBytes(_byteStream(sseLines)).toList();

      expect(tokens, [
        '黑棗是非常棒的養生食物喔！',
        '它富含膳食纖維',
        '，對腸胃很好。',
      ]);

      final joined = tokens.join();
      expect(joined.contains('chunk'), isFalse, reason: '不應該出現 JSON 鍵名文字');
      expect(joined.contains('{'), isFalse, reason: '不應該出現原始 JSON 大括號');
    });

    test('單一 SSE frame 被切成多個 TCP chunk 送達時仍能正確組回', () async {
      // 模擬 `data: {"chunk": "你好"}\n\n` 這一行被切成兩段送達，切割點落在
      // ASCII 引號上，不切斷「你」「好」的多位元組編碼。
      final split = _byteStream([
        'data: {"chunk": "',
        '你好"}\n\n',
      ]);
      final tokens = await AiChatApi.parseChatStreamBytes(split).toList();
      expect(tokens, ['你好']);
    });

    test('無法辨識的訊框不會被當成文字丟給使用者（只記錄不 yield）', () async {
      final tokens = await AiChatApi.parseChatStreamBytes(
        _byteStream(['data: {"unexpected_key": 123}\n\n', 'data: {"chunk": "後面正常"}\n\n']),
      ).toList();
      expect(tokens, ['後面正常']);
    });

    test('JSON 字串裡的 \\n 會變成真正的換行，畫面上不會看到字面上的反斜線 n', () async {
      final tokens = await AiChatApi.parseChatStreamBytes(
        _byteStream(['data: {"chunk": "第一行\\n第二行"}\n\n']),
      ).toList();
      expect(tokens, ['第一行\n第二行']);
      expect(tokens.single.contains(r'\n'), isFalse, reason: '不應出現字面上的反斜線 n');
      expect(tokens.single.contains('\n'), isTrue, reason: '應該是真正的換行字元');
    });

    test('[ERROR] 前綴字串仍會被 yield 出去（呼叫端靠它判斷連線失敗）', () async {
      final tokens = await AiChatApi.parseChatStreamBytes(
        _byteStream(['data: [ERROR] 伺服器錯誤: 500\n\n']),
      ).toList();
      expect(tokens, ['[ERROR] 伺服器錯誤: 500']);
    });
  });

  group('Canary：舊版解析邏輯在同一份輸入上必須「壞掉」', () {
    test('舊邏輯會把 JSON 原文吐給畫面（證明上面的測試抓得到這個 bug）', () async {
      final legacyTokens = await _legacyParseChatStreamBytes(_byteStream(sseLines)).toList();
      final joinedLegacy = legacyTokens.join();

      // 這正是使用者回報的畫面亂碼："...好處呢？\n\n"}{"chunk": "黑棗是非常棒的
      // 養生食物喔！..."}{"chunk": "..."} —— 舊邏輯把整個 JSON 物件原文吐出來。
      expect(
        joinedLegacy.contains('{"chunk"'),
        isTrue,
        reason: '舊解析邏輯應該要重現使用者回報的原始 JSON 洩漏 bug，'
            '否則這份 canary 就無法證明新測試有鑑別力',
      );

      // 新舊兩版對同一份輸入的輸出必須不同，否則代表新版沒有真的修正行為。
      final fixedTokens = await AiChatApi.parseChatStreamBytes(_byteStream(sseLines)).toList();
      expect(fixedTokens.join(), isNot(equals(joinedLegacy)));
    });
  });
}
