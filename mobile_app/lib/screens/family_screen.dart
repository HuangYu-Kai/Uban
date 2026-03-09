import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/signaling.dart';

class FamilyScreen extends StatefulWidget {
  final String roomId;
  const FamilyScreen({super.key, required this.roomId});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final Signaling _signaling = Signaling();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // 儲存線上的長輩設備列表
  List<dynamic> _onlineElders = [];
  // 是否正在觀看
  bool _isWatching = false;

  @override
  void initState() {
    super.initState();
    _remoteRenderer.initialize();

    _signaling.onAddRemoteStream = ((stream) {
      setState(() {
        _remoteRenderer.srcObject = stream;
        _isWatching = true; // 收到畫面，切換到觀看模式
      });
    });

    // 監聽後端傳來的設備列表
    _signaling.onUserListUpdate = (users) {
      setState(() {
        // 過濾出角色是 'elder' 的設備
        _onlineElders = users.where((u) => u['role'] == 'elder').toList();
      });
    };

    // 連線並告知我是 family
    _signaling.connect(widget.roomId, 'family');
  }

  @override
  void dispose() {
    _signaling.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isWatching ? '正在監控' : '選擇監控設備 (${widget.roomId})'),
        backgroundColor: Colors.green,
        leading: _isWatching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  // 簡單實作：退回列表需重連 (或是掛斷 peerConnection)
                  // 這裡為了穩定，直接讓使用者退回上一頁重選
                  Navigator.pop(context);
                },
              )
            : null,
      ),
      body: _isWatching ? _buildVideoView() : _buildDeviceList(),
    );
  }

  // 畫面 1: 設備列表
  Widget _buildDeviceList() {
    if (_onlineElders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("搜尋房間內的設備中..."),
            Text("請確認長輩端已開啟並進入同一房號"),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _onlineElders.length,
      itemBuilder: (context, index) {
        var device = _onlineElders[index];
        return Card(
          margin: const EdgeInsets.all(10),
          child: ListTile(
            leading: const Icon(
              Icons.camera_indoor,
              size: 40,
              color: Colors.orange,
            ),
            title: Text("長輩設備 ${index + 1}"),
            subtitle: Text("ID: ${device['id']}"),
            trailing: ElevatedButton(
              onPressed: () {
                // 點擊後發起監控
                _signaling.startMonitoring(device['id']);
              },
              child: const Text("連線"),
            ),
          ),
        );
      },
    );
  }

  // 畫面 2: 監控畫面
  Widget _buildVideoView() {
    return Container(color: Colors.black, child: RTCVideoView(_remoteRenderer));
  }
}
