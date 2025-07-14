@tool
class_name DungeonGenerator3DIntegrated
extends DungeonGenerator3D

var map_seed: int = 0
var rna: RandomNumberGenerator

signal generation_complete # Add this signal

func _ready():
	print("DungeonGenerator3DIntegrated ready")
	add_to_group("map_generator")  # Preserve MapGenerator's group for lobby system
	rna = RandomNumberGenerator.new()
	
	# Retain MapGenerator's activation logic
	if generate_on_ready and not Engine.is_editor_hint():
		generate_base_layout()

func generate_base_layout(seed: int = 0):
	print("=== GENERATING PROCEDURAL BASE LAYOUT ===")
	
	# Set up random seed as in MapGenerator
	if seed == 0:
		map_seed = randi()
	else:
		map_seed = seed
	rna.seed = map_seed
	print("Using seed: ", map_seed)
	
	# Clear existing rooms
	cleanup_and_reset_dungeon_generator()
	
	# Trigger DungeonGenerator3D's generation
	generate(map_seed)
	
	# Wait for generation to complete
	if is_currently_generating:
		await done_generating
	
	# Ensure scene tree is updated
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Create spawn areas after generation
	create_spawn_areas()
	
	emit_signal("generation_complete") # Emit signal
	print("=== PROCEDURAL BASE LAYOUT GENERATION COMPLETE ===")

# Utility functions for GameManager compatibility
func get_room_at_position(world_pos: Vector3) -> Dictionary:
	# Convert world position to grid position by dividing by voxel_scale and flooring
	var grid_pos = Vector3i(
		floor(world_pos.x / voxel_scale.x),
		floor(world_pos.y / voxel_scale.y),
		floor(world_pos.z / voxel_scale.z)
	)
	var room = get_room_at_pos(grid_pos)
	if room:
		return {
			"type": room.name,
			"position": room.get_position_from_grid_pos(room.get_grid_pos()),
			"node": room,
			"size": Vector3(room.get_grid_aabbi(false).size) * voxel_scale
		}
	return {}

func get_random_room_position() -> Vector3:
	var rooms = get_all_placed_and_preplaced_rooms()
	if rooms.size() > 0:
		var room = rooms[rna.randi() % rooms.size()]
		var grid_pos = room.get_grid_pos()
		var aabbi = room.get_grid_aabbi(false)
		var random_offset = Vector3(
			rna.randf_range(-aabbi.size.x / 2.0, aabbi.size.x / 2.0) * voxel_scale.x,
			1.0,  # Slightly above floor
			rna.randf_range(-aabbi.size.z / 2.0, aabbi.size.z / 2.0) * voxel_scale.z
		)
		return room.get_position_from_grid_pos(grid_pos) + random_offset
	return Vector3.ZERO

func get_current_seed() -> int:
	return map_seed

# Spawn area creation to match MapGenerator
func create_spawn_areas():
	print("Creating spawn areas...")
	#create_human_spawn_area() # Uncomment these
	#create_alien_spawn_area() # Uncomment these

func create_human_spawn_area():
	print("Creating human spawn area...")
	var spawn_area = Area3D.new()
	spawn_area.name = "HumanSpawnArea"
	# Position to the left of the dungeon, aligned with grid
	var world_pos = Vector3(-30, 0, 0)  # Default fallback position
	if rooms_container and rooms_container.get_child_count() > 0:
		var aabbi = get_grid_aabbi()
		var offset = Vector3(-(aabbi.size.x + 2) * voxel_scale.x, 0, 0)
		world_pos = rooms_container.global_position + offset
	spawn_area.position = world_pos
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
		spawn_area.owner = owner if owner else self
		print("Human spawn area created at ", spawn_area.position)
	else:
		spawn_area.queue_free()

func create_alien_spawn_area():
	print("Creating alien spawn area...")
	var spawn_area = Area3D.new()
	spawn_area.name = "AlienSpawnArea"
	# Position to the right of the dungeon, aligned with grid
	var world_pos = Vector3(30, 0, 0)  # Default fallback position
	if rooms_container and rooms_container.get_child_count() > 0:
		var aabbi = get_grid_aabbi()
		var offset = Vector3((aabbi.size.x + 2) * voxel_scale.x, 0, 0)
		world_pos = rooms_container.global_position + offset
	spawn_area.position = world_pos
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
		spawn_area.owner = owner if owner else self
		print("Alien spawn area created at ", spawn_area.position)
	else:
		spawn_area.queue_free()
