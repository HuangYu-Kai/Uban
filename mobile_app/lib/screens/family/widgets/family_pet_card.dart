import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/elder.dart';
import '../../../services/api/pet_gift_api.dart';
import '../../../theme/app_theme.dart';
import '../../pet_companion_studio/models/pet_growth_state.dart';
import '../../pet_companion_studio/services/pet_progress_service.dart';
import '../daily_question_screen.dart' show resolveFamilyId;
import '../sheets/send_pet_gift_sheet.dart';
import 'fam_interaction_ui.dart';
import 'fam_ui.dart';

/// 讀取小豬狀態的簽名（測試可注入；預設走 [PetGiftApi.getStatus]）。
typedef PetGiftStatusLoader = Future<PetGiftStatusResult> Function(
    int familyId, String elderId);

/// 開啟送點心面板的簽名（測試可注入；回傳 true 表示已送出）。
typedef PetGiftSheetOpener = Future<bool> Function(
    BuildContext context, String elderName, int familyId, String elderId);

/// 體重顯示：滿 1 公斤用 kg（1 位小數），否則用 g。
String formatPetWeight(int grams) =>
    grams >= 1000 ? '${(grams / 1000).toStringAsFixed(1)} kg' : '$grams g';

/// 依體重（讀長輩端同一份門檻 [PetGrowthStage.fromWeight]）與品種挑小豬圖，
/// 路徑規則與長輩端一致：`pet_breeds/{breed}_front_{stage}.png`。
String petCardImageAsset(int weightGrams, String breed) {
  final stageNo = PetGrowthStage.fromWeight(weightGrams).index + 1;
  final b = breed == 'black' ? 'black' : 'pink';
  return 'assets/images/pet_breeds/${b}_front_$stageNo.png';
}

/// ★ 2026-10-07 小豬共養：家屬互動分頁的「小豬」卡片。
///
/// 顯示長輩的小豬（依階段／品種）、體重、今天家人送了幾份點心、最近的點心紀錄與「送點心給小豬」。
/// 家屬互動分頁在 IndexedStack 內被保活，因此靠父層遞增 [refreshToken]
/// （收到 `pet-gift-fed` Socket 時）重讀，並在送出成功後自行重讀。
class FamilyPetCard extends StatefulWidget {
  final Elder? currentElder;
  final int? userId;
  final int refreshToken;

  /// 測試注入點。
  final PetGiftStatusLoader? loader;
  final PetGiftSheetOpener? sheetOpener;

  const FamilyPetCard({
    super.key,
    required this.currentElder,
    this.userId,
    this.refreshToken = 0,
    this.loader,
    this.sheetOpener,
  });

  @override
  State<FamilyPetCard> createState() => _FamilyPetCardState();
}

class _FamilyPetCardState extends State<FamilyPetCard> {
  bool _loading = true;
  bool _error = false;
  bool _notBound = false;
  PetGiftStatus? _status;
  int? _familyId;

  String? get _elderId =>
      widget.currentElder?.elderId ?? widget.currentElder?.id.toString();
  String get _elderName => widget.currentElder?.displayName ?? '長輩';

  @override
  void initState() {
    super.initState();
    // 成長階段門檻（與長輩端同一份）；測試注入 loader 時不碰網路／偏好。
    if (widget.loader == null) {
      unawaited(PetProgressService.ensureStageBoundsLoaded()
          .then((_) => PetProgressService.refreshStageBounds())
          .then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {}));
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant FamilyPetCard old) {
    super.didUpdateWidget(old);
    final oldId = old.currentElder?.elderId ?? old.currentElder?.id.toString();
    if (widget.refreshToken != old.refreshToken) {
      _load(silent: true);
    } else if (oldId != _elderId) {
      _status = null;
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    final id = _elderId;
    if (id == null) return;
    if (!silent && mounted) setState(() => _loading = true);
    PetGiftStatusResult r;
    try {
      final fid = _familyId ??= await resolveFamilyId(widget.userId);
      if (fid == null) {
        r = const PetGiftStatusResult();
      } else {
        r = widget.loader != null
            ? await widget.loader!(fid, id)
            : await PetGiftApi.getStatus(familyId: fid, elderId: id);
      }
    } catch (_) {
      r = const PetGiftStatusResult();
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.status != null) {
        _status = r.status;
        _error = false;
        _notBound = false;
      } else if (r.notBound) {
        _status = null;
        _notBound = true;
        _error = false;
      } else if (_status == null) {
        // 靜默重讀失敗時保留舊資料。
        _error = true;
      }
    });
  }

  Future<void> _openSheet() async {
    final fid = _familyId ?? await resolveFamilyId(widget.userId);
    final id = _elderId;
    if (fid == null || id == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final elderName = _elderName;
    // 先在 await 之前用目前 context 建好成功提示（套用家屬端統一樣式），避免跨 async 用 context。
    final snack =
        famSnackBar(context, '已送出！等$elderName餵小豬時會通知您', success: true);
    final bool ok;
    if (widget.sheetOpener != null) {
      ok = await widget.sheetOpener!(context, elderName, fid, id);
    } else {
      ok = await SendPetGiftSheet.show(context,
          elderName: elderName, familyId: fid, elderId: id);
    }
    if (!ok || !mounted) return;
    messenger.showSnackBar(snack);
    unawaited(_load(silent: true));
  }

  String _historyLine(PetGiftRecent g) {
    final who = g.familyName.trim().isEmpty ? '家人' : g.familyName.trim();
    final food = g.foodName.trim().isEmpty ? '點心' : g.foodName.trim();
    return '$who 送的$food ${g.fed ? '✓ 已餵' : '等$_elderName餵食'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final s = _status;

    Widget body;
    if (_loading && s == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      );
    } else if (s == null) {
      body = Text(
        _notBound
            ? '$_elderName還沒有開始養小豬喔'
            : (_error ? '暫時讀不到小豬的狀況，稍後再試一次' : '小豬還在準備中'),
        key: const ValueKey('pet_card_empty'),
        style: famText(c.text2, 14, height: 1.5),
      );
    } else {
      final recent = s.recent.take(2).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 圖＋文字：文字欄用 Expanded 可收縮（規則 14）。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Image.asset(
                  petCardImageAsset(s.weightGrams, s.breed),
                  key: const ValueKey('pet_card_image'),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                      child: Text('🐷', style: TextStyle(fontSize: 44))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${formatPetWeight(s.weightGrams)} · ${PetGrowthStage.fromWeight(s.weightGrams).title}',
                      key: const ValueKey('pet_card_weight'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text, 16,
                          weight: FontWeight.w800, height: 1.35),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '今天家人送了 ${s.elderGiftsToday}/${s.perElderPerDay} 份點心',
                      key: const ValueKey('pet_card_count'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: famText(c.text2, 13.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final g in recent)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _historyLine(g),
                  key: ValueKey('pet_card_gift_${g.giftId}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: famText(g.fed ? c.brandStrong : c.text3, 13.5,
                      height: 1.4),
                ),
              ),
          ],
        ],
      );
    }

    final canGift = s?.canGiftToday == true;
    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FamSecHead(title: '小豬'),
          const SizedBox(height: 10),
          body,
          if (s != null) ...[
            const SizedBox(height: 12),
            FamButton(
              key: const ValueKey('pet_card_gift'),
              label: canGift ? '送點心給小豬' : '今天已經送過了',
              height: 42,
              onPressed: canGift ? _openSheet : null,
            ),
          ],
        ],
      ),
    );
  }
}
