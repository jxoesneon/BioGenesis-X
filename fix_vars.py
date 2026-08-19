import os
import re

script_dir = '/Users/mey/BioGenesis-X/scripts/'

# Regex to match `var name = value` but not `var name := value` or `var name: type = value`
# It matches 'var', whitespace, identifier, whitespace, '=', whitespace
pattern = re.compile(r'^(?P<indent>\s*)var\s+(?P<var_name>[a-zA-Z0-9_]+)\s*=\s*(?P<val>.*)$')

modified_files = []

for root, _, files in os.walk(script_dir):
    for filename in files:
        if filename.endswith('.gd'):
            file_path = os.path.join(root, filename)
            with open(file_path, 'r', encoding='utf-8') as f:
                lines = f.readlines()
            
            modified = False
            for i in range(len(lines)):
                line = lines[i]
                match = pattern.match(line)
                if match:
                    new_line = f"{match.group('indent')}var {match.group('var_name')} := {match.group('val')}\n"
                    lines[i] = new_line
                    modified = True
            
            if modified:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.writelines(lines)
                modified_files.append(filename)

print("Modified files:")
for f in modified_files:
    print(f)
