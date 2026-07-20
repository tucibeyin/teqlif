import os
import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find all ScaffoldMessenger.of(context).showSnackBar(
    # We will look for "ScaffoldMessenger.of(context).showSnackBar("
    # or "ScaffoldMessenger.of(context)\n...showSnackBar(" etc
    # We can use a simpler approach: 
    # Just look for the substring ScaffoldMessenger.of
    import sys
    
    out = []
    i = 0
    changed = False
    
    while i < len(content):
        # find the next occurrence
        idx = content.find('ScaffoldMessenger.of(', i)
        if idx == -1:
            out.append(content[i:])
            break
            
        out.append(content[i:idx])
        
        # We found ScaffoldMessenger.of(
        # We need to parse until the end of the showSnackBar call.
        
        # Let's see if this chain calls showSnackBar
        # It could be ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))
        # Or messenger.showSnackBar(...)
        
        # We will do a simple regex for the common case:
        # ScaffoldMessenger.of(context).showSnackBar(\s*SnackBar\s*\(\s*content:\s*Text\((.*?)\)(?:[^)]*)\)\s*\)
        # Actually this is hard to parse correctly.
        
        # Let's just output it as is for now and advance i
        out.append('ScaffoldMessenger.of(')
        i = idx + len('ScaffoldMessenger.of(')

    # We didn't do replacements. Let's write a better parser.
    pass

def simple_regex_replace(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original = content
    
    # 1. Replace showErrorSnackbar(context, e) with TeqSnackBar... wait, error_helper already updated.
    
    # 2. Find instances of ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(X)))
    # We will use regex to find:
    # ScaffoldMessenger\.of\([^)]+\)\.showSnackBar\(\s*SnackBar\(\s*content:\s*Text\(([^)]+)\)[^;]*\)\s*\)
    # This might miss some nested parentheses inside Text().
    # But it covers many simple ones.
    
    pattern = re.compile(r'ScaffoldMessenger\.of\(([^)]+)\)\.showSnackBar\(\s*SnackBar\(\s*content:\s*Text\(((?:[^)(]+|\([^)(]*\))*)\)[^\)]*\)\s*\)?(,?)\s*\)?(;)?:?', re.DOTALL)
    
    def replacer(match):
        ctx = match.group(1).strip()
        text_content = match.group(2).strip()
        # if text_content contains AppLocalizations... it's a message
        # Let's replace with TeqSnackBar.show(ctx, message: text_content, type: TeqSnackBarType.info)
        # Wait, if we use snackbar_helper, we need to import it.
        # But we can just use TeqSnackBar.show directly if we import teq_snackbar.dart
        res = f"TeqSnackBar.show({ctx}, message: {text_content}, type: TeqSnackBarType.info)"
        
        # Keep trailing semi-colon if it existed
        if match.group(4) == ';':
            res += ';'
            
        return res
        
    new_content = pattern.sub(replacer, content)
    
    if new_content != original:
        # Add import if missing
        if 'teq_snackbar.dart' not in new_content:
            # find first import
            import_idx = new_content.find("import '")
            if import_idx != -1:
                # Need relative path to teq_snackbar
                # We can cheat by using package:teqlif/ui_library/... but flutter doesn't always like package imports mixed.
                # Let's count depth
                depth = filepath.count('/') - 1 # since filepath is mobile/lib/screens/...
                # actually filepath starts with lib/...
                depth = filepath.count('/') - 1
                prefix = '../' * depth
                if depth == 0: prefix = './'
                import_stmt = f"import '{prefix}ui_library/components/overlays/teq_snackbar.dart';\n"
                new_content = new_content[:import_idx] + import_stmt + new_content[import_idx:]
                
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated {filepath}")

import glob
for root, _, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            simple_regex_replace(os.path.join(root, f))
