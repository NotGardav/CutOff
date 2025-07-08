func spawn_player(player_id: int, team: String):
	print("Spawning player ", player_id, " on team ", team)
	
	if not multiplayer.is_server():
		return
	
	var spawn_position = get_random_spawn_position(get_spawn_area_for_team(team))
	print("Spawn position for player ", player_id, ": ", spawn_position)
	
	# Use MultiplayerSpawner instead of manual instantiation
	if multiplayer_spawner:
		# Create spawn data
		var spawn_data = {
			"player_id": player_id,
			"team": team,
			"position": spawn_position
		}
		
		# Spawn using MultiplayerSpawner
		var player_instance = multiplayer_spawner.spawn([spawn_data])
		
		if player_instance:
			player_instance.name = "Player_" + str(player_id)
			player_instance.set_multiplayer_authority(player_id)
			players[player_id] = player_instance
			print("Player ", player_id, " spawned via MultiplayerSpawner")
	else:
		print("ERROR: MultiplayerSpawner not available for spawning")
