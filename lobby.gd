extends Node3D
var alien_scene := preload("res://scenes/Alien.tscn")
var human_scene := preload("res://scenes/Human.tscn")
var players := {}

@onready var start_button = $StartGameButton

func _ready() -> void:
	start_button.game_start_requested.connect(_on_game_start_requested)
	# Safety checks
	if get_tree().get_multiplayer() == null or get_tree().get_multiplayer().multiplayer_peer == null:
		print("ERROR: Multiplayer not properly set up!")
		return
	
	print("=== LOBBY DEBUG ===")
	print("Is server: ", get_tree().get_multiplayer().is_server())
	print("Peer ID: ", get_tree().get_multiplayer().get_unique_id())
	
	var multiplayer_api = get_tree().get_multiplayer()
	multiplayer_api.peer_connected.connect(_on_peer_connected)
	multiplayer_api.peer_disconnected.connect(_on_peer_disconnected)
	
	if multiplayer_api.is_server():
		print("HOST: Setting up lobby")
		$CodeLabel.text = "Lobby Code: " + Globals.lobby_code
	else:
		print("CLIENT: Joined lobby")
		$CodeLabel.text = "Lobby Code: Connecting..."
		# Request the lobby code from the server
		_request_lobby_code.rpc_id(1)
	
	# Both host and client spawn their own player
	await get_tree().process_frame
	_spawn_local_player(multiplayer_api.get_unique_id())

func _spawn_local_player(peer_id: int):
	print("Spawning local player for peer: ", peer_id)
	
	var player_scene = alien_scene if peer_id % 2 == 0 else human_scene
	var player = player_scene.instantiate()
	
	# Set the player type based on peer ID
	player.player_type = "alien" if peer_id % 2 == 0 else "human"
	player.set_multiplayer_authority(peer_id)
	player.name = "Player_" + str(peer_id)
	
	# Add to tree
	add_child(player)
	print("DEBUG: Player added to tree with name: ", player.name)
	print("DEBUG: Full path: ", player.get_path())
	print("DEBUG: Can find via get_node: ", get_node_or_null("Player_" + str(peer_id)) != null)
	
	# Set spawn position with some spacing
	var spawn_positions = [
		Vector3(0, 2, 0),
		Vector3(3, 2, 0),
		Vector3(-3, 2, 0),
		Vector3(0, 2, 3),
		Vector3(0, 2, -3)
	]
	var pos_index = players.size() % spawn_positions.size()
	player.global_transform = Transform3D(player.global_transform.basis, spawn_positions[pos_index])
	
	players[peer_id] = player
	print("LOCAL: Spawned player ", peer_id, " as ", player.player_type, " at ", player.global_transform.origin)
	
	# Use call_deferred to ensure this happens after the scene is fully ready
	call_deferred("_announce_player", peer_id, player.player_type, player.global_transform.origin)

func _announce_player(peer_id: int, player_type: String, position: Vector3):
	print("Announcing player ", peer_id, " to all peers. Current peers: ", get_tree().get_multiplayer().get_peers())
	if get_tree().get_multiplayer().get_peers().size() > 0:
		_notify_player_spawned.rpc(peer_id, player_type, position)
	else:
		print("No peers to announce to yet")

func _on_peer_connected(peer_id: int) -> void:
	print("PEER CONNECTED: ", peer_id)
	
	await get_tree().create_timer(0.5).timeout
	
	if not get_tree().get_multiplayer().get_peers().has(peer_id):
		print("Peer ", peer_id, " disconnected before spawn")
		return
	
	if get_tree().get_multiplayer().is_server():
		print("SERVER: Handling new peer connection ", peer_id)
		# Send info about EXISTING players to the new peer (excluding the new peer itself)
		for existing_peer_id in players.keys():
			if existing_peer_id != peer_id:  # Don't send the new peer back to themselves
				var existing_player = players[existing_peer_id]
				print("SERVER: Sending existing player ", existing_peer_id, " to new peer ", peer_id)
				_spawn_remote_player.rpc_id(peer_id, existing_peer_id, existing_player.player_type, existing_player.global_transform.origin)
		
		# Tell the new peer to announce themselves to everyone
		_request_player_announcement.rpc_id(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("PEER DISCONNECTED: ", peer_id)
	_remove_player.rpc(peer_id)

# RPC to notify all peers that a new player has spawned
@rpc("any_peer", "reliable")
func _notify_player_spawned(peer_id: int, player_type: String, position: Vector3):
	print("=== SPAWN NOTIFICATION DEBUG ===")
	print("Notification for peer: ", peer_id, " (", player_type, ") at ", position)
	print("My peer ID: ", get_tree().get_multiplayer().get_unique_id())
	print("Are they the same? ", peer_id == get_tree().get_multiplayer().get_unique_id())
	print("Current players: ", players.keys())
	print("================================")
	
	# Don't spawn ourselves again
	if peer_id == get_tree().get_multiplayer().get_unique_id():
		print("Ignoring spawn notification for self")
		return
	
	# Don't spawn if already exists
	if peer_id in players:
		print("Player ", peer_id, " already exists, ignoring spawn notification")
		return
	
	print("PROCEEDING to create remote player for peer: ", peer_id)
	_create_remote_player(peer_id, player_type, position)

# RPC to spawn a remote player (used by server to tell clients about existing players)
@rpc("any_peer", "reliable")
func _spawn_remote_player(peer_id: int, player_type: String, position: Vector3):
	print("RPC: Spawn remote player ", peer_id, " as ", player_type)
	
	# Don't spawn ourselves
	if peer_id == get_tree().get_multiplayer().get_unique_id():
		return
	
	# Don't spawn if already exists
	if peer_id in players:
		print("Remote player ", peer_id, " already exists")
		return
	
	_create_remote_player(peer_id, player_type, position)

func _create_remote_player(peer_id: int, player_type: String, position: Vector3):
	print("Creating remote player: ", peer_id, " as ", player_type, " at ", position)
	
	# Validate position - ensure Y is reasonable
	if position.y < 0:
		print("WARNING: Invalid Y position ", position.y, " - using default spawn position")
		position.y = 2.0
	
	var player_scene = alien_scene if player_type == "alien" else human_scene
	var player = player_scene.instantiate()
	
	player.player_type = player_type
	player.set_multiplayer_authority(peer_id)
	player.name = "Player_" + str(peer_id)
	
	add_child(player)
	
	# Set position after adding to tree
	player.global_transform = Transform3D(player.global_transform.basis, position)
	
	players[peer_id] = player
	print("REMOTE: Created player ", peer_id, " as ", player_type, " - Total players: ", players.size())
	
# RPC to remove a player from all clients
@rpc("call_local", "reliable")
func _remove_player(peer_id: int):
	if peer_id in players:
		players[peer_id].queue_free()
		players.erase(peer_id)
		print("Removed player ", peer_id, " - Remaining players: ", players.size())

func _on_game_start_requested():
	print("Starting game!")
	print("Current players: ", players.keys())
	
	if get_tree().get_multiplayer().is_server():
		change_to_game_scene.rpc()

@rpc("call_local", "reliable") 
func change_to_game_scene():
	print("=== CHANGING TO GAME SCENE ===")
	var tree = get_tree()
	var result = tree.change_scene_to_file("res://Scenes/game_scene.tscn")
	if result != OK:
		print("ERROR: Failed to change scene, error code: ", result)
		return
	print("Scene change initiated successfully")

func _on_start_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/game_scene.tscn")

# RPC for server to request a peer to announce themselves
@rpc("any_peer", "reliable")
func _request_player_announcement():
	print("Received request to announce player")
	var my_id = get_tree().get_multiplayer().get_unique_id()
	if my_id in players:
		var my_player = players[my_id]
		print("Announcing my player: ", my_id, " as ", my_player.player_type, " at ", my_player.global_transform.origin)
		_notify_player_spawned.rpc(my_id, my_player.player_type, my_player.global_transform.origin)
	else:
		print("ERROR: My player not found in players dict!")

# RPC to send lobby code to clients
@rpc("any_peer", "reliable")
func _send_lobby_code(code: String):
	print("Received lobby code: ", code)
	$CodeLabel.text = "Lobby Code: " + code

# RPC for clients to request the lobby code
@rpc("any_peer", "reliable")
func _request_lobby_code():
	var sender_id = get_tree().get_multiplayer().get_remote_sender_id()
	if get_tree().get_multiplayer().is_server():
		print("Sending lobby code to client: ", sender_id)
		_send_lobby_code.rpc_id(sender_id, Globals.lobby_code)
