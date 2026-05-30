extends Node

const LOG_PATH = "res://decision_log.jsonl"
const PLANE_MIN = -5.0
const PLANE_MAX = 5.0

@onready var puppet: Node3D = $World/Puppet
@onready var goal: MeshInstance3D = $World/Goal

# Log data
var decisions: Array = []
var run_header: Dictionary = {}
var total_inference_time: float = 0.0
var recording_duration: float = 0.0

# Playback state
var current_decision: int = 0
var playback_timer: float = 0.0
var playback_speed: float = 1.0  # seconds between moves at 1x
var step_interval: float = 1.0
var is_playing: bool = false
var replay_start_time: float = 0.0
var replay_done: bool = false

# UI nodes
var speed_label: Label
var stats_label: Label
var slider: HSlider
var status_label: Label

func _ready():
	_load_log()
	_build_ui()
	_restore_start_state()
	replay_start_time = Time.get_unix_time_from_system()
	is_playing = true
	print("Replay starting — ", decisions.size(), " decisions to replay")
	print("Total inference time recorded: ", "%.2f" % total_inference_time, "s")

func _load_log():
	var path = ProjectSettings.globalize_path(LOG_PATH)
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("ERROR: Could not open log at ", path)
		return

	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line == "":
			continue
		var json = JSON.new()
		if json.parse(line) == OK:
			var entry = json.get_data()
			match entry.get("type", ""):
				"run_header":
					run_header = entry
				"decision":
					decisions.append(entry)
				"run_summary":
					total_inference_time = entry.get("total_inference_time", 0.0)
					recording_duration = entry.get("recording_duration", 0.0)
	file.close()
	print("Loaded ", decisions.size(), " decisions from log")

func _restore_start_state():
	if run_header.is_empty():
		print("ERROR: No run_header found in log")
		return

	var ps = run_header["puppet_start"]
	var gp = run_header["goal_position"]

	puppet.position = Vector3(ps["x"], ps["y"], ps["z"])
	goal.position = Vector3(gp["x"], gp["y"], gp["z"])
	print("Restored puppet start: ", puppet.position)
	print("Restored goal position: ", goal.position)

func _build_ui():
	# Root canvas layer
	var canvas = CanvasLayer.new()
	add_child(canvas)

	# Background panel
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(320, 180)
	canvas.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "TILISME — REPLAY"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# Stats
	stats_label = Label.new()
	stats_label.text = "Loading..."
	vbox.add_child(stats_label)

	# Speed label
	speed_label = Label.new()
	speed_label.text = "Speed: 1.0x  (interval: 1.00s)"
	vbox.add_child(speed_label)

	# Slider
	slider = HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 10.0
	slider.step = 0.1
	slider.value = 1.0
	slider.custom_minimum_size = Vector2(280, 24)
	slider.value_changed.connect(_on_speed_changed)
	vbox.add_child(slider)

	# Slider range labels
	var range_box = HBoxContainer.new()
	var min_label = Label.new()
	min_label.text = "0.1x (slow)"
	min_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var max_label = Label.new()
	max_label.text = "10x (fast)"
	max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	max_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_box.add_child(min_label)
	range_box.add_child(max_label)
	vbox.add_child(range_box)

	# Status
	status_label = Label.new()
	status_label.text = "Playing..."
	vbox.add_child(status_label)

func _on_speed_changed(value: float):
	playback_speed = value
	# At 1x, one move per second. At 10x, one move per 0.1s. At 0.1x, one move per 10s.
	step_interval = 1.0 / playback_speed
	speed_label.text = "Speed: %.1fx  (interval: %.2fs)" % [playback_speed, step_interval]

func _process(delta: float):
	if not is_playing or replay_done:
		return

	_update_stats_label()

	playback_timer += delta
	if playback_timer >= step_interval:
		playback_timer = 0.0
		_step()

func _step():
	if current_decision >= decisions.size():
		_finish_replay()
		return

	var entry = decisions[current_decision]
	var dx: float = entry.get("dx", 0.0)
	var dz: float = entry.get("dz", 0.0)

	var new_x = clamp(puppet.position.x + dx, PLANE_MIN, PLANE_MAX)
	var new_z = clamp(puppet.position.z + dz, PLANE_MIN, PLANE_MAX)
	puppet.position.x = new_x
	puppet.position.z = new_z

	print("Replay step ", current_decision + 1, "/", decisions.size(),
		  " → dx=", dx, " dz=", dz,
		  " pos=(", "%.2f" % puppet.position.x, ",", "%.2f" % puppet.position.z, ")")

	current_decision += 1

func _update_stats_label():
	var elapsed = Time.get_unix_time_from_system() - replay_start_time
	stats_label.text = (
		"Decision: %d / %d\n" % [current_decision, decisions.size()] +
		"Replay elapsed: %.2fs\n" % elapsed +
		"Original inference: %.2fs\n" % total_inference_time +
		"Original recording: %.2fs" % recording_duration
	)

func _finish_replay():
	replay_done = true
	is_playing = false
	var replay_duration = Time.get_unix_time_from_system() - replay_start_time

	status_label.text = "COMPLETE"
	stats_label.text = (
		"Decisions replayed: %d\n" % decisions.size() +
		"Replay duration: %.3fs\n" % replay_duration +
		"Original inference: %.2fs\n" % total_inference_time +
		"Original recording: %.2fs\n" % recording_duration +
		"Speedup: %.1fx" % (total_inference_time / replay_duration)
	)

	print("--- REPLAY COMPLETE ---")
	print("Decisions replayed: ", decisions.size())
	print("Replay duration:     ", "%.3f" % replay_duration, "s")
	print("Original inference:  ", "%.2f" % total_inference_time, "s")
	print("Original recording:  ", "%.2f" % recording_duration, "s")
	print("Speedup:             ", "%.1f" % (total_inference_time / replay_duration), "x")
