extends Node
class_name MusicManager

var player: AudioStreamPlayer

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.name = "Music"
	player.bus = "Music"
	add_child(player)

	player.finished.connect(_on_music_finished)

func play_stream(stream: AudioStream, from_sec := 0.0) -> void:
	if stream == null:
		return
	if player.stream != stream:
		player.stream = stream
	player.play(from_sec)

func stop() -> void:
	player.stop()

func _on_music_finished() -> void:
	player.play()  # restarts same stream from beginning
