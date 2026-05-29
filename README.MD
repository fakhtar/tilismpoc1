# Tilisme POC — Status & Run Guide

## What This Is

A proof of concept for an AI-driven film simulation pipeline. An external
intelligence observes a 3D world through a camera and issues commands that
move objects in that world. The world records every frame and every decision.

This is the foundation of the Tilisme platform — a system where LLM agents
drive puppet characters in a simulated world, producing footage that can be
corrected to photorealistic output in post.

---

## Current State

**Phase 0 complete.** The full observation-action loop is proven end to end:

- Godot runs a 3D scene with a ground plane and a capsule puppet
- A Camera3D captures frames continuously
- Godot sends the latest camera frame to Python as a JPEG every 0.5 seconds
- Python receives the frame and saves it to `latest_frame.jpg`
- Python sends a tool call back to Godot (`move_forward` with an amount)
- Godot executes the tool call, moves the puppet, logs the action and frame number
- The loop repeats

The LLM is not connected yet. Python sends hardcoded tool calls. This proves
the pipeline works before adding inference complexity.

---

## Files

```
tilism_poc/                         ← Godot project folder
    main.tscn                       ← Scene file
    main.gd                         ← Handles puppet movement, frame capture, decision log
    mcp_server.gd                   ← HTTP client that pushes frames and polls for commands

C:\Projects\Tilism\First\
    mcp_client.py                   ← Python HTTP server — stand-in for the LLM
    latest_frame.jpg                ← Current camera view, updated every 0.5s (generated at runtime)
```

---

## Scene Structure

```
Main (Node)              ← main.gd attached
└── World (Node3D)
    ├── DirectionalLight3D
    ├── Ground (MeshInstance3D)
    │   └── StaticBody3D
    │       └── CollisionShape3D
    └── Puppet (AnimatableBody3D)   ← the capsule placeholder
        ├── CollisionShape3D
        └── MeshInstance3D
├── Camera3D             ← positioned at (0, 4, 8), rotation (-20, 0, 0)
└── MCPServer (Node)     ← mcp_server.gd attached
```

---

## How To Run

**Step 1 — Start Python first**
```bash
cd C:\Projects\Tilism\First
python mcp_client.py
```
You should see:
```
MCP HTTP server listening on port 9876
Frames will be saved to: C:\Projects\Tilism\First\latest_frame.jpg
```

**Step 2 — Run the Godot scene**
- Open the `tilism_poc` project in Godot
- Press **F5**

You should see in the Godot Output panel:
```
MCP Client polling http://127.0.0.1:9876/poll
Frame output: ...
Log output: ...
```

And in the Python terminal:
```
Frame received: 1 (14237 bytes)
Sent tool call: {'id': 1, 'tool': 'move_forward', 'params': {'amount': 1.0}}
Result: { ... }
```

**Step 3 — Verify**
- Capsule moves forward in the Godot viewport
- `latest_frame.jpg` updates continuously with the camera view
- `decision_log.jsonl` records each tool call with frame number and position
- Frame PNGs accumulate in the Godot user data frames folder

**To stop:** Ctrl+C in the Python terminal, F8 in Godot.

**To run again:** Restart Python first, then F5 in Godot.

---

## Output Locations

| Output | Location |
|--------|----------|
| Frame PNGs | `C:\Users\faisa\AppData\Roaming\Godot\app_userdata\tilism_poc\frames\` |
| Decision log | `C:\Users\faisa\AppData\Roaming\Godot\app_userdata\tilism_poc\decision_log.jsonl` |
| Latest frame | `C:\Projects\Tilism\First\latest_frame.jpg` |

---

## Decision Log Format

Each line is one tool call:
```json
{"action": "move_forward", "amount": 1.0, "new_position": {"x": 0.0, "y": 0.0, "z": -1.0}, "frame": 11}
```

---

## What Is NOT Built Yet

- Local LLM receiving `latest_frame.jpg` and generating tool calls
- Second puppet with subordinate behavior (proves hierarchical agency)
- Deterministic reflex layer (puppet fallback when LLM call is slow)
- Replay system (re-execute decision log deterministically)

---

## Next Step

Replace the hardcoded tool calls in `mcp_client.py` with a local multimodal
LLM (LLaVA 7B quantized). The LLM receives `latest_frame.jpg`, reasons about
what the puppet should do, and returns a `move_forward` tool call. Hardware
requirement: GTX 1060 6GB is sufficient for a quantized 7B vision model.

ollama ps
ollama list
ollama run qwen2.5vl:7b "Hello! Are you working?"
