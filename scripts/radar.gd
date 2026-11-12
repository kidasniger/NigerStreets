extends Control
class_name Radar
# Ch31 - Radar style GTA.

@export var radius: float = 80.0
@export var scale_meters_per_pixel: float = 1.5
@export var player_color: Color = Color(1.0, 1.0, 1.0, 0.95)
@export var mission_color: Color = Color(1.0, 0.9, 0.2, 0.95)
@export var background_color: Color = Color(0.05, 0.08, 0.12, 0.85)
@export var border_color: Color = Color(1.0, 1.0, 1.0, 0.4)
@export var north_color: Color = Color(1.0, 0.8, 0.2, 0.9)

var player_node: Node3D = null
var player_yaw: float = 0.0
var mission_positions: Array[Vector3] = []
var _last_pos: Vector3 = Vector3.INF

func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        custom_minimum_size = Vector2(radius * 2, radius * 2)
        size = custom_minimum_size
        await get_tree().process_frame
        var players = get_tree().get_nodes_in_group("player")
        if players.size() > 0:
                player_node = players[0]
        resized.connect(queue_redraw)
        queue_redraw()

## Appelé chaque frame par le HUD : ne redessine QUE si le yaw ou la position ont changé.
func set_player_yaw(yaw: float) -> void:
        var moved: bool = player_node != null and player_node.global_position.distance_squared_to(_last_pos) > 0.0001
        if not moved and yaw == player_yaw:
                return
        if player_node != null:
                _last_pos = player_node.global_position
        player_yaw = yaw
        queue_redraw()

func _draw() -> void:
        var center: Vector2 = size * 0.5
        var draw_radius: float = minf(size.x, size.y) * 0.5
        draw_circle(center, draw_radius, background_color)
        if player_node == null:
                draw_arc(center, draw_radius, 0, TAU, 64, border_color, 2.0)
                _draw_player_arrow(center)
                return
        var player_pos: Vector3 = player_node.global_position
        for mission_pos in mission_positions:
                _draw_entity(center, draw_radius, player_pos, mission_pos, mission_color, 5.0)
        _draw_player_arrow(center)
        draw_arc(center, draw_radius, 0, TAU, 64, border_color, 2.0)
        _draw_north_indicator(center, draw_radius)

func _draw_entity(center: Vector2, radius: float, player_pos: Vector3, entity_pos: Vector3, color: Color, dot_size: float) -> void:
        var diff: Vector2 = Vector2(entity_pos.x - player_pos.x, entity_pos.z - player_pos.z)
        diff /= scale_meters_per_pixel
        var rotated_diff: Vector2 = diff.rotated(player_yaw)
        if rotated_diff.length() > radius - 2.0:
                rotated_diff = rotated_diff.normalized() * (radius - 2.0)
        var pos: Vector2 = center + rotated_diff
        draw_circle(pos, dot_size, color)

func _draw_player_arrow(center: Vector2) -> void:
        var arrow_size: float = 10.0
        var points: PackedVector2Array = PackedVector2Array([
                        center + Vector2(0, -arrow_size),
                        center + Vector2(-arrow_size * 0.6, arrow_size * 0.6),
                        center + Vector2(arrow_size * 0.6, arrow_size * 0.6)
        ])
        draw_colored_polygon(points, player_color)

func _draw_north_indicator(center: Vector2, radius: float) -> void:
        var north_dir: Vector2 = Vector2(0, -1).rotated(player_yaw)
        if north_dir.length() > 0.01:
                var pos: Vector2 = center + north_dir * (radius - 14.0)
                var font: Font = ThemeDB.fallback_font
                var text_size: Vector2 = font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
                var text_pos: Vector2 = pos - text_size * 0.5
                draw_string(font, text_pos, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, north_color)
