extends Node

const FRAME_DIR = "user://frames/"
const LOG_PATH = "res://decision_log.jsonl"
const RUNS_CSV = "res://runs.csv"
const DECISIONS_CSV = "res://decisions.csv"

var puppet_start: Vector3
const PLANE_MIN = -5.0
const PLANE_MAX = 5.0

var run_start_time: float = 0.0
var frame_number: int = 0
var capture_interval: float = 0.1
var capture_timer: float = 0.0
var is_recording: bool = true

var run_seed: int = 0
var goal_position: Vector3 = Vector3.ZERO

@onready var puppet: Node3D = $World/Puppet
@onready var goal: MeshInstance3D = $World/Goal


func _ready():
	run_start_time = Time.get_unix_time_from_system()

	# Clear log at start of each run
	var file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file:
		file.close()

	_init_csv_files()

	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(FRAME_DIR))

	run_seed = int(Time.get_unix_time_from_system())
	seed(run_seed)

	puppet_start = Vector3(
		randf_range(-3.0, 3.0),
		1.0,
		randf_range(-3.0, 3.0)
	)
	puppet.position = puppet_start

	var min_distance = 4.0
	var attempts = 0
	while attempts < 100:
		goal_position = Vector3(
			randf_range(-3.0, 3.0),
			1.0,
			randf_range(-3.0, 3.0)
		)
		if puppet_start.distance_to(goal_position) >= min_distance:
			break
		attempts += 1

	goal.position = goal_position

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
	print("Starting distance: ", "%.2f" % puppet_start.distance_to(goal_position))
	print("Frame output: ", ProjectSettings.globalize_path(FRAME_DIR))
	print("Log output: ", LOG_PATH)


func _init_csv_files():
	if not FileAccess.file_exists(RUNS_CSV):
		var f = FileAccess.open(RUNS_CSV, FileAccess.WRITE)
		if f:
			f.store_line("run_id,timestamp,seed,starting_distance,decision_count,inference_time_total,inference_time_mean,inference_time_min,inference_time_max,recording_duration,goal_reached,good_moves,bad_moves,good_move_rate,final_distance,path_efficiency")
			f.close()

	if not FileAccess.file_exists(DECISIONS_CSV):
		var f = FileAccess.open(DECISIONS_CSV, FileAccess.WRITE)
		if f:
			f.store_line("run_id,decision_number,inference_time,distance_before,distance_after,dx,dz,good_move")
			f.close()


func _get_next_run_id() -> int:
	if not FileAccess.file_exists(RUNS_CSV):
		return 1
	var f = FileAccess.open(RUNS_CSV, FileAccess.READ)
	if f == null:
		return 1
	var count = 0
	while not f.eof_reached():
		var line = f.get_line().strip_edges()
		if line != "":
			count += 1
	f.close()
	# Subtract 1 for header row
	return count


func _process(delta: float):
	capture_timer += delta
	if is_recording and capture_timer >= capture_interval:
		capture_timer = 0.0
		capture_frame()

	var distance_to_goal = puppet.position.distance_to(goal_position)
	if distance_to_goal < 0.8 and is_recording:
		print("GOAL REACHED at frame ", frame_number)
		is_recording = false

		# Read decisions from log
		var total_inference_time = 0.0
		var inference_time_min = 999.0
		var inference_time_max = 0.0
		var decision_count = 0
		var good_moves = 0
		var bad_moves = 0
		var total_distance_traveled = 0.0
		var decision_list = []

		var log_file = FileAccess.open(LOG_PATH, FileAccess.READ)
		if log_file:
			while not log_file.eof_reached():
				var line = log_file.get_line().strip_edges()
				if line == "":
					continue
				var json = JSON.new()
				if json.parse(line) == OK:
					var entry = json.get_data()
					if entry.get("type") == "decision":
						decision_list.append(entry)
						var it = entry.get("inference_time", 0.0)
						total_inference_time += it
						if it < inference_time_min:
							inference_time_min = it
						if it > inference_time_max:
							inference_time_max = it
						decision_count += 1
			log_file.close()

		# Compute navigation metrics
		for i in range(decision_list.size()):
			var d = decision_list[i]
			var dist_after = d.get("distance_to_goal", 0.0)
			var dist_before = 0.0
			if i == 0:
				dist_before = puppet_start.distance_to(goal_position)
			else:
				dist_before = decision_list[i - 1].get("distance_to_goal", 0.0)
			var change = dist_after - dist_before
			if change < -0.05:
				good_moves += 1
			elif change > 0.05:
				bad_moves += 1
			total_distance_traveled += abs(change)

		var recording_duration = Time.get_unix_time_from_system() - run_start_time
		var starting_distance = puppet_start.distance_to(goal_position)
		var inference_time_mean = total_inference_time / decision_count if decision_count > 0 else 0.0
		var good_move_rate = float(good_moves) / float(decision_count) if decision_count > 0 else 0.0
		var path_efficiency = starting_distance / total_distance_traveled if total_distance_traveled > 0 else 0.0
		var run_id = _get_next_run_id()

		# Write to log
		write_log({
			"type": "goal_reached",
			"frame": frame_number,
			"distance": distance_to_goal,
			"timestamp": Time.get_unix_time_from_system()
		})
		write_log({
			"type": "run_summary",
			"decision_count": decision_count,
			"total_inference_time": total_inference_time,
			"recording_duration": recording_duration,
			"timestamp": Time.get_unix_time_from_system()
		})

		# Write to runs.csv
		var runs_file = FileAccess.open(RUNS_CSV, FileAccess.READ_WRITE)
		if runs_file:
			runs_file.seek_end()
			runs_file.store_line("%d,%d,%d,%.4f,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%s,%d,%d,%.4f,%.4f,%.4f" % [
				run_id,
				int(Time.get_unix_time_from_system()),
				run_seed,
				starting_distance,
				decision_count,
				total_inference_time,
				inference_time_mean,
				inference_time_min,
				inference_time_max,
				recording_duration,
				"true",
				good_moves,
				bad_moves,
				good_move_rate,
				distance_to_goal,
				path_efficiency
			])
			runs_file.close()

		# Write to decisions.csv
		var dec_file = FileAccess.open(DECISIONS_CSV, FileAccess.READ_WRITE)
		if dec_file:
			dec_file.seek_end()
			for i in range(decision_list.size()):
				var d = decision_list[i]
				var dist_after = d.get("distance_to_goal", 0.0)
				var dist_before = 0.0
				if i == 0:
					dist_before = puppet_start.distance_to(goal_position)
				else:
					dist_before = decision_list[i - 1].get("distance_to_goal", 0.0)
				var change = dist_after - dist_before
				var good = "true" if change < -0.05 else "false"
				dec_file.store_line("%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%s" % [
					run_id,
					i + 1,
					d.get("inference_time", 0.0),
					dist_before,
					dist_after,
					d.get("dx", 0.0),
					d.get("dz", 0.0),
					good
				])
			dec_file.close()

		# Console summary
		print("--- RUN SUMMARY ---")
		print("Run ID:              ", run_id)
		print("Decisions:           ", decision_count)
		print("Good moves:          ", good_moves, " (", "%.0f" % (good_move_rate * 100), "%)")
		print("Bad moves:           ", bad_moves)
		print("Total inference:     ", "%.2f" % total_inference_time, "s")
		print("Mean inference:      ", "%.2f" % inference_time_mean, "s")
		print("Min inference:       ", "%.2f" % inference_time_min, "s")
		print("Max inference:       ", "%.2f" % inference_time_max, "s")
		print("Recording duration:  ", "%.2f" % recording_duration, "s")
		print("Path efficiency:     ", "%.2f" % path_efficiency)

		get_node("MCPServer").stop_polling()


func capture_frame():
	var viewport = get_viewport()
	var img: Image = viewport.get_texture().get_image()
	var filename = FRAME_DIR + "frame_%05d.png" % frame_number
	img.save_png(ProjectSettings.globalize_path(filename))
	frame_number += 1


func move_puppet(dx: float, dz: float, inference_time: float = 0.0) -> Dictionary:
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
		"inference_time": inference_time,
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
	var file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if file == null:
			print("LOG ERROR: ", FileAccess.get_open_error())
			return
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()
