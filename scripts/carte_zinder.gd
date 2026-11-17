extends CanvasLayer
class_name CarteZinder
# Niger Streets — Carte complète de Zinder, ouverte en touchant le radar du HUD.
# Carte VECTORIELLE hors connexion (OpenStreetMap, ODbL) :
#  - assets/data/zinder_map.json      : routes (6565) + eau (616 lignes)
#  - assets/data/zinder_buildings.json : 116111 bâtiments fusionnés en UN SEUL
#    ArrayMesh via Geometry2D.triangulate_polygon (dernier point retiré s'il
#    répète le premier, polygones non triangulables ignorés).
# Les JSON sont chargés à la PREMIÈRE ouverture de la carte (pas au démarrage du
# jeu) puis gardés en mémoire.
# Coordonnées en mètres autour du centre lon 8.9881, lat 13.8054 :
#   x = (lon - 8.9881) * 111320 * cos(rad(13.8054))   (x vers l'est)
#   y = -(lat - 13.8054) * 110540                     (y vers le sud)
# Interactions : molette souris ou pincement à deux doigts pour zoomer/dézoomer
# (limites min/max, zoom centré sur le point touché), glisser à un doigt ou à la
# souris pour se déplacer. Épaisseurs des traits et tailles des textes constantes
# à l'écran quel que soit le zoom (traits cuits en espace écran, transform du
# canvas item limité à une translation).
# API conservée : open(), close(), is_open(), close_current(), titre, bouton
# Fermer, pause du jeu, bouton retour Android qui ferme la carte d'abord (guard
# dans pause_menu.gd), flèche du Nord. L'ancienne image satellite
# carte_zinder.jpg reste dans le dépôt tant que la nouvelle carte n'est pas
# validée ; elle n'est plus utilisée par ce script.

const MAP_JSON_PATH := "res://assets/data/zinder_map.json"
const BUILDINGS_JSON_PATH := "res://assets/data/zinder_buildings.json"
const GOLD: Color = Color(1.0, 0.72, 0.20)
const BG_COLOR: Color = Color(0.05, 0.08, 0.12)
const BUILDING_COLOR: Color = Color(0.13, 0.16, 0.22)
const WATER_COLOR: Color = Color(0.20, 0.42, 0.72)
# classes : 0 = chemins/track/path/footway/service, 1 = residential,
# 2 = trunk/secondary/tertiary, 3 = primary
const ROAD_COLORS: Array[Color] = [
	Color(0.38, 0.42, 0.48),
	Color(0.55, 0.58, 0.64),
	Color(0.82, 0.79, 0.72),
	GOLD,
]
const ROAD_WIDTHS: Array[float] = [1.25, 2.5, 4.5, 6.0]   # pixels écran
const WATER_LINE_WIDTH: float = 2.0
const PIN_FONT_SIZE := 15
const ZOOM_WHEEL_FACTOR := 1.18
const ZOOM_MAX := 12.0            # px par mètre (niveau rue)
const VIEW_INIT_M := 15000.0      # largeur visible à l'ouverture (m)
const VIEW_MIN_M := 40000.0       # largeur visible au dézoom maximal (m)

## Repères réels en mètres, déduits des UV de l'image satellite (grille Esri
## b25 : N 13.85941 S 13.77407 E 9.03076 W 8.92090) puis convertis avec la
## formule ci-dessus. La mosquée retombe sur les coordonnées Wikidata exactes.
const PINS: Array[Dictionary] = [
	{"pos": Vector2(1423, 1251), "nom": "Grande Mosquée"},
	{"pos": Vector2(1016, 1061), "nom": "Birni — vieille ville"},
	{"pos": Vector2(-443, 431), "nom": "Zengou — Grand Marché"},
	{"pos": Vector2(-4551, 298), "nom": "Stade de Zinder"},
	{"pos": Vector2(-1924, 2708), "nom": "Aéroport de Zinder"},
]

static var _instance: CarteZinder = null

var _open := false
var _loaded := false
var _loading := false
var _load_count := 0
var _root: Control = null
var _map_area: Control = null
var _overlay: Control = null
var _loading_label: Label = null
var _ci_water: RID
var _ci_buildings: RID
var _ci_strokes: RID
var _buildings_mesh: ArrayMesh = null
var _strokes: Array[Dictionary] = []      # {pts: PackedVector2Array (monde, m), cls: int (-1 = eau)}
var _water_areas: Array[PackedVector2Array] = []
var _cam := Vector2.ZERO                  # centre caméra en mètres
var _zoom := 0.1                          # pixels par mètre (zoom cuit)
var _zoom_min := 0.02
var _zoom_max := ZOOM_MAX
var _pulse := 0.0
var _player_world := Vector2.ZERO         # à brancher sur la vraie position du joueur plus tard
var _touches := {}                        # index tactile → position locale
var _pinch_dist := -1.0
var _pinch_mid := Vector2.ZERO
var _mouse_drag := false
var _touch_device := false

static func is_open() -> bool:
	return _instance != null and _instance._open

static func close_current() -> void:
	if _instance != null and _instance._open:
		_instance.close()

func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_instance = self
	_touch_device = DisplayServer.is_touchscreen_available()
	_build_ui()
	visible = false

func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	for ci in [_ci_water, _ci_buildings, _ci_strokes]:
		if ci.is_valid():
			RenderingServer.free_rid(ci)
	_ci_water = RID()
	_ci_buildings = RID()
	_ci_strokes = RID()

func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ensure_loaded()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Position du joueur en mètres (x est, y sud) — à brancher sur la vraie
## position du joueur quand elle sera reliée à la carte de la ville.
func set_player_world(pos: Vector2) -> void:
	_player_world = pos

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # bloque les appuis derrière la carte
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	var title := Label.new()
	title.text = "ZINDER — CARTE DE LA VILLE"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 16.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 6)
	_root.add_child(title)

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
	_root.add_child(close_btn)

	_map_area = Control.new()
	_map_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_area.offset_top = 70.0
	_map_area.offset_bottom = -64.0
	_map_area.offset_left = 10.0
	_map_area.offset_right = -10.0
	_map_area.clip_contents = true
	_map_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_area.gui_input.connect(_on_map_input)
	_map_area.resized.connect(_on_area_resized)
	_root.add_child(_map_area)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.offset_top = 70.0
	_overlay.offset_bottom = -64.0
	_overlay.offset_left = 10.0
	_overlay.offset_right = -10.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_root.add_child(_overlay)

	var attrib := Label.new()
	attrib.text = "Données cartographiques © contributeurs OpenStreetMap (ODbL)"
	attrib.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	attrib.offset_bottom = -10.0
	attrib.offset_right = -14.0
	attrib.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	attrib.add_theme_font_size_override("font_size", 12)
	attrib.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_root.add_child(attrib)

	_loading_label = Label.new()
	_loading_label.text = "Chargement de la carte de Zinder…"
	_loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 26)
	_loading_label.add_theme_color_override("font_color", GOLD)
	_loading_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_loading_label.add_theme_constant_override("outline_size", 5)
	_loading_label.visible = false
	_root.add_child(_loading_label)

# ------------------------------------------------------------------ données

## Chargement différé à la première ouverture puis mise en mémoire.
func _ensure_loaded() -> void:
	if _loaded or _loading:
		return
	_loading = true
	_loading_label.visible = true
	await get_tree().process_frame   # laisse le label s'afficher avant le gros calcul
	if not is_inside_tree():
		return
	var ok := _load_data()
	_loading = false
	_loaded = ok
	_loading_label.visible = not ok

func _load_data() -> bool:
	_load_count += 1
	var t0 := Time.get_ticks_usec()

	var map_txt := FileAccess.get_file_as_string(MAP_JSON_PATH)
	var map_data: Variant = JSON.parse_string(map_txt)
	var bld_txt := FileAccess.get_file_as_string(BUILDINGS_JSON_PATH)
	var bld_data: Variant = JSON.parse_string(bld_txt)
	if map_data == null or bld_data == null or not (map_data is Dictionary) or not (bld_data is Array):
		push_error("CarteZinder : JSON cartographique illisible")
		_loading_label.text = "Erreur : données cartographiques illisibles"
		return false

	# routes et eau → traits en coordonnées monde (mètres)
	_strokes.clear()
	_water_areas.clear()
	for r in map_data.get("roads", []):
		var p: Array = r["p"]
		if p.size() < 4:
			continue
		_strokes.append({"pts": _flat_to_points(p), "cls": _road_class(str(r["k"]))})
	for w in map_data.get("water", []):
		var p2: Array = w["p"]
		if p2.size() < 4:
			continue
		if str(w["k"]) == "area":
			_water_areas.append(_flat_to_points(p2))
		else:
			_strokes.append({"pts": _flat_to_points(p2), "cls": -1})

	# items de rendu (l'ordre de création = ordre de dessin : eau, bâtiments, traits)
	_ci_water = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_ci_water, _map_area.get_canvas_item())
	_ci_buildings = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_ci_buildings, _map_area.get_canvas_item())
	_ci_strokes = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_ci_strokes, _map_area.get_canvas_item())

	for area in _water_areas:
		RenderingServer.canvas_item_add_polygon(_ci_water, area, PackedColorArray([WATER_COLOR]))

	_buildings_mesh = _build_mesh(bld_data)
	if _buildings_mesh != null:
		RenderingServer.canvas_item_add_mesh(_ci_buildings, _buildings_mesh.get_rid(), Transform2D(), BUILDING_COLOR)

	_bake_strokes()

	# vue initiale : ville centrée sur l'origine (carrefour central)
	_compute_view_limits()
	_apply_view()
	var ms := (Time.get_ticks_usec() - t0) / 1000
	print("CarteZinder : %d traits, %d bâtiments, maillage+chargement %d ms" % [_strokes.size(), bld_data.size(), ms])
	return true

func _flat_to_points(flat: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(flat.size() / 2)
	for i in range(0, flat.size() - 1, 2):
		pts[i / 2] = Vector2(flat[i], flat[i + 1])
	return pts

func _road_class(k: String) -> int:
	if k.contains("primary"):
		return 3
	if k.contains("trunk") or k.contains("secondary") or k.contains("tertiary"):
		return 2
	if k.contains("residential") or k.contains("living"):
		return 1
	return 0

## Tous les bâtiments fusionnés en UN SEUL ArrayMesh triangulé.
func _build_mesh(buildings: Array) -> ArrayMesh:
	var verts := PackedVector2Array()
	var idx := PackedInt32Array()
	for b in buildings:
		var flat: Array = b
		var n := flat.size() / 2
		if n < 3:
			continue
		# retirer le dernier point s'il répète le premier
		if flat[0] == flat[flat.size() - 2] and flat[1] == flat[flat.size() - 1]:
			n -= 1
		if n < 3:
			continue
		var poly := PackedVector2Array()
		poly.resize(n)
		for i in n:
			poly[i] = Vector2(flat[i * 2], flat[i * 2 + 1])
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			continue   # polygone non triangulable : ignoré
		var base := verts.size()
		verts.append_array(poly)
		for c in tri:
			idx.append(base + c)
	if verts.size() == 0:
		return null
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Traits cuits en espace "carte" (monde × zoom) ; le canvas item ne porte plus
## qu'une translation → épaisseur constante à l'écran quel que soit le zoom.
func _bake_strokes() -> void:
	if not _ci_strokes.is_valid():
		return
	RenderingServer.canvas_item_clear(_ci_strokes)
	for s in _strokes:
		var w: PackedVector2Array = s["pts"]
		var n := w.size()
		var pts := PackedVector2Array()
		pts.resize(n)
		for i in n:
			pts[i] = w[i] * _zoom
		var cls: int = s["cls"]
		var col: Color = WATER_COLOR if cls < 0 else ROAD_COLORS[cls]
		var wd: float = WATER_LINE_WIDTH if cls < 0 else ROAD_WIDTHS[cls]
		RenderingServer.canvas_item_add_polyline(_ci_strokes, pts, PackedColorArray([col]), wd, false)

# ------------------------------------------------------------------ vue

func _area_center() -> Vector2:
	return _map_area.size * 0.5

func _screen_to_world(p: Vector2) -> Vector2:
	return (p - _area_center()) / _zoom + _cam

func _compute_view_limits() -> void:
	_zoom_min = maxf(_map_area.size.x / VIEW_MIN_M, 0.001)
	_zoom_max = ZOOM_MAX
	_zoom = clampf(_map_area.size.x / VIEW_INIT_M, _zoom_min, _zoom_max)
	_cam = Vector2.ZERO

func _apply_view() -> void:
	if not _ci_water.is_valid():
		return
	var off := _area_center() - _cam * _zoom
	RenderingServer.canvas_item_set_transform(_ci_water, Transform2D(Vector2(_zoom, 0), Vector2(0, _zoom), off))
	RenderingServer.canvas_item_set_transform(_ci_buildings, Transform2D(Vector2(_zoom, 0), Vector2(0, _zoom), off))
	# traits : translation seule → épaisseurs écran intactes
	RenderingServer.canvas_item_set_transform(_ci_strokes, Transform2D(Vector2(1, 0), Vector2(0, 1), off))
	if _overlay != null:
		_overlay.queue_redraw()

func _zoom_at(p: Vector2, factor: float) -> void:
	var wa := _screen_to_world(p)
	_zoom = clampf(_zoom * factor, _zoom_min, _zoom_max)
	_cam = wa - (p - _area_center()) / _zoom
	_apply_view()
	_bake_strokes()

func _pan(delta: Vector2) -> void:
	_cam -= delta / _zoom
	_apply_view()

func _on_area_resized() -> void:
	if _loaded:
		_zoom = clampf(_zoom, _zoom_min, _zoom_max)
		_apply_view()

# ------------------------------------------------------------------ entrées

func _on_map_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() >= 2:
				_pinch_dist = -1.0   # (re)démarrage du pincement
		else:
			_touches.erase(event.index)
			_pinch_dist = -1.0
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var vals := _touches.values()
			var mid: Vector2 = (vals[0] + vals[1]) * 0.5
			var d: float = vals[0].distance_to(vals[1])
			if _pinch_dist > 0.0 and d > 0.0:
				var wa := _screen_to_world(_pinch_mid)
				_zoom = clampf(_zoom * (d / _pinch_dist), _zoom_min, _zoom_max)
				_cam = wa - (mid - _area_center()) / _zoom
				_apply_view()
				_bake_strokes()
			_pinch_dist = d
			_pinch_mid = mid
		else:
			_pan(event.relative)
		return
	if event is InputEventMouseButton:
		var wheel: bool = event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if _touch_device and not wheel:
			return   # sur écran tactile : souris émulée ignorée, roue acceptée
		if event.button_index == MOUSE_BUTTON_LEFT:
			_mouse_drag = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, ZOOM_WHEEL_FACTOR)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, 1.0 / ZOOM_WHEEL_FACTOR)
	elif event is InputEventMouseMotion and _mouse_drag and not _touch_device:
		_pan(event.relative)

# ------------------------------------------------------------------ calque haut

func _process(delta: float) -> void:
	if not _open:
		return
	_pulse = fmod(_pulse + delta * 0.8, 1.0)
	if _overlay != null:
		_overlay.queue_redraw()

func _draw_overlay() -> void:
	if _overlay == null:
		return
	var center := _area_center()
	var font: Font = ThemeDB.fallback_font
	# repères : points rouges + noms, tailles constantes à l'écran, hors écran ignorés
	for pin in PINS:
		var pos: Vector2 = (pin["pos"] - _cam) * _zoom + center
		var sz := _overlay.size
		if pos.x < -80.0 or pos.y < -80.0 or pos.x > sz.x + 80.0 or pos.y > sz.y + 80.0:
			continue
		_overlay.draw_circle(pos, 8.0, Color(0, 0, 0, 0.55))
		_overlay.draw_circle(pos, 6.5, Color(1.0, 0.32, 0.26))
		_overlay.draw_circle(pos, 3.0, Color.WHITE)
		var txt: String = pin["nom"]
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT_SIZE).x
		var lx := pos.x - tw * 0.5
		var ly := pos.y + 26.0 if pos.y < sz.y * 0.75 else pos.y - 16.0
		_overlay.draw_string_outline(font, Vector2(lx, ly), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT_SIZE, 4, Color(0, 0, 0, 0.9))
		_overlay.draw_string(font, Vector2(lx, ly), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, PIN_FONT_SIZE, Color.WHITE)

	# position du joueur : point doré + onde pulsée (monde → écran)
	var ppos: Vector2 = (_player_world - _cam) * _zoom + center
	var ring := 10.0 + _pulse * 18.0
	_overlay.draw_arc(ppos, ring, 0.0, TAU, 32, Color(GOLD.r, GOLD.g, GOLD.b, 0.9 - _pulse * 0.65), 3.0)
	_overlay.draw_circle(ppos, 7.0, GOLD)
	_overlay.draw_circle(ppos, 3.0, Color(0.12, 0.09, 0.02))

	# flèche du Nord (le nord est en haut dans les données OSM)
	var npos := Vector2(_overlay.size.x - 34.0, 30.0)
	_overlay.draw_line(npos, npos + Vector2(0, -18.0), Color.WHITE, 3.0)
	_overlay.draw_line(npos, npos + Vector2(-6.0, -8.0), Color.WHITE, 3.0)
	_overlay.draw_line(npos, npos + Vector2(6.0, -8.0), Color.WHITE, 3.0)
	_overlay.draw_string(font, npos + Vector2(-6.0, 18.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
