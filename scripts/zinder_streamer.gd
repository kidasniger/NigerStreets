extends Node3D

## Streaming des bâtiments et des routes OSM de Zinder.
## Tuiles binaires dans res://assets/data/tiles/ (produites par ~/make_tiles.py) :
## b_X_Y.bin = bâtiments (tuiles de 200 m), r_X_Y.bin = routes (tuiles de 400 m).
## Elles sont chargées autour de la caméra puis déchargées quand elles s'éloignent.
## Le maillage est construit dans un thread (WorkerThreadPool) ; un seul ajout à la scène par image.
## Les routes sont des rubans plats sans collision (le sol suffit), coupés au bord du grand cercle.
## Le sol (nœud "Ground" du parent) suit le joueur par pas de 200 m.

const KIND_BUILDINGS: int = 0
const KIND_ROADS: int = 1
## Largeur (m) par classe de route, dans l'ordre de meta.json
const ROAD_WIDTHS: Array = [18.0, 16.0, 14.0, 12.0, 10.0, 8.0, 7.0, 6.0, 5.0, 4.0, 4.0, 2.0, 2.0, 2.0, 2.0]

@export var tiles_dir: String = "res://assets/data/tiles/"
@export var tile_m: float = 200.0
@export var load_radius: float = 450.0
@export var unload_radius: float = 650.0
@export var ring_clear: float = 36.0
@export var height_min: float = 4.0
@export var height_max: float = 7.5
@export var ground_y: float = 0.0
@export var seed_value: int = 4242
@export var max_jobs: int = 2
@export var follow_ground: bool = true
@export var build_roads: bool = true
@export var road_tile_m: float = 400.0
@export var road_material: Material
@export var road_uv_m: float = 5.408
@export var clip_radius: float = 30.0
@export var surface_y: float = 0.03
@export var default_road_width: float = 6.0

class TileJob extends RefCounted:
    var kind: int = 0
    var key: Vector2i = Vector2i.ZERO
    var task_id: int = -1
    var verts := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var walls := PackedVector3Array()
    var kept: int = 0
    var skipped: int = 0

var _material: StandardMaterial3D
var _palette: Array[Color] = [
    Color(0.80, 0.68, 0.50), Color(0.74, 0.60, 0.42), Color(0.86, 0.78, 0.62),
    Color(0.70, 0.52, 0.38), Color(0.88, 0.84, 0.76),
]
var _tiles: Dictionary = {}     # Vector3i(x, y, genre) -> Node
var _jobs: Dictionary = {}      # Vector3i -> TileJob
var _missing: Dictionary = {}   # Vector3i -> true (pas de fichier ou tuile vide)
var _queue: Array[Vector3i] = []
var _timer: float = 0.0
var _ground: Node3D = null


func _ready() -> void:
    _material = StandardMaterial3D.new()
    _material.vertex_color_use_as_albedo = true
    _material.roughness = 1.0
    if road_material == null:
        var rm := StandardMaterial3D.new()
        rm.albedo_color = Color(0.17, 0.17, 0.18)
        rm.roughness = 1.0
        road_material = rm
    var parent: Node = get_parent()
    if parent != null:
        _ground = parent.get_node_or_null("Ground") as Node3D


func _exit_tree() -> void:
    for job: TileJob in _jobs.values():
        WorkerThreadPool.wait_for_task_completion(job.task_id)
    _jobs.clear()


func _process(delta: float) -> void:
    _collect_finished()
    _timer -= delta
    if _timer <= 0.0:
        _timer = 0.4
        _refresh()
    _start_jobs()


func _focus() -> Vector2:
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam != null:
        return Vector2(cam.global_position.x, cam.global_position.z)
    return Vector2.ZERO


func _size_of(kind: int) -> float:
    return road_tile_m if kind == KIND_ROADS else tile_m


func _tile_path(ck: Vector3i) -> String:
    var prefix: String = "r_" if ck.z == KIND_ROADS else "b_"
    return tiles_dir + ("%s%d_%d.bin" % [prefix, ck.x, ck.y])


func _dist_to_tile(p: Vector2, k: Vector2i, tsize: float) -> float:
    var x0: float = float(k.x) * tsize
    var y0: float = float(k.y) * tsize
    var dx: float = maxf(maxf(x0 - p.x, p.x - (x0 + tsize)), 0.0)
    var dy: float = maxf(maxf(y0 - p.y, p.y - (y0 + tsize)), 0.0)
    return sqrt(dx * dx + dy * dy)


func _by_dist(a: Array, b: Array) -> bool:
    return float(a[0]) < float(b[0])


func _refresh() -> void:
    var p: Vector2 = _focus()
    if follow_ground and _ground != null:
        var gx: float = snappedf(p.x, 200.0)
        var gz: float = snappedf(p.y, 200.0)
        if not is_equal_approx(_ground.global_position.x, gx) or not is_equal_approx(_ground.global_position.z, gz):
            _ground.global_position = Vector3(gx, 0.0, gz)

    # déchargement des tuiles éloignées
    for old_key: Vector3i in _tiles.keys():
        var old_d: float = _dist_to_tile(p, Vector2i(old_key.x, old_key.y), _size_of(old_key.z))
        if old_d > unload_radius:
            (_tiles[old_key] as Node).queue_free()
            _tiles.erase(old_key)

    # tuiles à charger (bâtiments et routes), les plus proches d'abord
    var kinds: Array[int] = [KIND_BUILDINGS]
    if build_roads:
        kinds.append(KIND_ROADS)
    var wanted: Array = []
    for kind: int in kinds:
        var tsize: float = _size_of(kind)
        var span: int = int(ceil(load_radius / tsize)) + 1
        var c := Vector2i(floori(p.x / tsize), floori(p.y / tsize))
        for ty in range(c.y - span, c.y + span + 1):
            for tx in range(c.x - span, c.x + span + 1):
                var ck := Vector3i(tx, ty, kind)
                if _tiles.has(ck) or _jobs.has(ck) or _missing.has(ck):
                    continue
                var d: float = _dist_to_tile(p, Vector2i(tx, ty), tsize)
                if d > load_radius:
                    continue
                if not FileAccess.file_exists(_tile_path(ck)):
                    _missing[ck] = true
                    continue
                wanted.append([d, ck])
    wanted.sort_custom(_by_dist)
    _queue.clear()
    for w: Array in wanted:
        _queue.append(w[1])


func _start_jobs() -> void:
    while _jobs.size() < max_jobs and not _queue.is_empty():
        var ck: Vector3i = _queue.pop_front()
        if _tiles.has(ck) or _jobs.has(ck):
            continue
        var job := TileJob.new()
        job.kind = ck.z
        job.key = Vector2i(ck.x, ck.y)
        job.task_id = WorkerThreadPool.add_task(_build_job.bind(job))
        _jobs[ck] = job


## Au plus une tuile terminée ajoutée à la scène par image
func _collect_finished() -> void:
    for ck: Vector3i in _jobs.keys():
        var job: TileJob = _jobs[ck]
        if not WorkerThreadPool.is_task_completed(job.task_id):
            continue
        WorkerThreadPool.wait_for_task_completion(job.task_id)
        _jobs.erase(ck)
        _commit(job)
        return


func _commit(job: TileJob) -> void:
    var ck := Vector3i(job.key.x, job.key.y, job.kind)
    if job.verts.is_empty():
        _missing[ck] = true
        return
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = job.verts
    arrays[Mesh.ARRAY_NORMAL] = job.normals
    if job.kind == KIND_ROADS:
        arrays[Mesh.ARRAY_TEX_UV] = job.uvs
    else:
        arrays[Mesh.ARRAY_COLOR] = job.colors
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

    if job.kind == KIND_ROADS:
        var rmi := MeshInstance3D.new()
        rmi.name = "Route_%d_%d" % [job.key.x, job.key.y]
        rmi.mesh = mesh
        rmi.material_override = road_material
        rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(rmi)
        _tiles[ck] = rmi
        return

    var body := StaticBody3D.new()
    body.name = "Tuile_%d_%d" % [job.key.x, job.key.y]
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = _material
    body.add_child(mi)
    if not job.walls.is_empty():
        var shape := ConcavePolygonShape3D.new()
        shape.set_faces(job.walls)
        var cs := CollisionShape3D.new()
        cs.shape = shape
        body.add_child(cs)
    add_child(body)
    _tiles[ck] = body


# ------------------------------------------------------------------ thread de construction

func _build_job(job: TileJob) -> void:
    if job.kind == KIND_ROADS:
        _build_roads_job(job)
    else:
        _build_buildings_job(job)


func _build_buildings_job(job: TileJob) -> void:
    var buf: PackedByteArray = FileAccess.get_file_as_bytes(_tile_path(Vector3i(job.key.x, job.key.y, KIND_BUILDINGS)))
    if buf.size() < 4:
        return
    var n: int = buf.decode_u32(0)
    var head: int = 4 + 4 * n
    if n <= 0 or buf.size() < head:
        return
    var coords: PackedFloat32Array = buf.slice(head).to_float32_array()
    var rng := RandomNumberGenerator.new()
    rng.seed = hash(Vector3i(job.key.x, job.key.y, seed_value))
    var cursor: int = 0
    for i in range(n):
        var cnt: int = buf.decode_u32(4 + 4 * i)
        if (cursor + cnt) * 2 > coords.size():
            break
        var poly := PackedVector2Array()
        poly.resize(cnt)
        for j in range(cnt):
            poly[j] = Vector2(coords[(cursor + j) * 2], coords[(cursor + j) * 2 + 1])
        cursor += cnt
        if not _accept(poly):
            job.skipped += 1
            continue
        var h: float = rng.randf_range(height_min, height_max)
        var col: Color = _palette[rng.randi() % _palette.size()]
        if _extrude(job, poly, h, col):
            job.kept += 1
        else:
            job.skipped += 1


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
    for p in poly:
        if p.length() < ring_clear:
            return false
    return true


## Ordonne un triangle pour que sa face avant regarde dans la direction n.
func _tri(job: TileJob, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, is_wall: bool) -> void:
    if (c - a).cross(b - a).dot(n) < 0.0:
        var t: Vector3 = b
        b = c
        c = t
    job.verts.append(a)
    job.verts.append(b)
    job.verts.append(c)
    for i in range(3):
        job.normals.append(n)
        job.colors.append(col)
    if is_wall:
        job.walls.append(a)
        job.walls.append(b)
        job.walls.append(c)


func _extrude(job: TileJob, poly: PackedVector2Array, h: float, col: Color) -> bool:
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
        _tri(job, Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(c.x, top, c.y), Vector3.UP, roof_col, false)

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
        _tri(job, b1, b2, t2, nrm, col, true)
        _tri(job, b1, t2, t1, nrm, col, true)
    return true


# ------------------------------------------------------------------ routes (thread)

func _build_roads_job(job: TileJob) -> void:
    var buf: PackedByteArray = FileAccess.get_file_as_bytes(_tile_path(Vector3i(job.key.x, job.key.y, KIND_ROADS)))
    if buf.size() < 4:
        return
    var n: int = buf.decode_u32(0)
    var head: int = 4 + 8 * n
    if n <= 0 or buf.size() < head:
        return
    var coords: PackedFloat32Array = buf.slice(head).to_float32_array()
    # la découpe au bord du rond-point ne sert que pour la tuile qui contient le rond-point
    var near_ring: bool = _dist_to_tile(Vector2.ZERO, job.key, road_tile_m) <= clip_radius + 1.0
    var cursor: int = 0
    for i in range(n):
        var cnt: int = buf.decode_u32(4 + 4 * i)
        var cls: int = buf.decode_u32(4 + 4 * n + 4 * i)
        if (cursor + cnt) * 2 > coords.size():
            break
        var pts := PackedVector2Array()
        pts.resize(cnt)
        for j in range(cnt):
            pts[j] = Vector2(coords[(cursor + j) * 2], coords[(cursor + j) * 2 + 1])
        cursor += cnt
        if cnt < 2:
            continue
        var width: float = default_road_width
        if cls < ROAD_WIDTHS.size():
            width = float(ROAD_WIDTHS[cls])
        if near_ring:
            for piece: PackedVector2Array in _clip(pts, _clip_for(width)):
                _add_ribbon(job, piece, width * 0.5)
        else:
            _add_ribbon(job, pts, width * 0.5)
    job.kept = job.verts.size() / 6


func _clip_for(width: float) -> float:
    var hw: float = width * 0.5
    return maxf(sqrt(maxf(clip_radius * clip_radius - hw * hw, 0.0)) - 0.5, 1.0)


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
func _add_ribbon(job: TileJob, pts: PackedVector2Array, hw: float) -> int:
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
        _vert(job, left[i])
        _vert(job, left[i + 1])
        _vert(job, right[i + 1])
        _vert(job, left[i])
        _vert(job, right[i + 1])
        _vert(job, right[i])
    return n - 1


func _vert(job: TileJob, p: Vector2) -> void:
    job.verts.append(Vector3(p.x, surface_y, p.y))
    job.normals.append(Vector3.UP)
    job.uvs.append(p / road_uv_m)
