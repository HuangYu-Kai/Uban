import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import '../../../services/api_service.dart';

// 【全新升級】長輩專屬落葉暖心對話木牌卡片 (沉香木紋與泥金宣紙風格，帶有拍立得家人照與後端 edge-tts 播放)

class LeafMessageCard extends StatefulWidget {
  final String id;
  final String message;
  final String? imageUrl;
  final VoidCallback onDismiss;

  const LeafMessageCard({
    super.key,
    required this.id,
    required this.message,
    this.imageUrl,
    required this.onDismiss,
  });

  @override
  State<LeafMessageCard> createState() => _LeafMessageCardState();
}

class _LeafMessageCardState extends State<LeafMessageCard> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoadingTts = false;
  String? _ttsError;

  @override
  void initState() {
    super.initState();
    // 監聽播放器狀態，結束時自動恢復喇叭按鈕
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // 提取 Base64 載荷 (相容 web / mobile 前綴，並安全補足 Padding)
  String _extractBase64Payload(String raw) {
    String text = raw.trim();
    if (text.startsWith('data:')) {
      final commaIndex = text.indexOf(',');
      if (commaIndex >= 0 && commaIndex < text.length - 1) {
        text = text.substring(commaIndex + 1);
      }
    }
    text = text.replaceAll(RegExp(r'\s+'), '');
    final missingPadding = text.length % 4;
    if (missingPadding > 0) {
      text += '=' * (4 - missingPadding);
    }
    return text;
  }

  // 調用後端 edge-tts 合成並播報
  Future<void> _speakTts() async {
    if (_isLoadingTts) return;

    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
      return;
    }

    setState(() {
      _isLoadingTts = true;
      _ttsError = null;
    });

    try {
      // 移除 [VIDEO_ID] 等標記，避免唸出技術細節
      String speakText = widget.message.replaceAll(RegExp(r'\[VIDEO_ID:[^\]]+\]'), '').trim();
      
      final response = await ApiService.synthesizeTts(text: speakText);
      final isSuccess = response['success'] == true || response['status'] == 'success';
      if (!isSuccess) {
        final detail = response['detail'] ?? response['message'] ?? response['error'];
        throw Exception(detail ?? 'TTS 合成失敗');
      }

      final audioBase64 = (response['audio'] ?? response['audio_base64'] ?? '').toString();
      if (audioBase64.isEmpty) {
        throw Exception('語音合成數據為空');
      }

      String payload = _extractBase64Payload(audioBase64);
      final audioBytes = base64Decode(payload);

      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(audioBytes));

      if (mounted) {
        setState(() {
          _isLoadingTts = false;
          _isPlaying = true;
        });
      }
    } catch (e) {
      debugPrint('LeafMessageCard TTS error: $e');
      if (mounted) {
        setState(() {
          _isLoadingTts = false;
          _ttsError = '語音合成失敗，請再點一次';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Dismissible(
        // 使用 leaf 的 id 做 ValueKey，確保滑動不遺失狀態
        key: ValueKey('leaf_dismiss_${widget.id}'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => widget.onDismiss(),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.88,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            // 溫潤宣紙金沙漸層
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFDF9), Color(0xFFFDFBF7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            // 古雅沉香實木邊框
            border: Border.all(
              color: const Color(0xFF8C6D58),
              width: 3.5,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              // 微熱浮動水燈光暈
              BoxShadow(
                color: const Color(0xFFFFB74D).withOpacity(0.18),
                blurRadius: 25,
                spreadRadius: 3,
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 頂部插圖與精緻標題
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFB74D),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '捎來的禪意捎信',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8C6D58),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFB74D),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 泥金精細分隔線
                Container(
                  height: 1.5,
                  width: 80,
                  color: const Color(0xFFD7CCC8),
                ),
                const SizedBox(height: 20),

                // 2. 拍立得紙框家人照片 (若有圖片則展示)
                if (widget.imageUrl != null) ...[
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE0DCD3), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            widget.imageUrl!,
                            fit: BoxFit.cover,
                            height: 180,
                            width: double.infinity,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                height: 180,
                                color: const Color(0xFFF5F2EB),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF8C6D58),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 180,
                              color: const Color(0xFFF5F2EB),
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image_rounded,
                                  color: Color(0xFFBCAAA4),
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                ],

                // 3. 訊息主體 (超大高對比巧克力黑體，長輩易讀)
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 27,
                    height: 1.55,
                    color: const Color(0xFF3E2723), // 深巧克力色，對比清晰溫和
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),

                // 4. 錯誤提示 (若有)
                if (_ttsError != null) ...[
                  Text(
                    _ttsError!,
                    style: GoogleFonts.notoSansTc(fontSize: 14, color: Colors.redAccent),
                  ),
                  const SizedBox(height: 8),
                ],

                // 5. 底部語音與關閉互動列
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // A. edge-tts 語音播報大按鈕
                    GestureDetector(
                      onTap: _speakTts,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: _isPlaying 
                              ? const Color(0xFFE8F5E9) 
                              : const Color(0xFFFFF3E0),
                          border: Border.all(
                            color: _isPlaying 
                                ? const Color(0xFF81C784) 
                                : const Color(0xFFFFB74D),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isLoadingTts)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFFB74D),
                                ),
                              )
                            else
                              Icon(
                                _isPlaying ? Icons.volume_up : Icons.volume_mute,
                                color: _isPlaying 
                                    ? const Color(0xFF388E3C) 
                                    : const Color(0xFFF57C00),
                                size: 24,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              _isPlaying ? '播報中' : '讀給我聽',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _isPlaying 
                                    ? const Color(0xFF388E3C) 
                                    : const Color(0xFFE65100),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // B. 傳統收起按鈕 (不需滑動也可直接點擊關閉)
                    ElevatedButton(
                      onPressed: () {
                        _audioPlayer.stop();
                        widget.onDismiss();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8C6D58),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        '關閉',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                // 6. 滑動引導指示
                Text(
                  '👈 左右滑動木牌亦可關閉 👉',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    color: const Color(0xFF8D6E63),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
    );
  }
}
