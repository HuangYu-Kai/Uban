import os, re

IMPORT_STMT = "import 'package:flutter_application_1/utils/app_logger.dart';"

def insert_import(content):
    if IMPORT_STMT in content:
        return content
    # Find the last import
    imports = list(re.finditer(r'^import\s+[\'"].*?[\'"];\n?', content, flags=re.MULTILINE))
    if imports:
        last_import = imports[-1]
        insert_pos = last_import.end()
        return content[:insert_pos] + IMPORT_STMT + '\n' + content[insert_pos:]
    else:
        # no imports, put at top
        return IMPORT_STMT + '\n\n' + content

def replace_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # simplest replacement
    new_content = re.sub(r'\bprint\(', 'appLogger.d(', content)
    
    if new_content != content:
        new_content = insert_import(new_content)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print('Updated', filepath)

for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart') and not root.endswith('utils'):
            replace_in_file(os.path.join(root, file))

# Wait, performance_optimizer.dart is in lib/utils so I should allow lib/utils too.
replace_in_file('lib/utils/performance_optimizer.dart')
# I'll just run on all, but skip app_logger.dart
