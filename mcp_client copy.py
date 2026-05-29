from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import os
import base64
import time
import re
import ollama

MODEL = "llava:7b-v1.6-mistral-q4_K_M"
FRAME_PATH = "latest_frame.jpg"
new_frame_received = False
frame_count = 0
call_id = 0
previous_frame_b64 = None
last_tool_call = None
prev_distance = None
curr_distance = None
distance_history = []
move_history = []


def encode_image(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def build_prompt(last_tool_call, prev_dist=None, curr_dist=None,
                 dist_history=None, mv_history=None):

    # --- LAYER 1: WORLD DESCRIPTION ---
    prompt = """WORLD DESCRIPTION:
You are looking at a TOP-DOWN bird's eye view of a flat surface.
This is a 2D overhead map — there is NO perspective distortion.

The scene contains exactly two objects:
- A WHITE CAPSULE (grey/white oval shape) — YOU CONTROL THIS. This is your agent.
- A RED DOT (small red circle) — THIS IS YOUR GOAL. It does not move. You cannot control it.

YOU ARE THE WHITE CAPSULE. YOUR JOB IS TO MOVE THE WHITE CAPSULE TO THE RED DOT.
THE RED DOT DOES NOT MOVE. ONLY THE WHITE CAPSULE MOVES.

COORDINATE SYSTEM (top-down view):
- Moving the WHITE CAPSULE UP in the image = use NEGATIVE dz
- Moving the WHITE CAPSULE DOWN in the image = use POSITIVE dz
- Moving the WHITE CAPSULE LEFT in the image = use NEGATIVE dx
- Moving the WHITE CAPSULE RIGHT in the image = use POSITIVE dx

"""

    # --- LAYER 2: MOVE HISTORY ---
    if mv_history and len(mv_history) > 0:
        prompt += "YOUR PREVIOUS MOVES (most recent last):\n"
        for i, m in enumerate(mv_history[-5:], 1):
            outcome = "GOOD" if m["change"] < -0.1 else ("BAD" if m["change"] > 0.1 else "NO EFFECT")
            prompt += (
                f"  {i}. dx={m['dx']:.2f}, dz={m['dz']:.2f} → "
                f"distance {m['prev_dist']:.2f} → {m['curr_dist']:.2f} "
                f"({outcome})\n"
            )

        if len(mv_history) >= 3:
            recent = mv_history[-3:]
            all_bad = all(m["change"] > 0.1 for m in recent)
            oscillating = (
                recent[-1]["change"] > 0.1 and
                recent[-2]["change"] < -0.1 and
                recent[-3]["change"] > 0.1
            )
            no_effect_count = sum(1 for m in mv_history[-3:] if abs(m["change"]) < 0.1)

            if all_bad:
                prompt += "  WARNING: 3 BAD moves in a row. Change BOTH dx and dz completely.\n"
            elif oscillating:
                prompt += "  WARNING: Oscillating. Pick a completely new direction.\n"
            elif no_effect_count >= 2:
                prompt += "  WARNING: Multiple NO EFFECT moves. You are at a boundary wall. Reverse direction.\n"

        prompt += "\n"

    # Last move feedback
    if last_tool_call and prev_dist is not None and curr_dist is not None:
        change = curr_dist - prev_dist
        if change < -0.1:
            feedback = f"GOOD — distance decreased by {abs(change):.2f}. This direction is working."
        elif change > 0.1:
            feedback = f"BAD — distance increased by {change:.2f}. Try a different direction."
        else:
            feedback = "NO EFFECT — distance unchanged. You hit a boundary wall. Reverse direction."
        prompt += f"LAST MOVE: {json.dumps(last_tool_call)}\n"
        prompt += f"RESULT: {feedback}\n\n"
    elif last_tool_call:
        prompt += f"LAST MOVE: {json.dumps(last_tool_call)}\n\n"

    # --- LAYER 3: OBSERVATION REQUEST ---
    prompt += """You have been given TWO images:
- IMAGE 1 (first image): PREVIOUS state — before your last move
- IMAGE 2 (second image): CURRENT state — after your last move

The WHITE CAPSULE moved between IMAGE 1 and IMAGE 2.
The RED DOT did not move — it is in the same place in both images.

STOP. Look carefully at IMAGE 2 only. Answer each step below in order.

Step 1 — Locate both objects in IMAGE 2:
WHITE_CAPSULE_IS_AT: [describe where the WHITE CAPSULE is in IMAGE 2, e.g. top-left, center, bottom-right]
RED_DOT_IS_AT: [describe where the RED DOT is in IMAGE 2, e.g. top-left, center, bottom-right]

Step 2 — Determine relative position of RED DOT compared to WHITE CAPSULE:
IS_RED_DOT_LEFT_OR_RIGHT_OF_CAPSULE: [answer LEFT or RIGHT — if the red dot is to the left of the white capsule, answer LEFT]
IS_RED_DOT_ABOVE_OR_BELOW_CAPSULE: [answer ABOVE or BELOW — if the red dot is higher in the image than the white capsule, answer ABOVE]

Step 3 — Derive movement values from Step 2:
DX: [if Step 2 says LEFT then -2.0, if RIGHT then +2.0]
DZ: [if Step 2 says ABOVE then -2.0, if BELOW then +2.0]

Step 4 — Output your move (copy DX and DZ values from Step 3 exactly):
MOVE: {"tool": "move", "params": {"dx": [DX value from Step 3], "dz": [DZ value from Step 3]}}

MOVE line is mandatory. DX and DZ must match Step 3 exactly."""

    return prompt

def extract_json(raw):
    """Extract tool call JSON. Three passes plus DX/DZ reconstruction fallback."""

    lines = [line.strip() for line in raw.split('\n') if line.strip()]

    # Pass 0: MOVE: prefix
    for line in lines:
        if line.upper().startswith("MOVE:"):
            candidate = line[5:].strip()
            try:
                parsed = json.loads(candidate)
                if "tool" in parsed:
                    return parsed
            except:
                pass

    # Pass 1: single-line JSON with "tool" key
    for line in reversed(lines):
        if line.startswith("```"):
            continue
        try:
            parsed = json.loads(line)
            if "tool" in parsed:
                return parsed
        except:
            continue

    # Pass 2: multiline JSON block starting with {"tool"
    match = re.search(r'\{\s*"tool"', raw)
    if match:
        start = match.start()
        candidate = raw[start:]
        depth = 0
        end = -1
        for i, ch in enumerate(candidate):
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
        if end != -1:
            try:
                parsed = json.loads(candidate[:end])
                if "tool" in parsed:
                    return parsed
            except:
                pass

    # Pass 3: markdown fences
    if "```" in raw:
        parts = raw.split("```")
        for part in parts:
            part = part.strip()
            if part.startswith("json"):
                part = part[4:].strip()
            try:
                parsed = json.loads(part)
                if "tool" in parsed:
                    return parsed
            except:
                continue

    # Pass 4: reconstruct from DX/DZ lines — safety net
    dx_match = re.search(r'^DX:\s*([-+]?\d*\.?\d+)', raw, re.MULTILINE | re.IGNORECASE)
    dz_match = re.search(r'^DZ:\s*([-+]?\d*\.?\d+)', raw, re.MULTILINE | re.IGNORECASE)
    if dx_match and dz_match:
        try:
            dx = float(dx_match.group(1))
            dz = float(dz_match.group(1))
            print(f"Pass 4 reconstruction: dx={dx}, dz={dz}")
            return {"tool": "move", "params": {"dx": dx, "dz": dz}}
        except:
            pass

    return None


def query_llava():
    global previous_frame_b64, last_tool_call, prev_distance, curr_distance
    global distance_history, move_history

    current_frame_b64 = encode_image(FRAME_PATH)
    print(f"DEBUG frame hash: {hash(current_frame_b64)}")
    print(f"DEBUG prev hash: {hash(previous_frame_b64) if previous_frame_b64 else 'None'}")

    images = []
    if previous_frame_b64 is not None:
        images.append(previous_frame_b64)
    images.append(current_frame_b64)

    prompt = build_prompt(
        last_tool_call, prev_distance, curr_distance,
        distance_history, move_history
    )

    try:
        start_time = time.time()
        print(f"DEBUG sending {len(images)} image(s) to model")
        response = ollama.chat(
            model=MODEL,
            messages=[{
                'role': 'user',
                'content': prompt,
                'images': images
            }],
            options={
                'num_predict': 200,
                'num_ctx': 2048,
                'temperature': 0.3
            }
        )
        inference_time = time.time() - start_time

        raw = response['message']['content'].strip()
        print(f"LLaVA reasoning ({inference_time:.1f}s):\n{raw}\n")

        tool_call = extract_json(raw)

        if tool_call is None:
            raise ValueError(f"No valid JSON found in response: {raw}")

        clean_call = {
            "tool": tool_call.get("tool", "move"),
            "params": tool_call.get("params", {"dx": 0.0, "dz": -1.0})
        }

        # Never allow no-op
        params = clean_call.get("params", {})
        if params.get("dx", 0) == 0.0 and params.get("dz", 0) == 0.0:
            print("WARNING: no-op move — overriding with dz=-1.0")
            clean_call["params"] = {"dx": 0.0, "dz": -1.0}

        previous_frame_b64 = current_frame_b64
        last_tool_call = clean_call

        print(f"Inference time: {inference_time:.2f}s")
        return clean_call, inference_time

    except Exception as e:
        print(f"LLaVA error: {e} — defaulting to move forward")
        previous_frame_b64 = current_frame_b64
        default = {"tool": "move", "params": {"dx": 0.0, "dz": -1.0}}
        last_tool_call = default
        return default, 0.0


class MCPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global call_id, new_frame_received
        if self.path == "/poll":
            if not os.path.exists(FRAME_PATH) or not new_frame_received:
                self.send_response(204)
                self.send_header("Content-Length", "0")
                self.end_headers()
                self.wfile.flush()
                return
            new_frame_received = False  # Reset flag before making decision
            print(f"\n--- LLM Decision {call_id + 1} ---")
            clean_call, inference_time = query_llava()
            call_id += 1

            envelope = {
                "id": call_id,
                "tool": clean_call["tool"],
                "params": clean_call.get("params", {}),
                "inference_time": inference_time
            }

            body = json.dumps(envelope).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", len(body))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            print(f"Sent: {envelope}")

    def do_POST(self):
        global frame_count, prev_distance, curr_distance
        global distance_history, move_history, last_tool_call, new_frame_received
        length = int(self.headers["Content-Length"])
        body = self.rfile.read(length)

        if self.path == "/frame":
            with open(FRAME_PATH, "wb") as f:
                f.write(body)
            frame_count += 1
            new_frame_received = True
            print(f"Frame {frame_count} received ({len(body)} bytes)")
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            self.wfile.flush()

        elif self.path == "/result":
            result = json.loads(body)
            result_data = result.get("result", {})
            prev_distance = curr_distance
            curr_distance = result_data.get("distance_to_goal")

            if prev_distance is not None and curr_distance is not None:
                change = curr_distance - prev_distance
                distance_history.append(change)
                if len(distance_history) > 5:
                    distance_history.pop(0)

                if last_tool_call and last_tool_call.get("params"):
                    params = last_tool_call["params"]
                    move_record = {
                        "dx": params.get("dx", 0.0),
                        "dz": params.get("dz", 0.0),
                        "prev_dist": prev_distance,
                        "curr_dist": curr_distance,
                        "change": change
                    }
                    move_history.append(move_record)
                    if len(move_history) > 5:
                        move_history.pop(0)

                direction = "closer" if change < 0 else "further"
                print(f"Distance: {prev_distance:.2f} → {curr_distance:.2f} "
                      f"({direction} by {abs(change):.2f})")

            print(f"Result: {json.dumps(result, indent=2)}")
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            self.wfile.flush()

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    print(f"MCP LLM server listening on port 9876")
    print(f"Model: {MODEL}")
    print(f"Waiting for frames from Godot...")
    server = HTTPServer(("127.0.0.1", 9876), MCPHandler)
    server.serve_forever()