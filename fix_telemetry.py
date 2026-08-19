import os

filepath = "/Users/mey/BioGenesis-X/scripts/verify_three_singletons.gd"

if os.path.exists(filepath):
    with open(filepath, "r") as f:
        content = f.read()

    content = content.replace('get_node("/root/OrganTelemetry")', 'load("res://resources/OrganTelemetry.tres")')

    with open(filepath, "w") as f:
        f.write(content)
    print("Replaced successfully.")
else:
    print(f"File not found: {filepath}")
