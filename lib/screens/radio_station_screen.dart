import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';

class RadioStationScreen extends StatefulWidget {
  const RadioStationScreen({super.key});

  @override
  State<RadioStationScreen> createState() => _RadioStationScreenState();
}

class _RadioStationScreenState extends State<RadioStationScreen> {
  final FlutterTts flutterTts = FlutterTts();

  // 頻道清單
  final List<String> channels = ['懷舊金曲', '農場話題', '養生保健', '以前的故事'];
  final List<dynamic> channelIcons = [
    FontAwesomeIcons.recordVinyl, // 懷舊金曲 (唱片/留聲機)
    Icons.local_florist, // 農場話題 (花草/種植)
    Icons.spa, // 養生保健 (身心靈/葉子)
    Icons.history_edu, // 以前的故事 (歷史/書寫)
  ];
  int _currentChannelIndex = 0;

  // 模擬語音留言
  List<Map<String, dynamic>> _voiceMessages = [];
  bool _isRecording = false;

  // 模擬後台 Log

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadChannelMessages(0); // 載入預設頻道訊息
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("zh-TW");
    await flutterTts.setSpeechRate(0.5);
  }

  // 切換頻道邏輯
  void _switchChannel(int index) {
    if (index == _currentChannelIndex) return;
    setState(() {
      _currentChannelIndex = index;
      _loadChannelMessages(index);
    });
    _addLog("頻道切換 -> ${channels[index]}");
  }

  void _loadChannelMessages(int index) {
    _voiceMessages.clear();
    // 根據頻道塞入假資料
    if (index == 2) {
      // 養生保健
      _voiceMessages.addAll([
        {
          'id': '1',
          'author': '李奶奶',
          'avatar': 'https://randomuser.me/api/portraits/women/60.jpg',
          'text': '最近天氣變冷，晚上睡覺腳都抽筋，不知道有沒有什麼好方法？',
          'isPlaying': true,
        },
      ]);
    } else {
      _voiceMessages.addAll([
        {
          'id': '101',
          'author': '王伯伯',
          'avatar': 'https://randomuser.me/api/portraits/men/55.jpg',
          'text': '大家早安啊！這個頻道真不錯。',
          'isPlaying': true,
        },
      ]);
    }

    // 模擬自動播放
    if (_voiceMessages.isNotEmpty) {
      _speak(_voiceMessages.first['text']);
    }
  }

  Future<void> _speak(String text) async {
    await flutterTts.stop();
    await flutterTts.speak(text);
  }

  void _addLog(String log) {
    debugPrint("[RadioLog] $log");
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
    });
    _addLog("系統狀態: 用戶開始錄音...");
  }

  void _stopRecording() {
    setState(() {
      _isRecording = false;
    });
    _addLog("系統狀態: 錄音結束，上傳中...");

    // 模擬 STT 與 AI 審查
    Future.delayed(const Duration(milliseconds: 1000), () {
      _addLog("AI 後台: STT 轉錄 -> '唉，最近膝蓋痠痛，不知道是不是要變天了。'");
      _addLog("AI 安全審查: 內容合規 (Safe)");

      // 5秒後模擬回應
      Future.delayed(const Duration(seconds: 4), () {
        _simulateResponse();
      });
    });
  }

  void _simulateResponse() {
    // 插入其他長輩回應
    setState(() {
      _voiceMessages.add({
        'id': '99',
        'author': '張阿姨',
        'avatar': 'https://randomuser.me/api/portraits/women/20.jpg',
        'text': '對啦，明天有寒流，要穿暖一點。',
        'isPlaying': false,
      });
    });
    _addLog("系統推播: 收到新留言 (張阿姨)");

    // 插入 AI 回應
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _voiceMessages.add({
          'id': '100',
          'author': '貼心小幫手',
          // 'isAi': true, // 可以加個 flag 區分樣式
          'avatar': null, // AI 用 icon 表示
          'text': '林爺爺，膝蓋痛可以用熱毛巾敷一下喔，氣象預報說明天會降溫 5 度。',
          'isPlaying': true,
        });
      });
      _addLog("AI 主動介入: 生成健康建議 (RAG: 關節保養)");
      _speak('林爺爺，膝蓋痛可以用熱毛巾敷一下喔，氣象預報說明天會降溫 5 度。');
    });
  }

  @override
  void dispose() {
    flutterTts.stop();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0E0E0), // 背景牆色
      appBar: AppBar(
        title: Text(
          '老友廣播站',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black54),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.85,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFD7CCC8), // 收音機外殼 - 淺木紋色
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: const Color(0xFF8D6E63),
              width: 8,
            ), // 深色邊框
            boxShadow: [
              const BoxShadow(
                color: Colors.black26,
                offset: Offset(0, 10),
                blurRadius: 20,
              ),
              const BoxShadow(
                color: Colors.white38,
                offset: Offset(0, 2),
                blurRadius: 2,
                spreadRadius: 1, // 頂部高光
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 16),
              // 1. 上方區塊：喇叭孔 + 顯示幕
              _buildTopSection(),

              const Spacer(),

              // 2. 中間區塊：實體頻道按鈕
              _buildChannelControlPanel(),

              const Spacer(),

              // 3. 下方區塊：麥克風
              _buildBottomControl(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // 上方區塊 (喇叭 + 螢幕)
  Widget _buildTopSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // 頂部裝飾線 (模擬舊式收音機散熱孔/喇叭)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              15,
              (index) => Container(
                width: 6,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF5D4037),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 液晶顯示幕 Container
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1B5E20), // 深綠色背光螢幕
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black54, width: 4),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  offset: Offset(2, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "FM 106.5",
                      style: GoogleFonts.notoSansTc(
                        color: Colors.white38,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red[900],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        "ON AIR",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 頻道名稱顯示
                Text(
                  channels[_currentChannelIndex],
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFC8E6C9), // 液晶字體顏色
                    shadows: [
                      const Shadow(color: Colors.greenAccent, blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // 正在播放的內容 (跑馬燈效果或是靜態文字)
                Text(
                  _voiceMessages.isNotEmpty
                      ? _voiceMessages.last['author']
                      : "訊號搜尋中...",
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 16),
                // 視覺化波形 (整合原本的 Visualizer)
                _buildDigitalVisualizer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 數位波形顯示
  Widget _buildDigitalVisualizer() {
    if (_voiceMessages.isEmpty) return const SizedBox(height: 60);
    bool isPlaying = _voiceMessages.last['isPlaying'] == true;

    return SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(20, (index) {
          return AnimatedContainer(
                duration: Duration(milliseconds: 100 + index * 50),
                width: 8,
                height: isPlaying
                    ? (index % 2 == 0 ? 40 : 25) + (index % 3) * 5.0
                    : 5,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              )
              .animate(
                onPlay: isPlaying ? (c) => c.repeat(reverse: true) : null,
              )
              .scaleY(
                begin: 0.5,
                end: 1.2,
                duration: 400.ms,
                curve: Curves.easeInOut,
              );
        }),
      ),
    );
  }

  // 中間區塊 (實體按鈕控制)
  Widget _buildChannelControlPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.4, // 方形大按鈕
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: channels.length,
            itemBuilder: (context, index) {
              return _buildTactileButton(index);
            },
          ),
        ],
      ),
    );
  }

  // 實體觸感按鈕 (Enhanced 3D UX)
  Widget _buildTactileButton(int index) {
    bool isSelected = index == _currentChannelIndex;
    return GestureDetector(
      onTap: () => _switchChannel(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: EdgeInsets.only(top: isSelected ? 6 : 0), // 按下時下沉更明顯
        decoration: BoxDecoration(
          color: const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.circular(16), // 圓角大一點，手感更好
          boxShadow: [
            if (!isSelected) ...[
              // 未按下：浮起效果 (Levitation)
              const BoxShadow(
                color: Colors.black26,
                offset: Offset(0, 8),
                blurRadius: 0,
              ), // 側面厚度
              const BoxShadow(
                color: Colors.black12,
                offset: Offset(0, 10),
                blurRadius: 10,
              ), // 投影
            ] else ...[
              // 按下：嵌入效果 (Inset)
              const BoxShadow(
                color: Colors.white,
                offset: Offset(0, 1),
                blurRadius: 0,
              ), // 邊緣高光
            ],
          ],
        ),
        child: Container(
          // 按鈕表面
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isSelected
                  ? [Colors.grey[400]!, Colors.grey[200]!] // 按下：較暗，內凹感
                  : [Colors.grey[100]!, Colors.grey[300]!], // 未按：亮面，凸起感
            ),
            border: Border.all(
              color: isSelected
                  ? Colors.black12
                  : Colors.white.withOpacity(0.8),
              width: 1.5,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 內部微凹槽 (增加層次)
              if (!isSelected)
                Positioned(
                  top: 2,
                  left: 2,
                  right: 2,
                  bottom: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0.5),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // LED 指示燈
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFF1744)
                          : Colors.grey[400],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: isSelected
                              ? Colors.redAccent.withOpacity(0.8)
                              : Colors.transparent,
                          blurRadius: isSelected ? 6 : 0,
                          spreadRadius: isSelected ? 2 : 0,
                        ),
                        if (!isSelected)
                          const BoxShadow(
                            color: Colors.black12,
                            offset: Offset(0, 1),
                            blurRadius: 0,
                          ), // 燈孔陰影
                      ],
                    ),
                  ),
                  // 頻道 Icon / Image
                  if (channelIcons[index] is IconData)
                    Icon(
                      channelIcons[index] as IconData,
                      color: isSelected
                          ? const Color(0xFF3E2723)
                          : Colors.grey[600],
                      size: 48,
                    )
                  else if (channelIcons[index] is String)
                    Image.asset(
                      channelIcons[index] as String,
                      width: 48,
                      height: 48,
                      color: isSelected
                          ? const Color(0xFF3E2723)
                          : Colors.grey[600],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 底部區塊 (硬體麥克風)
  Widget _buildBottomControl() {
    return Column(
      children: [
        Text(
          "按住通話鈕說話",
          style: GoogleFonts.notoSansTc(
            color: const Color(0xFF5D4037),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTapDown: (_) => _startRecording(),
          onTapUp: (_) => _stopRecording(),
          onTapCancel: () => _stopRecording(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: _isRecording ? 95 : 100,
            height: _isRecording ? 95 : 100,
            decoration: BoxDecoration(
              color: Colors.black87,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey[600]!, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black38,
                  offset: const Offset(0, 8),
                  blurRadius: 10,
                ),
              ],
              gradient: RadialGradient(
                colors: [Colors.grey[800]!, Colors.black],
                center: const Alignment(-0.3, -0.3),
              ),
            ),
            child: Icon(
              Icons.mic,
              color: _isRecording ? Colors.redAccent : Colors.grey[400],
              size: 40,
            ),
          ),
        ),
      ],
    );
  }
} // End of Class
