from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import os
import base64
import requests

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "llava:7b-v1.6-mistral-q4_K_M"
FRAME_PATH = "latest_frame.jpg"

frame_count = 0
call_id = 0

SYSTEM_PROMPT = """You control a capsule in a 3D scene.
Respond ONLY with JSON. No other text.
If capsule is visible: {"tool": "move_forward", "params": {"amount": 1.0}}
If capsule is at edge or not visible: {"tool": "stop", "params": {}}"""


def query_llava(image_path):
    """Send frame to LLaVA and get a tool call back."""
    with open(image_path, "rb") as f:
        image_b64 = base64.b64encode(f.read()).decode("utf-8")
    payload = {
        "model": MODEL,
        "prompt": SYSTEM_PROMPT,
        "images": [image_b64],
        "stream": False,
        "num_predict": 30,
        "options": {
            "num_ctx": 512
        }
    }

    try:
        response = requests.post(OLLAMA_URL, json=payload, timeout=30)
        result = response.json()
        raw = result.get("response", "").strip()
        print(f"LLaVA raw response: {raw}")
        tool_call = json.loads(raw)
        return tool_call
    except Exception as e:
        print(f"LLaVA error: {e} — defaulting to move_forward")
        return {"tool": "move_forward", "params": {"amount": 1.0}}


class MCPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global call_id
        if self.path == "/poll":
            if not os.path.exists(FRAME_PATH):
                # No frame yet - tell Godot nothing to do
                self.send_response(204)
                self.send_header("Content-Length", "0")
                self.end_headers()
                self.wfile.flush()
                return

            print(f"\n--- LLM Decision {call_id + 1} ---")
            tool_call = query_llava(FRAME_PATH)
            call_id += 1
            tool_call["id"] = call_id

            body = json.dumps(tool_call).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", len(body))
            self.end_headers()
            self.wfile.write(body)
            self.wfile.flush()
            print(f"Sent tool call: {tool_call}")

    def do_POST(self):
        global frame_count
        length = int(self.headers["Content-Length"])
        body = self.rfile.read(length)

        if self.path == "/frame":
            with open(FRAME_PATH, "wb") as f:
                f.write(body)
            frame_count += 1
            print(f"Frame {frame_count} received ({len(body)} bytes)")
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            self.wfile.flush()

        elif self.path == "/result":
            result = json.loads(body)
            print(f"Result: {json.dumps(result, indent=2)}")
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()
            self.wfile.flush()

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    # Install requests if needed
    try:
        import requests
    except ImportError:
        print("Installing requests...")
        os.system("pip install requests")
        import requests

    server = HTTPServer(("127.0.0.1", 9876), MCPHandler)
    print(f"MCP LLM server listening on port 9876")
    print(f"Model: {MODEL}")
    print(f"Waiting for frames from Godot...")
    server.serve_forever()