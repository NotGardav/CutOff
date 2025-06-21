# StartGameButton.gd
extends StaticBody3D

@onready var mesh_instance = $MeshInstance3D
@onready var interaction_area = $InteractionArea
# Fix: Create the InteractionPrompt node directly instead of trying to find it
var interaction_prompt: Label3D

var original_scale: Vector3
var button_material: StandardMaterial3D
var players_in_range = []
var local_player_in_range = false  # Track if LOCAL player is in range
var interact_key = KEY_E

signal game_start_requested

func _ready():
	# Connect area signals
	interaction_area.body_entered.connect(_on_player_entered)
	interaction_area.body_exited.connect(_on_player_exited)
	
	original_scale = scale
	setup_button_appearance()
	setup_interaction_area()
	setup_labels()

func setup_interaction_area():
	# Create interaction area (larger sphere around button)
	var area_collision = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 3.0  # Player can interact from 3 units away
	area_collision.shape = sphere_shape
	interaction_area.add_child(area_collision)

func setup_labels():
	var button_label = Label3D.new()
	button_label.text = "START GAME"
	button_label.position = Vector3(0, 0.4, 0)
	button_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(button_label)
	
	# Fix: Create the interaction prompt properly
	interaction_prompt = Label3D.new()
	interaction_prompt.position = Vector3(0, 1.0, 0)
	interaction_prompt.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	interaction_prompt.modulate = Color.YELLOW
	add_child(interaction_prompt)
	
	# Hide prompt initially
	interaction_prompt.visible = false

func setup_button_appearance():
	# Create a box mesh for the button
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2, 0.5, 1)
	mesh_instance.mesh = box_mesh
	
	# Create glowing material
	button_material = StandardMaterial3D.new()
	button_material.albedo_color = Color(0.2, 0.8, 0.2)
	button_material.emission_enabled = true
	button_material.emission = Color(0.1, 0.4, 0.1)
	button_material.metallic = 0.3
	button_material.roughness = 0.1
	mesh_instance.material_override = button_material
	
	# Setup collision for the button itself
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(2, 0.5, 1)
	collision_shape.shape = box_shape
	add_child(collision_shape)

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == interact_key and local_player_in_range:
			interact_with_button()

func _on_player_entered(body):
	if body.has_method("is_player") or body.is_in_group("players"):
		players_in_range.append(body)
		
		# Check if this is the LOCAL player (the one with authority on this client)
		if body.is_multiplayer_authority():
			local_player_in_range = true
			show_interaction_prompt()
			button_hover_effect(true)  # Only show effects for local player

func _on_player_exited(body):
	if body in players_in_range:
		players_in_range.erase(body)
		
		# Check if the local player left
		if body.is_multiplayer_authority():
			local_player_in_range = false
			hide_interaction_prompt()
			button_hover_effect(false)  # Only hide effects for local player

func show_interaction_prompt():
	if interaction_prompt:
		interaction_prompt.visible = true
		interaction_prompt.text = "Press E to Start Game"

func hide_interaction_prompt():
	if interaction_prompt:
		interaction_prompt.visible = false

func button_hover_effect(is_active: bool):
	if is_active:
		create_tween().tween_property(self, "scale", original_scale * 1.05, 0.2)
		button_material.emission = Color(0.2, 0.6, 0.2)
	else:
		create_tween().tween_property(self, "scale", original_scale, 0.2)
		button_material.emission = Color(0.1, 0.4, 0.1)

func interact_with_button():
	# Button press animation
	var tween = create_tween()
	tween.tween_property(self, "scale", original_scale * 0.95, 0.1)
	tween.tween_property(self, "scale", original_scale * 1.05, 0.1)
	
	# Flash effect
	button_material.emission = Color(0.5, 1.0, 0.5)
	create_tween().tween_property(button_material, "emission", Color(0.2, 0.6, 0.2), 0.5)
	
	print("Player interacted with Start Game button!")
	emit_signal("game_start_requested")
