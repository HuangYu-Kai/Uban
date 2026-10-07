import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/ui/ui.dart';
import 'elder_profile_shared.dart';

/// ★ 2026-10-07 交接 B1：「對話偏好」頁（原 elder_profile_edit_screen.dart 拆出的第二頁）。
///
/// 欄位：稱呼、語氣、篇幅、興趣與回憶素材，另有
/// - 話題偏好（想多聊 priority／避免 avoid／禁忌 forbidden，走 `/api/ai/topics`，
///   新增／刪除「立即生效」，不需按儲存）
/// - 主動關懷頻率（`heartbeat_frequency` 分鐘：0 關閉／30／60／120）
///
/// 語氣、篇幅 0–100；後端門檻 ≤40 偏左（客觀／簡潔）、≥60 偏右（熱情／詳細），中間為適中。
/// 讀取從 `{status, data}` 的 `data`；`interests` 後端回清單，畫面以全形逗號串起來編輯，
/// 送出時以半形逗號串成字串（後端存逗號分隔字串）。語氣／篇幅沒有值時顯示「尚未設定」，
/// 沒動滑桿就不送。只送有變更的欄位；成功訊息只在後端回 success 才顯示。
class ElderTalkPreferenceScreen extends StatefulWidget {
  final Map<String, dynamic> elderData;
  final ElderProfileGateway gateway;

  const ElderTalkPreferenceScreen({
    super.key,
    required this.elderData,
    this.gateway = const ElderProfileGateway.live(),
  });

  @override
  State<ElderTalkPreferenceScreen> createState() => _ElderTalkPreferenceScreenState();
}

/// 主動關懷頻率選項（分鐘 → 顯示文字）。
const List<(int, String)> kHeartbeatOptions = [
  (0, '關閉'),
  (30, '30 分鐘'),
  (60, '1 小時'),
  (120, '2 小時'),
];

const List<(String, String, String)> _kTopicGroups = [
  ('priority', '想多聊', '例如：孫子、園藝、老歌'),
  ('avoid', '盡量避免', '例如：過世的親人'),
  ('forbidden', '絕對禁忌', '例如：某段不愉快的往事'),
];

class _ElderTalkPreferenceScreenState extends State<ElderTalkPreferenceScreen> {
  final _appellationCtrl = TextEditingController();
  final _interestsCtrl = TextEditingController();

  String _baseAppellation = '';
  List<String> _baseInterests = const [];
  int? _baseTone;
  int? _baseVerbosity;
  int? _baseHeartbeat;

  double _tone = 50;
  double _verbosity = 50;
  bool _toneTouched = false;
  bool _verbosityTouched = false;
  int? _heartbeat;

  String? _elderCode; // elder_profile.elder_id（話題偏好用）
  List<Map<String, dynamic>> _topics = [];
  String? _topicsError;
  bool _topicsLoading = false;
  bool _topicBusy = false;
  final Map<String, TextEditingController> _topicCtrls = {
    for (final g in _kTopicGroups) g.$1: TextEditingController(),
  };

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  int? get _userId => elderUserIdOf(widget.elderData);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _appellationCtrl.dispose();
    _interestsCtrl.dispose();
    for (final c in _topicCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? _intOf(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  Future<void> _load() async {
    final uid = _userId;
    if (uid == null) {
      setState(() {
        _loading = false;
        _loadError = '無法讀取：找不到長輩帳號 ID';
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    Map<String, dynamic> resp;
    try {
      resp = await widget.gateway.load(uid);
    } catch (e) {
      resp = {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
    if (!mounted) return;
    final data = profileDataOf(resp);
    if (data == null) {
      setState(() {
        _loading = false;
        _loadError = ApiService.failureMessageOf(resp, fallback: '對話偏好讀取失敗');
      });
      return;
    }

    // interests：後端回清單；保險起見也接受字串。
    final rawInterests = data['interests'];
    final interests = rawInterests is List
        ? rawInterests.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
        : splitInterests('${rawInterests ?? ''}');

    final tone = _intOf(data['ai_emotion_tone']);
    final verbosity = _intOf(data['ai_text_verbosity']);
    final code = '${data['elder_id'] ?? ''}'.trim();

    setState(() {
      _baseAppellation = '${data['appellation'] ?? ''}'.trim();
      _baseInterests = interests;
      _baseTone = tone;
      _baseVerbosity = verbosity;
      _baseHeartbeat = _intOf(data['heartbeat_frequency']);
      _appellationCtrl.text = _baseAppellation;
      _interestsCtrl.text = interests.join('，');
      _tone = (tone ?? 50).clamp(0, 100).toDouble();
      _verbosity = (verbosity ?? 50).clamp(0, 100).toDouble();
      _toneTouched = false;
      _verbosityTouched = false;
      _heartbeat = _baseHeartbeat;
      _elderCode = code.isEmpty ? null : code;
      _loading = false;
    });
    if (_elderCode != null) _loadTopics();
  }

  Future<void> _loadTopics() async {
    final code = _elderCode;
    if (code == null) return;
    setState(() {
      _topicsLoading = true;
      _topicsError = null;
    });
    Map<String, dynamic> resp;
    try {
      resp = await widget.gateway.listTopics(code);
    } catch (e) {
      resp = {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
    if (!mounted) return;
    setState(() {
      _topicsLoading = false;
      if (resp['status'] == 'success' && resp['data'] is List) {
        _topics = (resp['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } else {
        _topicsError = ApiService.failureMessageOf(resp, fallback: '話題偏好讀取失敗');
      }
    });
  }

  List<Map<String, dynamic>> _topicsOf(String type) =>
      _topics.where((t) => '${t['topic_type']}' == type).toList();

  Future<void> _addTopic(String type) async {
    final code = _elderCode;
    if (code == null || _topicBusy) return;
    final ctrl = _topicCtrls[type]!;
    final keyword = ctrl.text.trim();
    if (keyword.isEmpty) return;
    if (keyword.length > 30) {
      showProfileSnack(context, '話題請控制在 30 字以內');
      return;
    }
    final dup = _topicsOf(type).any((t) => '${t['keyword']}'.trim() == keyword);
    if (dup) {
      showProfileSnack(context, '「$keyword」已經在清單裡了');
      return;
    }
    setState(() => _topicBusy = true);
    Map<String, dynamic> resp;
    try {
      resp = await widget.gateway.addTopic(code, keyword, type);
    } catch (e) {
      resp = {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
    if (!mounted) return;
    if (resp['status'] == 'success') {
      ctrl.clear();
      setState(() => _topicBusy = false);
      await _loadTopics(); // POST 不回新 id，重新讀清單
    } else {
      setState(() => _topicBusy = false);
      showProfileSnack(context, '新增失敗：${ApiService.failureMessageOf(resp)}');
    }
  }

  Future<void> _deleteTopic(Map<String, dynamic> topic) async {
    final id = _intOf(topic['topic_id']);
    final code = _elderCode;
    // ★ 2026-10-07 收尾：後端 DELETE /ai/topics/{id} 現在必帶 elder_id（驗證話題屬於該長輩）。
    if (id == null || code == null || _topicBusy) return;
    setState(() => _topicBusy = true);
    Map<String, dynamic> resp;
    try {
      resp = await widget.gateway.deleteTopic(id, code);
    } catch (e) {
      resp = {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
    if (!mounted) return;
    setState(() {
      _topicBusy = false;
      if (resp['status'] == 'success') {
        _topics.removeWhere((t) => _intOf(t['topic_id']) == id);
      }
    });
    if (resp['status'] != 'success') {
      showProfileSnack(context, '刪除失敗：${ApiService.failureMessageOf(resp)}');
    }
  }

  (Map<String, dynamic>, String?) _collectChanges() {
    final fields = <String, dynamic>{};
    final cleared = <String>[];

    final app = _appellationCtrl.text.trim();
    if (app != _baseAppellation) {
      app.isEmpty ? cleared.add('稱呼') : fields['appellation'] = app;
    }

    final interests = splitInterests(_interestsCtrl.text);
    final same = interests.length == _baseInterests.length &&
        List.generate(interests.length, (i) => interests[i] == _baseInterests[i]).every((e) => e);
    if (!same) {
      interests.isEmpty ? cleared.add('興趣與回憶素材') : fields['interests'] = interests.join(',');
    }

    if (_toneTouched && _tone.round() != _baseTone) fields['ai_emotion_tone'] = _tone.round();
    if (_verbosityTouched && _verbosity.round() != _baseVerbosity) {
      fields['ai_text_verbosity'] = _verbosity.round();
    }
    if (_heartbeat != null && _heartbeat != _baseHeartbeat) {
      fields['heartbeat_frequency'] = _heartbeat;
    }

    if (cleared.isNotEmpty) {
      return (fields, '「${cleared.join('、')}」目前無法清空，請改寫成新的內容再儲存');
    }
    return (fields, null);
  }

  Future<void> _save() async {
    final uid = _userId;
    if (uid == null || _saving) return;
    final (fields, problem) = _collectChanges();
    if (problem != null) {
      showProfileSnack(context, problem);
      return;
    }
    if (fields.isEmpty) {
      showProfileSnack(context, '沒有需要儲存的變更');
      return;
    }
    setState(() => _saving = true);
    Map<String, dynamic> resp;
    try {
      resp = await widget.gateway.save(uid, fields);
    } catch (e) {
      resp = {'status': 'error', 'message': '目前連不上伺服器，請確認網路後再試一次'};
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (resp['status'] == 'success') {
      showProfileSnack(context, '對話偏好已更新，AI 之後會採用新設定', success: true);
      Navigator.pop(context, true);
    } else {
      showProfileSnack(context, '儲存失敗：${ApiService.failureMessageOf(resp)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: c.text),
        title: Text('對話偏好', style: ubanText(19, FontWeight.w800, c.text)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.brand))
          : _loadError != null
              ? ProfileLoadError(message: _loadError!, onRetry: _load)
              : _buildForm(c),
    );
  }

  Widget _buildForm(UbanColors c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileSection(
            title: '稱呼與說話風格',
            icon: Icons.record_voice_over_rounded,
            children: [
              UbanTextField(
                label: 'AI 怎麼稱呼長輩',
                hintText: '例如：奶奶、阿公、伯伯',
                controller: _appellationCtrl,
              ),
              const SizedBox(height: 18),
              _slider(
                c,
                label: '陪伴語氣',
                value: _tone,
                loaded: _baseTone != null || _toneTouched,
                low: '客觀冷靜',
                high: '熱情親切',
                mid: '溫和適中',
                onChanged: (v) => setState(() {
                  _tone = v;
                  _toneTouched = true;
                }),
                sliderKey: const ValueKey('tone_slider'),
              ),
              const SizedBox(height: 18),
              _slider(
                c,
                label: '回覆篇幅',
                value: _verbosity,
                loaded: _baseVerbosity != null || _verbosityTouched,
                low: '簡潔扼要',
                high: '詳細愛聊',
                mid: '適度互動',
                onChanged: (v) => setState(() {
                  _verbosity = v;
                  _verbosityTouched = true;
                }),
                sliderKey: const ValueKey('verbosity_slider'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ProfileSection(
            title: '興趣與回憶素材',
            icon: Icons.favorite_rounded,
            children: [
              UbanTextField(
                label: '用逗號分開，讓 AI 更懂長輩',
                hintText: '例如：鄧麗君老歌，園藝，泡茶，大稻埕',
                controller: _interestsCtrl,
                maxLines: 4,
                minLines: 2,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTopicsSection(c),
          const SizedBox(height: 16),
          _buildHeartbeatSection(c),
          const SizedBox(height: 20),
          UbanButton(
            key: const ValueKey('save_talk_pref'),
            label: '儲存對話偏好',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _slider(
    UbanColors c, {
    required String label,
    required double value,
    required bool loaded,
    required String low,
    required String high,
    required String mid,
    required ValueChanged<double> onChanged,
    required Key sliderKey,
  }) {
    final v = value.round();
    final desc = v <= 40 ? low : (v >= 60 ? high : mid);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: ubanText(16, FontWeight.w800, c.text)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                loaded ? '$desc（$v）' : '尚未設定',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ubanText(14, FontWeight.w700, c.brandStrong),
              ),
            ),
          ],
        ),
        Slider(
          key: sliderKey,
          value: value,
          min: 0,
          max: 100,
          activeColor: c.brandFill,
          onChanged: onChanged,
        ),
        Row(
          children: [
            Expanded(
              child: Text(low, style: ubanText(12, FontWeight.w600, c.text3)),
            ),
            Expanded(
              child: Text(
                high,
                textAlign: TextAlign.end,
                style: ubanText(12, FontWeight.w600, c.text3),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTopicsSection(UbanColors c) {
    return ProfileSection(
      title: '話題偏好',
      icon: Icons.forum_rounded,
      children: [
        Text(
          '新增或刪除會立即生效，不需要按下方的儲存。',
          style: ubanText(13, FontWeight.w500, c.text3, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (_elderCode == null)
          Text('這位長輩尚無長輩代碼，無法設定話題偏好。',
              style: ubanText(14, FontWeight.w500, c.text2, height: 1.4))
        else if (_topicsLoading && _topics.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_topicsError != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_topicsError!, style: ubanText(14, FontWeight.w600, c.danger, height: 1.4)),
              const SizedBox(height: 8),
              UbanButton(
                label: '重新載入話題',
                expand: false,
                variant: UbanButtonVariant.tonal,
                onPressed: _loadTopics,
              ),
            ],
          )
        else
          for (final g in _kTopicGroups) ...[
            _topicGroup(c, g.$1, g.$2, g.$3),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  Widget _topicGroup(UbanColors c, String type, String title, String hint) {
    final items = _topicsOf(type);
    final ctrl = _topicCtrls[type]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileLabel(title),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('尚未設定', style: ubanText(13, FontWeight.w500, c.text3)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final t in items)
                  InputChip(
                    key: ValueKey('topic_${t['topic_id']}'),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text('${t['keyword']}', overflow: TextOverflow.ellipsis),
                    ),
                    onDeleted: _topicBusy ? null : () => _deleteTopic(t),
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: UbanTextField(
                key: ValueKey('topic_input_$type'),
                hintText: hint,
                controller: ctrl,
                maxLength: 30,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addTopic(type),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: ValueKey('topic_add_$type'),
              tooltip: '新增$title',
              onPressed: _topicBusy ? null : () => _addTopic(type),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeartbeatSection(UbanColors c) {
    final known = kHeartbeatOptions.any((o) => o.$1 == _heartbeat);
    return ProfileSection(
      title: '主動關懷頻率',
      icon: Icons.notifications_active_rounded,
      children: [
        Text(
          'AI 會在長輩一段時間沒互動時主動關心一下。',
          style: ubanText(13, FontWeight.w500, c.text3, height: 1.4),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final o in kHeartbeatOptions)
              ChoiceChip(
                key: ValueKey('heartbeat_${o.$1}'),
                label: Text(o.$2),
                selected: _heartbeat == o.$1,
                onSelected: (_) => setState(() => _heartbeat = o.$1),
              ),
            // 資料庫裡是 App 選項以外的值（例如 15 分）：顯示出來，避免看起來像沒設定。
            if (_heartbeat != null && !known)
              ChoiceChip(
                label: Text('目前 $_heartbeat 分鐘'),
                selected: true,
                onSelected: (_) {},
              ),
          ],
        ),
        if (_heartbeat == null) ...[
          const SizedBox(height: 6),
          Text('尚未設定', style: ubanText(13, FontWeight.w500, c.text3)),
        ],
      ],
    );
  }
}
