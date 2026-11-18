extends Node3D
## Routes OSM de la zone pilote (zone_elf_400m.json) : rubans plats, largeur selon la classe.
## Les routes s'arrêtent au bord du grand cercle du rond-point (clip_radius).

@export var json_path: String = "res://assets/data/zone_elf_400m.json"
@export var road_material: Material
@export var tile_m: float = 5.408
@export var clip_radius: float = 30.0
@export var surface_y: float = 0.03
@export var default_width: float = 6.0

var _widths: Dictionary = {
        "motorway": 18.0, "trunk": 16.0, "primary": 14.0, "secondary": 12.0,
        "tertiary": 10.0, "unclassified": 8.0, "residential": 7.0,
        "living_street": 6.0, "service": 5.0, "track": 4.0,
        "pedestrian": 4.0, "path": 2.0, "footway": 2.0, "cycleway": 2.0, "steps": 2.0,
}

func _ready() -> void:
        var text: String = FileAccess.get_file_as_string(json_path)
        if text.is_empty():
                push_error("ZinderRoads : fichier introuvable : " + json_path)
                return
        var data: Variant = JSON.parse_string(text)
        if not (data is Dictionary):
                push_error("ZinderRoads : JSON invalide")
                return
        var roads: Array = (data as Dictionary).get("roads", [])
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var pieces: int = 0
        var segments: int = 0
        for road: Variant in roads:
                var info: Dictionary = road as Dictionary
                var raw: Array = info.get("p", [])
                var width: float = _width_of(String(info.get("k", "")))
                var pts: PackedVector2Array = _to_points(raw)
                for piece: PackedVector2Array in _clip(pts, _clip_for(width)):
                        var added: int = _add_ribbon(st, piece, width * 0.5)
                        if added > 0:
                                pieces += 1
                                segments += added
        if segments == 0:
                push_warning("ZinderRoads : aucune route construite")
                return
        var mesh: ArrayMesh = st.commit()
        var body := StaticBody3D.new()
        body.name = "ZinderRoadsBody"
        body.collision_layer = 1
        body.collision_mask = 1
        add_child(body)
        var mesh_instance := MeshInstance3D.new()
        mesh_instance.mesh = mesh
        if road_material != null:
                mesh_instance.material_override = road_material
        body.add_child(mesh_instance)
        var collision := CollisionShape3D.new()
        collision.shape = mesh.create_trimesh_shape()
        body.add_child(collision)
        print("ZinderRoads : %d tronçons, %d segments" % [pieces, segments])

func _width_of(kind: String) -> float:
        var key: String = kind.trim_suffix("_link")
        return float(_widths.get(key, default_width))

func _clip_for(width: float) -> float:
        var hw: float = width * 0.5
        return maxf(sqrt(maxf(clip_radius * clip_radius - hw * hw, 0.0)) - 0.5, 1.0)

func _to_points(raw: Array) -> PackedVector2Array:
        var pts := PackedVector2Array()
        var i: int = 0
        while i + 1 < raw.size():
                pts.append(Vector2(float(raw[i]), float(raw[i + 1])))
                i += 2
        return pts

## Découpe la polyligne : ne garde que les parties hors du cercle de rayon rc
func _clip(pts: PackedVector2Array, rc: float) -> Array:
        var result: Array = []
        var current := PackedVector2Array()
        for i in range(pts.size() - 1):
                var a: Vector2 = pts[i]
                var b: Vector2 = pts[i + 1]
                var dv: Vector2 = b - a
                var qa: float = dv.dot(dv)
                if qa < 0.0001:
                        continue
                var bq: float = 2.0 * a.dot(dv)
                var cq: float = a.dot(a) - rc * rc
                var disc: float = bq * bq - 4.0 * qa * cq
                var intervals: Array = []
                var hit: bool = false
                var t1: float = 0.0
                var t2: float = 0.0
                if disc > 0.0:
                        var sq: float = sqrt(disc)
                        t1 = (-bq - sq) / (2.0 * qa)
                        t2 = (-bq + sq) / (2.0 * qa)
                        hit = t2 > 0.0 and t1 < 1.0
                if hit:
                        if t1 > 0.0:
                                intervals.append(Vector2(0.0, t1))
                        if t2 < 1.0:
                                intervals.append(Vector2(t2, 1.0))
                else:
                        intervals.append(Vector2(0.0, 1.0))
                for iv: Vector2 in intervals:
                        var pa: Vector2 = a + dv * iv.x
                        var pb: Vector2 = a + dv * iv.y
                        if current.is_empty():
                                current.append(pa)
                        elif current[current.size() - 1].distance_to(pa) > 0.01:
                                if current.size() >= 2:
                                        result.append(current)
                                current = PackedVector2Array()
                                current.append(pa)
                        current.append(pb)
                        if iv.y < 1.0:
                                if current.size() >= 2:
                                        result.append(current)
                                current = PackedVector2Array()
        if current.size() >= 2:
                result.append(current)
        return result

## Ruban le long d'une polyligne (coins en onglet) ; renvoie le nombre de segments
func _add_ribbon(st: SurfaceTool, pts: PackedVector2Array, hw: float) -> int:
        var clean := PackedVector2Array()
        for p: Vector2 in pts:
                if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.05:
                        clean.append(p)
        var n: int = clean.size()
        if n < 2:
                return 0
        var left := PackedVector2Array()
        var right := PackedVector2Array()
        for i in range(n):
                var dir_prev: Vector2 = Vector2.ZERO
                var dir_next: Vector2 = Vector2.ZERO
                if i > 0:
                        dir_prev = (clean[i] - clean[i - 1]).normalized()
                if i < n - 1:
                        dir_next = (clean[i + 1] - clean[i]).normalized()
                var tangent: Vector2 = dir_prev + dir_next
                var seg_dir: Vector2 = dir_next if i < n - 1 else dir_prev
                if tangent.length() < 0.001:
                        tangent = seg_dir
                tangent = tangent.normalized()
                var normal: Vector2 = Vector2(-tangent.y, tangent.x)
                var seg_normal: Vector2 = Vector2(-seg_dir.y, seg_dir.x)
                var factor: float = 1.0 / maxf(absf(normal.dot(seg_normal)), 0.5)
                var offset: Vector2 = normal * hw * factor
                left.append(clean[i] - offset)
                right.append(clean[i] + offset)
        for i in range(n - 1):
                _vert(st, left[i])
                _vert(st, left[i + 1])
                _vert(st, right[i + 1])
                _vert(st, left[i])
                _vert(st, right[i + 1])
                _vert(st, right[i])
        return n - 1

func _vert(st: SurfaceTool, p: Vector2) -> void:
        var v := Vector3(p.x, surface_y, p.y)
        st.set_normal(Vector3.UP)
        st.set_uv(Vector2(v.x, v.z) / tile_m)
        st.add_vertex(v)
