import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/family_member.dart';
import '../../models/care_task.dart';
import '../../services/contribution_service.dart';
import '../../services/task_board_service.dart';
import '../../services/elder_manager.dart';

/// 👨‍👩‍👧‍👦 家庭協作中心
/// 
/// 多人照護協調系統
/// 顯示家庭成員貢獻值和任務分配
class FamilyCollaborationScreen extends StatefulWidget {
  final String elderName;
  final int? elderId;

  const FamilyCollaborationScreen({
    super.key,
    required this.elderName,
    this.elderId,
  });

  @override
  State<FamilyCollaborationScreen> createState() => _FamilyCollaborationScreenState();
}

class _OldFamilyMember {
  final String id;
  final String name;
  final String role;
  final String avatarUrl;
  final double contributionScore; // 0-100
  final Map<String, int> activities; // 活動統計

  _OldFamilyMember({
    required this.id,
    required this.name,
    required this.role,
    required this.avatarUrl,
    required this.contributionScore,
    required this.activities,
  });

  Color get contributionColor {
    if (contributionScore >= 80) return const Color(0xFF10B981);
    if (contributionScore >= 50) return const Color(0xFF3B82F6);
    return const Color(0xFFF59E0B);
  }
}

class _OldCareTask {
  final String id;
  final String title;
  final String description;
  final String? assignedTo;
  final DateTime dueDate;
  final String priority;
  final bool isCompleted;

  _OldCareTask({
    required this.id,
    required this.title,
    required this.description,
    this.assignedTo,
    required this.dueDate,
    required this.priority,
    this.isCompleted = false,
  });

  Color get priorityColor {
    switch (priority) {
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF3B82F6);
    }
  }

  String get priorityLabel {
    switch (priority) {
      case 'high':
        return '重要';
      case 'medium':
        return '普通';
      default:
        return '一般';
    }
  }
}

class _FamilyCollaborationScreenState extends State<FamilyCollaborationScreen> {
  final ElderManager _elderManager = ElderManager();
  final _contributionService = ContributionService();
  final _taskBoardService = TaskBoardService();
  
  List<FamilyMember> _familyMembers = [];
  List<CareTask> _tasks = [];
  bool _isLoading = true;
  String _currentUserId = 'user1'; // TODO: 從認證服務獲取
  
  // 從 ElderManager 取得真實資料
  String get _displayElderName => _elderManager.currentElder?.displayName ?? widget.elderName;
  int? get _displayElderId => _elderManager.currentElder?.id ?? widget.elderId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // 加載家庭成員和任務
      final members = await _contributionService.getAllMembers();
      final tasks = await _taskBoardService.getAllTasks(
        elderId: widget.elderId,
      );
      
      // 觸發 AI 任務生成（如果需要）
      if (tasks.isEmpty && widget.elderId != null) {
        await _generateAiTasks();
      }
      
      setState(() {
        _familyMembers = members;
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateAiTasks() async {
    // 模擬健康數據
    final healthData = {
      'callsThisWeek': 2,
      'medicationDaysLeft': 5,
      'dailySteps': 1800,
      'daysSinceLastCheckup': 95,
    };
    
    await _taskBoardService.generateAiTasks(
      widget.elderId ?? 1,
      healthData,
    );
  }

  Future<void> _claimTask(CareTask task) async {
    HapticFeedback.mediumImpact();
    
    try {
      final member = _familyMembers.firstWhere((m) => m.id == _currentUserId);
      
      await _taskBoardService.claimTask(
        task.id,
        _currentUserId,
        member.name,
      );
      
      // 記錄貢獻
      await _contributionService.recordContribution(
        userId: _currentUserId,
        type: ContributionType.taskCompleted,
      );
      
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已認領任務：${task.title}'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('認領失敗，請重試')),
        );
      }
    }
  }

  Future<void> _completeTask(CareTask task) async {
    HapticFeedback.mediumImpact();
    
    try {
      await _taskBoardService.completeTask(task.id);
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已完成任務：${task.title} 🎉'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失敗，請重試')),
        );
      }
    }
  }

  List<_OldFamilyMember> _generateMockMembers() {
    return [
      _OldFamilyMember(
        id: '1',
        name: '王小明',
        role: '長子',
        avatarUrl: '',
        contributionScore: 85,
        activities: {'通話': 12, '視訊': 8, '任務': 5, '問候': 15},
      ),
      _OldFamilyMember(
        id: '2',
        name: '王小華',
        role: '次女',
        avatarUrl: '',
        contributionScore: 72,
        activities: {'通話': 8, '視訊': 6, '任務': 4, '問候': 10},
      ),
      _OldFamilyMember(
        id: '3',
        name: '陳看護',
        role: '看護',
        avatarUrl: '',
        contributionScore: 92,
        activities: {'通話': 5, '視訊': 3, '任務': 12, '問候': 20},
      ),
      _OldFamilyMember(
        id: '4',
        name: '王小美',
        role: '三女',
        avatarUrl: '',
        contributionScore: 45,
        activities: {'通話': 3, '視訊': 2, '任務': 1, '問候': 5},
      ),
    ];
  }

  List<_OldCareTask> _generateMockTasks() {
    final now = DateTime.now();
    return [
      _OldCareTask(
        id: '1',
        title: '週二陪診',
        description: '陪同前往台大醫院骨科門診',
        dueDate: now.add(const Duration(days: 2)),
        priority: 'high',
      ),
      _OldCareTask(
        id: '2',
        title: '藥物補充',
        description: '高血壓藥物即將用完，需要購買',
        assignedTo: '王小華',
        dueDate: now.add(const Duration(days: 3)),
        priority: 'medium',
      ),
      _OldCareTask(
        id: '3',
        title: '本週通話',
        description: '本週通話次數不足，建議增加關心',
        dueDate: now.add(const Duration(days: 1)),
        priority: 'low',
      ),
      _OldCareTask(
        id: '4',
        title: '生日禮物準備',
        description: '下月生日，需要準備禮物和慶祝',
        dueDate: now.add(const Duration(days: 25)),
        priority: 'medium',
      ),
    ];
  }

  void _oldClaimTask(_OldCareTask task) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已認領任務：${task.title}'),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    // TODO: 實際認領任務 API
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false, // 移除自動返回按鈕
        title: Text(
          '家庭協作中心',
          style: GoogleFonts.notoSansTc(
            color: const Color(0xFF1E293B),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // 本週照護報告
                    _buildWeeklyReport(),
                    
                    // 家庭成員貢獻地圖
                    _buildMembersGrid(),
                    
                    // 任務看板
                    _buildTaskBoard(),
                    
                    // 家庭動態牆
                    _buildActivityWall(),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildWeeklyReport() {
    final totalContribution = _familyMembers.fold(0.0, (sum, m) => sum + m.contributionScore);
    final avgContribution = totalContribution / _familyMembers.length;
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF8B5CF6),
            const Color(0xFF6366F1),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.people_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本週照護報告',
                      style: GoogleFonts.notoSansTc(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '家庭成員協作概況',
                      style: GoogleFonts.notoSansTc(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildReportItem('參與成員', '${_familyMembers.length}', '人'),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _buildReportItem('平均貢獻', '${avgContribution.toInt()}', '%'),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              Expanded(
                child: _buildReportItem('待完成', '${_tasks.where((t) => !t.isCompleted).length}', '項'),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildReportItem(String label, String value, String unit) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: GoogleFonts.notoSansTc(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                unit,
                style: GoogleFonts.notoSansTc(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMembersGrid() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '家庭成員貢獻',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.65,
            ),
            itemCount: _familyMembers.length,
            itemBuilder: (context, index) {
              final member = _familyMembers[index];
              return _buildMemberCard(member, index);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(FamilyMember member, int index) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 頭像 + 環形進度條
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 環形進度條
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: member.contributionScore / 100,
                    strokeWidth: 6,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation(member.contributionColor),
                  ),
                ),
                // 頭像
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: member.contributionColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      member.name.substring(0, 1),
                      style: GoogleFonts.notoSansTc(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: member.contributionColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ).animate(delay: (index * 100).ms)
            .fadeIn(duration: 400.ms)
            .scale(begin: const Offset(0.8, 0.8)),
          
          const SizedBox(height: 12),
          
          // 名字
          Text(
            member.name,
            style: GoogleFonts.notoSansTc(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          // 角色
          Text(
            member.role,
            style: GoogleFonts.notoSansTc(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 8),
          
          // 貢獻值
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: member.contributionColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${member.contributionScore.toInt()}% 貢獻',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: member.contributionColor,
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // 活動統計 - 改用 Column 避免 overflow
          if (member.activities.isNotEmpty)
            ...member.activities.entries.take(2).map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    '${entry.key} ${entry.value}',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildTaskBoard() {
    final unassignedTasks = _tasks.where((t) => t.assignedTo == null && !t.isCompleted).toList();
    
    if (unassignedTasks.isEmpty) {
      return const SizedBox();
    }
    
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '待認領任務',
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
          ...unassignedTasks.map((task) => _buildTaskCard(task)),
        ],
      ),
    );
  }

  Widget _buildTaskCard(CareTask task) {
    final daysUntilDue = task.dueDate.difference(DateTime.now()).inDays;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: task.priorityColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.priorityLabel,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: task.priorityColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            task.description,
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.access_time_rounded,
                    size: 14,
                    color: daysUntilDue <= 2 ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    daysUntilDue == 0 ? '今天' : daysUntilDue == 1 ? '明天' : '$daysUntilDue 天後',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: daysUntilDue <= 2 ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => _claimTask(task),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '認領任務',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1, end: 0);
  }

  Widget _buildActivityWall() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '家庭動態牆',
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          _buildActivityItem('王小明', '完成了視訊通話', '30 分鐘前', Icons.videocam, const Color(0xFF3B82F6)),
          _buildActivityItem('陳看護', '測量了血壓和心率', '2 小時前', Icons.favorite, const Color(0xFFEF4444)),
          _buildActivityItem('王小華', '認領了藥物補充任務', '5 小時前', Icons.task_alt, const Color(0xFF10B981)),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }

  Widget _buildActivityItem(String name, String action, String time, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B),
                    ),
                    children: [
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: ' $action'),
                    ],
                  ),
                ),
                Text(
                  time,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
