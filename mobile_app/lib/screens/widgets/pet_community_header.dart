import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/pet_controller.dart';
import 'pet_reward_dialog.dart';

class PetCommunityHeader extends StatefulWidget {
  final PetController? petController;
  final String elderName;
  final int latestPostCount;

  const PetCommunityHeader({
    super.key,
    this.petController,
    required this.elderName,
    this.latestPostCount = 0,
  });

  @override
  State<PetCommunityHeader> createState() => _PetCommunityHeaderState();
}

class _PetCommunityHeaderState extends State<PetCommunityHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String _customSpeech = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _getPetSpeech() {
    if (_customSpeech.isNotEmpty) return _customSpeech;
    final hour = DateTime.now().hour;
    if (hour < 11) {
      return '阿公早安！今天想跟家人分享什麼呢？🐾';
    } else if (hour < 14) {
      return '中午吃飽飽了嗎？拍張好吃的跟大家說～🍲';
    } else if (hour < 18) {
      return '下午散步走一走，心情一定很放鬆！🌸';
    } else {
      return '天黑了要注意保暖喔，小嘎一直陪著你～🌙';
    }
  }

  void _interactWithPet() {
    setState(() {
      _customSpeech = '嘎挖！謝謝你摸摸我，今天也是元氣滿滿的一天～💖';
    });
    PetRewardDialog.show(
      context,
      title: '摸摸小嘎！',
      message: '小嘎最喜歡陪伴在身邊了～',
      intimacyExp: 5,
      coins: 1,
    );
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _customSpeech = '');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.petController?.status;
    final happiness = pet?.happiness.toInt() ?? 88;
    final intimacyLevel = (happiness / 25).floor() + 1;
    final progress = (happiness % 25) / 25.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF55B695).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFDFFFF4),
          width: 2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 寵物可互動動態頭像
          GestureDetector(
            onTap: _interactWithPet,
            behavior: HitTestBehavior.opaque,
            child: ScaleTransition(
              scale: _pulseAnimation,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFDFFFF4), Color(0xFFE8FDF5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF55B695),
                        width: 2.5,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        '🐶',
                        style: TextStyle(fontSize: 40),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF55B695),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'LV.$intimacyLevel',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          // 寵物對話氣泡與親密度進度條
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '小嘎',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1E3A34),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('💖', style: TextStyle(fontSize: 11)),
                          SizedBox(width: 2),
                          Text(
                            '貼心守護中',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE11D48),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 說話氣泡
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFBBF7D0),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    _getPetSpeech(),
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF166534),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // 親密度小進度條
                Row(
                  children: [
                    Text(
                      '親密度',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.1, 1.0),
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF55B695),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF55B695),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
