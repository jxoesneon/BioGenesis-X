import os
import re

files = [
    "SpacePlasmaField.gd",
    "ShipBuilderUI.gd",
    "verify_three_singletons.gd",
    "build_galaxy_map_scene.gd",
    "playtest_cinematics.gd"
]

base_dir = "/Users/mey/BioGenesis-X/scripts"
modified_files = []

for f in files:
    path = os.path.join(base_dir, f)
    if not os.path.exists(path):
        continue
        
    with open(path, 'r') as file:
        lines = file.readlines()
        
    changed = False
    new_lines = []
    for line in lines:
        new_line = re.sub(r'(\bvar\s+[a-zA-Z_][a-zA-Z0-9_]*\s*)(?<![:+\-*/%<>!])=(?!=)', r'\1:=', line)
        if new_line != line:
            changed = True
            line = new_line
        new_lines.append(line)
        
    if changed:
        with open(path, 'w') as file:
            file.writelines(new_lines)
        modified_files.append(f)

print("MODIFIED:", ",".join(modified_files))
