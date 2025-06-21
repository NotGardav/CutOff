extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 5.0
@export var player_type: String = "human"  # "human" or "alien"

# Mouse look settings
@export var mouse_sensitivity: float = 0.002
@export var vertical_look_limit: float = 90.0

@onready var camera_pivot = $CameraPivot
@onready var camera = $CameraPivot/Camera3D
@onready var mesh_instance = $MeshInstance3D

var is_network_ready: bool = false
var last_sync_time: float = 0.0
const SYNC_INTERVAL: float = 0.016  # 60 FPS sync rate for smooth movement

@rpc("any_peer", "unreliable")
func sync_state(pos: Vector3, vel: Vector3, rot_y: float, rot_x: float):
	if not is_multiplayer_authority():
		# Smooth interpolation for remote players
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "global_position", pos, 0.1)
		tween.tween_property(self, "rotation:y", rot_y, 0.1)
		if camera_pivot:
			tween.tween_property(camera_pivot, "rotation:x", rot_x, 0.1)
		velocity = vel

func _ready():
	add_to_group("players")
	print("Player _ready called for: ", get_multiplayer_authority(), " (", player_type, ")")
	
	# Set team-specific visuals
	setup_visuals()
	
	# Setup based on authority
	if is_multiplayer_authority():
		print("Setting up LOCAL player: ", get_multiplayer_authority())
		# This is the local player
		set_physics_process(true)
		set_process_input(true)
	else:
		print("Setting up REMOTE player: ", get_multiplayer_authority())
		# This is a remote player
		set_physics_process(false)
		set_process_input(false)
	
	# Setup camera after a frame to ensure everything is ready
	await get_tree().process_frame
	setup_camera()
	
	# Mark as network ready
	await get_tree().create_timer(0.5).timeout
	is_network_ready = true
	print("Player network ready: ", get_multiplayer_authority(), " (", player_type, ")")

func setup_visuals():
	if mesh_instance:
		var material = StandardMaterial3D.new()
		if player_type == "human":
			material.albedo_color = Color.BLUE
		else:  # alien
			material.albedo_color = Color.RED
		material.albedo_color.a = 0.9
		mesh_instance.material_override = material
		print("Set material for ", player_type, " player: ", get_multiplayer_authority())
	else:
		print("Warning: No MeshInstance3D found for player ", player_type)

func setup_camera():
	if not camera or not camera_pivot:
		print("ERROR: Camera or CameraPivot not found for player ", get_multiplayer_authority())
		return
	
	if is_multiplayer_authority():
		print("Setting up camera for LOCAL player: ", get_multiplayer_authority())
		camera.current = true
		camera.fov = 70.0
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		print("Disabling camera for REMOTE player: ", get_multiplayer_authority())
		camera.current = false
		# Make sure remote players are visible
		visible = true

func _input(event):
	if not is_multiplayer_authority():
		return
	
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera_pivot:
			camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
			var current_rotation = camera_pivot.rotation_degrees.x
			current_rotation = clamp(current_rotation, -vertical_look_limit, vertical_look_limit)
			camera_pivot.rotation_degrees.x = current_rotation
		# Sync immediately on mouse movement for responsive feel
		if is_network_ready:
			sync_state_to_peers()

func _physics_process(delta):
	if not is_multiplayer_authority():
		return
	
	process_input(delta)
	
	# Sync state every frame for smooth movement
	if is_network_ready:
		sync_state_to_peers()

func process_input(delta):
	# Toggle mouse capture
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Movement input
	var input_dir = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.z -= 1
	if Input.is_action_pressed("move_backward"):
		input_dir.z += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	
	input_dir = input_dir.normalized()
	var direction = (transform.basis * input_dir).normalized()
	
	# Apply movement
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	
	# Handle jumping and gravity
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	
	move_and_slide()

func sync_state_to_peers():
	if not is_network_ready:
		return
	
	var multiplayer_api = get_tree().get_multiplayer()
	if not multiplayer_api or not multiplayer_api.has_multiplayer_peer():
		return
	
	if multiplayer_api.get_peers().size() > 0:
		var cam_rot_x = camera_pivot.rotation.x if camera_pivot else 0.0
		rpc("sync_state", global_transform.origin, velocity, rotation.y, cam_rot_x)

func is_player() -> bool:
	return true
