import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Test icon render', (tester) async {
    final matFile = File(r'C:\Users\OuO\.vscode\extensions\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf');
    print('matFile exists: ${matFile.existsSync()}');
    if (matFile.existsSync()) {
      final bytes = matFile.readAsBytesSync();
      final loader = FontLoader('MaterialIcons');
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      print('MaterialIcons loaded successfully!');
    }

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Container(
              color: Colors.white,
              child: const Row(
                children: [
                  Icon(Icons.play_arrow, size: 48, color: Colors.blue),
                  Icon(Icons.pause, size: 48, color: Colors.red),
                  Icon(Icons.skip_next, size: 48, color: Colors.green),
                  Text('測試文字 123', style: TextStyle(fontSize: 24, color: Colors.black)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('E:\\114Project\\test_icon_out.png');
    await file.writeAsBytes(byteData!.buffer.asUint8List());
    print('Wrote test_icon_out.png: ${file.lengthSync()} bytes');
  });
}
