# res://ui/quirk_tag.gd
extends PanelContainer
class_name QuirkTag

@export var font: Font
@export var font_size: int = 14
@export var pad_x: int = 6
@export var pad_y: int = 3

# Bracketless tags at start of desc:
# MOVE ATK DEF HAZ RISK ANOM TEAM KILL
const TAG_COLORS := {
	"MOVE": Color(0.45, 1.0, 0.55),  # green
	"ATK":  Color(1.0, 0.55, 0.25),  # orange
	"DEF":  Color(0.45, 0.85, 1.0),  # cyan-blue
	"HAZ":  Color(0.55, 1.0, 0.45),  # toxic green
	"RISK": Color(1.0, 0.30, 0.30),  # red
	"ANOM": Color(0.75, 0.55, 1.0),  # purple
	"TEAM": Color(0.65, 1.0, 0.85),  # mint
	"KILL": Color(1.0, 0.35, 0.35),  # blood red
}

var _rt: RichTextLabel

func _ready() -> void:
	# padding
	add_theme_constant_override("margin_left", pad_x)
	add_theme_constant_override("margin_right", pad_x)
	add_theme_constant_override("margin_top", pad_y)
	add_theme_constant_override("margin_bottom", pad_y)

	_rt = RichTextLabel.new()
	_rt.bbcode_enabled = true
	_rt.fit_content = true
	_rt.scroll_active = false
	_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if font:
		_rt.add_theme_font_override("normal_font", font)
		_rt.add_theme_font_size_override("normal_font_size", font_size)
	else:
		_rt.add_theme_font_size_override("normal_font_size", font_size)

	add_child(_rt)

func set_desc(desc: String) -> void:
	# Supports:
	# "ATK +1 damage"
	# "HAZ ATK When FIRE damages you..."
	desc = desc.strip_edges()
	if desc == "":
		_rt.text = ""
		return

	var words := desc.split(" ", false)
	if words.is_empty():
		_rt.text = desc
		return

	var i := 0
	var out := ""

	# color up to 2 leading tags if present
	for _k in range(2):
		if i >= words.size():
			break
		var w := words[i].to_upper()
		if TAG_COLORS.has(w):
			var hex = TAG_COLORS[w].to_html()
			out += "[color=%s][b]%s[/b][/color] " % [hex, w]
			i += 1
		else:
			break

	var rest := ""
	if i < words.size():
		rest = " ".join(words.slice(i, words.size()))
	out += rest

	_rt.bbcode_text = out
