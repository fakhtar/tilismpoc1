extends Node

const POLL_URL = "http://127.0.0.1:9876/poll"
const RESULT_URL = "http://127.0.0.1:9876/result"
const FRAME_URL = "http://127.0.0.1:9876/frame"
const POLL_INTERVAL = 0.5

var poll_timer: float = 0.0
var http_poll: HTTPRequest
var http_result: HTTPRequest
var http_frame: HTTPRequest
var waiting_for_response: bool = false

@onready var main: Node = get_parent()

func _ready():
	http_poll = HTTPRequest.new()
	add_child(http_poll)
	http_poll.request_completed.connect(_on_poll_completed)
	
	http_result = HTTPRequest.new()
	add_child(http_result)
	http_result.request_completed.connect(_on_result_completed)
	
	http_frame = HTTPRequest.new()
	add_child(http_frame)
	http_frame.request_completed.connect(_on_frame_sent)
	
	print("MCP Client polling ", POLL_URL)

func _process(delta: float):
	if waiting_for_response:
		return
	poll_timer += delta
	if poll_timer >= POLL_INTERVAL:
		poll_timer = 0.0
		_push_frame_then_poll()

func _push_frame_then_poll():
	print("Attempting frame capture...")
	var vp = get_viewport()
	var img = vp.get_texture().get_image()
	print("Image size: ", img.get_width(), "x", img.get_height())
	
	img.resize(336, 336)
	
	var jpeg_bytes: PackedByteArray = img.save_jpg_to_buffer(0.5)
	print("JPEG bytes: ", jpeg_bytes.size())
	
	if jpeg_bytes.is_empty():
		print("Frame capture failed - polling anyway")
		waiting_for_response = true
		_poll_for_command()
		return
	
	print("Sending frame to Python...")
	waiting_for_response = true
	
	var headers = PackedStringArray([
		"Content-Type: image/jpeg",
		"Content-Length: " + str(jpeg_bytes.size())
	])
	
	var err = http_frame.request_raw(
		FRAME_URL,
		headers,
		HTTPClient.METHOD_POST,
		jpeg_bytes
	)
	print("Frame request started, error code: ", err)

func _on_frame_sent(result, response_code, headers, body):
	if response_code != 200:
		print("Frame send error: ", response_code)
	waiting_for_response = false
	_poll_for_command()

func _poll_for_command():
	waiting_for_response = true
	http_poll.request(POLL_URL)

func _on_poll_completed(result, response_code, headers, body):
	waiting_for_response = false
	
	if response_code == 204:
		return
	
	if response_code != 200:
		print("Poll error: ", response_code)
		return
	
	var raw = body.get_string_from_utf8()
	
	var json = JSON.new()
	var err = json.parse(raw)
	if err != OK:
		print("JSON parse error on: ", raw)
		return
	
	var msg = json.get_data()
	print("MCP received tool call: ", msg["tool"], " | params: ", msg["params"])
	
	var tool_name: String = msg["tool"]
	var params: Dictionary = msg["params"]
	
	match tool_name:
		"move_forward":
			var amount: float = float(params.get("amount", 1.0))
			var call_result = main.move_puppet_forward(amount)
			print("Result: ", call_result)
			_send_result(msg.get("id", 0), call_result)
		_:
			print("Unknown tool: ", tool_name)

func _send_result(id, result: Dictionary):
	var response = JSON.stringify({"id": id, "status": "ok", "result": result})
	var headers = ["Content-Type: application/json"]
	http_result.request(RESULT_URL, headers, HTTPClient.METHOD_POST, response)

func _on_result_completed(result, response_code, headers, body):
	pass
