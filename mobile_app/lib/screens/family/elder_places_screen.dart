// lib/screens/family/elder_places_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../models/elder_place.dart';
import '../../services/api/location_api.dart';
import '../../theme/family_theme.dart';
import '../../widgets/ui/ui.dart';
import 'widgets/fam_ui.dart';
import 'widgets/gps_ui.dart';

/// 半徑可選值（公尺）；既有地點的半徑若不在其中，編輯時會補進選項。
const List<int> _kRadiusChoices = [100, 150, 300, 500];
const int _kDefaultRadiusM = 150;

/// 「遠離家提醒」可選距離（公里）；後端目前的值若不在其中，選單會補進該值。
const List<int> _kFarKmChoices = [1, 3, 5, 10];

/// 「失聯提醒」可選小時數。
const int _kMinNoUpdateHours = 1;
const int _kMaxNoUpdateHours = 12;

/// 安心提醒設定的預設值（後端尚未回傳該欄位時的顯示用）。
const String _kDefaultLateReturnTime = '21:00';
const String _kDefaultNoUpdateStart = '08:00';
const String _kDefaultNoUpdateEnd = '20:00';
const int _kDefaultNoUpdateHours = 3;
const int _kDefaultFarKm = 5;

/// 新增／編輯常去地點的共用對話框（家屬端專用；後端只允許家屬寫入）。
///
/// - 新增：傳 [position]（必填，否則視為程式錯誤而直接回傳 false）；
///   [presetHome] 為 true 時「設為家」預設開啟，名稱空白則預填「家」。
/// - 編輯：傳 [existing]，座標維持不變，只改名稱／半徑／是否為家。
///
/// 儲存成功回傳 true；取消或失敗（失敗會顯示 SnackBar 並留在對話框內）回傳 false。
Future<bool> showPlaceEditorDialog(
  BuildContext context, {
  required String elderId,
  required int userId,
  ElderPlace? existing,
  LatLng? position,
  bool presetHome = false,
}) async {
  if (existing == null && position == null) return false;
  // 新外觀（`#sh-place`）：以底部面板呈現；回傳值、不可點外面關閉的行為與舊對話框相同。
  // [context] 請傳家屬主題之下的 context，面板才會吃到家屬色票。
  final saved = await showUbanSheet<bool>(
    context,
    (_) => _PlaceEditorDialog(
      elderId: elderId,
      userId: userId,
      existing: existing,
      position: position,
      presetHome: presetHome,
    ),
    isDismissible: false,
  );
  return saved == true;
}

class _PlaceEditorDialog extends StatefulWidget {
  final String elderId;
  final int userId;
  final ElderPlace? existing;
  final LatLng? position;
  final bool presetHome;

  const _PlaceEditorDialog({
    required this.elderId,
    required this.userId,
    this.existing,
    this.position,
    this.presetHome = false,
  });

  @override
  State<_PlaceEditorDialog> createState() => _PlaceEditorDialogState();
}

class _PlaceEditorDialogState extends State<_PlaceEditorDialog> {
  late final TextEditingController _nameCtrl;
  late int _radiusM;
  late bool _isHome;
  bool _saving = false;
  String? _nameError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _isHome = e?.isHome ?? widget.presetHome;
    _radiusM = e?.radiusM ?? _kDefaultRadiusM;
    // 以「家」快速建立時先填好名稱，家屬可直接按儲存。
    final initialName = e?.name ?? (widget.presetHome ? '家' : '');
    _nameCtrl = TextEditingController(text: initialName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  List<int> get _radiusOptions {
    final opts = {..._kRadiusChoices, _radiusM}.toList()..sort();
    return opts;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '請輸入地點名稱');
      return;
    }
    if (name.length > 32) {
      setState(() => _nameError = '名稱最多 32 個字');
      return;
    }
    setState(() {
      _nameError = null;
      _saveError = null;
      _saving = true;
    });

    final existing = widget.existing;
    final ElderPlace? result;
    if (existing == null) {
      final pos = widget.position!;
      result = await LocationApi.createPlace(
        elderId: widget.elderId,
        userId: widget.userId,
        name: name,
        latitude: pos.latitude,
        longitude: pos.longitude,
        radiusM: _radiusM,
        isHome: _isHome,
      );
    } else {
      // 只送有改動的欄位；isHome 由伺服器負責清掉其他地點的「家」。
      result = await LocationApi.updatePlace(
        elderId: widget.elderId,
        placeId: existing.id,
        userId: widget.userId,
        name: name == existing.name ? null : name,
        radiusM: _radiusM == existing.radiusM ? null : _radiusM,
        isHome: _isHome == existing.isHome ? null : _isHome,
      );
    }

    if (!mounted) return;
    if (result == null) {
      // 面板的遮罩會蓋住底下的 SnackBar，所以同時在面板內顯示錯誤文字。
      setState(() {
        _saving = false;
        _saveError = '儲存失敗，請稍後再試';
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('儲存失敗，請稍後再試')));
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final isEdit = widget.existing != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isEdit ? '編輯地點' : '新增常去地點',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: famText(c.text, 20, weight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        UbanTextField(
          controller: _nameCtrl,
          label: '名稱',
          hintText: '例如：家、公園、市場',
          enabled: !_saving,
          maxLength: 32,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) {
            if (_nameError != null) setState(() => _nameError = null);
          },
          errorText: _nameError,
        ),
        const SizedBox(height: 14),
        Text('範圍半徑',
            style: famText(c.text2, 15, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        // 用 Wrap 讓窄螢幕／大字級自動換行，避免 RenderFlex 溢位。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in _radiusOptions) _radiusPill(c, r),
          ],
        ),
        const SizedBox(height: 14),
        // `.action`：surface2 底的「設為家」開關列。
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('設為家',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: famText(c.text, 15.5, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      '每位長輩只有一個家，設定後原本的家會取消',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text2, 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              UbanSwitch(
                value: _isHome,
                onChanged: _saving ? null : (v) => setState(() => _isHome = v),
              ),
            ],
          ),
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 10),
          Text(_saveError!, style: famText(c.danger, 14, weight: FontWeight.w700)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FamButton(
                label: '取消',
                kind: FamButtonKind.outline,
                onPressed: _saving ? null : () => Navigator.of(context).pop(false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FamButton(
                label: '儲存',
                onPressed: _saving ? null : _save,
                loading: _saving,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _radiusPill(UbanColors c, int r) {
    final selected = _radiusM == r;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _saving ? null : () => setState(() => _radiusM = r),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.brandContainer : c.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$r 公尺',
            style: famText(selected ? c.brandStrong : c.text2, 14.5,
                weight: FontWeight.w700, tabular: true),
          ),
        ),
      ),
    );
  }
}

/// 家屬端：長輩常去地點管理（列表、編輯、設為家、刪除）。
///
/// 返回時帶回「是否有任何變更」，呼叫端據此重新載入地圖上的地點。
class ElderPlacesScreen extends StatefulWidget {
  final String elderId;
  final int userId;
  final String elderName;

  const ElderPlacesScreen({
    super.key,
    required this.elderId,
    required this.userId,
    this.elderName = '長輩',
  });

  @override
  State<ElderPlacesScreen> createState() => _ElderPlacesScreenState();
}

enum _PlacesState { loading, ready, error }

enum _PlaceMenu { edit, setHome, delete }

class _ElderPlacesScreenState extends State<ElderPlacesScreen> {
  _PlacesState _state = _PlacesState.loading;
  List<ElderPlace> _places = const [];
  bool _changed = false;

  // 家屬主題之下的 context（State 自己的 context 在 FamilyThemeScope 之上）：
  // 用它開 sheet／對話框／時間選擇器，才會吃到家屬色票；每次 build 更新。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

  // 安心提醒設定（`settings` 為後端欄位原樣；null 表示尚未載入或讀取失敗）。
  Map<String, dynamic>? _alertSettings;
  bool _hasHome = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner && mounted) setState(() => _state = _PlacesState.loading);
    final result = await LocationApi.getPlaces(
      elderId: widget.elderId,
      userId: widget.userId,
    );
    if (!mounted) return;
    setState(() {
      if (result == null) {
        // 重新整理失敗時保留舊清單，只有首次載入失敗才顯示錯誤頁。
        _state = _places.isEmpty ? _PlacesState.error : _PlacesState.ready;
      } else {
        _places = _sorted(result);
        _state = _PlacesState.ready;
      }
    });
    // 地點變動後「家」可能剛被設定或移除，連同提醒設定一起重新讀取。
    if (result != null) unawaited(_loadAlertSettings());
  }

  Future<void> _loadAlertSettings() async {
    final data = await LocationApi.getAlertSettings(
      elderId: widget.elderId,
      userId: widget.userId,
    );
    if (!mounted || data == null) return;
    final raw = data['settings'];
    setState(() {
      if (raw is Map) _alertSettings = Map<String, dynamic>.from(raw);
      _hasHome = data['has_home'] == true;
    });
  }

  bool _alertBool(String key) => _alertSettings?[key] == true;

  int _alertInt(String key, int fallback) {
    final v = _alertSettings?[key];
    return v is num ? v.toInt() : fallback;
  }

  String _alertTime(String key, String fallback) {
    final v = _alertSettings?[key];
    if (v is! String) return fallback;
    final parts = v.split(':');
    if (parts.length < 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return fallback;
    return _formatTime(TimeOfDay(hour: h, minute: m));
  }

  static String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
  }

  /// 立即送出單一設定變更；失敗時只還原這次改動的欄位並提示。
  Future<void> _changeAlert(Map<String, dynamic> changes) async {
    final current = _alertSettings;
    if (current == null) return;
    final previous = {for (final k in changes.keys) k: current[k]};
    setState(() => _alertSettings = {...current, ...changes});

    final result = await LocationApi.updateAlertSettings(
      elderId: widget.elderId,
      userId: widget.userId,
      changes: changes,
    );
    if (!mounted) return;
    if (result == null) {
      setState(() => _alertSettings = {...?_alertSettings, ...previous});
      _snack('設定失敗，請稍後再試');
      return;
    }
    final saved = result['settings'];
    if (saved is Map) {
      setState(() => _alertSettings = {
            ...?_alertSettings,
            ...Map<String, dynamic>.from(saved),
          });
    }
  }

  Future<void> _pickTime(String key, String fallback) async {
    final picked = await showTimePicker(
      context: _themeCtx,
      initialTime: _parseTime(_alertTime(key, fallback)),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null || !mounted) return;
    final value = _formatTime(picked);
    if (value == _alertTime(key, fallback)) return;
    await _changeAlert({key: value});
  }

  /// 家排最前面，其餘維持後端順序。
  List<ElderPlace> _sorted(List<ElderPlace> src) => [
        ...src.where((p) => p.isHome),
        ...src.where((p) => !p.isHome),
      ];

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _edit(ElderPlace p) async {
    final saved = await showPlaceEditorDialog(
      _themeCtx,
      elderId: widget.elderId,
      userId: widget.userId,
      existing: p,
    );
    if (!saved || !mounted) return;
    _changed = true;
    await _load(showSpinner: false);
  }

  Future<void> _setHome(ElderPlace p) async {
    final result = await LocationApi.updatePlace(
      elderId: widget.elderId,
      placeId: p.id,
      userId: widget.userId,
      isHome: true,
    );
    if (!mounted) return;
    if (result == null) {
      _snack('儲存失敗，請稍後再試');
      return;
    }
    _changed = true;
    await _load(showSpinner: false);
  }

  Future<void> _delete(ElderPlace p) async {
    final ok = await showUbanDialog<bool>(
      _themeCtx,
      (ctx) {
        final c = UbanColors.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '刪除「${p.name}」？',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: famText(c.text, 20, weight: FontWeight.w900, height: 1.3),
            ),
            const SizedBox(height: 8),
            Text(
              '刪除後，這個地點不會再出現在地圖與行程中。',
              style: famText(c.text2, 14.5, height: 1.6),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FamButton(
                    label: '取消',
                    kind: FamButtonKind.outline,
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FamButton(
                    label: '刪除',
                    kind: FamButtonKind.danger,
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    final done = await LocationApi.deletePlace(
      elderId: widget.elderId,
      placeId: p.id,
      userId: widget.userId,
    );
    if (!mounted) return;
    if (!done) {
      _snack('刪除失敗，請稍後再試');
      return;
    }
    _changed = true;
    await _load(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    // 2026-10：push 出來的家屬頁要自己掛家屬主題。
    return FamilyThemeScope(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    _themed = context;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: _c.bg,
        appBar: famSubBar(context, title: '常去地點'),
        body: RefreshIndicator(
          onRefresh: () => _load(showSpinner: false),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _PlacesState.loading:
        return ListView(
          children: const [
            SizedBox(height: 200),
            Center(child: CircularProgressIndicator()),
          ],
        );
      case _PlacesState.error:
        return const GpsMapEmpty(
          icon: Icons.link_off_rounded,
          title: '無法讀取常去地點',
          message: '請確認網路連線，下拉即可重新整理',
        );
      case _PlacesState.ready:
        // 地點清單（或空狀態說明）下方接「安心提醒」設定，整頁同一條 ListView。
        final c = _c;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (_places.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 24, 12, 24),
                child: GpsEmptyBlock(
                  icon: Icons.bookmark_border_rounded,
                  title: '還沒有常去地點',
                  message: '在地圖上點停留點或長按地圖，就能命名常去的地點；'
                      '設定「家」之後可以看到外出次數，長輩端也會出現「帶我回家」按鈕。',
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                child: Text(
                  '設好「家」之後，地圖會標出地點名稱，安心提醒才能判斷晚歸和遠離家。',
                  style: famText(c.text2, 14, height: 1.6),
                ),
              ),
              FamCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < _places.length; i++)
                      _buildTile(_places[i], first: i == 0),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            ..._buildAlertSection(),
          ],
        );
    }
  }

  Widget _buildTile(ElderPlace p, {required bool first}) {
    final c = _c;
    return GpsPlaceRow(
      name: p.name,
      subtitle: '半徑 ${p.radiusM} 公尺',
      isHome: p.isHome,
      first: first,
      onTap: () => _edit(p),
      trailing: PopupMenuButton<_PlaceMenu>(
        tooltip: '更多',
        padding: EdgeInsets.zero,
        onSelected: (m) {
          switch (m) {
            case _PlaceMenu.edit:
              _edit(p);
            case _PlaceMenu.setHome:
              _setHome(p);
            case _PlaceMenu.delete:
              _delete(p);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _PlaceMenu.edit,
            child: Text('編輯', style: famText(c.text, 15)),
          ),
          if (!p.isHome)
            PopupMenuItem(
              value: _PlaceMenu.setHome,
              child: Text('設為家', style: famText(c.text, 15)),
            ),
          PopupMenuItem(
            value: _PlaceMenu.delete,
            child: Text('刪除', style: famText(c.danger, 15)),
          ),
        ],
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.more_horiz_rounded, color: c.text2),
        ),
      ),
    );
  }

  // ───────────────────────── 安心提醒設定 ─────────────────────────

  List<Widget> _buildAlertSection() {
    final c = _c;
    const header = FamSectionLabel('安心提醒');

    if (_alertSettings == null) {
      return [
        header,
        const SizedBox(height: 8),
        FamCard(
          child: Text(
            '暫時無法讀取提醒設定，下拉即可重新整理',
            style: famText(c.text2, 14, height: 1.5),
          ),
        ),
      ];
    }

    final footnote = Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
      child: Text(
        '符合條件時會通知您；長輩關閉位置分享時一律不提醒。',
        style: famText(c.text3, 12.5, height: 1.5),
      ),
    );

    final lateTime = _alertTime('late_return_time', _kDefaultLateReturnTime);
    final noUpdateStart = _alertTime('no_update_start', _kDefaultNoUpdateStart);
    final noUpdateEnd = _alertTime('no_update_end', _kDefaultNoUpdateEnd);
    final noUpdateHours = _alertInt('no_update_hours', _kDefaultNoUpdateHours)
        .clamp(_kMinNoUpdateHours, _kMaxNoUpdateHours);
    final farKm = _alertInt('far_km', _kDefaultFarKm);
    final farOptions = {..._kFarKmChoices, farKm}.toList()..sort();

    return [
      header,
      const SizedBox(height: 8),
      FamCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        child: Column(
          children: [
            GpsRuleRow(
              first: true,
              title: '晚歸提醒',
              disabled: !_hasHome,
              body: _hasHome
                  ? [
                      gpsInline(lateTime,
                          onTap: () => _pickTime('late_return_time', _kDefaultLateReturnTime)),
                      gpsPlain('後還不在家時通知我'),
                    ]
                  : [gpsPlain('先設定「家」才能使用')],
              trailing: UbanSwitch(
                value: _alertBool('late_return_enabled'),
                onChanged: _hasHome ? (v) => _changeAlert({'late_return_enabled': v}) : null,
              ),
            ),
            GpsRuleRow(
              title: '失聯提醒',
              body: [
                gpsInline(noUpdateStart,
                    onTap: () => _pickTime('no_update_start', _kDefaultNoUpdateStart)),
                gpsPlain('–'),
                gpsInline(noUpdateEnd,
                    onTap: () => _pickTime('no_update_end', _kDefaultNoUpdateEnd)),
                gpsPlain('之間超過'),
                _menuInline<int>(
                  label: '$noUpdateHours',
                  options: [for (var h = _kMinNoUpdateHours; h <= _kMaxNoUpdateHours; h++) h],
                  optionLabel: (h) => '$h 小時',
                  onSelected: (h) {
                    if (h != noUpdateHours) _changeAlert({'no_update_hours': h});
                  },
                ),
                gpsPlain('小時沒有位置時通知我'),
              ],
              trailing: UbanSwitch(
                value: _alertBool('no_update_enabled'),
                onChanged: (v) => _changeAlert({'no_update_enabled': v}),
              ),
            ),
            GpsRuleRow(
              title: '遠離家提醒',
              disabled: !_hasHome,
              body: _hasHome
                  ? [
                      gpsPlain('距離家超過'),
                      _menuInline<int>(
                        label: '$farKm',
                        options: farOptions,
                        optionLabel: (k) => '$k 公里',
                        onSelected: (k) {
                          if (k != farKm) _changeAlert({'far_km': k});
                        },
                      ),
                      gpsPlain('公里時通知我'),
                    ]
                  : [gpsPlain('先設定「家」才能使用')],
              trailing: UbanSwitch(
                value: _alertBool('far_enabled'),
                onChanged: _hasHome ? (v) => _changeAlert({'far_enabled': v}) : null,
              ),
            ),
          ],
        ),
      ),
      footnote,
    ];
  }

  /// 內嵌值（`.inl`）＋彈出選單。
  InlineSpan _menuInline<T>({
    required String label,
    required List<T> options,
    required String Function(T) optionLabel,
    required ValueChanged<T> onSelected,
  }) {
    final c = _c;
    return gpsInline(
      label,
      wrap: (chip) => PopupMenuButton<T>(
        tooltip: '選擇',
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final o in options)
            PopupMenuItem<T>(
              value: o,
              child: Text(optionLabel(o), style: famText(c.text, 15)),
            ),
        ],
        child: chip,
      ),
    );
  }
}
