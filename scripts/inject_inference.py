import os
import re

directory = "/Users/mey/BioGenesis-X/scripts"
files_to_modify = [
    "CinematicSequencer.gd",
    "ECGGraph.gd",
    "export_all_archetypes.gd",
    "FlightController.gd",
    "FlightHUDUI.gd"
]

pattern = re.compile(r'var\s+(\w+)\s*=\s*(?!$)')
replacement = r'var \1 := '

for filename in files_to_modify:
    filepath = os.path.join(directory, filename)
    if os.path.exists(filepath):
        with open(filepath, 'r') as file:
            content = file.read()
        
        new_content = pattern.sub(replacement, content)
        
        if content != new_content:
            with open(filepath, 'w') as file:
                file.write(new_content)
            print(f"Modified: {filename}")
        else:
            print(f"No changes needed: {filename}")
    else:
        print(f"File not found: {filename}")
