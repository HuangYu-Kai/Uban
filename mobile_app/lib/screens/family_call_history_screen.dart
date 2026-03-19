import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class FamilyCallHistoryScreen extends StatefulWidget {
  final String roomId;
  final String elderName;

  const FamilyCallHistoryScreen({
    super.key,
    required this.roomId,
    required this.elderName,
  });

  @override
  State<FamilyCallHistoryScreen> createState() => _FamilyCallHistoryScreenState();
}

class _FamilyCallHistoryScreenState extends State<FamilyCallHistoryScreen> {
  List<dynamic> _history = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final baseUrl = ApiService.baseUrl;
      final url = Uri.parse('$baseUrl/call_history?room_id=${widget.roomId}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          setState(() {
            _history = data['history'];
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = data['message'];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = '伺服器錯誤 (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '連線失敗: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F172A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '通訊紀錄 - ${widget.elderName}',
          style: GoogleFonts.notoSansTc(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF2563EB)),
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_error!, style: GoogleFonts.notoSansTc(color: Colors.redAccent)),
            TextButton(onPressed: _fetchHistory, child: const Text('重試')),
          ],
        ),
      );
    }

    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '尚無通訊紀錄',
              style: GoogleFonts.notoSansTc(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final record = _history[index];
        return _buildCallCard(record);
      },
    );
  }

  Widget _buildCallCard(Map<String, dynamic> record) {
    final status = record['status'] as String;
    final startTimeStr = record['start_time'] as String?;
    final endTimeStr = record['end_time'] as String?;
    
    DateTime? startTime;
    if (startTimeStr != null) startTime = DateTime.tryParse(startTimeStr)?.toLocal();
    
    IconData icon;
    Color color;
    String statusText;

    switch (status) {
      case 'connected':
      case 'ended':
        icon = Icons.call_made_rounded;
        color = Colors.green;
        statusText = '已接聽';
        break;
      case 'missed':
        icon = Icons.call_missed_rounded;
        color = Colors.orange;
        statusText = '未接聽';
        break;
      case 'rejected':
        icon = Icons.call_end_rounded;
        color = Colors.red;
        statusText = '已拒絕';
        break;
      default:
        icon = Icons.call_rounded;
        color = Colors.blue;
        statusText = '通話中';
    }

    String timeText = startTime != null ? DateFormat('MM/dd HH:mm').format(startTime) : '未知時間';
    
    // 計算時長
    String duration = '';
    if (startTimeStr != null && endTimeStr != null) {
      final start = DateTime.tryParse(startTimeStr);
      final end = DateTime.tryParse(endTimeStr);
      if (start != null && end != null) {
        final diff = end.difference(start);
        if (diff.inMinutes > 0) {
          duration = '${diff.inMinutes}分${diff.inSeconds % 60}秒';
        } else {
          duration = '${diff.inSeconds}秒';
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record['caller_name']} -> ${record['callee_name']}',
                  style: GoogleFonts.notoSansTc(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                Text(
                  '$statusText • $timeText',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 13,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (duration.isNotEmpty)
            Text(
              duration,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
