# GameManager.gd
extends Node

# These will be null initially since the game scene isn't loaded yet
var map_generator: Node3D
var multiplayer_spawner: MultiplayerSpawner

var game_started = false
var player_teams = {}  # Store player ID -> team assignments
var game_scene_loaded = false
var players = {}  # Store player_id -> player_instance references
var clients_ready = {}  # Track which clients are ready for game start

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
	print("Current scene: ", get_tree().current_scene.name if get_tree().current_scene else "None")
	
func _on_peer_disconnected(id):
	print("Peer disconnected: ", id)
	# Clean up disconnected player
	if id in players:
		if players[id] and is_instance_valid(players[id]):
			players[id].queue_free()
		players.erase(id)
	if id in clients_ready:
		clients_ready.erase(id)
	if id in player_teams:
		player_teams.erase(id)

func _check_game_scene_loaded():
	if not game_scene_loaded:
		var scene_root = get_tree().current_scene
		if not scene_root:
			print("No current scene found")
			return
		
		print("Checking scene: ", scene_root.name)
		print("Scene children: ", scene_root.get_children().map(func(child): return child.name))
		
		# Try to find components in the scene root
		map_generator = scene_root.get_node_or_null("MapGenerator")
		multiplayer_spawner = scene_root.get_node_or_null("MultiplayerSpawner")
		
		# If not found in root, search in groups
		if not map_generator:
			var map_nodes = get_tree().get_nodes_in_group("map_generator")
			if map_nodes.size() > 0:
				map_generator = map_nodes[0]
		
		if not multiplayer_spawner:
			var spawner_nodes = get_tree().get_nodes_in_group("multiplayer_spawner")
			if spawner_nodes.size() > 0:
				multiplayer_spawner = spawner_nodes[0]
		
		# Validate components
		var map_gen_valid = map_generator != null and is_instance_valid(map_generator)
		var spawner_valid = multiplayer_spawner != null and is_instance_valid(multiplayer_spawner)
		
		if map_gen_valid and spawner_valid:
			game_scene_loaded = true
			print("Game scene loaded successfully")
			print("MapGenerator: ", map_generator.name)
			print("MultiplayerSpawner: ", multiplayer_spawner.name)
		else:
			print("Components not ready - MapGen: ", map_gen_valid, " Spawner: ", spawner_valid)
			# Clean up invalid references
			if map_generator and not is_instance_valid(map_generator):
				map_generator = null
			if multiplayer_spawner and not is_instance_valid(multiplayer_spawner):
				multiplayer_spawner = null

func _on_game_start_requested():
	print("*** GAME START SIGNAL RECEIVED ***")
	if not game_started:
		# Wait a bit and then start
		print("Starting game in 1 second...")
		await get_tree().create_timer(1.0).timeout
		
		# Double-check our components are ready
		_check_game_scene_loaded()
		
		if game_scene_loaded:
			print("Components ready, starting game!")
			start_game()
		else:
			print("ERROR: Game components still not ready after waiting!")
			print("Current scene: ", get_tree().current_scene.name if get_tree().current_scene else "None")
			print("MapGenerator found: ", map_generator != null)
			print("MultiplayerSpawner found: ", multiplayer_spawner != null)
	else:
		print("Game already started!")

func start_game():
	print("*** START GAME CALLED ***")
	print("Game is starting...")
	game_started = true
	
	# Debug: Check if our components are still valid
	print("MapGenerator valid:", map_generator != null and is_instance_valid(map_generator))
	print("MultiplayerSpawner valid:", multiplayer_spawner != null and is_instance_valid(multiplayer_spawner))
	
	# First generate the map
	await generate_game_map()
	
	# Then setup multiplayer
	setup_multiplayer_game()
	
	# Wait for all clients to be ready before spawning
	print("Waiting for all clients to be ready...")
	rpc("client_scene_ready")
	
	# If this is a client, we're done here - server will handle the rest
	if not multiplayer.is_server():
		print("Client finished initialization, waiting for server")
		return

@rpc("any_peer", "call_local", "reliable")
func client_scene_ready():
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:  # Local call (from server)
		sender_id = multiplayer.get_unique_id()
	
	clients_ready[sender_id] = true
	print("Client ", sender_id, " is ready for game")
	
	# Only server should check if all clients are ready
	if multiplayer.is_server():
		var all_peers = multiplayer.get_peers()
		all_peers.append(1)  # Include host
		
		print("Checking if all clients ready. Expected: ", all_peers, " Ready: ", clients_ready.keys())
		
		var all_ready = true
		for peer_id in all_peers:
			if not clients_ready.get(peer_id, false):
				print("Still waiting for client: ", peer_id)
				all_ready = false
				break
		
		if all_ready:
			print("All clients ready, starting game logic")
			assign_player_teams()
			await spawn_all_players()

func generate_game_map():
	print("Generating game map...")
	if map_generator and is_instance_valid(map_generator):
		print("Found MapGenerator, generating layout...")
		await map_generator.generate_base_layout()
		print("Map generation complete!")
	else:
		print("ERROR: MapGenerator not found or invalid!")

func setup_multiplayer_game():
	print("Setting up multiplayer game...")
	
	if multiplayer_spawner and is_instance_valid(multiplayer_spawner):
		print("Found MultiplayerSpawner: ", multiplayer_spawner.name)
		print("Spawn path: ", multiplayer_spawner.spawn_path)
	else:
		print("WARNING: MultiplayerSpawner not found or invalid")
	
	print("Game setup complete!")

func assign_player_teams():
	print("Assigning player teams...")
	
	# Get all connected players
	var connected_players = multiplayer.get_peers()
	connected_players.append(1)  # Include host
	
	# Simple team assignment - alternate between human and alien
	for i in range(connected_players.size()):
		var player_id = connected_players[i]
		var team = "human" if i % 2 == 0 else "alien"
		player_teams[player_id] = team
		print("Player ", player_id, " assigned to ", team, " team")

func spawn_all_players():
	print("Spawning all players...")
	
	# Only server should spawn players
	if not multiplayer.is_server():
		print("Only server spawns players")
		return
	
	# Wait a frame to ensure everything is synchronized
	await get_tree().process_frame
	
	for player_id in player_teams.keys():
		var team = player_teams[player_id]
		await spawn_player(player_id, team)
		
		# Small delay between spawns to ensure proper synchronization
		await get_tree().create_timer(0.1).timeout
	
	print("All players spawned successfully!")

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
	var scene_root = get_tree().current_scene
	var existing_player = scene_root.get_node_or_null("Player_" + str(player_id))
	if existing_player:
		print("Player ", player_id, " already exists, skipping spawn")
		return
	
	# Determine if this is the local player
	var is_local = player_id == multiplayer.get_unique_id()
	print("This is ", "the local player" if is_local else "a remote player", " (", team, ").")
	
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
	
	# Add to the scene root (not GameManager)
	scene_root.add_child(player_instance, true)
	
	# Wait a frame to ensure everything is synchronized
	await get_tree().process_frame
	
	print("Player ", player_id, " spawned successfully at ", spawn_position, " for team ", team)
	
	# Store reference
	players[player_id] = player_instance
	
	# Send notification to all clients
	rpc("on_player_spawned", player_id, team, spawn_position)

@rpc("any_peer", "call_local", "reliable")
func on_player_spawned(player_id: int, team: String, position: Vector3):
	print("Game player network ready: ", player_id, " (", team, ")")
	# Additional client-side setup can go here if needed

func get_spawn_area_for_team(team: String) -> Area3D:
	var group_name = team + "_spawn_area"
	var spawn_areas = get_tree().get_nodes_in_group(group_name)
	
	if spawn_areas.size() > 0:
		return spawn_areas[0] as Area3D
	else:
		print("ERROR: No spawn area found for group ", group_name)
		print("Available groups: ", get_tree().get_nodes_in_group("human_spawn_area").size(), " human, ", get_tree().get_nodes_in_group("alien_spawn_area").size(), " alien")
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

# Helper function to get a player instance by ID
func get_player(player_id: int) -> Node:
	return players.get(player_id, null)

# Helper function to get all players
func get_all_players() -> Array:
	return players.values()

# Helper function to get players by team
func get_players_by_team(team: String) -> Array:
	var team_players = []
	for player_id in players.keys():
		if get_player_team(player_id) == team:
			team_players.append(players[player_id])
	return team_players
