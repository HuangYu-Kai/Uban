import 'package:flutter/material.dart';

class PetFoodItem {
  final int stepMilestone; // 1000, 2000, ... 8000
  final String id;
  final String name;
  final String emoji;
  final String subtitle;
  final String reactionQuote;
  final Color themeColor;
  final int vitalityGain;
  final int weightGainGrams; // ⚖️ 增重公克數
  final int intimacyGain;
  final String soundType; // crunch, sweet, chew, feast

  const PetFoodItem({
    required this.stepMilestone,
    required this.id,
    required this.name,
    required this.emoji,
    required this.subtitle,
    required this.reactionQuote,
    required this.themeColor,
    this.vitalityGain = 12,
    this.weightGainGrams = 50,
    this.intimacyGain = 6,
    this.soundType = 'crunch',
  });

  static const List<PetFoodItem> milestoneMenu = [
    PetFoodItem(
      stepMilestone: 1000,
      id: 'carrot',
      name: '鮮脆胡蘿蔔',
      emoji: '🥕',
      subtitle: '晨間爽脆開胃菜',
      reactionQuote: '咔滋咔滋！晨走 1,000 步好精神，小豬眼睛亮晶晶～🥕✨',
      themeColor: Color(0xFFF97316),
      vitalityGain: 10,
      weightGainGrams: 50,
      intimacyGain: 5,
      soundType: 'crunch',
    ),
    PetFoodItem(
      stepMilestone: 2000,
      id: 'apple',
      name: '蜜香紅蘋果',
      emoji: '🍎',
      subtitle: '富含維他命與活力',
      reactionQuote: '好甜好脆的蘋果！小豬臉頰紅通通，謝謝宇璿～🍎❤️',
      themeColor: Color(0xFFEF4444),
      vitalityGain: 12,
      weightGainGrams: 80,
      intimacyGain: 6,
      soundType: 'crunch',
    ),
    PetFoodItem(
      stepMilestone: 3000,
      id: 'banana',
      name: '元氣甜香蕉',
      emoji: '🍌',
      subtitle: '補充電解質防抽筋',
      reactionQuote: '香香甜甜的香蕉！補充滿滿體力，小豬又可以陪你走好遠～🍌🏃',
      themeColor: Color(0xFFFBBF24),
      vitalityGain: 15,
      weightGainGrams: 120,
      intimacyGain: 7,
      soundType: 'sweet',
    ),
    PetFoodItem(
      stepMilestone: 4000,
      id: 'corn',
      name: '香甜烤玉米',
      emoji: '🌽',
      subtitle: '金黃飽滿粗糧能量',
      reactionQuote: '粒粒飽滿的金黃玉米！小豬雙手捧著啃，好香好幸福～🌽😋',
      themeColor: Color(0xFFEAB308),
      vitalityGain: 18,
      weightGainGrams: 160,
      intimacyGain: 8,
      soundType: 'chew',
    ),
    PetFoodItem(
      stepMilestone: 5000,
      id: 'onigiri',
      name: '元氣海苔飯糰',
      emoji: '🍙',
      subtitle: '半數里程碑飽足補給',
      reactionQuote: '大口咬下海苔飯糰！已經走到 5,000 步了，太厲害啦～🍙🎉',
      themeColor: Color(0xFF10B981),
      vitalityGain: 20,
      weightGainGrams: 200,
      intimacyGain: 10,
      soundType: 'chew',
    ),
    PetFoodItem(
      stepMilestone: 6000,
      id: 'watermelon',
      name: '清甜大西瓜',
      emoji: '🍉',
      subtitle: '消暑解渴多汁享受',
      reactionQuote: '大口大口吃西瓜！滿滿清涼果汁，整隻小豬都消暑了～🍉💦',
      themeColor: Color(0xFFEC4899),
      vitalityGain: 22,
      weightGainGrams: 250,
      intimacyGain: 12,
      soundType: 'sweet',
    ),
    PetFoodItem(
      stepMilestone: 7000,
      id: 'cake',
      name: '草莓小蛋糕',
      emoji: '🍰',
      subtitle: '即將達標慶祝點心',
      reactionQuote: '綿密甜甜的草莓蛋糕！只差最後一哩路，小豬為你歡呼轉圈～🍰🎂',
      themeColor: Color(0xFFF43F5E),
      vitalityGain: 25,
      weightGainGrams: 300,
      intimacyGain: 15,
      soundType: 'sweet',
    ),
    PetFoodItem(
      stepMilestone: 8000,
      id: 'hotpot',
      name: '福氣金豬壽喜燒',
      emoji: '🍲',
      subtitle: '8,000步終極達標御膳',
      reactionQuote: '熱騰騰的大火鍋！今天 8,000 步完美達成，宇璿是超級健康之星 👑🍲🌟！',
      themeColor: Color(0xFF8B5CF6),
      vitalityGain: 35,
      weightGainGrams: 500,
      intimacyGain: 25,
      soundType: 'feast',
    ),
  ];
}
