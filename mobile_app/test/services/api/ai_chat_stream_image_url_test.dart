// ★ 2026-10-17 拍照問小嘎：AiChatApi.aiChatStream 只有在提供 imageUrl 時才在請求內容
// 帶 `image_url`；沒提供時請求內容與舊版相同。用 http 的 runWithClient 換成 MockClient，
// 不真的打網路。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/api/ai_chat_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<Map<String, dynamic>> _captureBody({String? imageUrl}) async {
  Map<String, dynamic>? body;
  Uri? uri;
  final client = MockClient.streaming((request, bodyStream) async {
    uri = request.url;
    body = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
    return http.StreamedResponse(
      Stream.value(utf8.encode('data: {"chunk": "好"}\n\ndata: {"done": true}\n\n')),
      200,
    );
  });
  final tokens = await http.runWithClient(
    () => AiChatApi.aiChatStream(1, '你好', imageUrl: imageUrl).toList(),
    () => client,
  );
  expect(tokens, ['好']);
  expect(uri!.path, endsWith('/ai/chat_stream'));
  return body!;
}

void main() {
  test('有 imageUrl 時請求內容帶 image_url', () async {
    final body = await _captureBody(imageUrl: '/uploads/abc.jpg');
    expect(body['image_url'], '/uploads/abc.jpg');
    expect(body['message'], '你好');
  });

  test('沒有 imageUrl 時請求內容不含 image_url（與舊版相同）', () async {
    final body = await _captureBody();
    expect(body.containsKey('image_url'), isFalse);
    expect(body['user_id'], 1);
  });
}
