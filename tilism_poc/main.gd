extends Node

const FRAME_DIR = "user://frames/"
const LOG_PATH = "user://decision_log.jsonl"
var puppet_start: Vector3
# Plane boundaries — keep positions within visible area
const PLANE_MIN = -5.0
const PLANE_MAX = 5.0

var frame_number: int = 0
var capture_interval: float = 0.1
var capture_timer: float = 0.0
var is_recording: bool = true

# Seed is fixed per run, written to log so replay can reproduce positions
var run_seed: int = 0

var goal_position: Vector3 = Vector3.ZERO

@onready var puppet: Node3D = $World/Puppet
@onready var goal: MeshInstance3D = $World/Goal

func _ready():
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	
	# Generate seed from current time - fixed for this run
	run_seed = int(Time.get_unix_time_from_system())
	seed(run_seed)
	
	# Random start position for puppet
	puppet_start = Vector3(
		randf_range(-2.0, 2.0),
		1.0,
		randf_range(-2.0, 2.0)
	)
	puppet.position = puppet_start
	
	# Random goal position - ensure it is not too close to puppet start
	var min_distance = 3.0
	var attempts = 0
	while attempts < 100:
		goal_position = Vector3(
			randf_range(-2.0, 2.0),
			1.0,
			randf_range(-2.0, 2.0)
		)
		if puppet_start.distance_to(goal_position) >= min_distance:
			break
		attempts += 1
	
	goal.position = goal_position
	
	# Write run header to log - replay reads this to restore positions
	var header = {
		"type": "run_header",
		"seed": run_seed,
		"puppet_start": {
			"x": puppet_start.x,
			"y": puppet_start.y,
			"z": puppet_start.z
		},
		"goal_position": {
			"x": goal_position.x,
			"y": goal_position.y,
			"z": goal_position.z
		},
		"timestamp": Time.get_unix_time_from_system()
	}
	write_log(header)
	
	print("Run seed: ", run_seed)
	print("Puppet start: ", puppet_start)
	print("Goal position: ", goal_position)
	print("Frame output: ", ProjectSettings.globalize_path(FRAME_DIR))
	print("Log output: ", ProjectSettings.globalize_path(LOG_PATH))

func _process(delta: float):
	capture_timer += delta
	if is_recording and capture_timer >= capture_interval:
		capture_timer = 0.0
		capture_frame()
	
	# Check if puppet has reached goal
	var distance_to_goal = puppet.position.distance_to(goal_position)
	if distance_to_goal < 0.8 and is_recording:
		print("GOAL REACHED at frame ", frame_number)
		is_recording = false
		write_log({
			"type": "goal_reached",
			"frame": frame_number,
			"distance": distance_to_goal,
			"timestamp": Time.get_unix_time_from_system()
		})
		# Stop the MCP server from polling
		get_node("MCPServer").stop_polling()
func capture_frame():
	var viewport = get_viewport()
	var img: Image = viewport.get_texture().get_image()
	var filename = FRAME_DIR + "frame_%05d.png" % frame_number
	img.save_png(ProjectSettings.globalize_path(filename))
	frame_number += 1

func move_puppet(dx: float, dz: float) -> Dictionary:
	# Scale factor makes each move more visible
	var scale = 1.0
	var new_x = clamp(puppet.position.x + (dx * scale), PLANE_MIN, PLANE_MAX)
	var new_z = clamp(puppet.position.z + (dz * scale), PLANE_MIN, PLANE_MAX)
	print("Moving from (", puppet.position.x, ",", puppet.position.z, ") to (", new_x, ",", new_z, ")")
	puppet.position.x = new_x
	puppet.position.z = new_z
	
	var distance_to_goal = puppet.position.distance_to(goal_position)
	
	var result = {
		"type": "decision",
		"action": "move",
		"dx": dx,
		"dz": dz,
		"position": {
			"x": puppet.position.x,
			"y": puppet.position.y,
			"z": puppet.position.z
		},
		"distance_to_goal": distance_to_goal,
		"goal": {
			"x": goal_position.x,
			"y": goal_position.y,
			"z": goal_position.z
		},
		"frame": frame_number,
		"timestamp": Time.get_unix_time_from_system()
	}
	write_log(result)
	return result

func stop_puppet() -> Dictionary:
	var distance_to_goal = puppet.position.distance_to(goal_position)
	var result = {
		"type": "decision",
		"action": "stop",
		"position": {
			"x": puppet.position.x,
			"y": puppet.position.y,
			"z": puppet.position.z
		},
		"distance_to_goal": distance_to_goal,
		"goal": {
			"x": goal_position.x,
			"y": goal_position.y,
			"z": goal_position.z
		},
		"frame": frame_number,
		"timestamp": Time.get_unix_time_from_system()
	}
	write_log(result)
	print("Stop called, distance to goal: ", distance_to_goal)
	return result
	
func write_log(entry: Dictionary):
	var path = ProjectSettings.globalize_path(LOG_PATH)
	var file = FileAccess.open(path, FileAccess.WRITE_READ)
	if file == null:
		print("LOG ERROR: ", FileAccess.get_open_error())
		return
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()
