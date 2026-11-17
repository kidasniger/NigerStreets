extends CanvasLayer
class_name CarteZinder
# Niger Streets — Carte complète de Zinder, ouverte en touchant le radar du HUD.
# Image satellite réelle de la ville (assets/environment/carte_zinder.jpg, source
# Esri World Imagery © Esri, Maxar, Earthstar Geographics). Repères : Grande Mosquée
# (coordonnées Wikidata), stade et aéroport identifiables sur l'image, quartiers
# Birni et Zengou d'après la géographie de la ville (position approximative).
# « Vous êtes ici » = position symbolique de la partie (carrefour central).
# L'ouverture met le jeu en pause comme le menu pause ; le bouton retour Android
# ferme d'abord la carte (guard dans pause_menu.gd).

const MAP_TEXTURE: Texture2D = preload("res://assets/environment/carte_zinder.jpg")
const GOLD: Color = Color(1.0, 0.72, 0.20)

## Repères réels : coordonnées UV (0..1) dans l'image satellite
const PINS: Array[Dictionary] = [
	{"uv": Vector2(0.7315, 0.7655), "nom": "Grande Mosquée"},
	{"uv": Vector2(0.6972, 0.7454), "nom": "Birni — vieille ville"},
	{"uv": Vector2(0.5744, 0.6786), "nom": "Zengou — Grand Marché"},
	{"uv": Vector2(0.2285, 0.6645), "nom": "Stade de Zinder"},
	{"uv": Vector2(0.4500, 0.9200), "nom": "Aéroport de Zinder"},
]
## Position symbolique de la partie (carrefour central de la ville)
const PLAYER_UV: Vector2 = Vector2(0.4651, 0.5790)

static var _instance: CarteZinder = null

var _open := false
var _map_area: Control = null
var _pulse := 0.0

static func is_open() -> bool:
	return _instance != null and _instance._open

static func close_current() -> void:
	if _instance != null and _instance._open:
		_instance.close()

func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_instance = self
	_build_ui()
	visible = false

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # bloque les appuis derrière la carte
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var title := Label.new()
	title.text = "ZINDER — CARTE DE LA VILLE"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 16.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	root.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "Fermer"
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_right = -12.0
	close_btn.offset_top = 10.0
	close_btn.offset_left = -152.0
	close_btn.custom_minimum_size = Vector2(140, 48)
	close_btn.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.13, 0.18, 0.98)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	close_btn.add_theme_stylebox_override("normal", sb)
	close_btn.pressed.connect(close)
	root.add_child(close_btn)

	_map_area = Control.new()
	_map_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_area.offset_top = 70.0
	_map_area.offset_bottom = -64.0
	_map_area.offset_left = 10.0
	_map_area.offset_right = -10.0
	_map_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_area.draw.connect(_draw_map)
	root.add_child(_map_area)

	var attrib := Label.new()
	attrib.text = "Imagerie satellite : © Esri, Maxar, Earthstar Geographics — position des repères approximative"
	attrib.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	attrib.offset_bottom = -10.0
	attrib.offset_right = -14.0
	attrib.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	attrib.add_theme_font_size_override("font_size", 12)
	attrib.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	root.add_child(attrib)

func _process(delta: float) -> void:
	if not _open:
		return
	_pulse = fmod(_pulse + delta * 0.8, 1.0)
	if _map_area != null:
		_map_area.queue_redraw()

func _draw_map() -> void:
	if _map_area == null:
		return
	var tex_size := MAP_TEXTURE.get_size()
	if tex_size.x <= 0.0 or _map_area.size.x <= 0.0:
		return
	var s := minf(_map_area.size.x / tex_size.x, _map_area.size.y / tex_size.y)
	var draw_size := tex_size * s
	var origin := (_map_area.size - draw_size) * 0.5
	_map_area.draw_texture_rect(MAP_TEXTURE, Rect2(origin, draw_size), false)

	var font: Font = ThemeDB.fallback_font
	var fsize := 15
	for pin in PINS:
		var uv: Vector2 = pin["uv"]
		var pos: Vector2 = origin + uv * draw_size
		_map_area.draw_circle(pos, 8.0, Color(0, 0, 0, 0.55))
		_map_area.draw_circle(pos, 6.5, Color(1.0, 0.32, 0.26))
		_map_area.draw_circle(pos, 3.0, Color.WHITE)
		var txt: String = pin["nom"]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var lx := pos.x - tw * 0.5
		var ly := pos.y + 26.0 if uv.y < 0.8 else pos.y - 16.0
		_map_area.draw_string_outline(font, Vector2(lx, ly), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.9))
		_map_area.draw_string(font, Vector2(lx, ly), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.WHITE)

	# position de la partie : point doré + onde pulsée
	var ppos: Vector2 = origin + PLAYER_UV * draw_size
	var ring := 10.0 + _pulse * 18.0
	_map_area.draw_arc(ppos, ring, 0.0, TAU, 32, Color(GOLD.r, GOLD.g, GOLD.b, 0.9 - _pulse * 0.65), 3.0)
	_map_area.draw_circle(ppos, 7.0, GOLD)
	_map_area.draw_circle(ppos, 3.0, Color(0.12, 0.09, 0.02))

	# flèche du Nord (les tuiles Esri sont orientées nord en haut)
	var npos := Vector2(_map_area.size.x - 34.0, 30.0)
	_map_area.draw_line(npos, npos + Vector2(0, -18.0), Color.WHITE, 3.0)
	_map_area.draw_line(npos, npos + Vector2(-6.0, -8.0), Color.WHITE, 3.0)
	_map_area.draw_line(npos, npos + Vector2(6.0, -8.0), Color.WHITE, 3.0)
	_map_area.draw_string(font, npos + Vector2(-6.0, 18.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
