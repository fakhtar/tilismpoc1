extends Node

const FRAME_DIR = "user://frames/"
const LOG_PATH = "user://decision_log.jsonl"

var frame_number: int = 0
var capture_interval: float = 0.1  # seconds between frame captures
var capture_timer: float = 0.0
var is_recording: bool = true

@onready var camera: Camera3D = $Camera3D
@onready var puppet: Node3D = $World/Puppet
@onready var mcp_server: Node = $MCPServer

func _ready():
	# Create frames directory
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	print("Frame output: ", ProjectSettings.globalize_path(FRAME_DIR))
	print("Log output: ", ProjectSettings.globalize_path(LOG_PATH))

func _process(delta: float):
	capture_timer += delta
	if is_recording and capture_timer >= capture_interval:
		capture_timer = 0.0
		capture_frame()

func capture_frame():
	# Capture viewport as image
	var viewport = get_viewport()
	var img: Image = viewport.get_texture().get_image()
	var filename = FRAME_DIR + "frame_%05d.png" % frame_number
	img.save_png(ProjectSettings.globalize_path(filename))
	frame_number += 1

func move_puppet_forward(amount: float) -> Dictionary:
	print("Puppet reference: ", puppet)
	print("Puppet is null: ", puppet == null)
	puppet.global_position.z -= amount # -Z is forward in Godot
	var result = {
		"action": "move_forward",
		"amount": amount,
		"new_position": {
			"x": puppet.position.x,
			"y": puppet.position.y,
			"z": puppet.position.z
		},
		"frame": frame_number
	}
	write_log(result)
	return result

func write_log(entry: Dictionary):
	var path = ProjectSettings.globalize_path(LOG_PATH)
	var file = FileAccess.open(path, FileAccess.WRITE_READ)
	if file == null:
		print("LOG ERROR: Could not open log file, error: ", FileAccess.get_open_error())
		return
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()
	print("Log written OK")
