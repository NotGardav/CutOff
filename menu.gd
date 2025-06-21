extends Control

var host_button: Button
var join_button: Button
var code_input: LineEdit
var lobby_code: String

func _ready():
	host_button = $HostButton
	join_button = $JoinButton
	code_input = $CodeInput
	host_button.connect("pressed", _on_host_game_pressed)
	join_button.connect("pressed", _on_join_game_pressed)

func _on_host_game_pressed():
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	lobby_code = str(rng.randi_range(100000, 999999))
	print("Hosting Game With Code:", lobby_code)
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_server(12345, 16)
	if result != OK:
		push_error("Failed to create server: " + str(result))
		return
	get_tree().get_multiplayer().multiplayer_peer = peer
	Globals.lobby_code = lobby_code
	get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")

func _on_join_game_pressed():
	var code = code_input.text
	if code == "":
		print("Please enter a lobby code!")
		return
	print("Attempting to join lobby with code:", code)
	join_game_with_code(code)

func join_game_with_code(code: String):
	var host_ip = "127.0.0.1"
	var peer = ENetMultiplayerPeer.new()
	var result = peer.create_client(host_ip, 12345)
	if result != OK:
		push_error("Failed to connect: " + str(result))
		return
	get_tree().get_multiplayer().multiplayer_peer = peer
	print("Connecting...")
	var multiplayer = get_tree().get_multiplayer()
	while multiplayer.get_unique_id() == 1:
		await get_tree().process_frame
	print("Connected! Peer ID:", multiplayer.get_unique_id())
	print("Changing to lobby scene...")
	await get_tree().create_timer(0.2).timeout
	get_tree().change_scene_to_file("res://Scenes/Lobby.tscn")
