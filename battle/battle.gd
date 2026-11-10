class_name Battle
extends Node3D
## Этап 1. Прототип битвы: отряды, приказы мышью, урон, запах колонии и бегство.
## Графика из кубиков. Поле 140 × 90 м, союзники внизу (z > 0), враги вверху.

const FIELD_W := 140.0
const FIELD_H := 90.0
const ENGAGE := 1.6          # расстояние между фронтами для боя, м
const ATTACK := 0.65         # урон одного муравья первых рядов в секунду
const SQUAD_SIZE := 42       # временно, в документе не решено
const FLEE_AT := 18.0
const RALLY_AT := 48.0
const SIM_STEP := 1.0 / 120.0

var squads: Array[Squad] = []
var selected: Array[Squad] = []
var speed := 1.0
var paused := false
var battle_time := 0.0
var over := false
var winner := ""

var camera: Camera3D
var ui: BattleUI
var _acc := 0.0
var _drag_start := Vector2.ZERO
var _dragging := false
var _drag_box := false
var _markers: Array = []  # [{node, t}]
var _marker_mesh: CylinderMesh


func _ready() -> void:
	_build_world()
	ui = BattleUI.new()
	ui.battle = self
	add_child(ui)
	reset_battle()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.045, 0.025)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.45, 0.35)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52, 35, 0)
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIELD_W, FIELD_H)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.24, 0.13)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)

	var border := MeshInstance3D.new()
	var bp := PlaneMesh.new()
	bp.size = Vector2(FIELD_W + 2, FIELD_H + 2)
	border.mesh = bp
	border.position.y = -0.05
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.85, 0.64, 0.25)
	border.material_override = bm
	add_child(border)

	# Тёплый «свой» запах внизу, холодный чужой вверху: полупрозрачные полосы
	_add_tint(Vector3(0, 0.01, FIELD_H * 0.3), Vector2(FIELD_W, FIELD_H * 0.4), Color(0.9, 0.55, 0.2, 0.12))
	_add_tint(Vector3(0, 0.01, -FIELD_H * 0.3), Vector2(FIELD_W, FIELD_H * 0.4), Color(0.1, 0.08, 0.2, 0.18))

	camera = Camera3D.new()
	camera.position = Vector3(0, 82, 52)
	camera.fov = 45
	add_child(camera)
	camera.look_at(Vector3(0, 0, -2), Vector3.UP)

	_marker_mesh = CylinderMesh.new()
	_marker_mesh.height = 0.05
	_marker_mesh.top_radius = 1.0
	_marker_mesh.bottom_radius = 1.0


func _add_tint(p: Vector3, size: Vector2, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.position = p
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	mi.material_override = m
	add_child(mi)


func reset_battle() -> void:
	for s in squads:
		s.queue_free()
	squads.clear()
	selected.clear()
	for m in _markers:
		m["node"].queue_free()
	_markers.clear()
	battle_time = 0.0
	over = false
	paused = false
	speed = 1.0
	# Союзники внизу смотрят вверх (-Z), враги сверху смотрят вниз (+Z)
	_spawn("ally", 0, Vector3(-22, 0, 25), -PI / 2)
	_spawn("ally", 1, Vector3(0, 0, 27), -PI / 2)
	_spawn("ally", 2, Vector3(22, 0, 25), -PI / 2)
	_spawn("enemy", 0, Vector3(-28, 0, -25), PI / 2)
	_spawn("enemy", 1, Vector3(3, 0, -29), PI / 2)
	_spawn("enemy", 2, Vector3(31, 0, -23), PI / 2)
	ui.rebuild_cards()
	ui.hide_end()


func _spawn(side: String, idx: int, p: Vector3, ang: float) -> void:
	var s := Squad.new()
	add_child(s)
	s.setup(side, idx, p, ang, SQUAD_SIZE)
	squads.append(s)


# ---------- симуляция ----------

func enemies_of(s: Squad) -> Array[Squad]:
	var out: Array[Squad] = []
	for o in squads:
		if o.side != s.side and o.is_alive():
			out.append(o)
	return out


func nearest(s: Squad, list: Array[Squad]) -> Squad:
	var best: Squad = null
	var bd := INF
	for o in list:
		var d := s.pos.distance_to(o.pos)
		if d < bd:
			bd = d
			best = o
	return best


func step(dt: float) -> void:
	battle_time += dt
	# Противник: каждый отряд идёт на ближайшего
	for s in squads:
		if s.side != "enemy" or not s.is_alive() or s.state == "fleeing":
			continue
		if s.target == null or not s.target.is_alive() or s.target.state == "fleeing":
			var e := enemies_of(s)
			var standing: Array[Squad] = []
			for o in e:
				if o.state != "fleeing":
					standing.append(o)
			var t := nearest(s, standing if standing.size() > 0 else e)
			if t != null:
				s.target = t
				s.move_to = null
				s.state = "moving"

	# Движение
	for s in squads:
		if not s.is_alive():
			continue
		s.in_contact = 0
		var spd := (6.2 if s.form == "column" else 4.8) * (1.7 if s.state == "fleeing" else 1.0)
		var goal = null
		if s.state == "fleeing":
			var e := nearest(s, enemies_of(s))
			if e != null:
				var away := (s.pos - e.pos)
				away.y = 0
				goal = s.pos + away.normalized() * 20.0
			else:
				goal = Vector3(s.pos.x, 0, FIELD_H if s.side == "ally" else -FIELD_H)
			if absf(s.pos.x) > FIELD_W / 2 + 2 or absf(s.pos.z) > FIELD_H / 2 + 2:
				s.state = "routed"
				continue
			s.morale = minf(100.0, s.morale + 5.0 * dt)
			if s.morale >= RALLY_AT and (e == null or s.pos.distance_to(e.pos) > 26.0):
				s.state = "idle"
				s.target = null
				s.move_to = null
		elif s.target != null:
			if not s.target.is_alive():
				s.target = null
				s.state = "idle"
			else:
				# Идём к ближайшей точке вражеского строя: так работает заход во фланг и в тыл
				var t := s.target
				var edge := t.closest_point(s.pos)
				if s.pos.distance_to(edge) > ENGAGE + 0.2:
					goal = edge
				else:
					s.state = "fighting"
					s.ang = lerp_angle(s.ang, atan2(edge.z - s.pos.z, edge.x - s.pos.x), minf(1.0, dt * 3.0))
		elif s.move_to != null:
			if s.pos.distance_to(s.move_to) < 0.3:
				s.move_to = null
				s.state = "idle"
			else:
				goal = s.move_to
		if goal != null:
			var dv: Vector3 = goal - s.pos
			dv.y = 0
			var l := dv.length()
			if l > 0.001:
				var m := minf(l, spd * dt)
				var ta := atan2(dv.z, dv.x)
				s.ang = lerp_angle(s.ang, ta, minf(1.0, dt * (6.0 if s.state == "fleeing" else 2.5)))
				var al := absf(angle_difference(s.ang, ta))
				var f := 0.35 if al > 1.2 else 1.0
				s.pos += dv / l * m * f
				var lim := 4.0 if s.state == "fleeing" else -2.0
				s.pos.x = clampf(s.pos.x, -FIELD_W / 2 - lim, FIELD_W / 2 + lim)
				s.pos.z = clampf(s.pos.z, -FIELD_H / 2 - lim, FIELD_H / 2 + lim)
		s.layout()

	# Мягкое расталкивание отрядов
	for i in squads.size():
		for j in range(i + 1, squads.size()):
			var a := squads[i]
			var b := squads[j]
			if not a.is_alive() or not b.is_alive():
				continue
			if a.side == b.side:
				var d := a.pos.distance_to(b.pos)
				var mn := (a.cols() + b.cols()) * Squad.SP * 0.35
				if d < mn and d > 0.0:
					var push := (mn - d) / 2.0
					var dir := (a.pos - b.pos) / d
					a.pos += dir * push
					b.pos -= dir * push
			else:
				# Фронт одного отряда не заходит внутрь строя другого
				_push_out(a, b)
				_push_out(b, a)

	# Бой
	for a in squads:
		if not a.is_alive() or a.state == "fleeing":
			continue
		for b in squads:
			if b.side == a.side or not b.is_alive():
				continue
			var d := a.pos.distance_to(b.closest_point(a.pos))
			var reach := ENGAGE + 0.6 + (1.4 if b.state == "fleeing" else 0.0)
			if d > reach:
				continue
			a.in_contact += 1
			b.in_contact += 1
			if a.state != "fighting" and a.state != "fleeing":
				a.state = "fighting"
				a.target = b
			var front_n := mini(a.ants.size(), a.cols() * 2)
			var dmg := front_n * ATTACK * dt * (2.2 if b.state == "fleeing" else 1.0)
			# Откуда бьют: по фронту, во фланг или в тыл обороняющегося
			var bc := b.block_center()
			var to_a := atan2(a.pos.z - bc.z, a.pos.x - bc.x)
			var rel := cos(to_a - b.ang)   # 1 фронт, -1 тыл
			var flank := 3.0 if rel < -0.5 else (1.8 if rel < 0.4 else 1.0)
			b.take_damage(dmg, flank)
			if flank > 1.0:
				b.morale -= dt * 3.0 * (flank - 1.0)
			if b.ants.size() == 0 and a.target == b:
				a.target = null
				a.state = "idle"

	# Запах колонии (мораль)
	for s in squads:
		if not s.is_alive():
			continue
		if s.in_contact == 0 and s.state != "fleeing":
			s.morale = minf(100.0, s.morale + 3.0 * dt)
		if s.state != "fleeing":
			for o in squads:
				if o != s and o.side == s.side and o.state == "fleeing" and s.pos.distance_to(o.pos) < 14.0:
					s.morale -= dt * 2.0
			if s.in_contact >= 2:
				s.morale -= dt * 2.5
		s.morale = clampf(s.morale, 0.0, 100.0)
		if s.state != "fleeing" and s.morale < FLEE_AT:
			s.state = "fleeing"
			s.target = null
			s.move_to = null
			selected.erase(s)
		if s.state == "fighting" and s.in_contact == 0 and s.target == null:
			s.state = "idle"

	# Итог
	var e_stand := 0
	var e_any := 0
	var a_stand := 0
	var a_any := 0
	var e_all_broken := true
	for s in squads:
		if not s.is_alive():
			continue
		if s.side == "enemy":
			e_any += 1
			if s.state != "fleeing":
				e_stand += 1
			if not (s.state == "fleeing" and s.morale < RALLY_AT):
				e_all_broken = false
		else:
			a_any += 1
			if s.state != "fleeing":
				a_stand += 1
	if (e_stand == 0 and e_any == 0) or (a_stand == 0 and a_any == 0) or (e_stand == 0 and a_stand > 0 and battle_time > 8.0 and e_any > 0 and e_all_broken):
		_finish(a_stand > 0)


## Выталкивает фронт отряда a из прямоугольника строя b до дистанции боя.
func _push_out(a: Squad, b: Squad) -> void:
	var edge := b.closest_point(a.pos)
	var dv := a.pos - edge
	var d := dv.length()
	var c := b.block_center()
	var inside := absf((a.pos - c).dot(b.forward())) < b.depth() / 2.0 and absf((a.pos - c).dot(b.right())) < b.cols() * Squad.SP / 2.0
	if inside:
		# Фронт внутри чужого строя: выводим к ближайшей стороне
		var lf := (a.pos - c).dot(b.forward())
		var lr := (a.pos - c).dot(b.right())
		var gap_f := b.depth() / 2.0 - absf(lf)
		var gap_r := b.cols() * Squad.SP / 2.0 - absf(lr)
		if gap_f < gap_r:
			a.pos += b.forward() * signf(lf if lf != 0.0 else 1.0) * (gap_f + ENGAGE)
		else:
			a.pos += b.right() * signf(lr if lr != 0.0 else 1.0) * (gap_r + ENGAGE)
	elif d < ENGAGE and d > 0.0:
		a.pos += dv / d * (ENGAGE - d)


func _finish(win: bool) -> void:
	if over:
		return
	over = true
	var lost := 0
	var killed := 0
	for s in squads:
		if s.side == "ally":
			lost += s.n0 - s.ants.size()
		else:
			killed += s.n0 - s.ants.size()
	ui.show_end(win, lost, killed, battle_time)


func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if not paused and not over:
		_acc += dt * speed
		while _acc > SIM_STEP:
			step(SIM_STEP)
			_acc -= SIM_STEP
	for s in squads:
		s.refresh_visuals(dt * speed if not paused else 0.0, selected.has(s))
	for m in _markers:
		m["t"] -= dt
		var k: float = 1.0 - m["t"] / 0.8
		m["node"].scale = Vector3(0.6 + k * 2.4, 1, 0.6 + k * 2.4)
		m["node"].material_override.albedo_color.a = (1.0 - k) * 0.6
	for i in range(_markers.size() - 1, -1, -1):
		if _markers[i]["t"] <= 0.0:
			_markers[i]["node"].queue_free()
			_markers.remove_at(i)
	ui.refresh()


# ---------- ввод ----------

func ground_point(screen: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit == null:
		return Vector3.ZERO
	return hit as Vector3


func squad_at(p: Vector3) -> Squad:
	var best: Squad = null
	var bd := INF
	for s in squads:
		if not s.is_alive():
			continue
		var rad := s.cols() * Squad.SP / 2.0 + 1.2
		var center := s.pos - s.forward() * s.depth() / 2.0
		var d := p.distance_to(center)
		if d < maxf(rad, s.depth()) + 0.6 and d < bd:
			bd = d
			best = s
	return best


func select_squad(s: Squad, add: bool) -> void:
	if not add:
		selected.clear()
	if s.is_alive() and s.state != "fleeing" and not selected.has(s):
		selected.append(s)


func select_all() -> void:
	selected.clear()
	for s in squads:
		if s.side == "ally" and s.is_alive() and s.state != "fleeing":
			selected.append(s)


func set_formation(f: String) -> void:
	for s in selected:
		s.set_formation(f)


func halt_selected() -> void:
	for s in selected:
		s.halt()


func set_speed(v: float) -> void:
	speed = v


func toggle_pause() -> void:
	paused = not paused


func issue(p: Vector3) -> void:
	var sel: Array[Squad] = []
	for s in selected:
		if s.is_alive():
			sel.append(s)
	if sel.is_empty():
		return
	var t := squad_at(p)
	if t != null and t.side == "enemy":
		for s in sel:
			s.order(p, t)
		_mark(t.pos, Color(0.95, 0.4, 0.3))
		return
	var c := Vector3.ZERO
	for s in sel:
		c += s.pos
	c /= sel.size()
	var a := atan2(p.z - c.z, p.x - c.x)
	var perp := Vector3(-sin(a), 0, cos(a))
	for i in sel.size():
		var s := sel[i]
		var off := (i - (sel.size() - 1) / 2.0) * (s.cols() * Squad.SP + 1.8)
		var q := p + perp * off
		q.x = clampf(q.x, -FIELD_W / 2 + 3, FIELD_W / 2 - 3)
		q.z = clampf(q.z, -FIELD_H / 2 + 3, FIELD_H / 2 - 3)
		s.order(q, null)
	_mark(p, Color(1.0, 0.78, 0.35))


func _mark(p: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _marker_mesh
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	mi.material_override = m
	mi.position = p + Vector3(0, 0.03, 0)
	add_child(mi)
	_markers.append({"node": mi, "t": 0.8})


func _unhandled_input(event: InputEvent) -> void:
	if over:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			issue(ground_point(mb.position))
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_box = false
				_drag_start = mb.position
			elif _dragging:
				_dragging = false
				ui.set_drag_rect(Rect2(), false)
				var add := Input.is_key_pressed(KEY_SHIFT)
				if _drag_box:
					if not add:
						selected.clear()
					var r := Rect2(_drag_start, mb.position - _drag_start).abs()
					for s in squads:
						if s.side == "ally" and s.is_alive() and s.state != "fleeing":
							var sp := camera.unproject_position(s.pos)
							if r.has_point(sp) and not selected.has(s):
								selected.append(s)
				else:
					var p := ground_point(mb.position)
					var t := squad_at(p)
					if t != null and t.side == "ally":
						select_squad(t, add)
					elif selected.size() > 0:
						issue(p)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_drag_start) > 8.0:
			_drag_box = true
			ui.set_drag_rect(Rect2(_drag_start, mm.position - _drag_start).abs(), true)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.physical_keycode:
			KEY_SPACE:
				toggle_pause()
			KEY_L:
				set_formation("line")
			KEY_K:
				set_formation("column")
			KEY_H:
				halt_selected()
			KEY_A:
				select_all()
			KEY_ESCAPE:
				selected.clear()
			KEY_1, KEY_2, KEY_3:
				var n := k.physical_keycode - KEY_1
				for s in squads:
					if s.side == "ally" and s.idx == n:
						select_squad(s, k.shift_pressed)
