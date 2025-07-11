extends Node3D

const ROOM_SIZE = Vector3(12, 4, 10)
const ROOM_SPACING = 2.0
const CORRIDOR_WIDTH = 3.0
const CORRIDOR_HEIGHT = 3.0

var rooms = []
var corridors = []
var room_types = ["reactor", "cafeteria", "filtration", "security", "defence", "bunks", "disinfectant", "storage", "medical", "engineering", "communication", "lab"]

# Procedural generation parameters
var map_seed: int = 0
var rng: RandomNumberGenerator
var grid_size = Vector2i(5, 5)  # 5x5 grid maximum
var min_rooms = 6
var max_rooms = 12
var connection_chance = 0.7  # Chance for additional connections beyond minimum spanning tree

# Room generation weights for different room types
var room_weights = {
	"reactor": 1.0,
	"cafeteria": 0.8,
	"filtration": 0.9,
	"security": 0.7,
	"defence": 0.6,
	"bunks": 0.8,
	"disinfectant": 0.5,
	"storage": 1.2,
	"medical": 0.7,
	"engineering": 0.8,
	"communication": 0.4,
	"lab": 0.6
}

func _ready():
	print("Enhanced MapGenerator ready")
	add_to_group("map_generator")
	rng = RandomNumberGenerator.new()

func generate_base_layout(seed: int = 0):
	print("=== GENERATING PROCEDURAL BASE LAYOUT ===")
	
	# Set up random seed
	if seed == 0:
		map_seed = randi()
	else:
		map_seed = seed
	rng.seed = map_seed
	print("Using seed: ", map_seed)
	
	clear_existing_rooms()
	await get_tree().process_frame
	
	# Generate procedural layout
	var room_positions = generate_room_positions()
	var room_connections = generate_room_connections(room_positions)
	
	generate_rooms_procedural(room_positions)
	await get_tree().process_frame
	
	generate_corridors(room_connections)
	await get_tree().process_frame
	
	create_spawn_areas()
	print("=== PROCEDURAL BASE LAYOUT GENERATION COMPLETE ===")

func clear_existing_rooms():
	print("Clearing existing rooms...")
	for child in get_children():
		child.queue_free()
	rooms.clear()
	corridors.clear()

func generate_room_positions() -> Array:
	print("Generating room positions...")
	var positions = []
	var num_rooms = rng.randi_range(min_rooms, max_rooms)
	var occupied_grid = {}
	
	# Always place a central room first
	var center_pos = Vector2i(grid_size.x / 2, grid_size.y / 2)
	positions.append(center_pos)
	occupied_grid[center_pos] = true
	
	# Generate remaining rooms using different algorithms
	var remaining_rooms = num_rooms - 1
	
	# 60% clustered growth, 40% random placement
	var clustered_rooms = int(remaining_rooms * 0.6)
	var random_rooms = remaining_rooms - clustered_rooms
	
	# Clustered growth - rooms tend to be near existing rooms
	for i in range(clustered_rooms):
		var new_pos = find_clustered_position(positions, occupied_grid)
		if new_pos != Vector2i(-1, -1):
			positions.append(new_pos)
			occupied_grid[new_pos] = true
	
	# Random placement for remaining rooms
	for i in range(random_rooms):
		var new_pos = find_random_position(occupied_grid)
		if new_pos != Vector2i(-1, -1):
			positions.append(new_pos)
			occupied_grid[new_pos] = true
	
	print("Generated ", positions.size(), " room positions")
	return positions

func find_clustered_position(existing_positions: Array, occupied: Dictionary) -> Vector2i:
	var attempts = 50
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	
	for attempt in range(attempts):
		var base_pos = existing_positions[rng.randi() % existing_positions.size()]
		var direction = directions[rng.randi() % directions.size()]
		var distance = rng.randi_range(1, 2)  # 1-2 tiles away
		var new_pos = base_pos + direction * distance
		
		if is_valid_grid_position(new_pos) and not occupied.has(new_pos):
			return new_pos
	
	return Vector2i(-1, -1)

func find_random_position(occupied: Dictionary) -> Vector2i:
	var attempts = 100
	for attempt in range(attempts):
		var pos = Vector2i(rng.randi() % grid_size.x, rng.randi() % grid_size.y)
		if not occupied.has(pos):
			return pos
	return Vector2i(-1, -1)

func is_valid_grid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y

func generate_room_connections(room_positions: Array) -> Array:
	print("Generating room connections...")
	var connections = []
	
	# Create minimum spanning tree to ensure all rooms are connected
	var mst_connections = create_minimum_spanning_tree(room_positions)
	connections.append_array(mst_connections)
	
	# Add additional connections for more interesting layouts
	for i in range(room_positions.size()):
		for j in range(i + 1, room_positions.size()):
			var pos1 = room_positions[i]
			var pos2 = room_positions[j]
			
			# Skip if already connected
			if are_rooms_connected(pos1, pos2, connections):
				continue
				
			# Calculate distance
			var distance = pos1.distance_to(pos2)
			
			# Higher chance for closer rooms, lower for distant ones
			var base_chance = connection_chance
			var distance_modifier = 1.0 / (1.0 + distance * 0.5)
			var final_chance = base_chance * distance_modifier
			
			if rng.randf() < final_chance:
				connections.append([pos1, pos2])
	
	print("Generated ", connections.size(), " connections")
	return connections

func create_minimum_spanning_tree(positions: Array) -> Array:
	if positions.size() <= 1:
		return []
	
	var mst = []
	var connected = [positions[0]]
	var unconnected = positions.slice(1)
	
	while unconnected.size() > 0:
		var min_distance = INF
		var best_connection = null
		
		for connected_pos in connected:
			for unconnected_pos in unconnected:
				var distance = connected_pos.distance_to(unconnected_pos)
				if distance < min_distance:
					min_distance = distance
					best_connection = [connected_pos, unconnected_pos]
		
		if best_connection:
			mst.append(best_connection)
			connected.append(best_connection[1])
			unconnected.erase(best_connection[1])
	
	return mst

func are_rooms_connected(pos1: Vector2i, pos2: Vector2i, connections: Array) -> bool:
	for connection in connections:
		if (connection[0] == pos1 and connection[1] == pos2) or (connection[0] == pos2 and connection[1] == pos1):
			return true
	return false

func generate_rooms_procedural(room_positions: Array):
	print("Generating rooms procedurally...")
	
	# Select room types based on weights and ensure key rooms are present
	var selected_room_types = select_room_types(room_positions.size())
	
	for i in range(room_positions.size()):
		var grid_pos = room_positions[i]
		var room_type = selected_room_types[i]
		
		# Add some variation to room sizes
		var size_variation = Vector3(
			rng.randf_range(0.8, 1.2),
			rng.randf_range(0.8, 1.2),
			rng.randf_range(0.8, 1.2)
		)
		var room_size = ROOM_SIZE * size_variation
		
		create_room_procedural(room_type, Vector3(grid_pos.x, 0, grid_pos.y), room_size)

func select_room_types(num_rooms: int) -> Array:
	var selected = []
	var essential_rooms = ["reactor", "cafeteria", "security"]  # Always include these
	
	# Add essential rooms first
	for room_type in essential_rooms:
		if selected.size() < num_rooms:
			selected.append(room_type)
	
	# Fill remaining slots with weighted random selection
	var available_types = room_types.duplicate()
	
	while selected.size() < num_rooms:
		var room_type = weighted_random_room_type(available_types)
		selected.append(room_type)
	
	# Shuffle to randomize positions
	selected.shuffle()
	return selected

func weighted_random_room_type(available_types: Array) -> String:
	var total_weight = 0.0
	for room_type in available_types:
		total_weight += room_weights.get(room_type, 1.0)
	
	var random_value = rng.randf() * total_weight
	var current_weight = 0.0
	
	for room_type in available_types:
		current_weight += room_weights.get(room_type, 1.0)
		if random_value <= current_weight:
			return room_type
	
	return available_types[0]  # Fallback

func create_room_procedural(room_type: String, grid_pos: Vector3, room_size: Vector3):
	var room_node = Node3D.new()
	room_node.name = room_type + "_room"
	var world_pos = Vector3(
		grid_pos.x * (ROOM_SIZE.x + ROOM_SPACING),
		0,
		grid_pos.z * (ROOM_SIZE.z + ROOM_SPACING)
	)
	room_node.position = world_pos
	
	# Create visual mesh with room-specific colors
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = room_size
	mesh_instance.mesh = box_mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = get_room_color(room_type)
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.2
	mesh_instance.material_override = material
	room_node.add_child(mesh_instance)
	
	# Add collision
	var static_body = StaticBody3D.new()
	static_body.name = "Collision"
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = room_size
	collision_shape.shape = box_shape
	static_body.add_child(collision_shape)
	room_node.add_child(static_body)
	
	# Add room-specific details
	add_room_details(room_node, room_type)
	
	if is_inside_tree():
		add_child(room_node)
		rooms.append({"type": room_type, "position": world_pos, "node": room_node, "size": room_size})
		print("Created ", room_type, " room at ", world_pos)
	else:
		print("ERROR: MapGenerator not in scene tree, cannot add room ", room_type)
		room_node.queue_free()

func get_room_color(room_type: String) -> Color:
	var colors = {
		"reactor": Color.ORANGE,
		"cafeteria": Color.YELLOW,
		"filtration": Color.CYAN,
		"security": Color.RED,
		"defence": Color.DARK_RED,
		"bunks": Color.BLUE,
		"disinfectant": Color.MAGENTA,
		"storage": Color.BROWN,
		"medical": Color.WHITE,
		"engineering": Color.GRAY,
		"communication": Color.PURPLE,
		"lab": Color.GREEN
	}
	return colors.get(room_type, Color.GRAY)

func add_room_details(room_node: Node3D, room_type: String):
	# Add some procedural details based on room type
	match room_type:
		"reactor":
			add_glowing_core(room_node)
		"cafeteria":
			add_tables(room_node)
		"security":
			add_security_panels(room_node)
		"medical":
			add_medical_equipment(room_node)
		# Add more room-specific details as needed

func add_glowing_core(room_node: Node3D):
	var core = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	core.mesh = sphere_mesh
	core.position = Vector3(0, 0, 0)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.ORANGE
	material.emission_enabled = true
	material.emission = Color.ORANGE * 0.8
	core.material_override = material
	
	room_node.add_child(core)

func add_tables(room_node: Node3D):
	for i in range(rng.randi_range(2, 4)):
		var table = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(2, 0.8, 1)
		table.mesh = box_mesh
		table.position = Vector3(
			rng.randf_range(-4, 4),
			-1.5,
			rng.randf_range(-3, 3)
		)
		room_node.add_child(table)

func add_security_panels(room_node: Node3D):
	var panel = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.2, 2, 1)
	panel.mesh = box_mesh
	panel.position = Vector3(5.5, 0, 0)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.RED
	material.emission_enabled = true
	material.emission = Color.RED * 0.5
	panel.material_override = material
	
	room_node.add_child(panel)

func add_medical_equipment(room_node: Node3D):
	var equipment = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.5
	cylinder_mesh.bottom_radius = 0.5
	cylinder_mesh.height = 1.5
	equipment.mesh = cylinder_mesh
	equipment.position = Vector3(0, -1, 0)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.emission_enabled = true
	material.emission = Color.WHITE * 0.3
	equipment.material_override = material
	
	room_node.add_child(equipment)

func generate_corridors(connections: Array):
	print("Generating corridors...")
	for connection in connections:
		var pos1 = connection[0]
		var pos2 = connection[1]
		create_corridor(pos1, pos2)

func create_corridor(grid_pos1: Vector2i, grid_pos2: Vector2i):
	var world_pos1 = Vector3(
		grid_pos1.x * (ROOM_SIZE.x + ROOM_SPACING),
		0,
		grid_pos1.y * (ROOM_SIZE.z + ROOM_SPACING)
	)
	var world_pos2 = Vector3(
		grid_pos2.x * (ROOM_SIZE.x + ROOM_SPACING),
		0,
		grid_pos2.y * (ROOM_SIZE.z + ROOM_SPACING)
	)
	
	# Create L-shaped corridor (horizontal then vertical)
	if world_pos1.x != world_pos2.x:
		create_corridor_segment(world_pos1, Vector3(world_pos2.x, world_pos1.y, world_pos1.z), true)
	if world_pos1.z != world_pos2.z:
		create_corridor_segment(Vector3(world_pos2.x, world_pos1.y, world_pos1.z), world_pos2, false)

func create_corridor_segment(start_pos: Vector3, end_pos: Vector3, is_horizontal: bool):
	var corridor_node = Node3D.new()
	corridor_node.name = "Corridor"
	
	var center_pos = (start_pos + end_pos) / 2
	var length = start_pos.distance_to(end_pos)
	
	if length < 0.1:  # Skip very short segments
		return
	
	corridor_node.position = center_pos
	
	# Create visual mesh
	var mesh_instance = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	if is_horizontal:
		box_mesh.size = Vector3(length, CORRIDOR_HEIGHT, CORRIDOR_WIDTH)
	else:
		box_mesh.size = Vector3(CORRIDOR_WIDTH, CORRIDOR_HEIGHT, length)
	
	mesh_instance.mesh = box_mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.3, 0.3)
	mesh_instance.material_override = material
	corridor_node.add_child(mesh_instance)
	
	# Add collision
	var static_body = StaticBody3D.new()
	static_body.name = "Collision"
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = box_mesh.size
	collision_shape.shape = box_shape
	static_body.add_child(collision_shape)
	corridor_node.add_child(static_body)
	
	if is_inside_tree():
		add_child(corridor_node)
		corridors.append(corridor_node)
		print("Created corridor segment at ", center_pos)
	else:
		corridor_node.queue_free()

func create_spawn_areas():
	print("Creating spawn areas...")
	create_human_spawn_area()
	create_alien_spawn_area()

func create_human_spawn_area():
	print("Creating human spawn area...")
	var spawn_area = Area3D.new()
	spawn_area.name = "HumanSpawnArea"
	spawn_area.position = Vector3(-30, 0, 0)
	spawn_area.add_to_group("human_spawn_area")
	
	# Area3D collision for detection
	var area_collision = CollisionShape3D.new()
	var area_box_shape = BoxShape3D.new()
	area_box_shape.size = Vector3(10, 5, 10)
	area_collision.shape = area_box_shape
	spawn_area.add_child(area_collision)
	
	# Solid platform
	var platform_body = StaticBody3D.new()
	platform_body.name = "Platform"
	var platform_collision = CollisionShape3D.new()
	var platform_shape = BoxShape3D.new()
	platform_shape.size = Vector3(10, 0.2, 10)
	platform_collision.shape = platform_shape
	platform_body.add_child(platform_collision)
	spawn_area.add_child(platform_body)
	
	# Visual mesh
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
		spawn_area.queue_free()

func create_alien_spawn_area():
	print("Creating alien spawn area...")
	var spawn_area = Area3D.new()
	spawn_area.name = "AlienSpawnArea"
	spawn_area.position = Vector3(30, 0, 0)
	spawn_area.add_to_group("alien_spawn_area")
	
	# Area3D collision for detection
	var area_collision = CollisionShape3D.new()
	var area_box_shape = BoxShape3D.new()
	area_box_shape.size = Vector3(10, 5, 10)
	area_collision.shape = area_box_shape
	spawn_area.add_child(area_collision)
	
	# Solid platform
	var platform_body = StaticBody3D.new()
	platform_body.name = "Platform"
	var platform_collision = CollisionShape3D.new()
	var platform_shape = BoxShape3D.new()
	platform_shape.size = Vector3(10, 0.2, 10)
	platform_collision.shape = platform_shape
	platform_body.add_child(platform_collision)
	spawn_area.add_child(platform_body)
	
	# Visual mesh
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
		spawn_area.queue_free()

# Utility functions for external access
func get_room_at_position(world_pos: Vector3) -> Dictionary:
	for room in rooms:
		var room_pos = room.position
		var room_size = room.get("size", ROOM_SIZE)
		if (abs(world_pos.x - room_pos.x) < room_size.x / 2 and 
			abs(world_pos.z - room_pos.z) < room_size.z / 2):
			return room
	return {}

func get_random_room_position() -> Vector3:
	if rooms.size() > 0:
		return rooms[rng.randi() % rooms.size()].position
	return Vector3.ZERO

func get_current_seed() -> int:
	return map_seed
