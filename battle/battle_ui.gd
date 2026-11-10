class_name BattleUI
extends CanvasLayer
## Интерфейс битвы: цели слева вверху, время сверху, карточки отрядов снизу,
## строй и приказы справа внизу. Тёмные полупрозрачные панели, золотые акценты.
## Миникарта появится, когда будет поле с местностью (этап 3).

const GOLD := Color(0.85, 0.64, 0.25)
const PANEL := Color(0.055, 0.035, 0.02, 0.78)
const MUTED := Color(0.73, 0.65, 0.54)
const GOOD := Color(0.55, 0.73, 0.36)
const WARN := Color(0.88, 0.66, 0.29)
const BAD := Color(0.83, 0.35, 0.29)

var battle: Battle
var _root: Control
var _cards: HBoxContainer
var _card_nodes: Dictionary = {}  # Squad -> {panel, count, state, hp, morale}
var _clock: Label
var _obj1: Label
var _drag: Panel
var _end: Control
var _end_title: Label
var _end_text: Label
var _btn_pause: Button
var _btn_1x: Button
var _btn_2x: Button


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Цели, слева вверху
	var obj := _panel()
	obj.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	var ov := VBoxContainer.new()
	obj.add_child(ov)
	var title := Label.new()
	title.text = "Формика"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	ov.add_child(title)
	var sub := Label.new()
	sub.text = "ЭТАП 1 · ПРОТОТИП БИТВЫ · САД, «БОРЬБА ЗА ТЕРРИТОРИЮ»"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", MUTED)
	ov.add_child(sub)
	_obj1 = _small_label("◆ Обратить в бегство или уничтожить все чёрные отряды")
	ov.add_child(_obj1)
	ov.add_child(_small_label("◆ Сохранить хотя бы один свой отряд"))

	# Подсказка, справа вверху
	var help := _panel()
	help.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.custom_minimum_size.x = 300
	var hl := Label.new()
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.custom_minimum_size.x = 276
	hl.add_theme_font_size_override("font_size", 12)
	hl.add_theme_color_override("font_color", MUTED)
	hl.text = "ЛКМ: выбрать отряд, рамкой несколько. ПКМ или клик с выбранным отрядом: идти; по врагу: атаковать.\n1 2 3 отряды · L линия · K колонна · H стоять · A все · Space пауза\nУдар во фланг и в тыл бьёт по запаху колонии. Отряд без запаха бежит."
	help.add_child(hl)

	# Время, сверху по центру
	var tp := _panel()
	tp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	tp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 6)
	tp.add_child(th)
	_btn_pause = _button("Пауза", func(): battle.toggle_pause())
	_btn_1x = _button("1×", func(): battle.set_speed(1.0))
	_btn_2x = _button("2×", func(): battle.set_speed(2.0))
	th.add_child(_btn_pause)
	th.add_child(_btn_1x)
	th.add_child(_btn_2x)
	_clock = Label.new()
	_clock.text = "0:00"
	_clock.custom_minimum_size.x = 46
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.add_theme_color_override("font_color", MUTED)
	th.add_child(_clock)

	# Карточки отрядов, снизу по центру
	var cp := _panel()
	cp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)
	cp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 8)
	cp.add_child(_cards)

	# Приказы, справа внизу
	var op := _panel()
	op.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	op.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	op.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	op.add_child(grid)
	grid.add_child(_button("═ Линия", func(): battle.set_formation("line")))
	grid.add_child(_button("║ Колонна", func(): battle.set_formation("column")))
	grid.add_child(_button("■ Стоять", func(): battle.halt_selected()))
	grid.add_child(_button("● Все", func(): battle.select_all()))
	var again := _button("↻ Заново", func(): battle.reset_battle())
	grid.add_child(again)
	grid.add_child(Control.new())

	# Рамка выделения
	_drag = Panel.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(GOLD, 0.08)
	ds.border_color = Color(GOLD, 0.8)
	ds.set_border_width_all(1)
	_drag.add_theme_stylebox_override("panel", ds)
	_drag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag.visible = false
	_root.add_child(_drag)

	# Экран итога
	_end = ColorRect.new()
	_end.color = Color(0.04, 0.02, 0.01, 0.55)
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.visible = false
	_root.add_child(_end)
	var ep := _panel(_end)
	ep.set_anchors_preset(Control.PRESET_CENTER)
	ep.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ep.grow_vertical = Control.GROW_DIRECTION_BOTH
	ep.custom_minimum_size = Vector2(400, 0)
	var ev := VBoxContainer.new()
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ep.add_child(ev)
	_end_title = Label.new()
	_end_title.add_theme_font_size_override("font_size", 32)
	_end_title.add_theme_color_override("font_color", GOLD)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ev.add_child(_end_title)
	_end_text = Label.new()
	_end_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_text.custom_minimum_size.x = 360
	_end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_text.add_theme_color_override("font_color", MUTED)
	ev.add_child(_end_text)
	var again2 := _button("Ещё раз", func(): battle.reset_battle())
	again2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ev.add_child(again2)


func _panel(parent: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = Color(GOLD, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	(parent if parent != null else _root).add_child(p)
	return p


func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(GOLD, 0.08 if st == "normal" else (0.18 if st == "hover" else 0.3))
		sb.border_color = Color(GOLD, 0.28 if st != "pressed" else 1.0)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(7)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	return b


func _bar(col: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(100, 5)
	pb.max_value = 100
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


func rebuild_cards() -> void:
	for c in _cards.get_children():
		c.queue_free()
	_card_nodes.clear()
	for s in battle.squads:
		if s.side != "ally":
			continue
		var p := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.03)
		sb.border_color = Color(GOLD, 0.28)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(5)
		sb.set_content_margin_all(7)
		p.add_theme_stylebox_override("panel", sb)
		p.custom_minimum_size.x = 118
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		p.add_child(v)
		var top := HBoxContainer.new()
		var nm := Label.new()
		nm.text = s.squad_name
		nm.add_theme_font_size_override("font_size", 12)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cnt := Label.new()
		cnt.add_theme_font_size_override("font_size", 12)
		cnt.add_theme_color_override("font_color", GOLD)
		top.add_child(nm)
		top.add_child(cnt)
		v.add_child(top)
		var st := Label.new()
		st.add_theme_font_size_override("font_size", 10)
		st.add_theme_color_override("font_color", MUTED)
		v.add_child(st)
		var hp := _bar(Color(0.78, 0.45, 0.16))
		v.add_child(hp)
		v.add_child(_tiny("численность"))
		var mo := _bar(GOOD)
		var mfill: StyleBoxFlat = mo.get_theme_stylebox("fill") as StyleBoxFlat
		v.add_child(mo)
		v.add_child(_tiny("запах колонии"))
		var sq := s
		p.gui_input.connect(func(e: InputEvent):
			var mb := e as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				battle.select_squad(sq, Input.is_key_pressed(KEY_SHIFT)))
		_cards.add_child(p)
		_card_nodes[s] = {"panel": p, "style": sb, "count": cnt, "state": st, "hp": hp, "morale": mo, "mfill": mfill}


func _tiny(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", MUTED)
	return l


const STATE_RU := {"idle": "стоит", "moving": "идёт", "fighting": "в бою", "fleeing": "бежит", "routed": "разбит"}


func refresh() -> void:
	for s in _card_nodes:
		var n: Dictionary = _card_nodes[s]
		var sel: bool = battle.selected.has(s)
		n["style"].border_color = GOLD if sel else Color(GOLD, 0.28)
		n["panel"].modulate.a = 1.0 if s.is_alive() else 0.4
		n["count"].text = "%d/%d" % [s.ants.size(), s.n0]
		n["state"].text = STATE_RU[s.state] + (" · колонна" if s.form == "column" and s.is_alive() else "")
		n["hp"].value = 100.0 * s.ants.size() / s.n0
		n["morale"].value = s.morale
		n["mfill"].bg_color = GOOD if s.morale >= 55 else (WARN if s.morale >= 30 else BAD)
	var t: float = battle.battle_time
	_clock.text = "%d:%02d" % [int(t / 60), int(t) % 60]
	_btn_pause.modulate = GOLD if battle.paused else Color.WHITE
	_btn_1x.modulate = GOLD if battle.speed == 1.0 else Color.WHITE
	_btn_2x.modulate = GOLD if battle.speed == 2.0 else Color.WHITE
	var e_stand := 0
	for s in battle.squads:
		if s.side == "enemy" and s.is_alive() and s.state != "fleeing":
			e_stand += 1
	_obj1.modulate = Color(MUTED, 0.6) if e_stand == 0 else Color.WHITE


func set_drag_rect(r: Rect2, show: bool) -> void:
	_drag.visible = show
	_drag.position = r.position
	_drag.size = r.size


func show_end(win: bool, lost: int, killed: int, t: float) -> void:
	_end_title.text = "Территория наша" if win else "Колония отступает"
	_end_text.text = ("Чёрные бегут. " if win else "Запах колонии рассеялся. ") + "Потеряно %d муравьёв, убито %d. Время боя %d:%02d." % [lost, killed, int(t / 60), int(t) % 60]
	_end.visible = true


func hide_end() -> void:
	_end.visible = false
