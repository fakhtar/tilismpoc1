from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import threading
import time

# Queue of tool calls to send
pending_calls = [
    {"id": 1, "tool": "move_forward", "params": {"amount": 1.0}},
    {"id": 2, "tool": "move_forward", "params": {"amount": 1.0}},
    {"id": 3, "tool": "move_forward", "params": {"amount": 2.0}},
    {"id": 4, "tool": "move_forward", "params": {"amount": 0.5}},
]
latest_frame_path = "latest_frame.jpg"
frame_count = 0
class MCPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/poll":
            if pending_calls:
                call = pending_calls.pop(0)
                body = json.dumps(call).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", len(body))
                self.end_headers()
                self.wfile.write(body)
                self.wfile.flush()
                print(f"Sent: {call}")
            else:
                self.send_response(204)
                self.send_header("Content-Length", "0")
                self.end_headers()
                self.wfile.flush()

    def do_POST(self):
        global frame_count
        length = int(self.headers["Content-Length"])
        body = self.rfile.read(length)

        if self.path == "/frame":
            with open(latest_frame_path, "wb") as f:
                f.write(body)
            frame_count += 1
            print(f"Frame received: {frame_count} ({len(body)} bytes)")
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
        pass  # Suppress default HTTP logging

if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", 9876), MCPHandler)
    print("MCP HTTP server listening on port 9876")
    server.serve_forever()