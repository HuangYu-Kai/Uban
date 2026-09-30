// lib/screens/family/elder_places_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../models/elder_place.dart';
import '../../services/api/location_api.dart';

/// 半徑可選值（公尺）；既有地點的半徑若不在其中，編輯時會補進選項。
const List<int> _kRadiusChoices = [100, 150, 300, 500];
const int _kDefaultRadiusM = 150;

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
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PlaceEditorDialog(
      elderId: elderId,
      userId: userId,
      existing: existing,
      position: position,
      presetHome: presetHome,
    ),
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
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('儲存失敗，請稍後再試', style: GoogleFonts.notoSansTc()),
          ),
        );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(
        isEdit ? '編輯地點' : '新增常去地點',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              enabled: !_saving,
              maxLength: 32,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              decoration: InputDecoration(
                labelText: '地點名稱',
                hintText: '例如：家、公園、市場',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '範圍半徑',
              style: GoogleFonts.notoSansTc(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            // 用 Wrap 讓窄螢幕自動換行，避免 RenderFlex 溢位。
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in _radiusOptions)
                  ChoiceChip(
                    label: Text('$r 公尺', style: GoogleFonts.notoSansTc(fontSize: 13)),
                    selected: _radiusM == r,
                    onSelected: _saving ? null : (_) => setState(() => _radiusM = r),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '設為家',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(fontSize: 15),
              ),
              subtitle: Text(
                '每位長輩只有一個家，設定後原本的家會取消',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansTc(fontSize: 12),
              ),
              value: _isHome,
              onChanged: _saving ? null : (v) => setState(() => _isHome = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text('取消', style: GoogleFonts.notoSansTc()),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('儲存', style: GoogleFonts.notoSansTc()),
        ),
      ],
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
  }

  /// 家排最前面，其餘維持後端順序。
  List<ElderPlace> _sorted(List<ElderPlace> src) => [
        ...src.where((p) => p.isHome),
        ...src.where((p) => !p.isHome),
      ];

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.notoSansTc())));
  }

  Future<void> _edit(ElderPlace p) async {
    final saved = await showPlaceEditorDialog(
      context,
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '刪除「${p.name}」？',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        content: Text(
          '刪除後，這個地點不會再出現在地圖與行程中。',
          style: GoogleFonts.notoSansTc(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: GoogleFonts.notoSansTc()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('刪除', style: GoogleFonts.notoSansTc()),
          ),
        ],
      ),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '常去地點',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
          ),
        ),
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
        return _buildMessage(
          icon: Icons.link_off_rounded,
          title: '無法讀取常去地點',
          message: '請確認網路連線，下拉即可重新整理',
        );
      case _PlacesState.ready:
        if (_places.isEmpty) {
          return _buildMessage(
            icon: Icons.bookmark_border_rounded,
            title: '還沒有常去地點',
            message: '在地圖上點停留點或長按地圖，就能命名常去的地點；'
                '設定「家」之後可以看到外出次數，長輩端也會出現「帶我回家」按鈕。',
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _places.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) => _buildTile(_places[i]),
        );
    }
  }

  Widget _buildTile(ElderPlace p) {
    final color = p.isHome ? const Color(0xFF22C55E) : const Color(0xFF6366F1);
    return ListTile(
      leading: Icon(
        p.isHome ? Icons.home_rounded : Icons.place_rounded,
        color: color,
      ),
      title: Text(
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '半徑 ${p.radiusM} 公尺',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.notoSansTc(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: PopupMenuButton<_PlaceMenu>(
        tooltip: '更多',
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
            child: Text('編輯', style: GoogleFonts.notoSansTc()),
          ),
          if (!p.isHome)
            PopupMenuItem(
              value: _PlaceMenu.setHome,
              child: Text('設為家', style: GoogleFonts.notoSansTc()),
            ),
          PopupMenuItem(
            value: _PlaceMenu.delete,
            child: Text('刪除', style: GoogleFonts.notoSansTc(color: Colors.red)),
          ),
        ],
      ),
      onTap: () => _edit(p),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: GoogleFonts.notoSansTc(fontSize: 14, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
