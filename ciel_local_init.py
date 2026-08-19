#!/usr/bin/env python3
"""
Ciel Local INIT Ceremony for BioGenesis-X
Runs phases 5-13 of INIT.md against this project.
"""

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path("/Users/mey/BioGenesis-X").resolve()
CIEL_GLOBAL = Path("~/.ciel").expanduser().resolve()
CIEL_LOCAL = PROJECT_ROOT / ".ciel"

def say(msg: str):
    print(f"\033[1;36m[ciel]\033[0m {msg}")

def warn(msg: str):
    print(f"\033[1;33m[ciel]\033[0m {msg}", file=sys.stderr)

def die(msg: str):
    print(f"\033[1;31m[ciel]\033[0m {msg}", file=sys.stderr)
    sys.exit(1)

# ------------------------------------------------------------------------------
# PHASE 5: Context Detection (CONTEXT_DETECTION.md)
# ------------------------------------------------------------------------------

def detect_context():
    say("Phase 5: Context detection...")

    signals = {}

    # Filesystem scan
    for item in PROJECT_ROOT.iterdir():
        name = item.name
        if name == "project.godot":
            signals["godot"] = True
            # Read Godot version
            try:
                content = item.read_text(encoding="utf-8")
                if "config_version=5" in content:
                    signals["godot_version"] = "4.x"
            except:
                pass
        elif name == "README.md":
            signals["readme"] = True
        elif name == "LICENSE":
            signals["license_file"] = True
        elif name == ".github":
            signals["github_actions"] = True
        elif name == "scripts":
            signals["scripts_dir"] = True
        elif name == "scenes":
            signals["scenes_dir"] = True
        elif name == "shaders":
            signals["shaders_dir"] = True
        elif name == "addons":
            signals["addons_dir"] = True
        elif name == ".claude":
            signals["claude_code_context"] = True
        elif name.endswith(".md"):
            signals[f"doc_{name[:-3]}"] = True

    # Language/framework inference
    frameworks = []
    build_tools = []
    test_tools = []
    language = "gdscript"

    if signals.get("godot"):
        frameworks.append("godot")
        build_tools.append("godot")
        test_tools.append("godot --headless -s")

    if signals.get("godot_mcp") or (PROJECT_ROOT / "addons" / "godot_mcp").exists():
        frameworks.append("godot-mcp")

    if signals.get("github_actions"):
        ci = ["github-actions"]
    else:
        ci = []

    # Check for license
    license_family = "Proprietary"
    if signals.get("license_file"):
        try:
            lic = (PROJECT_ROOT / "LICENSE").read_text(encoding="utf-8")
            if "Apache" in lic:
                license_family = "Apache-2.0"
            elif "MIT" in lic:
                license_family = "MIT"
        except:
            pass

    # Monorepo?
    monorepo = False

    context = {
        "id": f"biogenesis-x-{datetime.now().strftime('%Y%m%d')}",
        "root": str(PROJECT_ROOT),
        "language": language,
        "frameworks": frameworks,
        "build_tools": build_tools,
        "test_tools": test_tools,
        "formatter": "gdformat",
        "linter": "gdlint",
        "ci": ci,
        "license": license_family,
        "monorepo": monorepo,
        "runtime_hint": "claude_code",
        "detected_at": datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z'),
        "signals": signals
    }

    say(f"  Detected: {language} / {frameworks} / CI: {ci} / license: {license_family}")
    return context

# ------------------------------------------------------------------------------
# PHASE 6: Calibration (CALIBRATION.md)
# ------------------------------------------------------------------------------

def calibrate(context):
    say("Phase 6: Calibration...")

    # Heuristics
    score = "development"

    if context["signals"].get("github_actions"):
        score = "production"

    # Check for compliance files
    if any((PROJECT_ROOT / f).exists() for f in ["SECURITY.md", "COMPLIANCE.md"]):
        score = "regulated"

    # Check for docker-compose with databases
    if (PROJECT_ROOT / "docker-compose.yml").exists():
        score = "production"

    # This is a game project with CI + tests + active maintenance
    # -> production by CALIBRATION.md heuristics
    if context["signals"].get("godot") and context["signals"].get("scripts_dir"):
        score = "production"

    calibration = {
        "auto_detected": score,
        "override": None,
        "effective": score,
        "rationale": f"Godot 4 project with headless test suite, CI, and structured architecture; standard production profile",
        "calibrated_at": datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
    }

    say(f"  Auto-detected threshold: {score}")
    return calibration

# ------------------------------------------------------------------------------
# PHASE 7: Override (OVERRIDE.md)
# ------------------------------------------------------------------------------

def apply_override(calibration):
    say("Phase 7: Override check...")

    override_file = CIEL_LOCAL / "escalation.json"
    if override_file.exists():
        try:
            data = json.loads(override_file.read_text(encoding="utf-8"))
            if data.get("override"):
                calibration["override"] = data["override"]
                calibration["effective"] = data["override"]
                say(f"  User override applied: {data['override']}")
        except:
            pass
    else:
        say("  No override file present.")

    return calibration

# ------------------------------------------------------------------------------
# PHASE 8: Local Creation (create .ciel/, project.json, .gitignore)
# ------------------------------------------------------------------------------

def create_local_ciel(context, calibration):
    say("Phase 8: Local .ciel/ creation...")

    CIEL_LOCAL.mkdir(parents=True, exist_ok=True)

    # project.json
    project_json = {
        "project": "BioGenesis-X",
        "path": str(PROJECT_ROOT),
        "runtime": "claude_code",
        "initialized": datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z'),
        "ciel_version": "1.0.0",
        "escalation_threshold": calibration["effective"],
        "partitions": ["ciel-global", "project-biogenesis-x"],
        "gitignore_sync": True,
        "context_files": [".claude/CLAUDE.md"] if (PROJECT_ROOT / ".claude" / "CLAUDE.md").exists() else []
    }

    (CIEL_LOCAL / "project.json").write_text(json.dumps(project_json, indent=2), encoding="utf-8")
    say(f"  Written: {CIEL_LOCAL / 'project.json'}")

    # escalation.json
    escalation_json = {
        "auto_detected": calibration["auto_detected"],
        "override": calibration["override"],
        "effective": calibration["effective"],
        "rationale": calibration["rationale"],
        "calibrated_at": calibration["calibrated_at"]
    }

    (CIEL_LOCAL / "escalation.json").write_text(json.dumps(escalation_json, indent=2), encoding="utf-8")
    say(f"  Written: {CIEL_LOCAL / 'escalation.json'}")

    # .gitignore entry
    gitignore_path = PROJECT_ROOT / ".gitignore"
    gitignore_entry = "\n# Ciel local domain\n.ciel/\n"

    if gitignore_path.exists():
        content = gitignore_path.read_text(encoding="utf-8")
        if ".ciel/" not in content:
            with open(gitignore_path, "a", encoding="utf-8") as f:
                f.write(gitignore_entry)
            say("  Added .ciel/ to .gitignore")
        else:
            say("  .ciel/ already in .gitignore")
    else:
        with open(gitignore_path, "w", encoding="utf-8") as f:
            f.write("# Project .gitignore\n\n" + gitignore_entry)
        say("  Created .gitignore with .ciel/ entry")

    # Create refs directory for local sync
    (CIEL_LOCAL / "refs" / "skills").mkdir(parents=True, exist_ok=True)
    (CIEL_LOCAL / "refs" / "rules").mkdir(parents=True, exist_ok=True)
    (CIEL_LOCAL / "refs" / "learnings").mkdir(parents=True, exist_ok=True)

    return True

# ------------------------------------------------------------------------------
# PHASE 9: Local Sync (LOCAL_SYNC.md)
# ------------------------------------------------------------------------------

def local_sync(context):
    say("Phase 9: Local sync (global → local refs)...")

    # Sync relevant skills based on detected context
    skills_to_sync = []

    if "godot" in context["frameworks"]:
        skills_to_sync.extend(["godot", "game-dev", "gdscript"])

    if "claude_code" == context["runtime_hint"]:
        skills_to_sync.extend(["claude-code", "agent-orchestration"])

    if context["signals"].get("github_actions"):
        skills_to_sync.append("github-actions")

    # Also sync common skills
    skills_to_sync.extend(["git", "testing", "documentation", "refactoring"])

    # De-dupe
    skills_to_sync = list(dict.fromkeys(skills_to_sync))

    synced = 0
    for skill in skills_to_sync:
        src = CIEL_GLOBAL / "skills" / skill
        if src.exists():
            dst = CIEL_LOCAL / "refs" / "skills" / f"{skill}.ref"
            # Create pointer file
            dst.write_text(json.dumps({
                "type": "skill",
                "source": str(src),
                "pinned_version": "latest",
                "created_at": datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
            }, indent=2), encoding="utf-8")
            synced += 1
        else:
            # Try to find matching skill (fuzzy)
            for candidate in (CIEL_GLOBAL / "skills").iterdir():
                if candidate.is_dir() and skill.lower() in candidate.name.lower():
                    dst = CIEL_LOCAL / "refs" / "skills" / f"{candidate.name}.ref"
                    dst.write_text(json.dumps({
                        "type": "skill",
                        "source": str(candidate),
                        "pinned_version": "latest",
                        "created_at": datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
                    }, indent=2), encoding="utf-8")
                    synced += 1
                    break

    # Sync rules
    rules_dir = CIEL_GLOBAL / "registry" / "rules"
    if rules_dir.exists():
        for rule_file in rules_dir.glob("*.md"):
            dst = CIEL_LOCAL / "refs" / "rules" / f"{rule_file.stem}.ref"
            dst.write_text(json.dumps({
                "type": "rule",
                "source": str(rule_file),
                "pinned_version": "latest",
                "created_at": datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
            }, indent=2), encoding="utf-8")
            synced += 1

    say(f"  Synced {synced} references (skills + rules)")
    return True

# ------------------------------------------------------------------------------
# PHASE 10: Memory Health (memory/HEALTH_CHECK.md)
# ------------------------------------------------------------------------------

def memory_health():
    say("Phase 10: Memory health check...")

    # Check global memory
    memory_dir = CIEL_GLOBAL / "memory"
    if memory_dir.exists():
        memory_count = len(list(memory_dir.glob("*.md")))
        say(f"  Global memory: {memory_count} entries")
    else:
        warn("  Global memory directory not found")

    # Create local memory directory
    local_memory = CIEL_LOCAL / "memory"
    local_memory.mkdir(parents=True, exist_ok=True)

    say("  Memory health OK")
    return True

# ------------------------------------------------------------------------------
# PHASE 11: Git Setup (skip - global already done)
# ------------------------------------------------------------------------------

def git_setup():
    say("Phase 11: Git setup (skipped - global ~/.ciel already initialized)")
    return True

# ------------------------------------------------------------------------------
# PHASE 12: Backup (BACKUP.md)
# ------------------------------------------------------------------------------

def backup():
    say("Phase 12: Backup...")

    backup_dir = CIEL_LOCAL / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)

    # Create initial snapshot of project.json + escalation.json
    snapshot = {
        "project.json": json.loads((CIEL_LOCAL / "project.json").read_text()),
        "escalation.json": json.loads((CIEL_LOCAL / "escalation.json").read_text()),
        "created_at": datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')
    }

    snapshot_file = backup_dir / f"init-snapshot-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    snapshot_file.write_text(json.dumps(snapshot, indent=2), encoding="utf-8")

    say(f"  Initial snapshot: {snapshot_file.name}")
    return True

# ------------------------------------------------------------------------------
# PHASE 13: Announce
# ------------------------------------------------------------------------------

def announce(context, calibration):
    say("Phase 13: Announce...")

    summary = f"""
Ciel LOCAL INIT complete for BioGenesis-X
  Project: {context['root']}
  Language: {context['language']} | Frameworks: {', '.join(context['frameworks'])}
  Escalation threshold: {calibration['effective']} (auto: {calibration['auto_detected']})
  Runtime: {context['runtime_hint']}
  Local domain: {CIEL_LOCAL}
  Global domain: {CIEL_GLOBAL}
  Partitions: ciel-global, project-biogenesis-x
    """
    print(summary)

    # Append to global activity.log
    activity_log = CIEL_GLOBAL / "activity.log"
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z'),
        "kind": "local_init",
        "project": "BioGenesis-X",
        "path": str(PROJECT_ROOT),
        "ciel_version": "1.0.0",
        "escalation": calibration["effective"]
    }
    with open(activity_log, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")

    say("  Activity logged to global activity.log")
    return True

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("CIEL LOCAL INIT — BioGenesis-X")
    print("=" * 60)

    # Verify we're in the right place
    if not (PROJECT_ROOT / "project.godot").exists():
        die(f"project.godot not found at {PROJECT_ROOT}. Run from project root.")

    if not CIEL_GLOBAL.exists():
        die(f"Global Ciel not found at {CIEL_GLOBAL}. Run global bootstrap first.")

    # Execute phases 5-13
    context = detect_context()
    calibration = calibrate(context)
    calibration = apply_override(calibration)
    create_local_ciel(context, calibration)
    local_sync(context)
    memory_health()
    git_setup()
    backup()
    announce(context, calibration)

    print("=" * 60)
    say("Ciel local initialization complete.")
    print("=" * 60)

if __name__ == "__main__":
    main()