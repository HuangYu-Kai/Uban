import 'dart:io';

void main() async {
  final dir = Directory('lib');
  final importStmt = "import 'package:flutter_application_1/utils/app_logger.dart';";
  
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart') && !entity.path.contains('app_logger.dart')) {
      String content = await entity.readAsString();
      if (!content.contains('print(')) continue;
      
      final newContent = content.replaceAll(RegExp(r'\bprint\('), 'appLogger.d(');
      
      String finalContent = newContent;
      if (!newContent.contains(importStmt)) {
        final lines = newContent.split('\n');
        int lastImportLine = -1;
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].startsWith('import ')) {
            lastImportLine = i;
          }
        }
        
        if (lastImportLine != -1) {
          lines.insert(lastImportLine + 1, importStmt);
        } else {
          lines.insert(0, importStmt);
        }
        finalContent = lines.join('\n');
      }
      
      await entity.writeAsString(finalContent);
      print('Updated ${entity.path}');
    }
  }
}
