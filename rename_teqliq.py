import os
import re

def replace_in_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        return

    pattern = re.compile(r'teqliq(?!beyin)', re.IGNORECASE)
    new_content = pattern.sub('teqliq', content)
    
    # Check for teqliq as well, in case there was a typo earlier
    pattern2 = re.compile(r'teqliq', re.IGNORECASE)
    new_content = pattern2.sub('teqliq', new_content)

    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated content in {filepath}")

def main():
    root_dir = '/Users/tucibeyin/Desktop/teqlif'
    exclude_dirs = {'.git', 'node_modules', 'build', '.dart_tool', '.idea', '__pycache__', 'ios', 'android', 'linux', 'macos', 'windows', 'web'}
    
    # First, rename files
    files_to_rename = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs]
        for filename in filenames:
            if ('teqliq' in filename.lower() and 'tucibeyin' not in filename.lower()) or ('teqliq' in filename.lower()):
                files_to_rename.append(os.path.join(dirpath, filename))
                
    for filepath in files_to_rename:
        dirpath = os.path.dirname(filepath)
        filename = os.path.basename(filepath)
        
        new_filename = re.sub(r'teqliq(?!beyin)', 'teqliq', filename, flags=re.IGNORECASE)
        new_filename = re.sub(r'teqliq', 'teqliq', new_filename, flags=re.IGNORECASE)
        
        new_filepath = os.path.join(dirpath, new_filename)
        os.rename(filepath, new_filepath)
        print(f"Renamed {filepath} to {new_filepath}")

    # Now replace contents
    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in exclude_dirs]
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            replace_in_file(filepath)

if __name__ == "__main__":
    main()
