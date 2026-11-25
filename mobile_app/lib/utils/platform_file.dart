import 'dart:io' show File;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
// http 的傳遞依賴；MultipartFile.fromBytes 需要 MediaType。
// ignore: depend_on_referenced_packages
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 網頁版（Flutter Web）與手機共用的檔案小工具。
///
/// 網頁沒有 dart:io 的檔案系統：image_picker／record 回傳的是 `blob:` 網址，
/// 只能用 [XFile] 讀 bytes、用 NetworkImage／UrlSource 顯示與播放。
/// 手機端行為與原本完全一致（FileImage、fromPath、DeviceFileSource、暫存目錄）。

/// 圖片路徑 → ImageProvider（手機：FileImage；網頁：blob 網址的 NetworkImage）。
ImageProvider pathImageProvider(String path) =>
    kIsWeb ? NetworkImage(path) : FileImage(File(path));

/// 讀取檔案（或網頁 blob 網址）的 bytes。
Future<Uint8List> readPathBytes(String path) => XFile(path).readAsBytes();

/// 檔案大小（byte）。
Future<int> pathLength(String path) => XFile(path).length();

/// 錄音檔路徑 → 播放來源（手機：DeviceFileSource；網頁：blob 網址的 UrlSource）。
Source audioSourceFromPath(String path) =>
    kIsWeb ? UrlSource(path) : DeviceFileSource(path);

/// 語音留言用的錄音設定：手機維持 aacLc/.m4a；網頁用 wav（Safari 與 Chrome 皆支援，
/// 後端副檔名白名單含 .wav），16kHz 單聲道約 32KB/秒，3MB 上限可錄約 90 秒。
RecordConfig voiceRecordConfig() => kIsWeb
    ? const RecordConfig(
        encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1)
    : const RecordConfig(encoder: AudioEncoder.aacLc);

/// 錄音輸出路徑：手機放在暫存目錄（.m4a）；網頁由瀏覽器管理，路徑傳空字串即可。
Future<String> voiceRecordPath(String prefix) async {
  if (kIsWeb) return '';
  final dir = await getTemporaryDirectory();
  return '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.m4a';
}

/// 錄音檔上傳用的檔名／類型（網頁為 wav，手機維持 fromPath 原行為）。
Future<http.MultipartFile> audioMultipartFromPath(
    String field, String path) async {
  if (!kIsWeb) return http.MultipartFile.fromPath(field, path);
  final bytes = await readPathBytes(path);
  return http.MultipartFile.fromBytes(
    field,
    bytes,
    filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.wav',
    contentType: MediaType('audio', 'wav'),
  );
}

/// 依檔頭判斷圖片格式（網頁 blob 沒有副檔名可用）。
({String ext, String mime}) _sniffImage(Uint8List b, String? hintMime) {
  bool starts(List<int> sig) =>
      b.length >= sig.length &&
      List.generate(sig.length, (i) => b[i] == sig[i]).every((e) => e);
  if (starts([0x89, 0x50, 0x4E, 0x47])) return (ext: 'png', mime: 'image/png');
  if (starts([0x47, 0x49, 0x46])) return (ext: 'gif', mime: 'image/gif');
  if (starts([0x52, 0x49, 0x46, 0x46])) return (ext: 'webp', mime: 'image/webp');
  if (starts([0xFF, 0xD8])) return (ext: 'jpg', mime: 'image/jpeg');
  if (hintMime != null && hintMime.startsWith('image/')) {
    final sub = hintMime.substring(6);
    return (ext: sub == 'jpeg' ? 'jpg' : sub, mime: hintMime);
  }
  return (ext: 'jpg', mime: 'image/jpeg');
}

/// 圖片上傳用的 MultipartFile：手機走 fromPath（原行為）；網頁讀 bytes 並補副檔名／image/* 類型
/// （後端社群上傳會檢查 content-type 必須是 image/*）。
Future<http.MultipartFile> imageMultipartFromPath(
  String field,
  String path, {
  String? mimeType,
}) async {
  if (!kIsWeb) return http.MultipartFile.fromPath(field, path);
  final bytes = await readPathBytes(path);
  final t = _sniffImage(bytes, mimeType);
  return http.MultipartFile.fromBytes(
    field,
    bytes,
    filename: 'upload_${DateTime.now().millisecondsSinceEpoch}.${t.ext}',
    contentType: MediaType.parse(t.mime),
  );
}

/// 網頁體驗版不支援檔案匯出／分享（沒有可寫入的本機檔案系統）。
const String kWebExportUnsupportedMessage = '網頁體驗版不支援匯出，請使用手機 App';

/// 匯出類功能開頭呼叫：網頁版丟出帶友善訊息的 [UnsupportedError]，手機版不受影響。
void ensureFileExportSupported() {
  if (kIsWeb) throw UnsupportedError(kWebExportUnsupportedMessage);
}
