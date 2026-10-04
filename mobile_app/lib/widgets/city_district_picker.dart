import 'package:flutter/material.dart';
import '../utils/taiwan_districts.dart';
import 'ui/ui.dart';

/// 縣市／行政區串聯下拉選單。
///
/// ★ 第五十三輪 onboard53：長輩端／家屬端「年齡與居住地改為必填」共用元件。
///
/// 刻意用下拉選單而非自由文字輸入框——這筆資料「用於開發者統計」
/// （見 uban-api/routers/admin_stats.py），自由文字會讓同一個城市因為打法
/// 不同被統計成好幾組。選項來源固定為 [kTaiwanCities]／[kTaiwanDistricts]
/// （`lib/utils/taiwan_districts.dart`），與後端 `services/taiwan_regions.py`
/// 是同一份白名單的兩份拷貝，後端仍會再驗證一次，不因為前端已用下拉選單
/// 就略過（見 routers/auth.py::register() 與 routers/user.py::update_profile()）。
///
/// 換縣市時會自動清空已選的行政區——舊行政區可能不屬於新縣市，兩者必須
/// 成對合法（見 [isValidCityDistrict]），留著舊值只會製造「縣市與行政區對不
/// 起來」的髒資料。
///
/// [elderMode] 為 true 時套用長輩尺規（欄高 68、字級 20、縣市／行政區上下排列）；
/// 為 false 時走設計稿 `.input`（高 58、縣市／行政區並排）。外觀走 [UbanColors]，
/// 參數與回傳不變。
class CityDistrictPicker extends StatefulWidget {
  final String? initialCity;
  final String? initialDistrict;
  final void Function(String? city, String? district) onChanged;
  final bool elderMode;

  const CityDistrictPicker({
    super.key,
    this.initialCity,
    this.initialDistrict,
    required this.onChanged,
    this.elderMode = false,
  });

  @override
  State<CityDistrictPicker> createState() => _CityDistrictPickerState();
}

class _CityDistrictPickerState extends State<CityDistrictPicker> {
  String? _city;
  String? _district;

  @override
  void initState() {
    super.initState();
    // 只在「縣市＋行政區」本來就是合法組合時才帶入初始值，避免舊的自由文字
    // 殘留資料（例如既有 location 欄位解析出的怪值）餵進下拉選單找不到對應項。
    if (isValidCityDistrict(widget.initialCity, widget.initialDistrict)) {
      _city = widget.initialCity;
      _district = widget.initialDistrict;
    }
  }

  void _onCityChanged(String? city) {
    setState(() {
      _city = city;
      _district = null;
    });
    widget.onChanged(_city, _district);
  }

  void _onDistrictChanged(String? district) {
    setState(() => _district = district);
    widget.onChanged(_city, _district);
  }

  @override
  Widget build(BuildContext context) {
    final districts = _city != null ? (kTaiwanDistricts[_city] ?? const <String>[]) : const <String>[];

    final cityField = _buildDropdown(
      label: '縣市',
      value: _city,
      items: kTaiwanCities,
      hint: '請選擇縣市',
      onChanged: _onCityChanged,
    );
    final districtField = _buildDropdown(
      label: '區',
      value: _district,
      items: districts,
      hint: _city == null ? '請先選縣市' : '請選擇行政區',
      onChanged: districts.isEmpty ? null : _onDistrictChanged,
    );

    if (widget.elderMode) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cityField,
          const SizedBox(height: 20),
          districtField,
        ],
      );
    }
    // 設計稿：縣市與區並排，各佔一半；內容可收縮，窄螢幕／大字級不溢位。
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: cityField),
        const SizedBox(width: 10),
        Expanded(child: districtField),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?>? onChanged,
  }) {
    final c = UbanColors.of(context);
    final bool elderMode = widget.elderMode;
    final TextStyle labelStyle =
        ubanText(elderMode ? 18 : 15, FontWeight.w700, c.text2);
    final TextStyle itemStyle =
        ubanText(elderMode ? 20 : 17, FontWeight.w500, c.text);
    final TextStyle hintStyle =
        ubanText(elderMode ? 20 : 16, FontWeight.w500, c.text3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
        const SizedBox(height: 6),
        Container(
          constraints: BoxConstraints(minHeight: elderMode ? 68 : 58),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line, width: 1.5),
          ),
          // ★ 刻意用 DropdownButton（受控 value）而非 DropdownButtonFormField：
          //   後者的 initialValue 只在第一次建立時生效，換縣市時用 setState 把
          //   _district 設回 null 並不會真的清空畫面上已顯示的選取項——這是
          //   DropdownButtonFormField 已知的「非受控」行為，与本元件「換縣市要
          //   重新選區」的需求衝突。DropdownButton.value 每次 rebuild 都會套用，
          //   是這裡需要的完全受控行為，也與全 App 既有的 DropdownButton 用法
          //   一致（見 family_interaction_tab.dart／health_reminder_screen.dart）。
          child: DropdownButton<String>(
            value: value,
            isExpanded: true, // 讓選中文字在按鈕內可收縮，長行政區名不會溢出
            underline: const SizedBox.shrink(), // 外層已有自訂邊框，不需要預設底線
            dropdownColor: c.surface,
            borderRadius: BorderRadius.circular(18),
            icon: Icon(Icons.arrow_drop_down_rounded,
                size: elderMode ? 32 : 24, color: c.text2),
            hint: Text(hint, style: hintStyle, overflow: TextOverflow.ellipsis),
            items: items
                .map((item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item, style: itemStyle, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
