import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/pairing_api.dart';
import 'api/call_api.dart';
import 'api/ai_chat_api.dart';
import 'api/elder_data_api.dart';
import 'api/cctv_alert_api.dart';
import 'api/reminder_api.dart';
import 'api/community_api.dart';

export 'api/cctv_alert_api.dart' show CctvPushResult;
export 'api/api_client.dart';
export 'api/auth_api.dart';
export 'api/pairing_api.dart';
export 'api/call_api.dart';
export 'api/ai_chat_api.dart';
export 'api/elder_data_api.dart';
export 'api/cctv_alert_api.dart';
export 'api/reminder_api.dart';
export 'api/community_api.dart';

/// 專案 API 門面 (Facade Pattern)
///
/// 負責將所有舊版 `ApiService.xxx()` 的靜態呼叫透明轉發給對應的領域 API 模組：
/// - [AuthApi]: 登入、註冊、OIDC、訂閱、帳號復原、Session 管理
/// - [PairingApi]: 配對碼、監視機 Setup、長輩綁定與解綁
/// - [CallApi]: 來電拒接、通話歷史
/// - [AiChatApi]: AI 對話、串流、ASR/TTS、每日建議、情緒分析
/// - [ElderDataApi]: 長輩資料、個人檔案、活動紀錄、家庭留言
/// - [CctvAlertApi]: CCTV 串流、跌倒測試、設備管理、緊急警報歷史、室內定位 (IPS)
/// - [ReminderApi]: 排程提醒 CRUD 與打卡
/// - [CommunityApi]: 社群貼文、互動點讚、留言與圖片上傳
class ApiService {
  // --- 基礎 URL 與通用請求 ---
  static String get baseUrl => ApiClient.baseUrl;
  static String get serverRootUrl => ApiClient.serverRootUrl;
  static String get localAiBaseUrl => ApiClient.localAiBaseUrl;

  static Future<Map<String, dynamic>?> get(String path) => ApiClient.get(path);
  static Future<Map<String, dynamic>?> post(String path, Map<String, dynamic> body) => ApiClient.post(path, body);
  static Future<Map<String, dynamic>?> put(String path, Map<String, dynamic> body) => ApiClient.put(path, body);
  static Future<Map<String, dynamic>?> delete(String path) => ApiClient.delete(path);

  // --- Auth & Account ---
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String role,
  }) => AuthApi.register(username: username, email: email, password: password, role: role);

  static Future<Map<String, dynamic>> login(String email, String password) => AuthApi.login(email, password);

  static Future<Map<String, dynamic>> testOidc({
    required String provider,
    required String email,
    required String uid,
    required String token,
  }) => AuthApi.testOidc(provider: provider, email: email, uid: uid, token: token);

  static Future<Map<String, dynamic>> checkHealth() => AuthApi.checkHealth();

  static Future<Map<String, dynamic>> generateRecoveryLink({
    required int familyId,
    required String elderId,
  }) => AuthApi.generateRecoveryLink(familyId: familyId, elderId: elderId);

  static Future<Map<String, dynamic>> verifyRecoveryCode(String code) => AuthApi.verifyRecoveryCode(code);

  static Future<bool> releaseSession({
    required String fcmToken,
    int? userId,
    String? roomId,
  }) => AuthApi.releaseSession(fcmToken: fcmToken, userId: userId, roomId: roomId);

  static Future<Map<String, dynamic>> getSubscriptionTier(int userId) => AuthApi.getSubscriptionTier(userId);
  static Future<Map<String, dynamic>> getSubscriptionRecords(int userId) => AuthApi.getSubscriptionRecords(userId);

  // --- Pairing & Monitor Setup ---
  static String? get lastResolveError => PairingApi.lastResolveError;
  static set lastResolveError(String? value) => PairingApi.lastResolveError = value;

  static Future<Map<String, dynamic>> requestPairingCode() => PairingApi.requestPairingCode();
  static Future<Map<String, dynamic>> checkPairingStatus(String code) => PairingApi.checkPairingStatus(code);
  static Future<Map<String, dynamic>> confirmPairing({
    required int familyId,
    required String code,
    required String elderName,
    required String gender,
    required int age,
  }) => PairingApi.confirmPairing(
        familyId: familyId,
        code: code,
        elderName: elderName,
        gender: gender,
        age: age,
      );

  static Future<Map<String, dynamic>> ensureYuxuanDemoElder() => PairingApi.ensureYuxuanDemoElder();
  static Future<Map<String, dynamic>> ensureGawaDemoElder() => PairingApi.ensureGawaDemoElder();
  static Future<Map<String, dynamic>> unbindElder(int familyId, Object elderId) => PairingApi.unbindElder(familyId, elderId);

  static Future<Map<String, dynamic>?> createMonitorSetup(int familyId, String elderId, String deviceName) =>
      PairingApi.createMonitorSetup(familyId, elderId, deviceName);

  static Future<Map<String, dynamic>?> resolveMonitorSetup(String code) => PairingApi.resolveMonitorSetup(code);

  static Future<Map<String, dynamic>?> getMonitorSetupStatus(String code, {required int userId}) =>
      PairingApi.getMonitorSetupStatus(code, userId: userId);

  // --- Call ---
  static Future<bool> declineCall({
    required String roomId,
    required String senderId,
    String? callId,
  }) => CallApi.declineCall(roomId: roomId, senderId: senderId, callId: callId);

  static Future<Map<String, dynamic>> getCallHistory(String roomId) => CallApi.getCallHistory(roomId);

  // --- AI Chat, Voice, Persona, Daily Suggestions ---
  static Future<Map<String, dynamic>> aiChat(int userId, String message, {String? imageUrl}) =>
      AiChatApi.aiChat(userId, message, imageUrl: imageUrl);

  static Stream<String> aiChatStream(
    int userId,
    String message, {
    String? appellation,
    String? userName,
  }) => AiChatApi.aiChatStream(userId, message, appellation: appellation, userName: userName);

  static Future<String?> transcribeAudio(String filePath) => AiChatApi.transcribeAudio(filePath);
  static Future<Map<String, dynamic>> petGreeting(int userId, String context) => AiChatApi.petGreeting(userId, context);
  static Future<List<dynamic>> getPersonaTemplates() => AiChatApi.getPersonaTemplates();
  static Future<Map<String, dynamic>> getElderAgentProfile(int elderId) => AiChatApi.getElderAgentProfile(elderId);
  static Future<Map<String, dynamic>> getDailySuggestions(int elderId) => AiChatApi.getDailySuggestions(elderId);
  static Future<Map<String, dynamic>> getNews({
    String category = 'politics',
    int limit = 3,
    String? dataDate,
  }) => AiChatApi.getNews(category: category, limit: limit, dataDate: dataDate);

  static Future<Map<String, dynamic>> synthesizeTts({
    required String text,
    String? emotion,
    String engine = 'edge',
  }) => AiChatApi.synthesizeTts(text: text, emotion: emotion, engine: engine);

  static Future<Map<String, dynamic>> generatePondLeaf(int userId) => AiChatApi.generatePondLeaf(userId);
  static Future<Map<String, dynamic>?> getElderMoodInsight(String elderId) => AiChatApi.getElderMoodInsight(elderId);

  // --- Elder Data & Profile ---
  static Future<Map<String, dynamic>> getStatus(int userId) => ElderDataApi.getStatus(userId);

  static Future<Map<String, dynamic>> updateElderInfo({
    required int familyId,
    required int elderId,
    String? userName,
    int? age,
    String? gender,
  }) => ElderDataApi.updateElderInfo(
        familyId: familyId,
        elderId: elderId,
        userName: userName,
        age: age,
        gender: gender,
      );

  static Future<Map<String, dynamic>> logActivity(
    int userId,
    String type,
    String content, {
    Map<String, dynamic>? extraData,
  }) => ElderDataApi.logActivity(userId, type, content, extraData: extraData);

  static Future<Map<String, dynamic>> sendFamilyMessage({
    required int familyId,
    required int elderId,
    required String content,
  }) => ElderDataApi.sendFamilyMessage(familyId: familyId, elderId: elderId, content: content);

  @Deprecated('Use getPairedElders instead')
  static Future<List<dynamic>> getElderData(String userId) => ElderDataApi.getElderData(userId);
  static Future<List<dynamic>> getPairedElders(int userId) => ElderDataApi.getPairedElders(userId);
  static Future<bool> hasCommDevice(String elderId) => ElderDataApi.hasCommDevice(elderId);
  static Future<List<dynamic>> getPairedFamily(int userId) => ElderDataApi.getPairedFamily(userId);
  static Future<Map<String, dynamic>> getElderProfile(int userId) => ElderDataApi.getElderProfile(userId);

  static Future<Map<String, dynamic>> updateElderProfile({
    required int userId,
    String? phone,
    String? location,
    String? appellation,
    int? aiEmotionTone,
    int? aiTextVerbosity,
    String? chronicDiseases,
    String? medicationNotes,
    String? interests,
    String? aiPersona,
    String? lifeStory,
    int? heartbeatFrequency,
    int? age,
    String? residenceCity,
    String? residenceDistrict,
  }) => ElderDataApi.updateElderProfile(
        userId: userId,
        phone: phone,
        location: location,
        appellation: appellation,
        aiEmotionTone: aiEmotionTone,
        aiTextVerbosity: aiTextVerbosity,
        chronicDiseases: chronicDiseases,
        medicationNotes: medicationNotes,
        interests: interests,
        aiPersona: aiPersona,
        lifeStory: lifeStory,
        heartbeatFrequency: heartbeatFrequency,
        age: age,
        residenceCity: residenceCity,
        residenceDistrict: residenceDistrict,
      );

  static Future<Map<String, dynamic>> uploadAvatar(int userId, String filePath) =>
      ElderDataApi.uploadAvatar(userId, filePath);

  static Future<Map<String, dynamic>> uploadImage(String filePath) =>
      ElderDataApi.uploadImage(filePath);

  static Future<List<dynamic>> getElderActivityLogs(String elderId, {int limit = 10}) =>
      ElderDataApi.getElderActivityLogs(elderId, limit: limit);

  // --- CCTV, Alerts, Audio Bridge & IPS ---
  static Future<CctvPushResult> pushCctvFrame({
    required String elderId,
    required String deviceName,
    required Uint8List frameBytes,
  }) => CctvAlertApi.pushCctvFrame(
        elderId: elderId,
        deviceName: deviceName,
        frameBytes: frameBytes,
      );

  static Future<String?> triggerTestFall({
    required String elderId,
    required String deviceName,
  }) => CctvAlertApi.triggerTestFall(elderId: elderId, deviceName: deviceName);

  static Future<bool> deleteMonitorDevice({
    required String elderId,
    required String deviceName,
    int? userId,
  }) => CctvAlertApi.deleteMonitorDevice(
        elderId: elderId,
        deviceName: deviceName,
        userId: userId,
      );

  static Future<List<dynamic>> fetchMonitorDevices({
    required String elderId,
    required int userId,
  }) => CctvAlertApi.fetchMonitorDevices(elderId: elderId, userId: userId);

  static Future<List<dynamic>?> fetchMonitorDevicesOrNull({
    required String elderId,
    required int userId,
  }) => CctvAlertApi.fetchMonitorDevicesOrNull(elderId: elderId, userId: userId);

  static Future<Map<String, dynamic>?> renameMonitorDevice({
    required String elderId,
    required int userId,
    required String oldDeviceName,
    required String newDeviceName,
  }) => CctvAlertApi.renameMonitorDevice(
        elderId: elderId,
        userId: userId,
        oldDeviceName: oldDeviceName,
        newDeviceName: newDeviceName,
      );

  static Future<Map<String, dynamic>?> openAudioBridge({
    required int alertId,
    required int fromId,
    required int toDeviceId,
  }) => CctvAlertApi.openAudioBridge(
        alertId: alertId,
        fromId: fromId,
        toDeviceId: toDeviceId,
      );

  static Future<Map<String, dynamic>?> checkAudioBridge(int alertId, {int? userId}) =>
      CctvAlertApi.checkAudioBridge(alertId, userId: userId);

  static Future<Map<String, dynamic>?> markFalseAlarm({
    required int alertId,
    required int userId,
  }) => CctvAlertApi.markFalseAlarm(alertId: alertId, userId: userId);

  static Future<List<dynamic>> getEmergencyAlerts(
    String elderId, {
    required int userId,
    String? status,
    int limit = 20,
  }) => CctvAlertApi.getEmergencyAlerts(
        elderId,
        userId: userId,
        status: status,
        limit: limit,
      );

  static Future<List<dynamic>> getZoneConfig(
    String elderId, {
    required int userId,
    required int deviceId,
  }) => CctvAlertApi.getZoneConfig(elderId, userId: userId, deviceId: deviceId);

  static Future<String?> saveZoneConfig(
    String elderId, {
    required int userId,
    required int deviceId,
    required List<Map<String, dynamic>> zones,
  }) => CctvAlertApi.saveZoneConfig(
        elderId,
        userId: userId,
        deviceId: deviceId,
        zones: zones,
      );

  static Future<Map<String, dynamic>> getCurrentZone(
    String elderId, {
    required int userId,
    required int deviceId,
  }) => CctvAlertApi.getCurrentZone(elderId, userId: userId, deviceId: deviceId);

  static String zoneSnapshotUrl(
    String elderId, {
    required int userId,
    required int deviceId,
  }) => CctvAlertApi.zoneSnapshotUrl(elderId, userId: userId, deviceId: deviceId);

  // --- Remote Reminders ---
  static Future<List<dynamic>> getElderReminders(String elderId) => ReminderApi.getElderReminders(elderId);
  static Future<bool> createElderReminder(Map<String, dynamic> body) => ReminderApi.createElderReminder(body);
  static Future<bool> toggleElderReminder(int reminderId) => ReminderApi.toggleElderReminder(reminderId);
  static Future<bool> deleteElderReminder(int reminderId) => ReminderApi.deleteElderReminder(reminderId);
  static Future<bool> updateElderReminder(int reminderId, Map<String, dynamic> body) =>
      ReminderApi.updateElderReminder(reminderId, body);
  static Future<bool> completeElderReminder(int reminderId) => ReminderApi.completeElderReminder(reminderId);

  // --- Community ---
  static Future<List<dynamic>> getCommunityPosts({
    int? familyId,
    int? userId,
    int limit = 50,
  }) => CommunityApi.getCommunityPosts(familyId: familyId, userId: userId, limit: limit);

  static Future<Map<String, dynamic>?> createCommunityPost({
    required int familyId,
    required int authorId,
    required String authorName,
    String authorRole = 'elder',
    required String content,
    String mood = '😊',
    String? stampType,
    String? imageUrl,
  }) => CommunityApi.createCommunityPost(
        familyId: familyId,
        authorId: authorId,
        authorName: authorName,
        authorRole: authorRole,
        content: content,
        mood: mood,
        stampType: stampType,
        imageUrl: imageUrl,
      );

  static Future<Map<String, dynamic>?> toggleCommunityPostLike({
    required int postId,
    required int userId,
  }) => CommunityApi.toggleCommunityPostLike(postId: postId, userId: userId);

  static Future<Map<String, dynamic>?> addCommunityComment({
    required int postId,
    required int authorId,
    required String authorName,
    String authorRole = 'elder',
    required String message,
    String? imageUrl,
  }) => CommunityApi.addCommunityComment(
        postId: postId,
        authorId: authorId,
        authorName: authorName,
        authorRole: authorRole,
        message: message,
        imageUrl: imageUrl,
      );

  static Future<String?> uploadCommunityImage(File imageFile) =>
      CommunityApi.uploadCommunityImage(imageFile);
}
