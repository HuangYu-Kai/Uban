import 'package:flutter/material.dart';

import '../../../services/api/pet_gift_api.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ui/uban_sheet.dart';
import '../widgets/fam_ui.dart';

/// 送出動作的簽名（測試可注入；預設走 [PetGiftApi.send]）。
typedef PetGiftSender = Future<PetGiftSendResult> Function(String foodId);

/// ★ 2026-10-07 小豬共養：家屬挑一種點心送給長輩的小豬。
///
/// 點心不是直接餵，而是放進長輩的小豬食物盒，由長輩親手餵——這句話放在面板裡講清楚。
/// 成功以 `Navigator.pop(true)` 關閉，呼叫端顯示 SnackBar 並重讀卡片；
/// 失敗（含「今天已送過」）訊息留在面板內，使用者可改選或關閉。
class SendPetGiftSheet extends StatefulWidget {
  final String elderName;
  final int familyId;
  final String elderId;

  /// 測試注入點；null 時使用真實 API。
  final PetGiftSender? sender;

  const SendPetGiftSheet({
    super.key,
    required this.elderName,
    required this.familyId,
    required this.elderId,
    this.sender,
  });

  /// 顯示面板；回傳 true 表示已成功送出。
  static Future<bool> show(
    BuildContext context, {
    required String elderName,
    required int familyId,
    required String elderId,
  }) async {
    final r = await showUbanSheet<bool>(
      context,
      (ctx) => SendPetGiftSheet(
        elderName: elderName,
        familyId: familyId,
        elderId: elderId,
      ),
    );
    return r == true;
  }

  @override
  State<SendPetGiftSheet> createState() => _SendPetGiftSheetState();
}

class _SendPetGiftSheetState extends State<SendPetGiftSheet> {
  String? _selected;
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    final food = _selected;
    if (food == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final PetGiftSendResult r;
    try {
      r = widget.sender != null
          ? await widget.sender!(food)
          : await PetGiftApi.send(
              familyId: widget.familyId, elderId: widget.elderId, foodId: food);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = PetGiftApi.networkErrorMessage;
        });
      }
      return;
    }
    if (!mounted) return;
    if (r.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _sending = false;
        _error = r.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    // 面板外殼（UbanSheet）已提供捲動與 86% 高度上限，這裡不再包 Flexible／捲動。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 標題含長輩姓名（長度不可控），maxLines＋ellipsis（規則 14）。
        Text(
          '送點心給${widget.elderName}的小豬',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: famText(c.text, 18, weight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          '點心會放進${widget.elderName}的小豬食物盒，由${widget.elderName}親手餵牠',
          style: famText(c.text2, 13, height: 1.45),
        ),
        const SizedBox(height: 14),
        // 三個大圖磚用 Wrap：窄螢幕／大字級會自動換行而不溢位。
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final f in PetGiftFood.defaults) _tile(c, f),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const ValueKey('pet_gift_error'),
            style:
                famText(c.danger, 13.5, weight: FontWeight.w600, height: 1.4),
          ),
        ],
        const SizedBox(height: 16),
        FamButton(
          key: const ValueKey('pet_gift_send'),
          label: '送出',
          loading: _sending,
          onPressed: (_selected == null || _sending) ? null : _send,
        ),
      ],
    );
  }

  Widget _tile(UbanColors c, PetGiftFood f) {
    final selected = _selected == f.id;
    return Semantics(
      button: true,
      selected: selected,
      label: f.name,
      child: GestureDetector(
        key: ValueKey('pet_gift_food_${f.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: _sending
            ? null
            : () => setState(() {
                  _selected = f.id;
                  _error = null;
                }),
        child: Container(
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? c.brandContainer : c.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? c.brand : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: Image.asset(
                  f.imageAsset,
                  fit: BoxFit.contain,
                  // 資產缺失時退回 emoji，不要紅畫面。
                  errorBuilder: (_, __, ___) => Center(
                      child:
                          Text(f.emoji, style: const TextStyle(fontSize: 36))),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: famText(selected ? c.brandStrong : c.text, 14,
                    weight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
