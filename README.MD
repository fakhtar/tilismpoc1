# Tilisme POC — Inference-Subordinate Simulation

A proof of concept implementation for Paper One of the Tilisme 
platform. Demonstrates that a 3D simulation engine can be operated 
as an inference-subordinate recording system, completely decoupling 
inference time from playback time.

**Paper:** *Inference-Subordinate Simulation: Decoupling Agent Decision 
Time from Playback Time in 3D Environments*  
**Author:** Faisal Akhtar  
**arXiv:** [link when published]

---

## The Core Claim

The simulation engine advances **only when the LLM issues a decision**. 
Recorded decisions replay at any speed without re-running the LLM. 
Inference time and playback time are fully decoupled.

---

## Repository Structure

```
tilisme-poc/
│
├── mcp_client.py              # Python inference server
│                              # Receives frames, runs LLM inference,
│                              # returns tool calls to Godot
│
└── tilism_poc/                # Godot 4 project
    ├── main.tscn              # Recording scene (bird's eye camera active)
    ├── main.gd                # Puppet movement, frame capture,
    │                          # decision log, CSV data collection
    ├── mcp_server.gd          # HTTP polling client, passes tool calls
    │                          # from Python to main.gd
    ├── replay.tscn            # Replay scene (ground level camera active)
    ├── replay.gd              # Reads decision log, replays at variable
    │                          # speed, displays timing comparison UI
    ├── project.godot          # Godot project configuration
    ├── decision_log.jsonl     # Generated at runtime — last recording run
    ├── runs.csv               # Generated at runtime — all run summaries
    └── decisions.csv          # Generated at runtime — all per-decision data
```

---

## Prerequisites

**Godot 4**
- Version 4.6.2 or later
- Download from https://godotengine.org

**Python**
- Version 3.9 or later
- Required package: `anthropic`

```bash
pip install anthropic
```

**Anthropic API Key**
- Obtain from https://console.anthropic.com
- Set as environment variable:

```bash
# Windows
set ANTHROPIC_API_KEY=your-api-key-here

# macOS / Linux
export ANTHROPIC_API_KEY=your-api-key-here
```

---

## Running a Recording Session

A recording session runs the LLM-driven agent, logs all decisions, 
and writes results to CSV.

**Step 1 — Start the inference server**

```bash
cd path/to/tilisme-poc
python mcp_client.py
```

You should see:
```
MCP LLM server listening on port 9876
Model: claude-opus-4-5
Waiting for frames from Godot...
```

**Step 2 — Open the Godot project**

1. Open Godot 4
2. Import the project from `tilism_poc/`
3. Open `main.tscn`
4. Press **F5** or click **Run Project**

The simulation will start. Godot sends frames to the inference 
server, Claude reasons about each frame, and the capsule navigates 
toward the red sphere. Each decision is logged automatically.

**Step 3 — Wait for goal reached**

When the capsule reaches the goal you will see in the Godot console:

```
GOAL REACHED at frame N
--- RUN SUMMARY ---
Run ID:              1
Decisions:           8
Good moves:          7 (88%)
Total inference:     36.42s
Mean inference:      4.55s
Recording duration:  61.20s
Path efficiency:     1.09
```

The Python server can then be stopped with `Ctrl+C`.

---

## Running the Replay

The replay reads the last recorded `decision_log.jsonl` and 
reproduces the behavior at variable speed using the ground level 
camera — no LLM required.

1. In the Godot editor, open `replay.tscn`
2. Press **F6** (Run Current Scene)
3. Use the **speed slider** in the top-left UI panel to adjust 
   playback speed from 0.1x to 10x in real time

At replay completion the UI panel displays:

```
Decisions replayed:   8
Replay duration:      0.82s
Original inference:   36.42s
Original recording:   61.20s
Speedup:              44.4x
```

---

## Output Files

All output files are written to the Godot project directory 
`tilism_poc/`.

**`decision_log.jsonl`**  
Overwritten each recording run. Contains one JSON entry per line:

| Entry type | Description |
|---|---|
| `run_header` | Seed, puppet start position, goal position |
| `decision` | dx, dz, inference\_time, position, distance\_to\_goal, frame, timestamp |
| `goal_reached` | Frame and distance at goal detection |
| `run_summary` | Total decisions, total inference time, recording duration |

**`runs.csv`**  
Appended each recording run. One row per run:

| Column | Description |
|---|---|
| run\_id | Auto-incrementing integer |
| timestamp | Unix timestamp at run completion |
| seed | Random seed used for spawn positions |
| starting\_distance | Straight-line distance at run start |
| decision\_count | Total decisions made |
| inference\_time\_total | Sum of all inference times (seconds) |
| inference\_time\_mean | Mean inference time per decision |
| inference\_time\_min | Fastest decision |
| inference\_time\_max | Slowest decision |
| recording\_duration | Wall clock from start to goal reached |
| goal\_reached | true / false |
| good\_moves | Decisions that decreased distance |
| bad\_moves | Decisions that increased distance |
| good\_move\_rate | good\_moves / decision\_count |
| final\_distance | Distance at run end |
| path\_efficiency | starting\_distance / total\_distance\_traveled |

**`decisions.csv`**  
Appended each recording run. One row per decision:

| Column | Description |
|---|---|
| run\_id | Foreign key to runs.csv |
| decision\_number | Position in sequence (1-indexed) |
| inference\_time | Time for this inference call (seconds) |
| distance\_before | Distance to goal before this move |
| distance\_after | Distance to goal after this move |
| dx | X-axis displacement applied |
| dz | Z-axis displacement applied |
| good\_move | true if distance decreased by > 0.05 units |

---

## Swapping the Model

The inference layer is a single function in `mcp_client.py`. 
To substitute a different model, change two lines:

```python
# Current
MODEL = "claude-opus-4-5"
client = anthropic.Anthropic(api_key=API_KEY)

# Example: different Anthropic model
MODEL = "claude-sonnet-4-5"

# Example: OpenAI
from openai import OpenAI
client = OpenAI(api_key=API_KEY)
# Update the client.messages.create() call accordingly
```

No changes to the Godot project, communication protocol, 
decision log format, or replay system are required. The 
architecture is model-agnostic. Navigation quality is 
model-dependent — see Section 4.5 of the paper for the 
model selection rationale.

---

## Empirical Dataset

The repository includes the complete dataset from the paper:

- `tilism_poc/runs.csv` — 26 runs
- `tilism_poc/decisions.csv` — 222 decisions

Key results:

| Metric | Value |
|---|---|
| Runs | 26 |
| Total decisions | 222 |
| Goal success rate | 100% |
| Mean inference time | 4.53s ± 1.12s |
| Mean good move rate | 92.1% |
| Mean path efficiency | 1.065 |
| Max replay speedup | >38× |

---

## Scene Configuration

| Parameter | Value |
|---|---|
| Navigable plane | −5.0 to +5.0 (X and Z) |
| Spawn range | −3.0 to +3.0 (X and Z) |
| Minimum spawn separation | 4.0 units |
| Step size | 0.5 units per decision per axis |
| Goal detection threshold | 0.8 units |
| LLM camera | Bird's eye at (0, 20, 0) |
| Replay camera | Ground level at (0, 4, 8) |
| Viewport capture size | 336 × 336 pixels |

---

## Paper Two

Paper Two will examine orthogonal multi-view observation: 
simultaneous bird's eye and ground-level cameras to decompose 
3D spatial reasoning into independent 2D problems. This 
repository is the foundation on which that work builds.

---

## Citation

If you use this work please cite:

```bibtex
@article{akhtar2025inference,
  title={Inference-Subordinate Simulation: Decoupling Agent 
         Decision Time from Playback Time in 3D Environments},
  author={Akhtar, Faisal},
  journal={arXiv preprint},
  year={2026},
  url={https://github.com/fakhtar/tilismpoc1}
}
```

---

## License

MIT License. See `LICENSE` for details.

---

## Contact

Faisal Akhtar  
[linkedin.com/in/faisalakhtar](https://www.linkedin.com/in/faisalakhtar/)