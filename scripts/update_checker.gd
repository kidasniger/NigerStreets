extends Node
# Niger Streets - Vérification automatique de mise à jour (autoload).
# Au lancement (après CHECK_DELAY), interroge la dernière release GitHub et compare
# le numéro de build (bNN) avec la version installée (config/version, remplie par la CI).
# Si une version plus récente existe : popup dorée, TÉLÉCHARGEMENT DANS L'APPLI
# (HTTPRequest avec barre de progression) puis installation via le plugin Android
# UpdateInstaller (PackageInstaller, aucune sortie de l'application).
# Repli navigateur si le plugin est absent (build sans gradle) ou si l'installation échoue.
# Silencieux en cas d'absence de réseau, d'erreur API ou de version d'éditeur (sans bNN).

const API_URL: String = "https://api.github.com/repos/kidasniger/NigerStreets/releases/latest"
const CHECK_DELAY: float = 4.0
const APK_SAVE_PATH: String = "user://update.apk"
const APK_MIN_SIZE: int = 1048576   # un vrai APK fait ~43 Mo ; en dessous : téléchargement tronqué

## true tant qu'une popup de mise à jour est affichée (le splash ne doit pas démarrer le jeu)
var popup_open: bool = false

var _http: HTTPRequest = null
var _popup_layer: CanvasLayer = null
var _apk_url: String = ""
var _tag: String = ""
var _dl_http: HTTPRequest = null
var _msg: Label = null
var _progress: Label = null
var _buttons_box: HBoxContainer = null
var _manual_cb := Callable()   # résultat d'une vérification manuelle (bouton des réglages)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # la progression doit vivre même en pause
	get_tree().create_timer(CHECK_DELAY).timeout.connect(_check)

func _process(_delta: float) -> void:
	if _progress != null and _dl_http != null:
		var total: int = _dl_http.get_body_size()
		var done: int = _dl_http.get_downloaded_bytes()
		if total > 0:
			_progress.text = "Téléchargement… %d %%" % (100 * done / total)
		else:
			_progress.text = "Téléchargement… %d Mo" % (done / 1048576)

## Vérification manuelle (bouton « Rechercher les mises à jour » des réglages).
## Callback appelé avec un message de statut : chaîne vide si une mise à jour
## existe (la popup d'installation s'ouvre à la place).
func check_manual(on_done: Callable) -> void:
	if popup_open or _http != null:
		if on_done.is_valid():
			on_done.call("" if popup_open else "Une vérification est déjà en cours…")
		return
	_manual_cb = on_done
	_check()

func _check() -> void:
	# Comme MusicPro : le fichier APK d'une installation précédente est supprimé
	# (cleanup) avant chaque vérification/téléchargement pour libérer le stockage.
	_delete_old_apk()
	var local_build: int = _build_number(str(ProjectSettings.get_setting("application/config/version", "1.0")))
	if local_build <= 0:
		_finish_manual("Vérification impossible : numéro de build inconnu (éditeur).")
		return   # version d'éditeur sans numéro de build : rien à vérifier
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	_http.request_completed.connect(_on_response)
	add_child(_http)
	var headers: PackedStringArray = PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: NigerStreets-UpdateCheck",
	])
	if _http.request(API_URL, headers) != OK:
		_finish_manual("Vérification impossible : connexion Internet requise.")
		_cleanup()

## Supprime l'APK téléchargé par une installation précédente (file dans user://)
func _delete_old_apk() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.file_exists("update.apk"):
		dir.remove("update.apk")
	if dir.dir_exists("updates"):
		for f in DirAccess.get_files_at("user://updates"):
			dir.remove("updates/" + f)
		dir.remove("updates")

func _on_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var remote_build: int = 0
	var apk_url: String = ""
	var tag: String = ""
	var size_mb: int = 0
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary:
			tag = str(data.get("tag_name", ""))
			remote_build = _build_number(tag)
			var assets: Variant = data.get("assets", [])
			if assets is Array:
				for a: Variant in assets:
					if a is Dictionary and str(a.get("name", "")).ends_with(".apk"):
						apk_url = str(a.get("browser_download_url", ""))
						size_mb = int(float(a.get("size", 0.0)) / 1048576.0)
						break
			if apk_url.is_empty():
				apk_url = str(data.get("html_url", ""))
	var local_build: int = _build_number(str(ProjectSettings.get_setting("application/config/version", "1.0")))
	if remote_build > local_build and not apk_url.is_empty():
		_show_popup(tag, apk_url, local_build, size_mb)
		_finish_manual("Nouvelle version %s trouvée" % tag)
	else:
		_finish_manual("Vous avez déjà la dernière version (b%d)" % local_build if response_code == 200 else "Vérification impossible : connexion Internet requise.")
	_cleanup()

## Termine une vérification manuelle avec un message (auto-check : callback vide)
func _finish_manual(msg: String) -> void:
	if _manual_cb.is_valid():
		var cb := _manual_cb
		_manual_cb = Callable()
		cb.call(msg)

## Extrait le numéro de build d'une chaîne « 1.0-b12 » ou « v1.0-b12 » (0 si absent/invalide)
func _build_number(version: String) -> int:
	var idx := version.rfind("b")
	if idx < 0:
		return 0
	var suffix := version.substr(idx + 1)
	return int(suffix) if suffix.is_valid_int() else 0

func _cleanup() -> void:
	if _http != null:
		_http.queue_free()
		_http = null

## Plugin Android « UpdateInstaller » (null si build sans gradle)
func _get_installer_plugin() -> Object:
	if Engine.has_singleton("UpdateInstaller"):
		return Engine.get_singleton("UpdateInstaller")
	return null

# ------------------------------------------------------------------ popup

func _show_popup(tag: String, apk_url: String, local_build: int, size_mb: int) -> void:
	if popup_open:
		return
	popup_open = true
	_apk_url = apk_url
	_tag = tag
	_popup_layer = CanvasLayer.new()
	_popup_layer.layer = 20
	add_child(_popup_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # bloque les appuis derrière la popup
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	_popup_layer.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.97)
	sb.border_color = Color(1.0, 0.72, 0.20)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 30.0
	sb.content_margin_right = 30.0
	sb.content_margin_top = 24.0
	sb.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.custom_minimum_size = Vector2(520, 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Nouvelle mise à jour disponible"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.20))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var size_txt: String = "" if size_mb <= 0 else ", %d Mo" % size_mb
	var body := Label.new()
	body.text = "Version %s disponible (installée : b%d%s).\n\nTéléchargement et installation directement dans l'application." % [tag, local_build, size_txt]
	body.add_theme_font_size_override("font_size", 17)
	body.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)

	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", 15)
	_msg.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.visible = false
	vbox.add_child(_msg)

	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 19)
	_progress.add_theme_color_override("font_color", Color(1.0, 0.72, 0.20))
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress.visible = false
	vbox.add_child(_progress)

	_buttons_box = HBoxContainer.new()
	_buttons_box.add_theme_constant_override("separation", 12)
	_buttons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_buttons_box)

	_set_buttons([
		["Télécharger et installer", _on_install_pressed],
		["Plus tard", _close_popup],
	])

## Remplace les boutons affichés (liste de paires [texte, callable]) ; le premier est accentué
func _set_buttons(defs: Array) -> void:
	for c in _buttons_box.get_children():
		c.queue_free()
	for i in range(defs.size()):
		var d: Variant = defs[i]
		var b := Button.new()
		b.text = str(d[0])
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 18)
		_style_button(b, i == 0)
		b.pressed.connect(d[1])
		_buttons_box.add_child(b)

func _set_message(txt: String) -> void:
	if _msg != null:
		_msg.text = txt
		_msg.visible = true

# ------------------------------------------------------------------ flux d'installation

func _on_install_pressed() -> void:
	var plugin := _get_installer_plugin()
	if plugin == null:
		# build sans gradle : ancien comportement (navigateur)
		OS.shell_open(_apk_url)
		_close_popup()
		return
	if not plugin.canRequestInstall():
		_set_message("Android demande l'autorisation d'installer des applications inconnues. Activez-la pour Niger Streets puis revenez ici.")
		_set_buttons([
			["Autoriser l'installation", func() -> void: plugin.openUnknownSourceSettings()],
			["Télécharger quand même", _begin_download],
			["Plus tard", _close_popup],
		])
		return
	_begin_download()

## Phase 1 : téléchargement de l'APK dans le stockage de l'appli, avec progression
func _begin_download() -> void:
	if _msg != null:
		_msg.visible = false
	_delete_old_apk()   # jamais deux APK en stock (suppression du fichier après installation, comme MusicPro)
	_progress.text = "Téléchargement… 0 %"
	_progress.visible = true
	_set_buttons([])
	_dl_http = HTTPRequest.new()
	_dl_http.download_file = APK_SAVE_PATH
	_dl_http.timeout = 600.0   # 43 Mo sur une connexion mobile lente
	_dl_http.request_completed.connect(_on_download_completed)
	add_child(_dl_http)
	var headers: PackedStringArray = PackedStringArray(["User-Agent: NigerStreets-UpdateDownload"])
	if _dl_http.request(_apk_url, headers) != OK:
		_show_download_error()

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var size := 0
	var f := FileAccess.open(APK_SAVE_PATH, FileAccess.READ)
	if f != null:
		size = f.get_length()
		f.close()
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and size >= APK_MIN_SIZE
	_cleanup_dl()
	if not ok:
		_show_download_error()
		return
	# Phase 2 : installation par le plugin Android (confirmation système, sans navigateur)
	var plugin := _get_installer_plugin()
	if plugin != null:
		var abs_path: String = ProjectSettings.globalize_path(APK_SAVE_PATH)
		if plugin.installApk(abs_path):
			_progress.visible = false
			_set_message("Téléchargement terminé. Android vous demande de confirmer l'installation de la version %s." % _tag)
			_set_buttons([
				["Fermer", _close_popup],
				["Ouvrir dans le navigateur", _open_in_browser],
			])
			return
	# Repli : navigateur (l'installation ne s'est pas lancée)
	OS.shell_open(_apk_url)
	_close_popup()

## Secours : ouvre la page de téléchargement dans le navigateur (la popup reste affichée)
func _open_in_browser() -> void:
	OS.shell_open(_apk_url)

func _build_tag() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))

func _show_download_error() -> void:
	_progress.visible = false
	_set_message("Échec du téléchargement. Vérifiez votre connexion Internet.")
	_set_buttons([
		["Réessayer", _begin_download],
		["Ouvrir dans le navigateur", func() -> void:
			OS.shell_open(_apk_url)
			_close_popup()],
		["Plus tard", _close_popup],
	])

func _cleanup_dl() -> void:
	if _dl_http != null:
		_dl_http.queue_free()
		_dl_http = null

func _close_popup() -> void:
	popup_open = false
	_cleanup_dl()
	_msg = null
	_progress = null
	_buttons_box = null
	if _popup_layer != null:
		_popup_layer.queue_free()
		_popup_layer = null

func _style_button(b: Button, accent: bool) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1.0, 0.72, 0.20) if accent else Color(0.10, 0.13, 0.18, 0.98)
	normal.set_corner_radius_all(8)
	if not accent:
		normal.border_color = Color(1, 1, 1, 0.22)
		normal.set_border_width_all(2)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(1.0, 0.62, 0.10) if accent else Color(0.18, 0.22, 0.30, 0.98)
	pressed.set_corner_radius_all(8)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.78, 0.32) if accent else Color(0.14, 0.18, 0.25, 0.98)
	hover.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.06, 0.07, 0.09) if accent else Color(1, 1, 1, 0.95))
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.07, 0.09))
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.07, 0.09))
