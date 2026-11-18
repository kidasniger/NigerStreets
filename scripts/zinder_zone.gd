extends Node3D
## Zone pilote de Zinder : extrusion des polygones OSM (centrée sur le rond-point ELF).
## Données : res://assets/data/zone_elf_400m.json (mètres, y de la carte = Z du jeu).

@export var data_path: String = "res://assets/data/zone_elf_400m.json"
@export var min_area: float = 15.0
@export var ring_clear: float = 36.0
@export var clear_arms: bool = false
@export var arm_half_width: float = 14.0
@export var arm_length: float = 135.0
@export var height_min: float = 4.0
@export var height_max: float = 7.5
@export var ground_y: float = 0.0
@export var seed_value: int = 4242


func _ready() -> void:
    var text: String = FileAccess.get_file_as_string(data_path)
    if text.is_empty():
        push_error("ZinderZone : fichier introuvable : " + data_path)
        return
    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Dictionary):
        push_error("ZinderZone : JSON invalide : " + data_path)
        return
    var data: Dictionary = parsed
    var list: Array = data.get("buildings", [])

    var palette: Array[Color] = [
        Color(0.80, 0.68, 0.50), Color(0.74, 0.60, 0.42), Color(0.86, 0.78, 0.62),
        Color(0.70, 0.52, 0.38), Color(0.88, 0.84, 0.76),
    ]
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var wall_faces := PackedVector3Array()
    var kept: int = 0
    var skipped: int = 0

    for flat in list:
        var poly: PackedVector2Array = _to_poly(flat)
        if not _accept(poly):
            skipped += 1
            continue
        var h: float = rng.randf_range(height_min, height_max)
        var col: Color = palette[rng.randi() % palette.size()]
        if _extrude(st, wall_faces, poly, h, col):
            kept += 1
        else:
            skipped += 1

    if kept == 0:
        push_warning("ZinderZone : aucun bâtiment construit")
        return

    var mi := MeshInstance3D.new()
    mi.name = "ZinderBuildings"
    mi.mesh = st.commit()
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 1.0
    mi.material_override = mat
    add_child(mi)

    var body := StaticBody3D.new()
    body.name = "ZinderBuildingsBody"
    var cs := CollisionShape3D.new()
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(wall_faces)
    cs.shape = shape
    body.add_child(cs)
    add_child(body)

    print("ZinderZone : %d bâtiments construits, %d ignorés, %d triangles de murs" % [kept, skipped, wall_faces.size() / 3])


func _to_poly(flat: Array) -> PackedVector2Array:
    var poly := PackedVector2Array()
    var n: int = flat.size() - 1
    var i: int = 0
    while i < n:
        poly.append(Vector2(float(flat[i]), float(flat[i + 1])))
        i += 2
    if poly.size() > 1 and poly[0].distance_to(poly[poly.size() - 1]) < 0.01:
        poly.remove_at(poly.size() - 1)
    return poly


func _signed_area(poly: PackedVector2Array) -> float:
    var s: float = 0.0
    var n: int = poly.size()
    for i in range(n):
        var a: Vector2 = poly[i]
        var b: Vector2 = poly[(i + 1) % n]
        s += a.x * b.y - b.x * a.y
    return s * 0.5


func _accept(poly: PackedVector2Array) -> bool:
    if poly.size() < 3:
        return false
    if absf(_signed_area(poly)) < min_area:
        return false
    var min_p := Vector2(INF, INF)
    var max_p := Vector2(-INF, -INF)
    for p in poly:
        if p.length() < ring_clear:
            return false
        min_p = Vector2(minf(min_p.x, p.x), minf(min_p.y, p.y))
        max_p = Vector2(maxf(max_p.x, p.x), maxf(max_p.y, p.y))
    if clear_arms:
        # bande nord-sud (le long de Z) et bande est-ouest (le long de X)
        var hits_ns: bool = min_p.x < arm_half_width and max_p.x > -arm_half_width and min_p.y < arm_length and max_p.y > -arm_length
        var hits_ew: bool = min_p.y < arm_half_width and max_p.y > -arm_half_width and min_p.x < arm_length and max_p.x > -arm_length
        if hits_ns or hits_ew:
            return false
    return true


## Ordonne un triangle pour que sa face avant (sens horaire, Godot) regarde dans la direction n.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> PackedVector3Array:
    if (c - a).cross(b - a).dot(n) < 0.0:
        var t: Vector3 = b
        b = c
        c = t
    for v in [a, b, c]:
        st.set_color(col)
        st.set_normal(n)
        st.add_vertex(v)
    return PackedVector3Array([a, b, c])


func _extrude(st: SurfaceTool, wall_faces: PackedVector3Array, poly: PackedVector2Array, h: float, col: Color) -> bool:
    # orientation anti-horaire dans le plan (x, z) pour connaître le côté extérieur des murs
    var pts := PackedVector2Array()
    if _signed_area(poly) < 0.0:
        for i in range(poly.size() - 1, -1, -1):
            pts.append(poly[i])
    else:
        pts = poly
    var tris: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
    if tris.is_empty():
        return false

    var top: float = ground_y + h
    var roof_col: Color = col.darkened(0.15)
    for k in range(0, tris.size(), 3):
        var a: Vector2 = pts[tris[k]]
        var b: Vector2 = pts[tris[k + 1]]
        var c: Vector2 = pts[tris[k + 2]]
        _tri(st, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(c.x, top, c.y), Vector3.UP, roof_col)

    var n: int = pts.size()
    for i in range(n):
        var p1: Vector2 = pts[i]
        var p2: Vector2 = pts[(i + 1) % n]
        var d: Vector2 = p2 - p1
        if d.length() < 0.05:
            continue
        var nrm: Vector3 = Vector3(d.y, 0.0, -d.x).normalized()
        var b1 := Vector3(p1.x, ground_y, p1.y)
        var b2 := Vector3(p2.x, ground_y, p2.y)
        var t1 := Vector3(p1.x, top, p1.y)
        var t2 := Vector3(p2.x, top, p2.y)
        wall_faces.append_array(_tri(st, b1, b2, t2, nrm, col))
        wall_faces.append_array(_tri(st, b1, t2, t1, nrm, col))
    return true
