import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/taiwan_districts.dart';
import '../../widgets/city_district_picker.dart';
import '../../widgets/locate_city_button.dart';
import '../../widgets/ui/ui.dart';
import 'elder_profile_shared.dart';

/// ★ 2026-10-07 交接 B1：「長輩檔案」頁（原 elder_profile_edit_screen.dart 拆出的第一頁）。
///
/// 欄位：姓名、年齡、性別、地區（縣市／區）、慢性病、用藥備註。
///
/// 讀取：後端回 `{status, data}`，一律從 `data` 取；讀取失敗顯示原因＋重試，
/// 不顯示空白表單（避免誤存）。
/// 儲存：只送「跟載入時不同」的欄位（PUT 部分更新）；後端把空白字串視為沒送，
/// 因此「清空欄位」無法儲存，這裡會明確告知而不是假裝成功。姓名改名由後端同步
/// 寫入 `elder_profile.elder_name`；地區縣市「台→臺」由後端正規化。
/// 成功訊息只在後端真的回 success 才顯示，失敗顯示後端給的真實原因。
class ElderBasicProfileScreen extends StatefulWidget {
  /// 至少含 `user_id`（或 `id`）；`user_name`／`age`／`gender`／`location` 僅作載入前的預填。
  final Map<String, dynamic> elderData;
  final VoidCallback? onUnbind;
  final ElderProfileGateway gateway;

  const ElderBasicProfileScreen({
    super.key,
    required this.elderData,
    this.onUnbind,
    this.gateway = const ElderProfileGateway.live(),
  });

  @override
  State<ElderBasicProfileScreen> createState() => _ElderBasicProfileScreenState();
}

class _ElderBasicProfileScreenState extends State<ElderBasicProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _chronicCtrl = TextEditingController();
  final _medCtrl = TextEditingController();
  final ValueNotifier<int> _locateReset = ValueNotifier<int>(0);

  String? _gender; // 'M'／'F'／null（未填）
  String? _city;
  String? _district;

  // 載入當下的基準值（只送跟它不同的欄位）
  String _baseName = '';
  int? _baseAge;
  String? _baseGender;
  String? _baseCity;
  String? _baseDistrict;
  String _baseChronic = '';
  String _baseMed = '';
  String _legacyLocation = '';

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
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _chronicCtrl.dispose();
    _medCtrl.dispose();
    _locateReset.dispose();
    super.dispose();
  }

  /// 縣市「台→臺」；行政區原樣不合法才嘗試正規化版本（雲林縣「台西鄉」白名單本身是「台」）。
  (String?, String?) _normalizeRegion(String? city, String? district) {
    if (city == null || city.trim().isEmpty) return (null, null);
    final c = city.trim().replaceAll('台', '臺');
    final d = district?.trim();
    if (d == null || d.isEmpty) return (null, null);
    if (isValidCityDistrict(c, d)) return (c, d);
    final alt = d.replaceAll('台', '臺');
    if (isValidCityDistrict(c, alt)) return (c, alt);
    return (null, null);
  }

  /// 舊資料只有 `location` 自由文字（例「台北市大安區」）→ 試著切成縣市＋區。
  (String?, String?) _parseLegacyLocation(String loc) {
    final cityIdx = loc.indexOf('市');
    final countyIdx = loc.indexOf('縣');
    final idxs = [cityIdx, countyIdx].where((i) => i >= 0).toList()..sort();
    if (idxs.isEmpty || idxs.first + 1 >= loc.length) return (null, null);
    final split = idxs.first + 1;
    return _normalizeRegion(loc.substring(0, split), loc.substring(split));
  }

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
        _loadError = ApiService.failureMessageOf(resp, fallback: '長輩資料讀取失敗');
      });
      return;
    }

    final name = '${data['elder_name'] ?? data['user_name'] ?? ''}'.trim();
    final ageRaw = data['age'];
    final age = ageRaw is num ? ageRaw.toInt() : int.tryParse('${ageRaw ?? ''}');
    final gender = normalizeGender(data['gender']);
    var (city, district) = _normalizeRegion(
      data['residence_city']?.toString(),
      data['residence_district']?.toString(),
    );
    final legacy = '${data['location'] ?? ''}'.trim();
    if (city == null) (city, district) = _parseLegacyLocation(legacy);

    setState(() {
      _baseName = name;
      _baseAge = age;
      _baseGender = gender;
      _baseCity = city;
      _baseDistrict = district;
      _baseChronic = '${data['chronic_diseases'] ?? ''}'.trim();
      _baseMed = '${data['medication_notes'] ?? ''}'.trim();
      _legacyLocation = legacy;
      _nameCtrl.text = name;
      _ageCtrl.text = age?.toString() ?? '';
      _gender = gender;
      _city = city;
      _district = district;
      _chronicCtrl.text = _baseChronic;
      _medCtrl.text = _baseMed;
      _loading = false;
    });
  }

  /// 只回傳跟載入值不同的欄位；回傳 (欄位, 錯誤訊息)。
  (Map<String, dynamic>, String?) _collectChanges() {
    final fields = <String, dynamic>{};
    final cleared = <String>[];

    final name = _nameCtrl.text.trim();
    if (name != _baseName) {
      if (name.isEmpty) {
        cleared.add('姓名');
      } else {
        fields['user_name'] = name; // 後端會同步寫 elder_profile.elder_name
      }
    }

    final ageText = _ageCtrl.text.trim();
    if (ageText.isEmpty) {
      if (_baseAge != null) cleared.add('年齡');
    } else {
      final age = int.tryParse(ageText);
      if (age == null || age < 1 || age > 120) {
        return (fields, '年齡請輸入 1 到 120 之間的整數');
      }
      if (age != _baseAge) fields['age'] = age;
    }

    if (_gender != null && _gender != _baseGender) fields['gender'] = _gender;

    if (_city != null &&
        _district != null &&
        (_city != _baseCity || _district != _baseDistrict)) {
      fields['residence_city'] = _city;
      fields['residence_district'] = _district;
      fields['location'] = '$_city$_district';
    }

    final chronic = _chronicCtrl.text.trim();
    if (chronic != _baseChronic) {
      chronic.isEmpty ? cleared.add('慢性病') : fields['chronic_diseases'] = chronic;
    }
    final med = _medCtrl.text.trim();
    if (med != _baseMed) {
      med.isEmpty ? cleared.add('用藥備註') : fields['medication_notes'] = med;
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
      showProfileSnack(context, '長輩檔案已更新', success: true);
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
        title: Text('長輩檔案', style: ubanText(19, FontWeight.w800, c.text)),
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
            title: '基本資料',
            icon: Icons.person_rounded,
            children: [
              UbanTextField(
                label: '姓名',
                hintText: '長輩的姓名',
                controller: _nameCtrl,
              ),
              const SizedBox(height: 14),
              UbanTextField(
                label: '年齡',
                hintText: '歲數',
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              const ProfileLabel('性別'),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('gender_M'),
                    label: const Text('男性'),
                    selected: _gender == 'M',
                    onSelected: (_) => setState(() => _gender = 'M'),
                  ),
                  ChoiceChip(
                    key: const ValueKey('gender_F'),
                    label: const Text('女性'),
                    selected: _gender == 'F',
                    onSelected: (_) => setState(() => _gender = 'F'),
                  ),
                ],
              ),
              if (_gender == null) ...[
                const SizedBox(height: 6),
                Text('尚未填寫', style: ubanText(13, FontWeight.w500, c.text3)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          ProfileSection(
            title: '居住地區',
            icon: Icons.location_on_rounded,
            children: [
              LocateCityButton(
                resetNotifier: _locateReset,
                onLocated: (city, district) => setState(() {
                  _city = city;
                  _district = district;
                }),
              ),
              const SizedBox(height: 12),
              CityDistrictPicker(
                initialCity: _city,
                initialDistrict: _district,
                onChanged: (city, district) {
                  _locateReset.value++;
                  setState(() {
                    _city = city;
                    _district = district;
                  });
                },
              ),
              if (_city == null && _legacyLocation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '目前紀錄的地區：$_legacyLocation（請重新選擇縣市與區）',
                  style: ubanText(13, FontWeight.w500, c.text3, height: 1.4),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          ProfileSection(
            title: '健康與用藥',
            icon: Icons.health_and_safety_rounded,
            children: [
              UbanTextField(
                label: '慢性病與健康注意',
                hintText: '例如：高血壓、糖尿病、對盤尼西林過敏',
                controller: _chronicCtrl,
                maxLines: 3,
                minLines: 2,
              ),
              const SizedBox(height: 14),
              UbanTextField(
                label: '用藥備註',
                hintText: '例如：早晚飯後服用降血壓藥',
                controller: _medCtrl,
                maxLines: 3,
                minLines: 2,
              ),
            ],
          ),
          const SizedBox(height: 20),
          UbanButton(
            key: const ValueKey('save_basic_profile'),
            label: '儲存長輩檔案',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (widget.onUnbind != null) ...[
            const SizedBox(height: 12),
            UbanButton(
              label: '解除與此長輩的綁定',
              variant: UbanButtonVariant.outline,
              icon: Icons.link_off_rounded,
              onPressed: widget.onUnbind,
            ),
          ],
        ],
      ),
    );
  }
}
