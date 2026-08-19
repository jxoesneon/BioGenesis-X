import time
import sys

def verify():
    filepath = "/Users/mey/BioGenesis-X/scripts/BioManager.gd"
    for i in range(15):
        try:
            with open(filepath, 'r') as f:
                content = f.read()
                if 'class_name BioManager' in content and 'extends Resource' in content:
                    print("Verification passed.")
                    sys.exit(0)
        except FileNotFoundError:
            pass
        time.sleep(1)
    
    print("Verification failed.")
    sys.exit(1)

if __name__ == "__main__":
    verify()
