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
    
    out = ''
    i = 0
    changed = False
    
    while i < len(content):
        match = re.search(r'\bprint\(', content[i:])
        if not match:
            out += content[i:]
            break
        
        idx = i + match.start()
        
        out += content[i:idx]
        out += 'appLogger.d('
        
        # find matching paren
        p_count = 1
        j = idx + len('print(')
        start_val = j
        while j < len(content) and p_count > 0:
            if content[j] == '(':
                p_count += 1
            elif content[j] == ')':
                p_count -= 1
            elif content[j] == "'" or content[j] == '"':
                quote = content[j]
                j += 1
                while j < len(content):
                    if content[j] == '\\':
                        j += 2
                        continue
                    if content[j] == quote:
                        break
                    j += 1
            j += 1
        
        val = content[start_val:j-1]
        out += val + ')'
        i = j
        changed = True

    if changed:
        out = insert_import(out)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(out)
        print('Updated', filepath)

for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            replace_in_file(os.path.join(root, file))
