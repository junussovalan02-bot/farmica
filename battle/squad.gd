class_name Squad
extends Node3D
## Отряд: один объект с позицией, строем, здоровьем и моралью.
## Отдельные муравьи только рисуются вокруг него через MultiMesh.

const SP := 1.1            # шаг между местами в строю, м
const ANT_HP := 10.0

var side: String = "ally"  # "ally" | "enemy"
var idx: int = 0
var squad_name: String = ""
var form: String = "line"  # "line" | "column"
var state: String = "idle" # idle | moving | fighting | fleeing | routed
var target: Squad = null
var move_to = null         # Vector3 или null
var morale: float = 100.0
var n0: int = 0
var in_contact: int = 0
var dmg_pool: float = 0.0
var flash: float = 0.0
var pos: Vector3 = Vector3.ZERO   # центр фронта отряда (y = 0)
var ang: float = 0.0              # направление фронта в плоскости XZ

var ants: Array = []  # [{pos: Vector3, tgt: Vector3, ph: float}]

var _mmi: MultiMeshInstance3D
var _mat: StandardMaterial3D
var _base_color: Color
var _banner: Label3D
var _ring: MeshInstance3D
var _ring_mesh: CylinderMesh
var _ring_mat: StandardMaterial3D
var _flee_label: Label3D


func setup(p_side: String, p_idx: int, p_pos: Vector3, p_ang: float, count: int) -> void:
	side = p_side
	idx = p_idx
	pos = p_pos
	ang = p_ang
	n0 = count
	squad_name = ("Солдаты " if side == "ally" else "Чёрные ") + str(idx + 1)
	_base_color = Color(0.78, 0.45, 0.16) if side == "ally" else Color(0.09, 0.07, 0.06)

	for i in count:
		var p := pos + Vector3(randf_range(-3, 3), 0, randf_range(-2, 2))
		ants.append({"pos": p, "tgt": p, "ph": randf() * TAU})

	# Муравьи: кубики через MultiMesh
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.3, 0.42)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = _base_color
	_mat.roughness = 0.7
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = count
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mmi)

	# Знамя: номер отряда над центром
	_banner = Label3D.new()
	_banner.text = str(idx + 1)
	_banner.font_size = 64
	_banner.pixel_size = 0.02
	_banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_banner.modulate = Color(0.95, 0.65, 0.25) if side == "ally" else Color(0.75, 0.72, 0.8)
	_banner.outline_size = 12
	_banner.outline_modulate = Color(0.1, 0.05, 0.02)
	add_child(_banner)

	# Кольцо выделения
	_ring_mesh = CylinderMesh.new()
	_ring_mesh.height = 0.05
	_ring = MeshInstance3D.new()
	_ring.mesh = _ring_mesh
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(0.85, 0.64, 0.25, 0.28)
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = _ring_mat
	_ring.visible = false
	add_child(_ring)

	_flee_label = Label3D.new()
	_flee_label.text = "бегут"
	_flee_label.font_size = 40
	_flee_label.pixel_size = 0.02
	_flee_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_flee_label.modulate = Color(0.95, 0.4, 0.3)
	_flee_label.outline_size = 10
	_flee_label.visible = false
	add_child(_flee_label)

	layout()
	for a in ants:
		a["pos"] = a["tgt"]
	refresh_visuals(0.0, false)


func is_alive() -> bool:
	return ants.size() > 0 and state != "routed"


func forward() -> Vector3:
	return Vector3(cos(ang), 0, sin(ang))


func right() -> Vector3:
	return Vector3(-sin(ang), 0, cos(ang))


func cols() -> int:
	var n := ants.size()
	if form == "line":
		return maxi(1, int(ceil(sqrt(n * 2.6))))
	return maxi(1, int(ceil(sqrt(n / 2.6))))


func rows() -> int:
	return int(ceil(float(ants.size()) / cols()))


func depth() -> float:
	return rows() * SP


func layout() -> void:
	var c := cols()
	var fw := forward()
	var rt := right()
	for i in ants.size():
		var r := i / c
		var k := i % c
		var lx := (k - (c - 1) / 2.0) * SP
		var ly := r * SP  # ряды позади фронта
		ants[i]["tgt"] = pos - fw * ly + rt * lx


func set_formation(f: String) -> void:
	form = f
	layout()


func order(p: Vector3, t: Squad) -> void:
	if not is_alive() or state == "fleeing":
		return
	target = t
	move_to = null if t != null else p
	state = "moving"


func halt() -> void:
	if state != "fleeing" and is_alive():
		target = null
		move_to = null
		state = "idle"


## Снимает муравьёв с фронта. Возвращает число убитых.
func take_damage(dmg: float, flank_mult: float) -> int:
	dmg_pool += dmg
	var killed := 0
	while dmg_pool >= ANT_HP and ants.size() > 0:
		dmg_pool -= ANT_HP
		var front_n := mini(ants.size(), cols() * 2)
		ants.remove_at(randi() % front_n)
		morale -= (100.0 / n0) * 1.25 * flank_mult
		flash = 0.15
		killed += 1
	if ants.size() == 0:
		state = "routed"
	return killed


## Муравьи догоняют свои места в строю; обновляет MultiMesh и подписи.
func refresh_visuals(dt: float, selected: bool) -> void:
	var mm := _mmi.multimesh
	if state == "routed":
		mm.visible_instance_count = 0
		_banner.visible = false
		_ring.visible = false
		_flee_label.visible = false
		return
	var moving := state != "idle"
	var k := 8.0 if state == "fleeing" else 6.0
	var rot := Basis(Vector3.UP, -ang)
	for i in ants.size():
		var a: Dictionary = ants[i]
		a["pos"] = a["pos"].lerp(a["tgt"], minf(1.0, dt * k))
		a["ph"] += dt * 9.0
		var ph: float = a["ph"]
		var bob := sin(ph) * 0.04 if moving else 0.0
		var b := rot
		if state == "fleeing":
			b = Basis(Vector3.UP, -(ang + sin(ph) * 0.5))
		mm.set_instance_transform(i, Transform3D(b, a["pos"] + Vector3(0, 0.15 + bob, 0)))
	mm.visible_instance_count = ants.size()

	flash = maxf(0.0, flash - dt)
	_mat.albedo_color = _base_color.lerp(Color(1.0, 0.85, 0.6), clampf(flash * 4.0, 0.0, 1.0))

	_banner.position = pos + Vector3(0, 2.6, 0)
	_banner.visible = true
	_ring.visible = selected
	if selected:
		var r := cols() * SP / 2.0 + 0.8
		_ring_mesh.top_radius = r
		_ring_mesh.bottom_radius = r
		_ring.position = pos - forward() * depth() / 2.0 + Vector3(0, 0.02, 0)
	_flee_label.visible = state == "fleeing"
	_flee_label.position = pos - forward() * depth() + Vector3(0, 1.6, 0)
