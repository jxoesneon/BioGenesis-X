import time
import sys

filepath = "/Users/mey/BioGenesis-X/scripts/verify_three_singletons.gd"

print("Waiting 5 seconds...")
time.sleep(5)

try:
    with open(filepath, "r") as f:
        content = f.read()
    
    new_content = content.replace('get_node("/root/BioManager")', 'load("res://resources/BioManager.tres")')
    
    with open(filepath, "w") as f:
        f.write(new_content)
    print("Done replacing.")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
