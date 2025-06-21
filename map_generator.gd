extends Node3D

const ROOM_SIZE = Vector3(12, 4, 10)
const ROOM_SPACING = 2.0

var rooms = []
var room_types = ["reactor", "cafeteria", "filtration", "security", "defence", "bunks", "disinfectant"]

func _ready():
	print("MapGenerator ready")

func generate_base_layout():
	print("=== GENERATING BASE LAYOUT ===")
	clear_existing_rooms()
	await get_tree().process_frame
	generate_rooms()
	await get_tree().process_frame
	create_spawn_areas()
	print("=== BASE LAYOUT GENERATION COMPLETE ===")

func clear_existing_rooms():
	print("Clearing existing rooms...")
	for child in get_children():
		child.queue_free()
	rooms.clear()

func generate_rooms():
	print("Generating rooms...")
	var grid_positions = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, -1)
	]
	for i in range(min(room_types.size(), grid_positions.size())):
		var room_type = room_types[i]
		var grid_pos = grid_positions[i]
		create_room(room_type, grid_pos)

func create_room(room_type: String, grid_pos: Vector3):
	var room_node = Node3D.new()
	room_node.name = room_type + "_room"
	var world_pos = Vector3(
		grid_pos.x * (ROOM_SIZE.x + ROOM_SPACING),
		0,
		grid_pos.z * (ROOM_SIZE.z + ROOM_SPACING)
	)
	room_node.position = world_pos
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = ROOM_SIZE
	mesh_instance.mesh = box_mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5)
	mesh_instance.material_override = material
	room_node.add_child(mesh_instance)
	if is_inside_tree():
		add_child(room_node)
		rooms.append({"type": room_type, "position": world_pos, "node": room_node})
		print("Created ", room_type, " room at ", world_pos)
	else:
		print("ERROR: MapGenerator not in scene tree, cannot add room ", room_type)
		room_node.queue_free()

func create_spawn_areas():
	print("Creating spawn areas...")
	create_human_spawn_area()
	create_alien_spawn_area()

func create_human_spawn_area():
	print("Creating human spawn area...")
	var spawn_area = Area3D.new()
	spawn_area.name = "HumanSpawnArea"
	spawn_area.position = Vector3(-25, 0, 0)
	spawn_area.add_to_group("human_spawn_area")
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(10, 5, 10)
	collision_shape.shape = box_shape
	spawn_area.add_child(collision_shape)
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(10, 0.2, 10)
	mesh_instance.mesh = box_mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.GREEN
	material.emission_enabled = true
	material.emission = Color.GREEN * 0.3
	mesh_instance.material_override = material
	spawn_area.add_child(mesh_instance)
	if is_inside_tree():
		add_child(spawn_area)
		print("Human spawn area created at ", spawn_area.position)
	else:
		print("ERROR: MapGenerator not in scene tree, cannot add human spawn area")
		spawn_area.queue_free()

func create_alien_spawn_area():
	print("Creating alien spawn area...")
	var spawn_area = Area3D.new()
	spawn_area.name = "AlienSpawnArea"
	spawn_area.position = Vector3(25, 0, 0)
	spawn_area.add_to_group("alien_spawn_area")
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(10, 5, 10)
	collision_shape.shape = box_shape
	spawn_area.add_child(collision_shape)
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(10, 0.2, 10)
	mesh_instance.mesh = box_mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.RED
	material.emission_enabled = true
	material.emission = Color.RED * 0.3
	mesh_instance.material_override = material
	spawn_area.add_child(mesh_instance)
	if is_inside_tree():
		add_child(spawn_area)
		print("Alien spawn area created at ", spawn_area.position)
	else:
		print("ERROR: MapGenerator not in scene tree, cannot add alien spawn area")
		spawn_area.queue_free()
