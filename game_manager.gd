# GameManager.gd
extends Node

func _ready():
	print("*** GAME MANAGER READY ***")
	print("GameManager is loaded and working!")
	add_to_group("game_manager")
	
	# Auto-start the game when the scene loads
	call_deferred("start_game")

func start_game():
	print("*** START GAME CALLED ***")
	print("Game is starting...")
	
	# Add your game initialization here:
	# - Setup players
	# - Initialize map
	# - Start gameplay logic
	
	# Example:
	setup_multiplayer_game()

func setup_multiplayer_game():
	print("Setting up multiplayer game...")
	
	# Get the multiplayer spawner if you have one
	var spawner = get_node_or_null("../MultiplayerSpawner")
	if spawner:
		print("Found MultiplayerSpawner")
	
	# Initialize your map generator
	var map_generator = get_parent().get_node_or_null("MapGenerator")
	if map_generator:
		print("Found MapGenerator, initializing...")
		# Call your map generation here
		# map_generator.generate_map()
	
	print("Game setup complete!")
