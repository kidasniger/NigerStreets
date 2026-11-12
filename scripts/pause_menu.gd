extends CanvasLayer
class_name PauseMenu
# Ch31 - Menu pause + réglages (sensibilité caméra, volume, qualité graphique :
# ombres + MSAA + échelle de rendu 3D).
# Ouverture : Échap (PC), bouton Android « retour », ou bouton dessiné sous le radar.
# L'ouverture met l'arbre du jeu en pause (get_tree().paused) ; cette couche reste
# active grâce à PROCESS_MODE_ALWAYS. Affichage et hit-test faits à la main
# (même principe que mobile_controls.gd : fiable au doigt, sans passer par le GUI).

const SPLASH_SCENE: String = "res://scenes/splash.tscn"
const GOLD: Color = Color(1.0, 0.72, 0.20)
const PANEL_BG: Color = Color(0.05, 0.08, 0.12, 0.97)
const BTN_BG: Color = Color(0.10, 0.13, 0.18, 0.98)

var open: bool = false
var show_settings: bool = false
var overlay: PauseOverlay
var _click_sfx: AudioStreamPlayer

func _ready() -> void:
        layer = 8
        process_mode = Node.PROCESS_MODE_ALWAYS   # reste actif quand le jeu est en pause
        overlay = PauseOverlay.new()
        overlay.parent_menu = self
        overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
        overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(overlay)
        _click_sfx = AudioStreamPlayer.new()
        var sfx_path: String = "res://assets/audio/ui_click.ogg"
        if ResourceLoader.exists(sfx_path):
                _click_sfx.stream = load(sfx_path) as AudioStream
        add_child(_click_sfx)
        GameSettings.load_settings()
        GameSettings.apply_audio()

func _notification(what: int) -> void:
        if what == NOTIFICATION_WM_GO_BACK_REQUEST:
                toggle()   # bouton Android « retour » : ouvre la pause au lieu de quitter l'app

## Ouvre/ferme le menu et met l'arbre du jeu en pause
func toggle() -> void:
        open = not open
        show_settings = false
        get_tree().paused = open
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
        overlay.queue_redraw()

func _play_click() -> void:
        if _click_sfx.stream != null:
                _click_sfx.play()

## Retour à l'écran titre (appelé par l'overlay)
func go_to_menu() -> void:
        GameSettings.save_settings()
        get_tree().paused = false
        get_tree().change_scene_to_file(SPLASH_SCENE)

func quit_game() -> void:
        GameSettings.save_settings()
        get_tree().quit()


# ------------------------------------------------------------------ overlay

class PauseOverlay extends Control:
        const MOUSE_FINGER: int = -2   # index fictif pour distinguer la souris des doigts
        var parent_menu: PauseMenu
        var _slider_finger: int = -1   # doigt (ou souris) en train de régler un curseur
        var _slider_id: String = ""    # "sens" ou "vol"

        func _input(event: InputEvent) -> void:
                var menu := parent_menu
                if menu == null:
                        return
                # Échap / manette : bascule la pause, ouvert ou fermé
                if event.is_action("ui_cancel") and event.is_pressed() and not event.is_echo():
                        get_viewport().set_input_as_handled()
                        menu.toggle()
                        return
                var touch := event as InputEventScreenTouch
                if touch != null:
                        if touch.pressed:
                                _press(touch.position, touch.index)
                        elif touch.index == _slider_finger:
                                _end_slider()
                        return
                var click := event as InputEventMouseButton
                if click != null and click.button_index == MOUSE_BUTTON_LEFT:
                        if click.pressed:
                                _press(click.position, MOUSE_FINGER)
                        elif _slider_finger == MOUSE_FINGER:
                                _end_slider()
                        return
                var drag := event as InputEventScreenDrag
                if drag != null and drag.index == _slider_finger:
                        _update_slider(drag.position)
                        return
                var motion := event as InputEventMouseMotion
                if motion != null and _slider_finger == MOUSE_FINGER and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
                        _update_slider(motion.position)

        func _press(pos: Vector2, finger: int) -> void:
                var menu := parent_menu
                if not menu.open:
                        if pos.distance_to(_pause_btn_center()) <= 28.0:
                                get_viewport().set_input_as_handled()   # ne pas réveiller joystick / caméra
                                menu.toggle()
                        return
                var slider: String = _slider_hit(pos)
                if not slider.is_empty():
                        _slider_finger = finger
                        _slider_id = slider
                        _update_slider(pos)
                        return
                if menu.show_settings:
                        if _in(_retour_rect(), pos):
                                menu.show_settings = false; menu._play_click(); queue_redraw()
                        elif _in(_quality_rect(), pos):
                                _toggle_quality()
                        return
                if _in(_btn_rect(0), pos):
                        menu._play_click(); menu.toggle()          # Reprendre
                elif _in(_btn_rect(1), pos):
                        menu.show_settings = true; menu._play_click(); queue_redraw()
                elif _in(_btn_rect(2), pos):
                        menu._play_click(); menu.go_to_menu()      # Menu principal
                elif _in(_btn_rect(3), pos):
                        menu.quit_game()                           # Quitter l'application

        func _end_slider() -> void:
                _slider_finger = -1
                _slider_id = ""
                GameSettings.save_settings()

        func _toggle_quality() -> void:
                GameSettings.quality_high = not GameSettings.quality_high
                GameSettings.apply_shadows(get_tree())
                GameSettings.apply_viewport(get_viewport())   # MSAA + échelle de rendu 3D
                GameSettings.save_settings()
                parent_menu._play_click()
                queue_redraw()

        func _slider_hit(pos: Vector2) -> String:
                if not parent_menu.open or not parent_menu.show_settings:
                        return ""
                if pos.y >= _slider_track_y(0) - 22.0 and pos.y <= _slider_track_y(0) + 22.0:
                        return "sens"
                if pos.y >= _slider_track_y(1) - 22.0 and pos.y <= _slider_track_y(1) + 22.0:
                        return "vol"
                return ""

        func _update_slider(pos: Vector2) -> void:
                var t: float = clampf((pos.x - _track_x0()) / maxf(_track_x1() - _track_x0(), 1.0), 0.0, 1.0)
                if _slider_id == "sens":
                        GameSettings.camera_sensitivity = lerpf(0.3, 3.0, t)
                elif _slider_id == "vol":
                        GameSettings.master_volume = t
                        GameSettings.apply_audio()
                queue_redraw()

        # ------------------------------------------------ géométrie

        func _panel_rect() -> Rect2:
                var w: float = minf(size.x * 0.92, 560.0)
                var h: float = 372.0 if parent_menu.show_settings else 344.0
                return Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h)

        func _btn_rect(i: int) -> Rect2:
                var p := _panel_rect()
                var y: float = p.position.y + 74.0 + float(i) * 64.0
                return Rect2(p.position.x + 28.0, y, p.size.x - 56.0, 52.0)

        func _slider_track_y(i: int) -> float:
                return _panel_rect().position.y + 108.0 + float(i) * 66.0

        func _track_x0() -> float:
                return _panel_rect().position.x + 28.0

        func _track_x1() -> float:
                return _panel_rect().end.x - 110.0

        func _quality_rect() -> Rect2:
                var p := _panel_rect()
                return Rect2(p.position.x + 28.0, p.position.y + 244.0, p.size.x - 56.0, 52.0)

        func _retour_rect() -> Rect2:
                var p := _panel_rect()
                return Rect2(p.position.x + 28.0, p.position.y + 308.0, p.size.x - 56.0, 52.0)

        func _pause_btn_center() -> Vector2:
                var left: float = 56.0 if OS.has_feature("mobile") else 14.0
                return Vector2(left + 22.0, 200.0)

        func _in(r: Rect2, pos: Vector2) -> bool:
                return pos.x >= r.position.x and pos.x <= r.end.x and pos.y >= r.position.y and pos.y <= r.end.y

        # ------------------------------------------------ dessin

        func _draw() -> void:
                var menu := parent_menu
                if not menu.open:
                        _draw_pause_btn()
                        return
                draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.55))
                var p := _panel_rect()
                draw_rect(p, PANEL_BG)
                draw_rect(p, GOLD, false, 2.0)
                _text(Vector2(p.get_center().x, p.position.y + 42.0), "RÉGLAGES" if menu.show_settings else "PAUSE", 30, GOLD, true)
                if menu.show_settings:
                        _draw_settings()
                else:
                        var labels: Array[String] = ["Reprendre", "Réglages", "Menu principal", "Quitter l'application"]
                        for i in labels.size():
                                _draw_btn(_btn_rect(i), labels[i], i == 0)
                _text(Vector2(p.get_center().x, p.end.y - 14.0), "Échap / retour : fermer", 13, Color(1, 1, 1, 0.45), true)

        func _draw_settings() -> void:
                _slider("Sensibilité caméra", 0, GameSettings.camera_sensitivity, 0.3, 3.0, true)
                _slider("Volume général", 1, GameSettings.master_volume, 0.0, 1.0, false)
                _draw_btn(_quality_rect(), "Qualité : %s" % ("haute" if GameSettings.quality_high else "éco"), GameSettings.quality_high)
                _draw_btn(_retour_rect(), "Retour", false)

        func _slider(label: String, i: int, value: float, vmin: float, vmax: float, as_mult: bool) -> void:
                var y: float = _slider_track_y(i)
                var x0: float = _track_x0()
                var x1: float = _track_x1()
                _text(Vector2(x0, y - 24.0), label, 18, Color(1, 1, 1, 0.9), false)
                var t: float = clampf((value - vmin) / maxf(vmax - vmin, 0.0001), 0.0, 1.0)
                var knob: float = lerpf(x0, x1, t)
                draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.18), 6.0)
                draw_line(Vector2(x0, y), Vector2(knob, y), GOLD, 6.0)
                draw_circle(Vector2(knob, y), 13.0, Color.WHITE)
                var val: String = ("×%.2f" % value) if as_mult else "%d %%" % int(round(value * 100.0))
                var font: Font = ThemeDB.fallback_font
                var vw: float = font.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
                _text(Vector2(_panel_rect().end.x - 24.0 - vw, y + 5.0), val, 18, GOLD, false)

        func _draw_btn(r: Rect2, label: String, accent: bool) -> void:
                draw_rect(r, GOLD if accent else BTN_BG)
                if not accent:
                        draw_rect(r, Color(1, 1, 1, 0.22), false, 1.5)
                _text(Vector2(r.get_center().x, r.get_center().y + 8.0), label, 22, Color(0.06, 0.07, 0.09) if accent else Color(1, 1, 1, 0.95), true)

        func _draw_pause_btn() -> void:
                var c := _pause_btn_center()
                draw_circle(c, 22.0, Color(0.08, 0.10, 0.14, 0.78))
                draw_arc(c, 22.0, 0.0, TAU, 40, Color(1, 1, 1, 0.35), 2.5)
                draw_rect(Rect2(c + Vector2(-7.5, -9.0), Vector2(5.5, 18.0)), Color(1, 1, 1, 0.92))
                draw_rect(Rect2(c + Vector2(2.0, -9.0), Vector2(5.5, 18.0)), Color(1, 1, 1, 0.92))

        func _text(pos: Vector2, txt: String, font_size: int, col: Color, centered: bool) -> void:
                var font: Font = ThemeDB.fallback_font
                var p := pos
                if centered:
                        var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
                        p.x -= w * 0.5
                draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
