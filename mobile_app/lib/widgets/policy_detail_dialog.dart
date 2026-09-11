import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/privacy_policy_content.dart';

/// ★ 2026-09-11 第四十五輪第五項需求：從 `registration_screen.dart` 抽出的
/// 共用政策詳情彈窗（原私有類別 `_ModernPolicyDialog` / `_SectionData`）。
///
/// 目的是讓「家屬註冊頁的《隱私權政策》彈窗」與「首次安裝的精簡同意頁點擊
/// 超連結後彈出的政策全文」使用**同一份彈窗外觀**，而不是各自刻一份、日後
/// 樣式漸行漸遠。內容一律透過 [PrivacyPolicySection]（見
/// `../data/privacy_policy_content.dart`）傳入，本檔案只負責呈現。
///
/// 醫療免責聲明（`registration_screen.dart` 的 `_showDisclaimerDialog`）
/// 內容仍留在原檔案、邏輯完全不變，只是改用這裡的共用外觀渲染。
class PolicyDetailDialog extends StatefulWidget {
  final String title;
  final String introText;
  final List<PrivacyPolicySection> sections;
  final Color primaryColor;
  final Color secondaryColor;
  final IconData headerIcon;

  /// 顯示於標題下方的「最後更新」字樣；預設值與本專案既有政策彈窗一致，
  /// 傳入 `PrivacyPolicyContent.lastUpdated` 可顯示隱私權政策自己的日期。
  final String lastUpdated;

  const PolicyDetailDialog({
    super.key,
    required this.title,
    required this.introText,
    required this.sections,
    required this.primaryColor,
    required this.secondaryColor,
    required this.headerIcon,
    this.lastUpdated = '最後更新：2026 年 6 月 4 日',
  });

  /// 以本專案既有的縮放＋淡入轉場顯示本彈窗，取代呼叫端各自重複的
  /// `showGeneralDialog(...)` 樣板。
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String introText,
    required List<PrivacyPolicySection> sections,
    required Color primaryColor,
    required Color secondaryColor,
    required IconData headerIcon,
    String? lastUpdated,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Transform.scale(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.easeOutBack,
          ).value,
          child: Opacity(
            opacity: anim1.value,
            child: PolicyDetailDialog(
              title: title,
              introText: introText,
              headerIcon: headerIcon,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
              sections: sections,
              lastUpdated: lastUpdated ?? '最後更新：2026 年 6 月 4 日',
            ),
          ),
        );
      },
    );
  }

  @override
  State<PolicyDetailDialog> createState() => _PolicyDetailDialogState();
}

class _PolicyDetailDialogState extends State<PolicyDetailDialog> {
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _onScroll();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll > 0) {
      setState(() {
        _scrollProgress = (currentScroll / maxScroll).clamp(0.0, 1.0);
      });
    } else {
      setState(() {
        _scrollProgress = 1.0;
      });
    }
  }

  bool get _isFullyRead {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return true;
    return _scrollProgress >= 0.92;
  }

  @override
  Widget build(BuildContext context) {
    final bool isRead = _isFullyRead;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // 1. Header (Gradient background with icon & title)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [widget.primaryColor, widget.secondaryColor],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.headerIcon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.lastUpdated,
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // 2. Scroll Progress bar
            Container(
              height: 4,
              width: double.infinity,
              color: widget.primaryColor.withValues(alpha: 0.1),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _scrollProgress,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.primaryColor, widget.secondaryColor],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Scrollable Content
            Expanded(
              child: RawScrollbar(
                controller: _scrollController,
                thumbColor: widget.primaryColor.withValues(alpha: 0.3),
                radius: const Radius.circular(4),
                thickness: 4,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Intro Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: widget.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.primaryColor.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: widget.primaryColor,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.introText,
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 12.5,
                                  color: widget.primaryColor.withValues(alpha: 0.85),
                                  height: 1.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Section list
                      ...widget.sections.asMap().entries.map((entry) {
                        return _buildSectionCard(entry.value, entry.key + 1);
                      }),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // 4. Bottom Action Area
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isRead
                                ? [widget.primaryColor, widget.secondaryColor]
                                : [Colors.grey[400]!, Colors.grey[500]!],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: isRead
                                  ? widget.primaryColor.withValues(alpha: 0.3)
                                  : Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            if (isRead) {
                              Navigator.pop(context);
                            } else {
                              _scrollController.animateTo(
                                _scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isRead ? Icons.check_circle_outline : Icons.arrow_downward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isRead ? '我已閱讀並理解' : '向下滾動閱讀全文',
                                style: GoogleFonts.notoSansTc(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(PrivacyPolicySection section, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: widget.primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: widget.primaryColor.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            section.icon,
                            size: 16,
                            color: widget.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            section.title,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...section.bulletPoints.map((point) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0, right: 8.0),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: widget.primaryColor.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: RichText(
                                  text: _parseFormattedText(point),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _parseFormattedText(String text) {
    final List<TextSpan> children = [];
    final RegExp regExp = RegExp(r'\*\*(.*?)\*\*');
    int start = 0;

    for (final Match match in regExp.allMatches(text)) {
      if (match.start > start) {
        children.add(TextSpan(
          text: text.substring(start, match.start),
          style: GoogleFonts.notoSansTc(
            fontSize: 13,
            color: const Color(0xFF4B5563),
            height: 1.5,
          ),
        ));
      }
      children.add(TextSpan(
        text: match.group(1),
        style: GoogleFonts.notoSansTc(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0F172A),
          height: 1.5,
        ),
      ));
      start = match.end;
    }

    if (start < text.length) {
      children.add(TextSpan(
        text: text.substring(start),
        style: GoogleFonts.notoSansTc(
          fontSize: 13,
          color: const Color(0xFF4B5563),
          height: 1.5,
        ),
      ));
    }

    return TextSpan(children: children);
  }
}
