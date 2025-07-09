extends CharacterBody3D

@export var speed: float = 5.0
@export var jump_velocity: float = 5.0
@export var player_type: String = "alien"  # "human" or "alien"

# Mouse look settings
@export var mouse_sensitivity: float = 0.002
@export var vertical_look_limit: float = 90.0

@onready var camera_pivot = $CameraPivot
@onready var camera = $CameraPivot/Camera3D

var is_network_ready: bool = false
var setup_complete: bool = false

@rpc("any_peer", "call_local", "unreliable")
func sync_state(pos: Vector3, vel: Vector3):
	if not is_multiplayer_authority():
		global_transform.origin = pos
		velocity = vel

func _ready():
	print("Player _ready() called for ", name, " with authority ", get_multiplayer_authority())
	add_to_group("players")
	
	# Set team-specific visuals
	_setup_visuals()
	
	# Wait for proper scene setup
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Setup camera and controls
	_setup_camera_and_controls()
	
	# Wait a bit more for network stability
	await get_tree().create_timer(0.5).timeout
	is_network_ready = true
	setup_complete = true
	
	print("Player setup complete for ", name, " (authority: ", get_multiplayer_authority(), ", local: ", is_multiplayer_authority(), ")")

func _setup_visuals():
	var mesh_instance = get_node_or_null("MeshInstance3D")
	if mesh_instance:
		var material = StandardMaterial3D.new()
		material.albedo_color = Color.BLUE if player_type == "human" else Color.RED
		mesh_instance.material_override = material
		print("Set visual for ", player_type, " player")
	else:
		print("Warning: No MeshInstance3D found for player ", player_type)

func _setup_camera_and_controls():
	# Try to find camera components with error handling
	if not camera_pivot:
		camera_pivot = get_node_or_null("CameraPivot")
		if not camera_pivot:
			print("ERROR: CameraPivot not found for player ", get_multiplayer_authority())
			return
	
	if not camera:
		camera = get_node_or_null("CameraPivot/Camera3D")
		if not camera:
			print("ERROR: Camera3D not found for player ", get_multiplayer_authority())
			return
	
	print("Setting up camera for player ", get_multiplayer_authority(), " (is_authority: ", is_multiplayer_authority(), ")")
	
	if is_multiplayer_authority():
		print("This is the local player (", player_type, ") - activating camera")
		camera.current = true
		
		# Set mouse mode with a small delay to ensure scene is ready
		call_deferred("_set_mouse_mode")
	else:
		print("This is a remote player (", player_type, ") - deactivating camera")
		camera.current = false

func _set_mouse_mode():
	if is_multiplayer_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		print("Mouse captured for local player")

func _input(event):
	if not setup_complete or not is_multiplayer_authority():
		return
	
	if event is InputEventMouseMotion:
		_handle_mouse_look(event)

func _handle_mouse_look(event: InputEventMouseMotion):
	if not camera_pivot:
		return
		
	# Horizontal rotation (Y-axis)
	rotate_y(-event.relative.x * mouse_sensitivity)
	
	# Vertical rotation (X-axis) - constrained
	camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
	var current_rotation = camera_pivot.rotation_degrees.x
	current_rotation = clamp(current_rotation, -vertical_look_limit, vertical_look_limit)
	camera_pivot.rotation_degrees.x = current_rotation

func _physics_process(delta):
	if not setup_complete or not is_multiplayer_authority():
		return
	
	process_input(delta)
	
	# Only sync if we have a valid multiplayer setup and peers
	if is_network_ready and can_use_rpc():
		sync_state.rpc(global_transform.origin, velocity)

func can_use_rpc() -> bool:
	return (multiplayer and 
			multiplayer.has_multiplayer_peer() and 
			get_multiplayer_authority() != 0 and
			multiplayer.get_peers().size() > 0)

func process_input(delta):
	# Handle escape key for mouse toggle
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Handle movement
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

func is_player() -> bool:
	return true
