# GameManager.gd
extends Node

var map_generator: Node3D
var game_started = false
var game_scene_loaded = false
var is_transitioning_to_game = false
var players = {}
var clients_ready = {}
var player_teams = {}

# Map generation state
var map_generation_seed: int = 0
var map_generation_complete = {}  # Track which clients have finished map generation

# Preload player scenes
var alien_scene = preload("res://scenes/Alien.tscn")
var human_scene = preload("res://scenes/Human.tscn")

func _ready():
	print("*** GAME MANAGER READY ***")
	add_to_group("game_manager")
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	if GameSignals:
		GameSignals.game_start_requested.connect(_on_game_start_requested)
		print("Connected to GameSignals.game_start_requested")
	
	# Wait for scene to be fully ready before checking components
	call_deferred("_initialize_game_scene")

func _initialize_game_scene():
	print("Initializing game scene...")
	await get_tree().process_frame
	_check_game_scene_loaded()
	
	# If we're a client, notify server we're ready with retry logic
	if not multiplayer.is_server():
		print("Client preparing to notify server of readiness")
		_notify_server_with_retry()

func _notify_server_with_retry():
	var retry_count = 0
	var max_retries = 10
	var acknowledged = false
	
	while retry_count < max_retries and not acknowledged:
		print("Client notifying server of readiness (attempt ", retry_count + 1, ")")
		rpc_id(1, "client_ready_for_game")
		
		# Wait for acknowledgment
		await get_tree().create_timer(1.0).timeout
		
		# Check if we received acknowledgment
		if clients_ready.get(multiplayer.get_unique_id(), false):
			print("Server acknowledged client readiness")
			acknowledged = true
			break
		
		retry_count += 1
	
	if not acknowledged:
		print("ERROR: Failed to get server acknowledgment after ", max_retries, " attempts")

func _on_peer_connected(id):
	print("Peer connected: ", id)
	
func _on_peer_disconnected(id):
	print("Peer disconnected: ", id)
	_cleanup_player(id)

func _cleanup_player(id):
	if id in players:
		if players[id] and is_instance_valid(players[id]):
			players[id].queue_free()
		players.erase(id)
	if id in clients_ready:
		clients_ready.erase(id)
	if id in player_teams:
		player_teams.erase(id)
	if id in map_generation_complete:
		map_generation_complete.erase(id)

func _check_game_scene_loaded():
	if game_scene_loaded:
		return
		
	var scene_root = get_tree().current_scene
	if not scene_root:
		print("No current scene found")
		return
	
	print("Checking scene: ", scene_root.name)
	print("Client ID: ", multiplayer.get_unique_id())
	
	# Find map generator
	map_generator = scene_root.get_node_or_null("MapGenerator")
	if not map_generator:
		var map_nodes = get_tree().get_nodes_in_group("map_generator")
		if map_nodes.size() > 0:
			map_generator = map_nodes[0]
			print("Found MapGenerator in group: ", map_generator.name)
	
	if map_generator and is_instance_valid(map_generator):
		game_scene_loaded = true
		print("Game scene loaded successfully with MapGenerator")
		print("MapGenerator node path: ", map_generator.get_path())
		print("MapGenerator supports procedural generation: ", map_generator.has_method("generate_base_layout"))
		
		# Import lobby data immediately when scene is ready
		_import_lobby_data()
	else:
		print("MapGenerator not found - retrying in 0.5 seconds")
		print("Available nodes in scene:")
		for child in scene_root.get_children():
			print("  - ", child.name, " (", child.get_class(), ")")
		await get_tree().create_timer(0.5).timeout
		_check_game_scene_loaded()

func _import_lobby_data():
	print("Importing lobby data...")
	
	# Get team assignments from lobby
	var lobby_data = GameSignals.get_lobby_data()
	if "team_assignments" in lobby_data:
		player_teams = lobby_data["team_assignments"]
		print("Imported team assignments: ", player_teams)
	else:
		print("No team assignments found in lobby data")
	
	# Get player data from Globals
	if Globals.lobby_players:
		print("Found lobby players in Globals: ", Globals.lobby_players.keys())
		for player_id in Globals.lobby_players.keys():
			var player_data = Globals.lobby_players[player_id]
			player_teams[player_id] = player_data.get("team", 0)
	
	print("Final team assignments: ", player_teams)

@rpc("any_peer", "reliable")
func client_ready_for_game():
	var sender_id = multiplayer.get_remote_sender_id()
	print("*** CLIENT READY MESSAGE RECEIVED ***")
	print("From client: ", sender_id)
	print("Is server: ", multiplayer.is_server())
	
	if multiplayer.is_server():
		print("Server: Client ", sender_id, " is ready for game")
		clients_ready[sender_id] = true
		
		# Send acknowledgment back to client
		rpc_id(sender_id, "server_acknowledges_client_ready")
		
		_check_if_all_ready()
	else:
		print("WARNING: Non-server received client_ready_for_game from ", sender_id)

@rpc("any_peer", "reliable")
func server_acknowledges_client_ready():
	print("Server acknowledged client readiness")
	clients_ready[multiplayer.get_unique_id()] = true

func _check_if_all_ready():
	if not multiplayer.is_server():
		return
		
	var expected_peers = multiplayer.get_peers()
	expected_peers.append(multiplayer.get_unique_id())
	
	print("*** CHECKING IF ALL READY ***")
	print("Expected peers: ", expected_peers)
	print("Clients ready: ", clients_ready)
	
	# Mark server as ready automatically
	clients_ready[multiplayer.get_unique_id()] = true
	
	for peer_id in expected_peers:
		if not clients_ready.get(peer_id, false):
			print("Still waiting for: ", peer_id)
			return
	
	print("All clients ready - starting game!")
	_start_game_synchronized()

func _on_game_start_requested():
	print("*** GAME START SIGNAL RECEIVED ***")
	
	if game_started or is_transitioning_to_game:
		print("Game already started or transitioning")
		return
	
	if not game_scene_loaded:
		print("Game scene not loaded yet, waiting...")
		await get_tree().create_timer(0.5).timeout
		_check_game_scene_loaded()
		
		if not game_scene_loaded:
			print("ERROR: Game scene still not ready!")
			return
	
	if multiplayer.is_server():
		print("Server starting game start process")
		_check_if_all_ready()
	else:
		print("Client received game start request - already notified server of readiness")

func _start_game_synchronized():
	print("*** STARTING GAME SYNCHRONIZED ***")
	is_transitioning_to_game = true
	
	# Clear any existing conflicting data
	players.clear()
	map_generation_complete.clear()
	
	# Generate a shared seed for consistent maps across all clients
	if multiplayer.is_server():
		map_generation_seed = randi()
		print("Server generated map seed: ", map_generation_seed)
	
	# Generate map on ALL clients using RPC with shared seed
	print("Requesting synchronized map generation on all clients...")
	rpc("generate_game_map_rpc", map_generation_seed)
	
	# Wait for all clients to complete map generation
	await _wait_for_all_map_generation()
	
	# Then spawn players
	await spawn_all_players()
	
	# Mark game as started
	game_started = true
	is_transitioning_to_game = false
	
	print("Game started successfully!")
	
	# Notify all clients that game is ready
	rpc("on_game_fully_ready")

func _wait_for_all_map_generation():
	print("Waiting for all clients to complete map generation...")
	
	var expected_peers = multiplayer.get_peers()
	expected_peers.append(multiplayer.get_unique_id())
	
	var max_wait_time = 30.0  # 30 seconds timeout
	var wait_time = 0.0
	var check_interval = 0.5
	
	while wait_time < max_wait_time:
		var all_complete = true
		
		for peer_id in expected_peers:
			if not map_generation_complete.get(peer_id, false):
				print("Still waiting for map generation from peer: ", peer_id)
				all_complete = false
				break
		
		if all_complete:
			print("All clients completed map generation!")
			return
		
		await get_tree().create_timer(check_interval).timeout
		wait_time += check_interval
	
	print("WARNING: Map generation timeout reached, proceeding anyway...")

@rpc("any_peer", "call_local", "reliable")
func generate_game_map_rpc(seed: int):
	print("=== GENERATING SYNCHRONIZED GAME MAP ===")
	print("Client ID: ", multiplayer.get_unique_id())
	print("Using seed: ", seed)
	print("Is server: ", multiplayer.is_server())
	
	if map_generator and is_instance_valid(map_generator):
		print("MapGenerator found, generating layout with seed...")
		
		# Check if the map generator supports seeded generation
		if map_generator.has_method("generate_base_layout"):
			await map_generator.generate_base_layout(seed)
			print("✓ Procedural map generation complete on client ", multiplayer.get_unique_id())
		else:
			# Fallback to old method if enhanced generator not available
			print("Using legacy map generation method")
			await map_generator.generate_base_layout()
		
		# Notify server that this client completed map generation
		rpc_id(1, "map_generation_complete_notification", multiplayer.get_unique_id())
		
	else:
		print("ERROR: MapGenerator not available on client ", multiplayer.get_unique_id())
		print("Attempting to find MapGenerator again...")
		
		# Try to find it again
		var scene_root = get_tree().current_scene
		if scene_root:
			map_generator = scene_root.get_node_or_null("MapGenerator")
			if not map_generator:
				var map_nodes = get_tree().get_nodes_in_group("map_generator")
				if map_nodes.size() > 0:
					map_generator = map_nodes[0]
			
			if map_generator and is_instance_valid(map_generator):
				print("Found MapGenerator on retry, generating layout...")
				if map_generator.has_method("generate_base_layout"):
					await map_generator.generate_base_layout(seed)
				else:
					await map_generator.generate_base_layout()
				print("✓ Map generation complete on client ", multiplayer.get_unique_id())
				rpc_id(1, "map_generation_complete_notification", multiplayer.get_unique_id())
			else:
				print("CRITICAL ERROR: Still no MapGenerator found on client ", multiplayer.get_unique_id())
				# Mark as complete anyway to prevent hanging
				rpc_id(1, "map_generation_complete_notification", multiplayer.get_unique_id())

@rpc("any_peer", "reliable")
func map_generation_complete_notification(client_id: int):
	if multiplayer.is_server():
		print("Server received map generation complete from client: ", client_id)
		map_generation_complete[client_id] = true
	else:
		# Clients also track their own completion
		if client_id == multiplayer.get_unique_id():
			map_generation_complete[client_id] = true

@rpc("any_peer", "call_local", "reliable")
func on_game_fully_ready():
	print("Game is fully ready!")
	
	# Optional: Add any post-game-start setup here
	if map_generator and map_generator.has_method("get_current_seed"):
		var current_seed = map_generator.get_current_seed()
		print("Current map seed: ", current_seed)

func spawn_all_players():
	print("Spawning all players...")
	
	# Get all connected peers
	var connected_players = multiplayer.get_peers()
	connected_players.append(multiplayer.get_unique_id())
	
	print("Connected players: ", connected_players)
	print("Team assignments: ", player_teams)
	
	# Let everyone spawn their own player locally, then sync positions
	for player_id in connected_players:
		var team = player_teams.get(player_id, 0)
		var player_type = "human" if team == 0 else "alien"
		var spawn_position = get_spawn_position_for_team(team)
		
		print("Spawning player ", player_id, " as ", player_type, " on team ", team)
		
		# Tell everyone (including self) to spawn this player
		rpc("spawn_player_everywhere", player_id, player_type, team, spawn_position)
		
		# Small delay between spawns to prevent issues
		await get_tree().create_timer(0.1).timeout
	
	print("All players spawned!")

@rpc("any_peer", "call_local", "reliable")
func spawn_player_everywhere(player_id: int, player_type: String, team: int, spawn_position: Vector3):
	print("Spawning player ", player_id, " as ", player_type, " locally")
	
	# Don't spawn if already exists
	if player_id in players and is_instance_valid(players[player_id]):
		print("Player ", player_id, " already exists, skipping spawn")
		return
	
	# Create player instance
	var player_scene = alien_scene if player_type == "alien" else human_scene
	var player_instance = player_scene.instantiate()
	
	# Set properties BEFORE adding to scene
	player_instance.name = "Player_" + str(player_id)
	player_instance.player_type = player_type
	
	# Add to scene first
	get_tree().current_scene.add_child(player_instance)
	
	# Wait for node to be properly added
	await get_tree().process_frame
	
	# Set authority and position AFTER adding to scene
	player_instance.set_multiplayer_authority(player_id)
	player_instance.global_position = spawn_position
	
	if not is_instance_valid(player_instance):
		print("ERROR: Player instance invalid after spawn!")
		return
	
	# Store reference
	players[player_id] = player_instance
	
	# Add to group
	if not player_instance.is_in_group("players"):
		player_instance.add_to_group("players")
	
	# Check if this is the local player
	var is_local_player = player_id == multiplayer.get_unique_id()
	print("✓ Player ", player_id, " spawned at ", spawn_position, " (local: ", is_local_player, ")")
	
	# Debug: Show current players
	var all_players = get_tree().get_nodes_in_group("players")
	print("Current players in scene:")
	for player in all_players:
		var authority = player.get_multiplayer_authority()
		var is_local = authority == multiplayer.get_unique_id()
		print("  - ", player.name, " (authority: ", authority, ", local: ", is_local, ")")

func get_spawn_position_for_team(team: int) -> Vector3:
	var team_name = "human" if team == 0 else "alien"
	var spawn_area = get_spawn_area_for_team(team_name)
	
	if spawn_area:
		return get_random_spawn_position(spawn_area)
	else:
		# Enhanced fallback positions - try to get positions from map generator
		if map_generator and map_generator.has_method("get_random_room_position"):
			var room_position = map_generator.get_random_room_position()
			if room_position != Vector3.ZERO:
				print("Using random room position for team ", team)
				return room_position + Vector3(0, 2, 0)  # Spawn above room floor
		
		# Ultimate fallback positions
		var fallback_positions = [
			Vector3(0, 2, 0),
			Vector3(5, 2, 0),
			Vector3(-5, 2, 0),
			Vector3(0, 2, 5),
			Vector3(0, 2, -5)
		]
		var index = team % fallback_positions.size()
		print("Using fallback spawn position for team ", team)
		return fallback_positions[index]

func get_spawn_area_for_team(team_name: String) -> Area3D:
	var group_name = team_name + "_spawn_area"
	var spawn_areas = get_tree().get_nodes_in_group(group_name)
	
	if spawn_areas.size() > 0:
		return spawn_areas[0] as Area3D
	else:
		print("WARNING: No spawn area found for ", group_name)
		return null

func get_random_spawn_position(spawn_area: Area3D) -> Vector3:
	if not spawn_area:
		return Vector3.ZERO
	
	if spawn_area.get_child_count() > 0:
		var collision_shape = spawn_area.get_child(0) as CollisionShape3D
		if collision_shape and collision_shape.shape is BoxShape3D:
			var box_shape = collision_shape.shape as BoxShape3D
			var bounds = box_shape.size
			
			var random_x = randf_range(-bounds.x/2, bounds.x/2)
			var random_z = randf_range(-bounds.z/2, bounds.z/2)
			
			return spawn_area.global_position + Vector3(random_x, 1, random_z)
	
	return spawn_area.global_position + Vector3(0, 1, 0)

# Helper functions
func get_player_team(player_id: int) -> int:
	return player_teams.get(player_id, 0)

func get_player(player_id: int) -> Node:
	return players.get(player_id)

func get_local_player() -> Node:
	return get_player(multiplayer.get_unique_id())

func get_all_players() -> Array:
	var all_players = get_tree().get_nodes_in_group("players")
	var result = []
	
	for player in all_players:
		if player and is_instance_valid(player):
			var authority = player.get_multiplayer_authority()
			players[authority] = player
			result.append(player)
	
	return result

func get_players_by_team(team: int) -> Array:
	var team_players = []
	var all_players = get_all_players()
	
	for player in all_players:
		var player_id = player.get_multiplayer_authority()
		if get_player_team(player_id) == team:
			team_players.append(player)
	
	return team_players

# NEW: Utility functions for procedural map integration
func get_current_map_seed() -> int:
	if map_generator and map_generator.has_method("get_current_seed"):
		return map_generator.get_current_seed()
	return map_generation_seed

func get_room_at_position(world_pos: Vector3) -> Dictionary:
	if map_generator and map_generator.has_method("get_room_at_position"):
		return map_generator.get_room_at_position(world_pos)
	return {}

func get_random_room_position() -> Vector3:
	if map_generator and map_generator.has_method("get_random_room_position"):
		return map_generator.get_random_room_position()
	return Vector3.ZERO

# NEW: Debug function to regenerate map (useful for testing)
func regenerate_map_with_seed(seed: int):
	if not multiplayer.is_server():
		print("Only server can regenerate map")
		return
	
	if game_started:
		print("Cannot regenerate map while game is running")
		return
	
	print("Regenerating map with seed: ", seed)
	map_generation_complete.clear()
	rpc("generate_game_map_rpc", seed)
