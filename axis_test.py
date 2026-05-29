"""
AXIS VERIFICATION TEST
Run this instead of mcp_client.py to verify camera orientation.
Watch the bird's eye viewport in Godot for each move.

Move 1: dx=+2, dz=0  → capsule should move RIGHT in image if X axis is correct
Move 2: dx=-2, dz=0  → capsule should move LEFT in image
Move 3: dx=0, dz=-2  → watch which direction capsule moves (UP or DOWN)
Move 4: dx=0, dz=+2  → should be opposite of Move 3

Record what you see for each move. That tells us the true camera mapping.
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import time

TOOL_CALLS = [
    {"id": 1, "tool": "move", "params": {"dx": 2.0, "dz": 0.0}},
    {"id": 2, "tool": "move", "params": {"dx": -2.0, "dz": 0.0}},
    {"id": 3, "tool": "move", "params": {"dx": 0.0, "dz": -2.0}},
    {"id": 4, "tool": "move", "params": {"dx": 0.0, "dz": 2.0}},
]

pending = list(TOOL_CALLS)
frame_count = 0
call_id = 0


class TestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global call_id, pending
        if self.path == "/poll":
            if not pending:
                self.send_response(204)
                self.send_header("Content-Length", "0")
                self.end_headers()
                self.wfile.flush()
                return

            call = pending.pop(0)
            call_id += 1
            call["id"] = call_id

            body = json.dumps(call).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", len(body))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()

            labels = {
                1: "MOVE RIGHT (dx=+2) — watch capsule direction",
                2: "MOVE LEFT (dx=-2) — watch capsule direction",
                3: "MOVE NEGATIVE Z (dz=-2) — watch capsule direction",
                4: "MOVE POSITIVE Z (dz=+2) — watch capsule direction",
            }
            print(f"\nSent move {call_id}: {labels.get(call_id, '')}")
            print(f"  params: {call['params']}")

    def do_POST(self):
        global frame_count
        length = int(self.headers["Content-Length"])
        body = self.rfile.read(length)

        if self.path == "/frame":
            frame_count += 1
            print(f"Frame {frame_count} received")
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            self.wfile.flush()

        elif self.path == "/result":
            result = json.loads(body)
            r = result.get("result", {})
            pos = r.get("position", {})
            print(f"  Result: position x={pos.get('x', 0):.2f}, z={pos.get('z', 0):.2f}, "
                  f"distance={r.get('distance_to_goal', 0):.2f}")

            if not pending:
                print("\n" + "="*50)
                print("ALL 4 MOVES COMPLETE")
                print("Record which direction the capsule moved in the image for each move.")
                print("="*50)

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    print("Axis Verification Test")
    print("="*50)
    print("Start Godot scene first, then observe the bird's eye viewport.")
    print("The capsule will make 4 moves. Record the direction for each.")
    print("="*50)
    server = HTTPServer(("127.0.0.1", 9876), TestHandler)
    server.serve_forever()