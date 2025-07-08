# GameManager.gd
extends Node

# These will be null initially since the game scene isn't loaded yet
var map_generator: Node3D
var multiplayer_spawner: MultiplayerSpawner

var game_started = false
var player_teams = {}  # Store player ID -> team assignments
var game_scene_loaded = false
var players = {}  # Store player_id -> player_instance references


func _ready():
	print("*** GAME MANAGER READY (PRELOADED) ***")
	print("GameManager is preloaded and waiting...")
	add_to_group("game_manager")
	# Debug: Catch RPC errors
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# Connect to the global game signal manager
	if GameSignals:
		GameSignals.game_start_requested.connect(_on_game_start_requested)
		print("Connected to GameSignals.game_start_requested")
	
	# Listen for when the game scene is actually loaded
	get_tree().connect("tree_changed", _check_game_scene_loaded)
	
	print("GameManager preloaded, waiting for game start signal...")

func _on_peer_connected(id):
	print("Peer connected: ", id)
	print("Current scene children: ", get_tree().current_scene.get_children())
	
func _on_peer_disconnected(id):
	print("Peer disconnected: ", id)

func _check_game_scene_loaded():
	# Check if we're now in the game scene and can find our nodes
	if not game_scene_loaded:
		# Try different ways to find the nodes
		
		# Method 1: Try relative paths (your original)
		map_generator = get_node_or_null("../MapGenerator")
		multiplayer_spawner = get_node_or_null("../MultiplayerSpawner")
		
		# Method 2: If that fails, try from scene root
		if not map_generator:
			var scene_root = get_tree().current_scene
			if scene_root:
				map_generator = scene_root.get_node_or_null("MapGenerator")
		
		if not multiplayer_spawner:
			var scene_root = get_tree().current_scene
			if scene_root:
				multiplayer_spawner = scene_root.get_node_or_null("MultiplayerSpawner")
		
		# Method 3: Search everywhere
		if not map_generator:
			var all_nodes = get_tree().get_nodes_in_group("map_generator")
			if all_nodes.size() > 0:
				map_generator = all_nodes[0]
		
		# Check if we found valid nodes (not null objects)
		var map_gen_valid = map_generator != null and is_instance_valid(map_generator)
		var spawner_valid = multiplayer_spawner != null and is_instance_valid(multiplayer_spawner)
		
		if map_gen_valid and spawner_valid:
			game_scene_loaded = true
			print("Game scene detected as loaded, components found")
			print("MapGenerator found:", map_gen_valid)
			print("MultiplayerSpawner found:", spawner_valid)
		else:
			print("Still looking for components... MapGen:", map_gen_valid, " Spawner:", spawner_valid)
			# Reset null objects to prevent <Object#null> errors
			if map_generator and not is_instance_valid(map_generator):
				map_generator = null
			if multiplayer_spawner and not is_instance_valid(multiplayer_spawner):
				multiplayer_spawner = null
				
func _on_game_start_requested():
	print("*** GAME START SIGNAL RECEIVED ***")
	if not game_started:
		# Simple approach: just wait a bit and then start
		print("Starting game in 1 second...")
		await get_tree().create_timer(1.0).timeout
		
		# Double-check our components are ready
		_check_game_scene_loaded()
		
		if game_scene_loaded:
			print("Components ready, starting game!")
			start_game()
		else:
			print("ERROR: Game components still not ready after waiting!")
			print("MapGenerator:", get_node_or_null("../MapGenerator"))
			print("MultiplayerSpawner:", get_node_or_null("../MultiplayerSpawner"))
	else:
		print("Game already started!")

func await_game_scene_and_start():
	print("Checking if game scene is ready...")
	# Keep checking until the game scene is loaded
	while not game_scene_loaded:
		await get_tree().process_frame
		_check_game_scene_loaded()
		print("Still waiting for game scene... game_scene_loaded:", game_scene_loaded)
	
	print("Game scene ready, starting game...")
	start_game()

func start_game():
	print("*** START GAME CALLED ***")
	print("Game is starting...")
	game_started = true
	
	# Debug: Check if our components are still valid
	print("MapGenerator valid:", map_generator != null)
	print("MultiplayerSpawner valid:", multiplayer_spawner != null)
	
	# First generate the map
	await generate_game_map()
	
	# Then setup multiplayer
	setup_multiplayer_game()
	
	# Assign teams and spawn players
	await get_tree().process_frame  # Wait for map to be fully ready
	assign_player_teams()
	spawn_all_players()

func generate_game_map():
	print("Generating game map...")
	if map_generator:
		print("Found MapGenerator, generating layout...")
		await map_generator.generate_base_layout()
		print("Map generation complete!")
	else:
		print("ERROR: MapGenerator not found!")

func setup_multiplayer_game():
	print("Setting up multiplayer game...")
	
	if multiplayer_spawner:
		print("Found MultiplayerSpawner")
	else:
		print("WARNING: MultiplayerSpawner not found")
	
	print("Game setup complete!")

func assign_player_teams():
	print("Assigning player teams...")
	
	# Get all connected players
	var players = multiplayer.get_peers()
	players.append(1)  # Include host
	
	# Simple team assignment - alternate between human and alien
	for i in range(players.size()):
		var player_id = players[i]
		var team = "human" if i % 2 == 0 else "alien"
		player_teams[player_id] = team
		print("Player ", player_id, " assigned to ", team, " team")

func spawn_all_players():
	print("Spawning all players...")
	
	# Only server should spawn players
	if not multiplayer.is_server():
		print("Only server spawns players")
		return
	
	for player_id in player_teams.keys():
		var team = player_teams[player_id]
		await spawn_player(player_id, team)
		# Small delay between spawns to ensure proper synchronization
		await get_tree().create_timer(0.1).timeout

func spawn_player(player_id: int, team: String):
	print("Spawning player ", player_id, " on team ", team)
	
	# Only the server should spawn players
	if not multiplayer.is_server():
		print("Client received spawn request, ignoring (server handles spawning)")
		return
	
	var spawn_area = get_spawn_area_for_team(team)
	if not spawn_area:
		print("ERROR: No spawn area found for team ", team)
		return
	
	var spawn_position = get_random_spawn_position(spawn_area)
	print("Spawn position for player ", player_id, ": ", spawn_position)
	
	# Check if player already exists
	var existing_player = get_tree().current_scene.get_node_or_null("Player_" + str(player_id))
	if existing_player:
		print("Player ", player_id, " already exists, skipping spawn")
		return
	
	# Load and instantiate the player scene
	var player_scene = preload("res://Scenes/player.tscn")
	var player_instance = player_scene.instantiate()
	
	# Set the player's position
	player_instance.global_position = spawn_position
	
	# Set the player's team/type
	player_instance.player_type = team
	
	# Give the player a unique name BEFORE adding to scene
	player_instance.name = "Player_" + str(player_id)
	
	# Set multiplayer authority BEFORE adding to scene
	player_instance.set_multiplayer_authority(player_id)
	
	# Add to the scene
	add_child(player_instance, true)
	
	# Wait a frame to ensure everything is synchronized
	await get_tree().process_frame
	
	print("Player ", player_id, " spawned successfully at ", spawn_position, " for team ", team)
	
	players[player_id] = player_instance

func get_spawn_area_for_team(team: String) -> Area3D:
	var group_name = team + "_spawn_area"
	var spawn_areas = get_tree().get_nodes_in_group(group_name)
	
	if spawn_areas.size() > 0:
		return spawn_areas[0] as Area3D
	else:
		print("ERROR: No spawn area found for group ", group_name)
		return null

func get_random_spawn_position(spawn_area: Area3D) -> Vector3:
	if not spawn_area:
		return Vector3.ZERO
	
	# Get the collision shape to determine spawn bounds
	var collision_shape = spawn_area.get_child(0) as CollisionShape3D
	if collision_shape and collision_shape.shape is BoxShape3D:
		var box_shape = collision_shape.shape as BoxShape3D
		var bounds = box_shape.size
		
		# Generate random position within the spawn area bounds
		var random_x = randf_range(-bounds.x/2, bounds.x/2)
		var random_z = randf_range(-bounds.z/2, bounds.z/2)
		
		return spawn_area.global_position + Vector3(random_x, 1, random_z)
	
	# Fallback to spawn area position
	return spawn_area.global_position + Vector3(0, 1, 0)

func get_player_team(player_id: int) -> String:
	return player_teams.get(player_id, "human")  # Default to human if not found
