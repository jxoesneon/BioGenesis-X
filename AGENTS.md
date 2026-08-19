# BioGenesis-X — Agent Operating Guide

## Godot Process Lifecycle Management

**CRITICAL**: Never leave Godot test/runtime instances running after verification.

### Rules
1. **Before launching any Godot command**: Kill stale Godot test instances (preserve the editor and MCP server)
2. **After any Godot command completes**: Ensure the process is dead
3. **Never use raw `&` backgrounding without a cleanup guarantee**
4. **Prefer headless `--script` tests** that exit on their own over `--debug` scene launches
5. **If a scene must be launched for runtime testing**: Use a timeout and kill the process after

### Hooks (Registered in ~/.claude/settings.json)
- **PreToolUse (exec)**: `~/.ciel/skills/godot/hooks/godot_exec_preflight.sh` — kills stale Godot instances before any exec command containing "godot"
- **PostToolUse (exec)**: `~/.ciel/skills/godot/hooks/godot_exec_postflight.sh` — kills any Godot instances left after exec completes
- **PreToolUse (write/edit)**: `~/.ciel/skills/godot/hooks/godot_preflight.sh` — injects AAA+ Godot guidance
- **PostToolUse (write/edit)**: `~/.ciel/skills/godot/hooks/godot_postflight.sh` — validates Godot anti-patterns

### Helper Script
`~/.ciel/skills/godot/hooks/godot_safe_run.sh` — wraps Godot launches with automatic cleanup:
```bash
~/.ciel/skills/godot/hooks/godot_safe_run.sh --headless --script res://scripts/test_aaa_audio_suite.gd --timeout 30
~/.ciel/skills/godot/hooks/godot_safe_run.sh --path . --debug res://scenes/space_flight.tscn --timeout 15
```

### What Gets Killed
- Any process matching `Godot.app/Contents/MacOS/Godot` or `/bin/godot`
- That does NOT have the `--editor` flag

### What Is Preserved
- The Godot editor (`--editor` flag)
- The godot-mcp node server (it's a node process, not a Godot binary)
- All non-Godot processes

## Build & Test Commands

```bash
# Debugger audit (all scripts + scenes)
Godot --headless --script res://scripts/test_clean_debugger_audit.gd

# AAA audio suite
Godot --headless --script res://scripts/test_aaa_audio_suite.gd

# Planet landing integration suite (127 tests across 11 subsystems)
Godot --headless --script res://scripts/test_planet_landing_suite.gd

# Autoload startup test (zero errors/warnings on full boot)
Godot --headless --quit-after 3

# Runtime scene test (use timeout, clean up after)
Godot --path . --debug res://scenes/space_flight.tscn  # MUST be killed within 15s
```

## Project Architecture

- **Engine**: Godot 4.7.1 stable, Forward+ renderer, JoltPhysics3D
- **Audio**: Procedural synthesis via `BioAudioSynth.gd` (autoload) + `BioAudioDirector.gd` (autoload) for scene/event transitions
- **Autoloads**: OrganTelemetry, BioManager, SaveSystem, BioAudioSynth, BioAudioDirector, PlanetDescentController, PlanetEntryManager, DescentAudioController, LandingSequenceController
- **Sample rate**: 22050 Hz (GDScript AudioStreamGenerator performance requirement)
- **Buffer length**: 0.15s
