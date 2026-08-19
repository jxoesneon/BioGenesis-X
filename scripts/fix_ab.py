import re
import os

files = [
    "AsteroidField.gd",
    "BioAudioSynth.gd",
    "BioManager.gd",
    "BioPlasmaProjectile.gd",
    "BioSporeCloud.gd",
    "build_galaxy_map_scene.gd"
]

base_dir = "/Users/mey/BioGenesis-X/scripts/"
modified_files = []

for filename in files:
    filepath = os.path.join(base_dir, filename)
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            content = f.read()
        
        # Regex to find `var something = ` and replace with `var something := `
        # Negative lookahead (?!=) to ensure we don't match `==`
        # Also ensure we don't match if there's already `:` before `=`
        new_content = re.sub(r'var\s+([a-zA-Z0-9_]+)\s*=\s*(?!=)', r'var \1 := ', content)
        
        if new_content != content:
            with open(filepath, 'w') as f:
                f.write(new_content)
            modified_files.append(filename)

print("Modified files:", modified_files)
