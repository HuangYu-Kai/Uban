import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../identification_screen.dart';
import '../../services/session_manager.dart';
import '../../services/api_service.dart';
import '../../services/friend_service.dart';
import '../../services/elder_location_service.dart';
import 'elder_layout.dart';
import '../../services/api/location_api.dart';
import '../../services/location_device_status.dart';
import '../../theme/app_theme.dart' show ElderScale;
import '../../services/elder_reminder_manager.dart';
import '../../widgets/spotlight_tutorial.dart';

// 模組化子元件與彈窗
import 'profile/models/pet_mood.dart'; // ⚠️ 只借用 PetHeartParticle，PetMood 列舉本身在小豬之家改版後已不再使用
import 'profile/dialogs/family_pairing_dialog.dart';
import 'profile/dialogs/ai_assistant_settings_dialog.dart';
import 'profile/widgets/today_tasks_handmade_section.dart';
import 'profile/widgets/profile_action_card.dart';

class ElderProfileTab extends StatefulWidget {
  final int userId;
  final String userName;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey，全部選填。由
  //   上層 ElderHomeScreen 持有並傳入，傳 null 時完全不影響現有畫面。
  final GlobalKey? tasksKey;
  final GlobalKey? familyPairingKey;
  final GlobalKey? aiAssistantKey;

  const ElderProfileTab({
    super.key,
    required this.userId,
    required this.userName,
    this.tasksKey,
    this.familyPairingKey,
    this.aiAssistantKey,
  });

  @override
  State<ElderProfileTab> createState() => _ElderProfileTabState();
}

class _ElderProfileTabState extends State<ElderProfileTab>
    with TickerProviderStateMixin, WidgetsBindingObserver {


  // 小豬預設對話語錄（用於任務打卡的短暫慶祝語結束後回到的預設狀態）
  // ★ 2026-09-15 溢位巡檢時發現：這句沿用自舊的 _pigQuotes，寫死了「阿公」。
  //   自主模式的長輩過去會預設叫「長輩朋友」、性別未知（第四十九輪已改為必須
  //   輸入真實稱呼，不再有這個預設值），但阿嬤看到小豬喊她阿公一樣會困惑
  //   ——與 memoir_service 先前修掉的是同一類問題，故仍保留中性稱呼。
  static const String _defaultSpeechText = '今天天氣真好，一起散步活動身體吧！🌿';

  // ── 🐾 小豬之家狀態 ────────────────────────────────────────
  late AnimationController _particleController;
  late AnimationController _petBounceController;
  final List<PetHeartParticle> _petParticles = [];

  // ★ 第四十一輪（item 3）：朋友圈好友 ID（見 PetCornerActions 內部另行解析，
  // 本欄位供 _loadElderReminders 讀排程提醒使用）。null 代表尚未載入完成或
  // 載入失敗。
  // ★ 第五十輪：同時也是好友寵物排行榜（PetLeaderboardService）與今日食物
  // 解鎖來源（PetProgressService.loadFoodUnlocks）要用的權威 elder_id，
  // 三者共用同一把鍵，理由同 _loadElderReminders 的既有註解——不可各自
  // 用 widget.userId 補零臆測。
  String? _myFriendElderId;

  // ── 🛰️ 與家人分享 GPS 位置（戶外定位軌跡，與上方本機步數用途的 GPS 追蹤
  //   是不同的東西——見 ElderLocationService 檔頭說明）───────────────
  // 系統預設開啟（與後端 elder_profile.location_sharing_enabled DEFAULT 1 一致），
  // 實際值以 _loadLocationSharingState() 讀回的後端狀態為準。
  bool _locationSharingEnabled = true;
  bool _locationSharingBusy = false;


  // ── 📋 子女排程生活任務 ──────────────────────────────────
  List<Map<String, dynamic>> _reminders = [];
  Set<int> _completedReminderIds = {};
  bool _isLoadingReminders = false;
  // ★ 第四十九輪：見 _loadElderReminders 的 catch 區塊與
  // TodayTasksHandmadeSection.hasLoadError 的說明——讀取失敗不該跟「真的
  // 沒有安排提醒」顯示成同一張空狀態卡片。
  bool _hasReminderLoadError = false;

  // ── 🎨 小豬對話氣泡文字 ──────────────────────────────
  // 小豬頁面搬到 ElderPetTab 後，本分頁不再顯示氣泡；任務打卡失敗回退仍照舊
  // 重設這個值（_toggleTaskCompletion 邏輯一行未改），故保留欄位。
  // ignore: unused_field
  String _speechText = _defaultSpeechText;
  Timer? _speechBubbleTimer;

  // ★ 第四十一輪（item 3）：讀取朋友圈好友 ID。權威來源是後端 elder_profile
  // 表（見 FriendService.resolveMyElderId 的說明），不可用 userId 補零臆測。
  Future<void> _loadMyFriendElderId() async {
    final id = await FriendService.resolveMyElderId(widget.userId);
    if (mounted) {
      setState(() => _myFriendElderId = id);
      // ★ 第四十三輪修復：_loadElderReminders 讀取排程提醒的權威鍵就是這裡解析
      // 出的 elder_id（見該函式說明）。initState 呼叫 _loadElderReminders 時
      // 本欄位通常還沒載入完成而被暫緩，這裡載入完成後補發一次真正的讀取。
      _loadElderReminders();
    }
  }

  @override
  void initState() {
    super.initState();

    _particleController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..addListener(_updateParticles);

    _petBounceController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _loadElderReminders();
    ElderReminderManager.instance.addListener(_onReminderManagerUpdate);
    _loadMyFriendElderId();
    _loadLocationSharingState();
    // 長輩從手機「設定」頁（開定位／改權限）回到 App 時，重新檢查定位權限，
    // 讓「我的」分頁的提示自動消失、位置回報自動恢復。這個觀察者只做這一件
    // 事（見 didChangeAppLifecycleState），與 ElderHomeScreen 自己的觀察者
    // 互不影響。
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 只在回到前景時重查；recheckDeviceStatus 內部自帶守門（分享關閉、正在啟動
    // 時直接返回），而且只用 checkPermission，不會再次跳出權限對話框。
    if (state == AppLifecycleState.resumed && _locationSharingEnabled) {
      unawaited(ElderLocationService.instance.recheckDeviceStatus());
    }
  }

  /// 讀取目前「與家人分享我的位置」開關狀態，供 [_buildLocationSharingCard] 顯示。
  /// 失敗（離線／尚未配對）時維持預設開啟的顯示，不影響畫面其餘功能。
  Future<void> _loadLocationSharingState() async {
    final elderId = await FriendService.resolveMyElderId(widget.userId);
    if (elderId == null || !mounted) return;
    final enabled = await LocationApi.getSharingEnabled(
      elderId: elderId,
      userId: widget.userId,
    );
    if (enabled != null && mounted) {
      setState(() => _locationSharingEnabled = enabled);
    }
  }

  Future<void> _handleLocationSharingToggle(bool value) async {
    if (_locationSharingBusy) return;
    setState(() => _locationSharingBusy = true);
    final ok = await ElderLocationService.instance.setSharingEnabled(value);
    if (!mounted) return;
    setState(() {
      _locationSharingBusy = false;
      if (ok) _locationSharingEnabled = value;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('設定失敗，請檢查網路連線後再試一次')),
      );
    }
  }

  void _onReminderManagerUpdate() {
    if (mounted) {
      _loadElderReminders();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ElderReminderManager.instance.removeListener(_onReminderManagerUpdate);
    _particleController.dispose();
    _petBounceController.dispose();
    super.dispose();
  }

  void _spawnHeartParticles() {
    _petParticles.clear();
    final rand = math.Random();
    const colors = [
      Color(0xFFFF6B8B),
      Color(0xFFFF8E53),
      Color(0xFFEC4899),
      Color(0xFFF43F5E),
      Color(0xFFA855F7),
    ];
    for (int i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + (rand.nextDouble() - 0.5) * 1.4;
      final speed = 70.0 + rand.nextDouble() * 100.0;
      _petParticles.add(
        PetHeartParticle(
          position: Offset(65.0 + (rand.nextDouble() - 0.5) * 36, 65.0),
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          scale: 0.8 + rand.nextDouble() * 0.6,
          opacity: 1.0,
          color: colors[rand.nextInt(colors.length)],
        ),
      );
    }
  }

  void _updateParticles() {
    if (_petParticles.isEmpty) return;
    final progress = _particleController.value;
    for (final p in _petParticles) {
      p.position += p.velocity * 0.016;
      p.opacity = (1.0 - progress).clamp(0.0, 1.0);
      p.scale = math.max(0.2, p.scale * 0.98);
    }
    setState(() {});
  }

  // ── 📋 載入子女排程生活任務 ──────────────────────────────────
  Future<void> _loadElderReminders() async {
    // ★ 第四十三輪修復：排程提醒送達失敗的根因之一是讀寫用了兩把不同的鍵——
    // 家屬端寫入 `remote_reminders.elder_id` 用的是 elder_profile 的 4 碼房號
    // （見 alert_center_screen.dart:20-23 的既定寫法），這裡卻讀 widget.userId
    // （DB 整數 PK）。後端 main.py::check_remote_reminders_job 組 Socket 房名
    //／查 FCM token 都是用前者，兩把鍵對不上時，觸發會送到沒人在的房間、
    // FCM 也查無 token——長輩端前景背景兩者皆完全收不到。
    // 權威鍵與「我的好友 ID」（_myFriendElderId，見 _loadMyFriendElderId）
    // 一致，兩者都是後端 elder_profile 表解析出的同一個 4 碼 elder_id。
    // initState 會在 _myFriendElderId 尚未載入完成前先呼叫一次本函式；此時
    // 寧可暫緩本次讀取、維持讀取中畫面，也不能退回 widget.userId 兜底——那樣
    // 讀到的會是另一把鍵，等同沒修。_loadMyFriendElderId 載入完成後會再呼叫
    // 一次本函式補讀正確資料。
    final elderKey = _myFriendElderId;
    if (elderKey == null) {
      if (mounted) setState(() => _isLoadingReminders = true);
      return;
    }

    setState(() => _isLoadingReminders = true);
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final completedList = prefs.getStringList('completed_tasks_$today') ?? [];
    _completedReminderIds =
        completedList.map((e) => int.tryParse(e) ?? -1).toSet();

    try {
      final list = await ApiService.getElderReminders(elderKey);
      if (mounted) {
        // ★ 第四十六輪（E3）：API 回空清單時，過去會塞入 3 筆假提醒
        // （id 101/102/103：服藥／溫開水／散步），讓真的沒設提醒的長輩
        // 看到可以「完成」的假任務，還會驅動小豬心情與「全數達標」徽章。
        // 現在誠實呈現空清單，空狀態文案交給 TodayTasksHandmadeSection
        // 既有的空狀態分支處理。
        setState(() {
          _reminders = List<Map<String, dynamic>>.from(list);
          _isLoadingReminders = false;
          _hasReminderLoadError = false;
        });
      }
    } catch (e) {
      // ★ 第四十九輪：讀取失敗與「真的沒有安排提醒」以前是同一種空清單畫面
      // （`_reminders` 維持空陣列），長輩會被誤導成「今天沒有藥要吃」。
      // 本函式有三個呼叫點（initState／_loadMyFriendElderId 完成後／
      // ElderReminderManager 通知監聽器，見上方 _onReminderManagerUpdate），
      // 後者會在約每 2 分鐘一次的後端排程同步成功時觸發，等同已經有自動
      // 重試機制，不需要像 elder_home_tab.dart 那樣額外排一次性重試計時器。
      if (mounted) {
        setState(() {
          _isLoadingReminders = false;
          _hasReminderLoadError = true;
        });
      }
    }
  }

  // ── 🎯 任務打卡完成切換 ────────────────────────────────────
  Future<void> _toggleTaskCompletion(int reminderId) async {
    HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final isAlreadyDone = _completedReminderIds.contains(reminderId);
    setState(() {
      if (isAlreadyDone) {
        _completedReminderIds.remove(reminderId);
      } else {
        _completedReminderIds.add(reminderId);
        _spawnHeartParticles();
        _petBounceController.forward(from: 0.0);
        _particleController.forward(from: 0.0);
      }
    });

    await prefs.setStringList(
      'completed_tasks_$today',
      _completedReminderIds.map((e) => e.toString()).toList(),
    );

    // ★ 第四十六輪（E1）：比照 elder_home_tab.dart 的 _completeNextDose——
    // 本機立即更新給即時回饋，另外同步後端，家屬端才看得到長輩在「我的」
    // 分頁的打卡紀錄。只在「標記為完成」時同步，取消完成（isAlreadyDone
    // 為 true）不呼叫——後端沒有取消端點，這是既有限制，不在本次修復
    // 範圍內。⚠️ 已知後果：長輩取消打卡後，後端 activity_log 仍留著那筆
    // medication 紀錄不會被撤銷；只要有消費端是直接讀 activity_log（而非
    // 本機 completed_tasks_<date>）判斷「今天吃藥了沒」，就可能誤判成
    // 已完成。
    //
    // ★ 第四十九輪修復：原本用 unawaited 完全不管成不成功，網路失敗時
    // 畫面照樣顯示打卡完成（含小豬慶祝動畫），家屬端資料庫其實沒有這筆
    // 紀錄，是用藥安全問題。改成 await 讀 bool，失敗時要把上面 setState
    // 區塊在「標記為完成」分支寫入的三份樂觀更新狀態全部回退：記憶體中的
    // _completedReminderIds、SharedPreferences 的 completed_tasks_<today>、
    // 以及被提前導向慶祝文案的 _speechText（連同尚未觸發的
    // _speechBubbleTimer 一併取消)——否則小豬會在打卡其實失敗時仍開心地說
    // 「打卡成功」。粒子與彈跳動畫（_spawnHeartParticles／
    // _petBounceController／_particleController）屬於已播放的短暫視覺
    // 效果，等網路來回一趟通常早已播完，不追加回滾。
    // ApiService.completeElderReminder 內部已經把逾時／連線失敗／後端
    // 錯誤全部吞成 false、不會對外拋例外（見 reminder_api.dart），這裡的
    // try/catch 只是防禦未來改版又開始拋例外，不能取代讀 bool。
    if (!isAlreadyDone) {
      bool success;
      try {
        success = await ApiService.completeElderReminder(reminderId);
      } catch (e) {
        debugPrint('⚠️ [ElderProfileTab] completeElderReminder 例外: $e');
        success = false;
      }
      if (!mounted) return;
      if (!success) {
        _speechBubbleTimer?.cancel();
        setState(() {
          _completedReminderIds.remove(reminderId);
          _speechText = _defaultSpeechText;
        });
        await prefs.setStringList(
          'completed_tasks_$today',
          _completedReminderIds.map((e) => e.toString()).toList(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '打卡沒有送出成功，請確認網路後再按一次',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor: const Color(0xFFB91C1C),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.all(20),
          ),
        );
      }
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '切換身分',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: Text('確定要登出並回到身分辨識頁面嗎？', style: GoogleFonts.notoSansTc()),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              '取消',
              style: GoogleFonts.notoSansTc(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // ★ 2026-08-10 第二十輪：改走 SessionManager 統一釋放入口，
              //   除了原本清的 device_role_*／saved_is_cctv，
              //   也一併清掉 user_role，避免殘留 'elder' 造成下次冷啟動被誤判為長輩 session。
              // ★ 2026-08-25（本輪）：這是長輩自己主動按「登出」，不是家屬遠端強制
              //   解綁，帶 preserveQuickLogin: true 保留 last_elder_* 快速登入記憶鍵
              //   （護欄 G24），讓下次可以在配對頁「快速登入同一長輩」一鍵登回。
              await SessionManager.releaseSession(preserveQuickLogin: true);

              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const IdentificationScreen()),
                (route) => false,
              );
            },
            child: Text(
              '登出',
              style: GoogleFonts.notoSansTc(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 💡 長輩後悔藥：隨時重新觀看新手教學（暖色手作系統，全頁唯一抽出的
  // inline widget——標題／副標題皆為固定文案，非使用者可控字串，但仍加
  // maxLines/ellipsis 做防禦）。
  Widget _buildTutorialReplayCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.school_rounded,
              color: Color(0xFFB45309), size: 28),
        ),
        title: Text(
          '重新觀看新手導覽',
          style: GoogleFonts.notoSansTc(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF451A03),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '忘記功能怎麼用？點此重新開啟操作介紹',
          style: GoogleFonts.notoSansTc(
              fontSize: 14, color: const Color(0xFF8C6D58)),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            size: 18, color: Color(0xFFD4C5B9)),
        onTap: () async {
          await SpotlightTutorial.resetAllTutorials();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已重新開啟教學！切換至首頁即可重新查看導覽。')),
            );
          }
        },
      ),
    );
  }

  // 🛰️ 與家人分享我的位置：長輩本人的隱私開關，系統預設開啟，長輩可隨時
  // 自行關閉（完全由長輩本人決定，家屬無法代為切換）。關閉時家屬即使
  // 已配對也看不到位置資料（伺服器端讀取端會再檢查一次，這裡的開關只
  // 決定裝置要不要持續耗電回報）。標題／副標題為固定文案，仍加
  // maxLines/ellipsis 防禦（Row 內含開關元件，同列有其他元素）。
  Widget _buildLocationSharingCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            secondary: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.route_rounded,
                  color: Color(0xFFB45309), size: 28),
            ),
            title: Text(
              '與家人分享我的位置',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF451A03),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _locationSharingEnabled ? '子女可以看到您的位置與移動路線' : '目前未分享，子女無法看到您的位置',
              style: GoogleFonts.notoSansTc(
                  fontSize: 14, color: const Color(0xFF8C6D58)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            value: _locationSharingEnabled,
            onChanged: _locationSharingBusy ? null : _handleLocationSharingToggle,
            activeThumbColor: const Color(0xFFB45309),
          ),
          // 手機的定位功能／權限沒開時，開關雖然是「開」，位置其實傳不出去：
          // 在開關下方直接告訴長輩原因與怎麼修。
          ValueListenableBuilder<String?>(
            valueListenable: ElderLocationService.instance.deviceStatus,
            builder: (context, status, _) {
              if (!_locationSharingEnabled ||
                  !LocationDeviceStatus.isProblem(status)) {
                return const SizedBox.shrink();
              }
              return _buildLocationStatusHint(status!);
            },
          ),
        ],
      ),
    );
  }

  /// 位置分享卡片下方的「手機沒開定位」提示：白話說明原因 + 一顆大按鈕直接
  /// 帶長輩去修。沒有 Row——文字與按鈕都是整列寬度、可自動換行，不會溢位
  /// （鐵律 #14）。長輩從設定頁回來後由 [didChangeAppLifecycleState] 重查，
  /// 修好了提示就會自己消失。
  Widget _buildLocationStatusHint(String status) {
    final String message;
    final String buttonLabel;
    final Future<bool> Function() onPressed;
    switch (status) {
      case LocationDeviceStatus.serviceDisabled:
        message = '手機的定位功能關閉了';
        buttonLabel = '打開定位';
        onPressed = Geolocator.openLocationSettings;
        break;
      case LocationDeviceStatus.foregroundOnly:
        message = '位置權限只開了「使用 App 時」，請改成「一律允許」，家人才看得到';
        buttonLabel = '前往設定';
        onPressed = Geolocator.openAppSettings;
        break;
      default: // permission_denied／permission_denied_forever
        message = '還沒允許 Uban 使用位置';
        buttonLabel = '前往設定';
        onPressed = Geolocator.openAppSettings;
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '⚠️ $message',
            style: ElderScale.body.copyWith(
              color: const Color(0xFF7C2D12),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB45309),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () async {
                try {
                  await onPressed();
                } catch (e) {
                  debugPrint('⚠️ [ElderProfileTab] 開啟手機設定失敗: $e');
                }
              },
              child: Text(
                buttonLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ElderScale.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    String greetingTitle = '早安';
    if (hour >= 12 && hour < 18) greetingTitle = '午安';
    if (hour >= 18 || hour < 5) greetingTitle = '晚安';
    final orientation = MediaQuery.of(context).orientation;
    final bool isLandscape = orientation == Orientation.landscape &&
        MediaQuery.of(context).size.width >= 720;
    final String greetingLine = '$greetingTitle，${widget.userName}';

    // 小豬已搬到「小豬」分頁（ElderPetTab）；本頁只剩任務、家人綁定、
    // 語音助理、教學重播、位置分享與切換身分。
    final Widget body = isLandscape
        ? _buildLandscapeBody(context)
        : _buildPortraitBody(greetingLine, context);

    return Container(
      color: const Color(0xFFFAF7F2), // 溫暖手作燕麥宣紙底色
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(
            top: isLandscape ? 6 : 0,
            bottom: elderNavClearance(context),
          ),
          child: body,
        ),
      ),
    );
  }

  // ── 直屏 ──
  Widget _buildPortraitBody(
    String greetingLine,
    BuildContext context,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 0. 頁首：小豬搬走後留下的簡單標題（用戶名可能很長，需可收縮）
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '我的',
                style: GoogleFonts.notoSansTc(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF451A03),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                greetingLine,
                style: GoogleFonts.notoSansTc(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8C6D58),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 3. 今日生活排程與用藥打卡手帳
              TodayTasksHandmadeSection(
                key: widget.tasksKey,
                reminders: _reminders,
                completedReminderIds: _completedReminderIds,
                isLoadingReminders: _isLoadingReminders,
                onToggleTask: _toggleTaskCompletion,
                hasLoadError: _hasReminderLoadError,
              ),

              const SizedBox(height: 16),

              // 4. 底部快捷操作列
              Row(
                children: [
                  Expanded(
                    child: ProfileActionCard(
                      key: widget.familyPairingKey,
                      icon: Icons.family_restroom_rounded,
                      title: '家人綁定',
                      subtitle: '出示配對碼',
                      color: const Color(0xFFF59E0B),
                      // ★ 第四十九輪修復：過去沒傳 explicitElderId，對話框內部
                      // 只能猜 SharedPreferences 的 caregiver_id/last_elder_id，
                      // 兩鍵都讀不到時會靜默送出缺 id 的配對碼請求，被後端當成
                      // 新長輩註冊、家屬綁到幽靈帳號（見
                      // family_pairing_dialog.dart 的 fetchCode 說明）。這裡是
                      // 呼叫端手上現成、保證非空的正確長輩 id，直接明確傳入。
                      onTap: () =>
                          showFamilyPairingDialog(context, widget.userId),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ProfileActionCard(
                      key: widget.aiAssistantKey,
                      icon: Icons.assistant_rounded,
                      title: '語音助理',
                      subtitle: 'Hey 嘎蛙',
                      color: const Color(0xFFF59E0B),
                      onTap: () => showAiAssistantSettingsDialog(
                        context: context,
                        userId: widget.userId,
                        userName: widget.userName,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ProfileActionCard(
                      icon: Icons.logout_rounded,
                      title: '切換身分',
                      subtitle: '登出系統',
                      color: const Color(0xFFEF4444),
                      onTap: _handleLogout,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 5. 重新觀看新手導覽
              _buildTutorialReplayCard(context),

              const SizedBox(height: 12),

              // 6. 與家人分享我的位置（GPS 移動軌跡隱私開關）
              _buildLocationSharingCard(context),
            ],
          ),
        ),
      ],
    );
  }

  // ── 橫屏模式（平板座充模式）：左欄排程、右欄快捷操作 ──
  Widget _buildLandscapeBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 👉 右欄：今日生活排程打卡手帳 ＆ 底部快捷操作列（佔 50%）
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TodayTasksHandmadeSection(
                      key: widget.tasksKey,
                      reminders: _reminders,
                      completedReminderIds: _completedReminderIds,
                      isLoadingReminders: _isLoadingReminders,
                      onToggleTask: _toggleTaskCompletion,
                      isLandscape: true,
                      hasLoadError: _hasReminderLoadError,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ProfileActionCard(
                            key: widget.familyPairingKey,
                            icon: Icons.family_restroom_rounded,
                            title: '家人綁定',
                            subtitle: '出示配對碼',
                            color: const Color(0xFFF59E0B),
                            // ★ 第四十九輪修復：理由同直屏版本，見上方
                            // _buildPortraitBody 對應按鈕的註解。
                            onTap: () =>
                                showFamilyPairingDialog(context, widget.userId),
                            isLandscape: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ProfileActionCard(
                            key: widget.aiAssistantKey,
                            icon: Icons.assistant_rounded,
                            title: '語音助理',
                            subtitle: 'Hey 嘎蛙',
                            color: const Color(0xFFF59E0B),
                            onTap: () => showAiAssistantSettingsDialog(
                              context: context,
                              userId: widget.userId,
                              userName: widget.userName,
                            ),
                            isLandscape: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ProfileActionCard(
                            icon: Icons.logout_rounded,
                            title: '切換身分',
                            subtitle: '登出系統',
                            color: const Color(0xFFEF4444),
                            onTap: _handleLogout,
                            isLandscape: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ★ 橫向版面原本漏掉「重新觀看新手導覽」，本輪補回
          _buildTutorialReplayCard(context),

          const SizedBox(height: 8),

          _buildLocationSharingCard(context),
        ],
      ),
    );
  }
}

