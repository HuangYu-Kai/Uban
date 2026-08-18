// lib/screens/family/zone_calibration_screen.dart
//
// ★ IPS（室內定位）校準畫面：家屬替每一台監視機畫出樓層區域（客廳／廚房／
//   臥室／浴室…）的多邊形範圍，供後端 YOLO 判斷長輩目前所在的房間。完整
//   後端邏輯與能力邊界見 `uban-api/services/indoor_position.py` 的模組
//   docstring；本畫面只負責「把使用者點的頂點換算成正規化座標、組成
//   zones 陣列」，幾何判定（point-in-polygon／first-match-wins 順序）全部
//   在後端。
//
// 座標系規則（務必與後端一致，見 indoor_position.py::validate_zones）：
//   - 正規化 [0,1]，原點在畫面左上角。
//   - 多邊形描述的是「地板上的區域」——後端比對的是人物的腳點（bbox 底邊
//     中點），不是人物中心，因此校準時應沿著地板範圍畫，而不是人的輪廓。
//   - zones 陣列的順序＝比對優先順序（first-match-wins），範圍較小、較
//     精確的區域（例如「浴室」）必須排在範圍較大的區域（例如「臥室」）
//     之前，否則永遠不會被分類到——畫面上的「往前排／往後排」就是用來
//     調整這個順序。
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';

class ZoneCalibrationScreen extends StatefulWidget {
  /// 長輩的 elder_id（四碼字串，非 user_id）。
  final String elderId;

  /// 監視機的 device_id（`services/monitor_identity.py` 由裝置名稱算出的
  /// crc32），決定這份 zone 設定只套用在哪一台監視機。
  final int deviceId;

  /// 監視機顯示名稱，僅用於畫面標題，不參與任何 API 呼叫。
  final String deviceName;

  /// 目前登入家屬的 caregiver_id，後端用來驗證此人是否與該長輩有配對
  /// 關係（無關係一律 404）。
  final int userId;

  const ZoneCalibrationScreen({
    super.key,
    required this.elderId,
    required this.deviceId,
    required this.deviceName,
    required this.userId,
  });

  @override
  State<ZoneCalibrationScreen> createState() => _ZoneCalibrationScreenState();
}

class _ZoneCalibrationScreenState extends State<ZoneCalibrationScreen> {
  static const List<String> _quickZoneNames = ['客廳', '廚房', '臥室', '浴室', '走廊'];

  // 有限色盤：finished zone 依陣列 index 循環取色，讓「疊圖上的色塊」與
  // 「下方清單的色點」永遠是同一個顏色，不需要額外存一份 zone→color 映射。
  static const List<Color> _zonePalette = [
    Color(0xFF60A5FA), // 藍
    Color(0xFF34D399), // 綠
    Color(0xFFFBBF24), // 黃
    Color(0xFFF472B6), // 粉
    Color(0xFFA78BFA), // 紫
    Color(0xFFFB923C), // 橘
  ];

  static const Color _draftColor = Color(0xFFFBBF24);

  late final String _snapshotUrl;
  late final ImageProvider _imageProvider;
  late final ImageStreamListener _imageStreamListener;
  ImageStream? _imageStream;
  Size? _intrinsicSize;
  _SnapshotState _snapshotState = _SnapshotState.loading;

  bool _zonesLoading = true;
  final List<_ZoneDef> _zones = [];

  // 目前正在畫的區域；null 代表沒有正在進行的繪製。
  String? _draftName;
  List<Offset> _draftPolygon = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _snapshotUrl = ApiService.zoneSnapshotUrl(
      widget.elderId,
      userId: widget.userId,
      deviceId: widget.deviceId,
    );
    // 用 NetworkImage 自建 provider（而非直接用 Image.network 語法糖），
    // 這樣才能同時：① 用同一個 provider 餵給畫面上的 Image widget（共用
    // 快取，不會重複發送請求）；② 掛一支 ImageStreamListener 取得原始
    // 影像的實際像素尺寸與載入失敗事件，用來算出 BoxFit.contain 的letterbox
    // 矩形、以及呈現「尚未收到畫面」空狀態（見類別註解與 _buildSnapshotArea）。
    _imageProvider = NetworkImage(_snapshotUrl);
    _imageStreamListener = ImageStreamListener(_onImageLoaded, onError: _onImageError);
    _resolveImage();
    _loadZoneConfig();
  }

  void _resolveImage() {
    _imageStream = _imageProvider.resolve(const ImageConfiguration());
    _imageStream!.addListener(_imageStreamListener);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageStreamListener);
    super.dispose();
  }

  void _onImageLoaded(ImageInfo info, bool synchronousCall) {
    if (!mounted) return;
    setState(() {
      _intrinsicSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
      _snapshotState = _SnapshotState.loaded;
    });
  }

  void _onImageError(Object exception, StackTrace? stackTrace) {
    // 最常見成因是後端尚無快取影格（404）——監視機還沒推過任何一幀，或
    // /api/ips/snapshot 端點尚未部署完成。不當成例外拋出，只切換到空狀態。
    debugPrint('⚠️ [ZoneCalibrationScreen] 讀取監視機快照失敗: $exception');
    if (!mounted) return;
    setState(() => _snapshotState = _SnapshotState.failed);
  }

  Future<void> _retrySnapshot() async {
    _imageStream?.removeListener(_imageStreamListener);
    setState(() => _snapshotState = _SnapshotState.loading);
    // 不 evict 的話，NetworkImage 會直接回放快取住的失敗結果，畫面會卡在
    // loading 轉一圈後立刻又變回失敗，使用者會以為「重試」沒有作用。
    await _imageProvider.evict();
    if (!mounted) return;
    _resolveImage();
  }

  Future<void> _loadZoneConfig() async {
    final raw = await ApiService.getZoneConfig(
      widget.elderId,
      userId: widget.userId,
      deviceId: widget.deviceId,
    );
    if (!mounted) return;
    setState(() {
      _zones
        ..clear()
        ..addAll(
          raw
              .whereType<Map>()
              .map((z) => _ZoneDef.fromJson(Map<String, dynamic>.from(z)))
              // 防呆：忽略格式異常（頂點數 < 3）的舊資料，避免疊圖與清單
              // 畫出退化多邊形。正常情況下不會發生，因為後端寫入前已經過
              // validate_zones 驗證。
              .where((z) => z.polygon.length >= 3),
        );
      _zonesLoading = false;
    });
  }

  /// 算出「這張影像在目前版面裡實際被畫在哪個矩形」——BoxFit.contain 讓
  /// 影像維持長寬比置中縮放，四周可能留有 letterbox 空白，這個矩形正是
  /// 扣掉空白後的實際畫面範圍。點擊座標與疊圖都必須以此為基準換算，
  /// 否則長寬比不一致時座標會全部偏移。
  Rect _imageRectWithin(Size box) {
    if (_intrinsicSize == null || box.isEmpty) return Rect.zero;
    final fitted = applyBoxFit(BoxFit.contain, _intrinsicSize!, box);
    final dest = fitted.destination;
    final dx = (box.width - dest.width) / 2;
    final dy = (box.height - dest.height) / 2;
    return Rect.fromLTWH(dx, dy, dest.width, dest.height);
  }

  void _handleTap(Offset localPosition, Rect imageRect) {
    if (_draftName == null) {
      _toast('請先按「新增區域」，再開始點選頂點');
      return;
    }
    if (!imageRect.contains(localPosition)) {
      return; // 點在 letterbox 的空白處，不是畫面範圍內，忽略。
    }
    final nx = ((localPosition.dx - imageRect.left) / imageRect.width).clamp(0.0, 1.0).toDouble();
    final ny = ((localPosition.dy - imageRect.top) / imageRect.height).clamp(0.0, 1.0).toDouble();
    setState(() => _draftPolygon.add(Offset(nx, ny)));
  }

  Future<void> _startNewZone() async {
    final name = await _promptZoneName();
    if (!mounted || name == null) return;
    setState(() {
      _draftName = name;
      _draftPolygon = [];
    });
  }

  /// 彈窗輸入新區域名稱：提供常見房型快速選取，也可自行輸入。快速選取的
  /// 「已選取」狀態直接由 controller 目前文字比對得出，不用另外存一份
  /// 選取狀態——輸入框永遠是唯一事實來源，兩者不會分岔。
  Future<String?> _promptZoneName() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            '新增區域',
            style: GoogleFonts.notoSansTc(
              color: const Color(0xFFE2E8F0),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '快速選擇：',
                  style: GoogleFonts.notoSansTc(color: const Color(0xFF94A3B8), fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickZoneNames.map((name) {
                    final selected = controller.text.trim() == name;
                    return ChoiceChip(
                      label: Text(name),
                      selected: selected,
                      onSelected: (_) => setDialogState(() => controller.text = name),
                      selectedColor: const Color(0xFF59B294),
                      backgroundColor: const Color(0xFF334155),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : const Color(0xFFCBD5E1),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 20,
                  style: const TextStyle(color: Color(0xFFE2E8F0)),
                  decoration: const InputDecoration(
                    labelText: '區域名稱',
                    hintText: '例如：客廳',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF334155)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF59B294)),
                    ),
                  ),
                  // 手動輸入時也要重新整理快選 chip 的高亮狀態。
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF59B294),
                foregroundColor: Colors.white,
              ),
              child: const Text('開始畫'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  void _undoLastVertex() {
    setState(() {
      if (_draftPolygon.isNotEmpty) _draftPolygon.removeLast();
    });
  }

  void _finishCurrentZone() {
    if (_draftPolygon.length < 3) {
      _toast('至少需要 3 個點才能圍成一個區域，目前只點了 ${_draftPolygon.length} 個點');
      return;
    }
    setState(() {
      _zones.add(_ZoneDef(name: _draftName!, polygon: List.of(_draftPolygon)));
      _draftName = null;
      _draftPolygon = [];
    });
  }

  void _cancelDrawing() {
    setState(() {
      _draftName = null;
      _draftPolygon = [];
    });
  }

  void _moveZone(int from, int to) {
    setState(() {
      final item = _zones.removeAt(from);
      _zones.insert(to, item);
    });
  }

  Future<void> _deleteZone(int index) async {
    final zone = _zones[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '刪除區域',
          style: GoogleFonts.notoSansTc(color: const Color(0xFFE2E8F0), fontWeight: FontWeight.w800),
        ),
        content: Text(
          '確定要刪除「${zone.name}」這個區域嗎？',
          style: GoogleFonts.notoSansTc(color: const Color(0xFFCBD5E1)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFF87171)),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _zones.removeAt(index));
  }

  Future<void> _handleSave() async {
    if (_draftName != null) {
      _toast('請先完成或取消「$_draftName」的繪製，再儲存');
      return;
    }
    if (_zones.isEmpty) {
      _toast('尚未新增任何區域，無法儲存');
      return;
    }
    setState(() => _saving = true);
    final error = await ApiService.saveZoneConfig(
      widget.elderId,
      userId: widget.userId,
      deviceId: widget.deviceId,
      zones: _zones.map((z) => z.toJson()).toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      _toast('已儲存 ${_zones.length} 個區域設定');
    } else {
      _toast(error, isError: true);
    }
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFB91C1C) : const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFE2E8F0)),
        title: Text(
          '校準區域・${widget.deviceName}',
          style: GoogleFonts.notoSansTc(
            color: const Color(0xFFE2E8F0),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: _zonesLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF59B294)))
            : Column(
                children: [
                  Expanded(flex: 5, child: _buildSnapshotArea()),
                  _buildToolbar(),
                  Expanded(flex: 4, child: _buildZoneList()),
                  _buildSaveBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildSnapshotArea() {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (_snapshotState == _SnapshotState.failed) {
            return _buildSnapshotEmptyState();
          }
          if (_snapshotState == _SnapshotState.loading || _intrinsicSize == null) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF59B294)));
          }
          final box = Size(constraints.maxWidth, constraints.maxHeight);
          final imageRect = _imageRectWithin(box);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTap(details.localPosition, imageRect),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 交給 Image 自己用 BoxFit.contain 畫——這保證視覺上的
                // letterbox 位置與 _imageRectWithin() 算出來的完全一致，
                // 因為兩者用的是同一套 applyBoxFit 邏輯。
                Image(image: _imageProvider, fit: BoxFit.contain),
                CustomPaint(
                  size: box,
                  painter: _ZonePainter(
                    imageRect: imageRect,
                    zones: _zones,
                    palette: _zonePalette,
                    draftPolygon: _draftPolygon,
                    draftColor: _draftColor,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSnapshotEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, color: Color(0xFF64748B), size: 48),
            const SizedBox(height: 12),
            Text(
              '尚未收到這台監視機的畫面，請確認監視機在線並稍候重試',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFFCBD5E1),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _retrySnapshot,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重試'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF59B294),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final drawing = _draftName != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: const Color(0xFF0F172A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (drawing) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '正在畫：$_draftName（已點 ${_draftPolygon.length} 個點）',
                    style: GoogleFonts.notoSansTc(
                      color: const Color(0xFFFBBF24),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _cancelDrawing,
                  child: Text(
                    '取消繪製',
                    style: GoogleFonts.notoSansTc(color: const Color(0xFFF87171), fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              Expanded(
                child: _toolbarButton(
                  icon: Icons.add_location_alt_rounded,
                  label: '新增區域',
                  onPressed: drawing ? null : _startNewZone,
                  color: const Color(0xFF59B294),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _toolbarButton(
                  icon: Icons.undo_rounded,
                  label: '復原上一點',
                  onPressed: drawing && _draftPolygon.isNotEmpty ? _undoLastVertex : null,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _toolbarButton(
                  icon: Icons.check_circle_rounded,
                  label: '完成此區域',
                  onPressed: drawing ? _finishCurrentZone : null,
                  color: const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.notoSansTc(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF334155),
        disabledForegroundColor: const Color(0xFF64748B),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _buildZoneList() {
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOrderHint(),
          const SizedBox(height: 8),
          Expanded(
            child: _zones.isEmpty
                ? Center(
                    child: Text(
                      '尚未設定任何區域，點「新增區域」開始校準',
                      style: GoogleFonts.notoSansTc(color: const Color(0xFF64748B), fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: _zones.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _buildZoneRow(index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2A0B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF92400E)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFFBBF24), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '順序決定歸屬：範圍較小的區域（如浴室）要排在範圍較大的區域（如臥室）前面',
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFFFBBF24),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneRow(int index) {
    final zone = _zones[index];
    final color = _zonePalette[index % _zonePalette.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              zone.name,
              style: GoogleFonts.notoSansTc(
                color: const Color(0xFFE2E8F0),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${zone.polygon.length} 點',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            color: index == 0 ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            onPressed: index == 0 ? null : () => _moveZone(index, index - 1),
            tooltip: '往前排',
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward_rounded, size: 18),
            color: index == _zones.length - 1 ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
            onPressed: index == _zones.length - 1 ? null : () => _moveZone(index, index + 1),
            tooltip: '往後排',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            color: const Color(0xFFF87171),
            onPressed: () => _deleteZone(index),
            tooltip: '刪除',
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(top: BorderSide(color: Color(0xFF334155))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _handleSave,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_rounded),
          label: Text(
            _saving ? '儲存中…' : '儲存',
            style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF59B294),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }
}

enum _SnapshotState { loading, loaded, failed }

/// 單一樓層區域的本地模型：`polygon` 一律是正規化 [0,1] 座標，與後端
/// `elder_zone_config.zones` 的 JSON 形狀一一對應（見 routers/ips.py）。
class _ZoneDef {
  String name;
  List<Offset> polygon;

  _ZoneDef({required this.name, required this.polygon});

  factory _ZoneDef.fromJson(Map<String, dynamic> json) {
    final points = <Offset>[];
    final rawPolygon = json['polygon'];
    if (rawPolygon is List) {
      for (final vertex in rawPolygon) {
        if (vertex is List && vertex.length == 2) {
          final x = vertex[0];
          final y = vertex[1];
          if (x is num && y is num) {
            points.add(Offset(x.toDouble(), y.toDouble()));
          }
        }
      }
    }
    return _ZoneDef(name: (json['name'] ?? '').toString(), polygon: points);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'polygon': polygon.map((p) => [p.dx, p.dy]).toList(),
      };
}

/// 疊在監視機快照上的區域繪製層：已完成的區域畫成半透明色塊＋外框＋
/// 名稱標籤，正在畫的區域只畫頂點與邊線（尚未封閉，不需要填色）。
class _ZonePainter extends CustomPainter {
  final Rect imageRect;
  final List<_ZoneDef> zones;
  final List<Color> palette;
  final List<Offset> draftPolygon;
  final Color draftColor;

  _ZonePainter({
    required this.imageRect,
    required this.zones,
    required this.palette,
    required this.draftPolygon,
    required this.draftColor,
  });

  Offset _toCanvas(Offset normalized) => Offset(
        imageRect.left + normalized.dx * imageRect.width,
        imageRect.top + normalized.dy * imageRect.height,
      );

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < zones.length; i++) {
      final zone = zones[i];
      _paintPolygon(
        canvas,
        zone.polygon,
        palette[i % palette.length],
        closed: true,
        label: zone.name,
      );
    }
    if (draftPolygon.isNotEmpty) {
      _paintPolygon(canvas, draftPolygon, draftColor, closed: false, label: null);
    }
  }

  void _paintPolygon(
    Canvas canvas,
    List<Offset> normalizedPoints,
    Color color, {
    required bool closed,
    String? label,
  }) {
    if (normalizedPoints.isEmpty) return;
    final points = normalizedPoints.map(_toCanvas).toList();

    if (closed && points.length >= 3) {
      final fillPath = Path()..addPolygon(points, true);
      canvas.drawPath(
        fillPath,
        Paint()
          ..color = color.withValues(alpha: 0.28)
          ..style = PaintingStyle.fill,
      );
    }

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    canvas.drawPath(Path()..addPolygon(points, closed), strokePaint);

    for (final p in points) {
      canvas.drawCircle(p, 5, Paint()..color = color);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    if (label != null) {
      final centroid = points.reduce((a, b) => a + b) / points.length.toDouble();
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 4)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        centroid - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ZonePainter oldDelegate) {
    // 校準畫面的互動頻率低（點擊/按鈕觸發，不是逐幀動畫），且 _zones 是
    // 原地增刪、物件參考不會變化，用內容比較反而抓不到變化；比照
    // script_editor_painters.dart::NodeLinkPainter 的既有慣例，一律重繪
    // 最單純可靠。
    return true;
  }
}
