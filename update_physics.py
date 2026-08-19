#!/usr/bin/env python3
"""
update_physics.py - AAA+ Physics Configuration Script for BioGenesis-X

Configures and enforces AAA+ Godot Jolt physics engine parameters in project.godot:
- 3d/physics_engine="JoltPhysics3D"
- common/physics_interpolation=true
- common/physics_ticks_per_second=60
- common/max_physics_steps_per_frame=8
- 3d/solver/solver_iterations=16
- 3d/default_gravity=0.0
- 3d/default_gravity_vector=Vector3(0, 0, 0)
- 3d/default_linear_damp=0.0
- 3d/default_angular_damp=0.0
"""

import os
import sys

PHYSICS_SETTINGS = {
    "3d/physics_engine": '"JoltPhysics3D"',
    "common/physics_interpolation": "true",
    "common/physics_ticks_per_second": "60",
    "common/max_physics_steps_per_frame": "8",
    "3d/solver/solver_iterations": "16",
    "3d/default_gravity": "0.0",
    "3d/default_gravity_vector": "Vector3(0, 0, 0)",
    "3d/default_linear_damp": "0.0",
    "3d/default_angular_damp": "0.0",
}

def update_physics_settings(project_file: str) -> bool:
    if not os.path.exists(project_file):
        print(f"Error: Project file not found at {project_file}")
        return False

    with open(project_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    new_lines = []
    in_physics_section = False
    physics_section_found = False
    handled_keys = set()

    for line in lines:
        stripped = line.strip()

        # Check for section header
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_physics_section:
                # Add any missing physics settings before leaving the physics section
                for key, val in PHYSICS_SETTINGS.items():
                    if key not in handled_keys:
                        new_lines.append(f"{key}={val}\n")
                        handled_keys.add(key)
                in_physics_section = False

            if stripped == "[physics]":
                in_physics_section = True
                physics_section_found = True

            new_lines.append(line)
            continue

        if in_physics_section:
            # Check if this line is setting a physics key
            key_matched = False
            for key, val in PHYSICS_SETTINGS.items():
                if stripped.startswith(f"{key}=") or stripped == key:
                    new_lines.append(f"{key}={val}\n")
                    handled_keys.add(key)
                    key_matched = True
                    break

            if not key_matched:
                new_lines.append(line)
        else:
            new_lines.append(line)

    # If EOF was reached while still in physics section
    if in_physics_section:
        for key, val in PHYSICS_SETTINGS.items():
            if key not in handled_keys:
                new_lines.append(f"{key}={val}\n")
                handled_keys.add(key)

    # If physics section was not found at all
    if not physics_section_found:
        if new_lines and not new_lines[-1].endswith("\n"):
            new_lines.append("\n")
        new_lines.append("\n[physics]\n\n")
        for key, val in PHYSICS_SETTINGS.items():
            new_lines.append(f"{key}={val}\n")
            handled_keys.add(key)

    with open(project_file, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    print(f"Successfully configured AAA+ physics settings in {project_file}:")
    for key, val in PHYSICS_SETTINGS.items():
        print(f"  - {key} = {val}")

    return True

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_file = os.path.join(script_dir, "project.godot")
    if not os.path.exists(project_file):
        project_file = "/Users/mey/BioGenesis-X/project.godot"

    success = update_physics_settings(project_file)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
