import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

class PedometerTestScreen extends StatefulWidget {
  const PedometerTestScreen({super.key});

  @override
  State<PedometerTestScreen> createState() => _PedometerTestScreenState();
}

class _PedometerTestScreenState extends State<PedometerTestScreen> {
  late Stream<StepCount> _stepCountStream;
  late Stream<PedestrianStatus> _pedestrianStatusStream;
  String _status = '未知';
  int _steps = 0;
  bool _isPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _initPedometer();
  }

  void _initPedometer() async {
    // 方案二：回歸最底層、保證相容的硬體感測器
    if (await Permission.activityRecognition.request().isGranted) {
      if (mounted) setState(() => _isPermissionGranted = true);
      
      _pedestrianStatusStream = Pedometer.pedestrianStatusStream;
      _pedestrianStatusStream.listen(onPedestrianStatusChanged).onError(onPedestrianStatusError);

      _stepCountStream = Pedometer.stepCountStream;
      _stepCountStream.listen(onStepCount).onError(onStepCountError);
    } else {
      if (mounted) {
        setState(() {
          _status = '權限遭拒';
        });
      }
    }
  }

  void onStepCount(StepCount event) {
    if (mounted) setState(() => _steps = event.steps);
  }

  void onPedestrianStatusChanged(PedestrianStatus event) {
    if (mounted) {
      setState(() {
        _status = event.status == 'walking' ? '行走中' : '靜止';
      });
    }
  }

  void onPedestrianStatusError(error) {
    if (mounted) setState(() => _status = '狀態讀取失敗');
  }

  void onStepCountError(error) {
    if (mounted) print('Pedometer step count error: $error');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('實體計步器沙盒 (平滑增強版)'),
        backgroundColor: Colors.teal,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('開機以來總步數 (硬體原生):', style: TextStyle(fontSize: 22)),
            const SizedBox(height: 10),
            // 加強 UI：平滑數字滾動特效以掩蓋硬體批次延遲
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: _steps),
              duration: const Duration(milliseconds: 1500),
              builder: (context, value, child) {
                return Text(
                  '$value',
                  style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.teal),
                );
              },
            ),
            const Divider(height: 50, thickness: 2, indent: 40, endIndent: 40),
            const Text('當前硬體動態:', style: TextStyle(fontSize: 22)),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
              child: Icon(
                _status == '行走中' ? Icons.directions_run : (_status == '靜止' ? Icons.accessibility_new : Icons.error),
                key: ValueKey<String>(_status),
                size: 100,
                color: _status == '行走中' ? Colors.green : Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _status,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: _status == '行走中' ? Colors.green : Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 30),
            if (!_isPermissionGranted)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('此功能依賴硬體步數感測器，請務必授予活動追蹤權限以啟動沙盒。', style: TextStyle(color: Colors.red)),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                '💡 UI 動畫增強：因應 Android 作業系統省電模組，硬體感測器會刻意產生 10 秒左右的批次延遲。\n此介面特別加入了「平滑過渡滾動動畫」，讓 10 秒一次暴增的步數能滑順賞心悅目地滾動完畢。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
