import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final FlutterTts flutterTts = FlutterTts();

  // 模擬聯絡人資料
  final List<Contact> contacts = [
    Contact(
      name: '大兒子',
      relation: '王大明',
      imageUrl: 'https://randomuser.me/api/portraits/men/11.jpg',
      phoneNumber: '0912345678',
    ),
    Contact(
      name: '二女兒',
      relation: '王小美',
      imageUrl: 'https://randomuser.me/api/portraits/women/44.jpg',
      phoneNumber: '0987654321',
    ),
    Contact(
      name: '乖孫',
      relation: '小寶',
      imageUrl: 'https://randomuser.me/api/portraits/men/8.jpg', // 暫用年輕男性模擬
      phoneNumber: '0911223344',
    ),
    Contact(
      name: '老伴',
      relation: '牽手',
      imageUrl: 'https://randomuser.me/api/portraits/women/90.jpg',
      phoneNumber: '0223456789',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("zh-TW");
    await flutterTts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  // 撥打電話
  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法撥打電話，請檢查裝置設定')));
      }
    }
  }

  // 顯示撥號確認對話框
  void _showCallConfirmation(Contact contact) {
    // 播放語音
    flutterTts.speak('要打給${contact.name}嗎？');

    showDialog(
      context: context,
      barrierDismissible: false, // 強制選擇，防止誤觸背景關閉
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 大頭照
                CircleAvatar(
                  radius: 80, // 加大
                  backgroundColor: Colors.grey[200],
                  backgroundImage: contact.imageUrl != null
                      ? NetworkImage(contact.imageUrl!)
                      : null,
                  child: contact.imageUrl == null
                      ? const FaIcon(FontAwesomeIcons.user, size: 60)
                      : null,
                ),
                const SizedBox(height: 24),

                // 詢問文字
                Text(
                  '要打給',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 48,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  contact.name,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  '嗎？',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 48,
                    color: Colors.grey[700],
                  ),
                ),

                const SizedBox(height: 48),

                // 按鈕區
                Row(
                  children: [
                    // 取消按鈕 (紅色)
                    Expanded(
                      child: SizedBox(
                        height: 100, // 加高
                        child: ElevatedButton.icon(
                          onPressed: () {
                            flutterTts.stop();
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[100],
                            foregroundColor: Colors.red[800],
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          icon: const Icon(Icons.close, size: 40),
                          label: Text(
                            '取消',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 撥打按鈕 (綠色)
                    Expanded(
                      child: SizedBox(
                        height: 100, // 加高
                        child: ElevatedButton.icon(
                          onPressed: () {
                            flutterTts.stop();
                            Navigator.pop(context); // 關閉對話框
                            _makePhoneCall(contact.phoneNumber); // 執行撥號
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green, // 鮮豔綠
                            foregroundColor: Colors.white,
                            elevation: 5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          icon: const Icon(Icons.phone, size: 40),
                          label: Text(
                            '撥打',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0), // 溫馨米黃
      appBar: AppBar(
        title: Text(
          '找家人',
          style: GoogleFonts.notoSansTc(
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF333333),
        elevation: 0,
        toolbarHeight: 100, // 加大標題列
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. SOS 緊急求救按鈕
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 120, // 加高
                child: ElevatedButton.icon(
                  onPressed: () => _showCallConfirmation(
                    Contact(
                      name: '緊急求救',
                      relation: '119',
                      imageUrl: null, // SOS 沒有照片
                      phoneNumber: '119',
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 5,
                  ),
                  icon: const FaIcon(FontAwesomeIcons.truckMedical, size: 50),
                  label: Text(
                    'SOS 求救',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            // 2. 聯絡人網格
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // 兩欄
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.55, // 調整比例以容納超大字 (避免 Bottom Overflow)
                ),
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  return GestureDetector(
                    onTap: () => _showCallConfirmation(contact),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 真實照片 (大圓)
                          Container(
                            padding: const EdgeInsets.all(4), // 白邊
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.teal.withValues(
                                  alpha: 0.5,
                                ), // 青綠色
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 55,
                              backgroundColor: Colors.grey[200],
                              backgroundImage: contact.imageUrl != null
                                  ? NetworkImage(contact.imageUrl!)
                                  : null,
                              child: contact.imageUrl == null
                                  ? const FaIcon(
                                      FontAwesomeIcons.user,
                                      size: 50,
                                      color: Colors.grey,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 名字 (超大讓長輩看清楚)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              contact.name,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 64, // 64px 大字
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF333333),
                              ),
                            ),
                          ),
                          // 稱謂 (小一點但還是要大)
                          FittedBox(
                            // 防止爆版
                            fit: BoxFit.scaleDown,
                            child: Text(
                              contact.relation,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 48, // 48px
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 聯絡人資料模型
class Contact {
  final String name;
  final String relation;
  final String phoneNumber;
  final String? imageUrl; // 改用 Url

  Contact({
    required this.name,
    required this.relation,
    required this.phoneNumber,
    required this.imageUrl,
  });
}
