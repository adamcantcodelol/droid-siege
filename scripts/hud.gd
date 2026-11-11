extends CanvasLayer
const MechVisual = preload("res://scripts/mech.gd")
const TrooperClass = preload("res://scripts/trooper_class.gd")
## In-mission HUD: objective, health, ammo, squad, messages, pause and end screens.

var world
var obj_label: Label
var health_bar: ProgressBar
var health_label: Label
var ammo_label: Label
var squad_label: Label
var msg_label: Label
var cross: Control
var cap_bar: ProgressBar
var cap_label: Label
var revive_bar: ProgressBar
var revive_label: Label
var down_label: Label
var flash: ColorRect
var pause_panel: PanelContainer
var end_panel: PanelContainer
var end_title: Label
var end_stats: Label
var again_btn: Button
var wait_label: Label
var sens_slider: HSlider
var msg_time := 0.0
var hit_time := 0.0
var score_panel: PanelContainer
var score_label: Label
var feed_box: VBoxContainer
var dmg_ind: Control
var dmg_poly: Polygon2D
var dmg_from := Vector3.ZERO
var dmg_time := 0.0
var veh_bar: ProgressBar
var veh_label: Label
var ver_label: Label
var controls_hint: Label
var rank_rect: TextureRect
var rank_name_label: Label
var _hud_cache := {}


func _ready() -> void:
	world = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	flash = ColorRect.new()
	flash.color = Color(0.8, 0, 0, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

	obj_label = _label(root, 20, Vector2(20, 16))
	squad_label = _label(root, 18, Vector2(-260, 16), Control.PRESET_TOP_RIGHT)
	var squad_box := VBoxContainer.new()
	squad_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	squad_box.position = Vector2(-280, 16)
	squad_box.custom_minimum_size = Vector2(260, 0)
	squad_box.add_theme_constant_override("separation", 2)
	root.add_child(squad_box)
	squad_label.visible = false
	self.set_meta("squad_box", squad_box)
	health_label = _label(root, 20, Vector2(20, -70), Control.PRESET_BOTTOM_LEFT)
	health_bar = ProgressBar.new()
	health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_bar.position = Vector2(20, -40)
	health_bar.size = Vector2(280, 22)
	health_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.2, 0.75, 0.3)
	health_bar.add_theme_stylebox_override("fill", fill)
	root.add_child(health_bar)
	var rank_row := HBoxContainer.new()
	rank_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	rank_row.position = Vector2(20, -118)
	rank_row.add_theme_constant_override("separation", 6)
	rank_rect = TextureRect.new()
	rank_rect.custom_minimum_size = Vector2(20, 20)
	rank_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rank_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rank_rect.texture = Game.rank_icon(Game.local_rank())
	rank_row.add_child(rank_rect)
	rank_name_label = Label.new()
	rank_name_label.add_theme_font_size_override("font_size", 16)
	rank_name_label.text = Game.player_name
	rank_row.add_child(rank_name_label)
	root.add_child(rank_row)
	veh_label = _label(root, 16, Vector2(20, -100), Control.PRESET_BOTTOM_LEFT)
	veh_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.25))
	veh_bar = ProgressBar.new()
	veh_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	veh_bar.position = Vector2(20, -78)
	veh_bar.size = Vector2(280, 14)
	veh_bar.show_percentage = false
	var vfill := StyleBoxFlat.new()
	vfill.bg_color = Color(0.95, 0.55, 0.15)
	veh_bar.add_theme_stylebox_override("fill", vfill)
	veh_bar.visible = false
	root.add_child(veh_bar)
	ver_label = _label(root, 14, Vector2(-120, -28), Control.PRESET_BOTTOM_RIGHT)
	ver_label.text = "v%s" % Game.GAME_VERSION
	ver_label.modulate = Color(1, 1, 1, 0.55)
	ammo_label = _label(root, 24, Vector2(-300, -120), Control.PRESET_BOTTOM_RIGHT)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.size = Vector2(280, 80)
	controls_hint = _label(root, 15, Vector2.ZERO)
	_anchor(controls_hint, 0.5, 1.0, -420, -52, 840, 36)
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_hint.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 0.92))
	controls_hint.autowrap_mode = TextServer.AUTOWRAP_OFF

	cross = preload("res://scripts/crosshair.gd").new()
	root.add_child(cross)

	cap_label = _label(root, 22, Vector2.ZERO)
	_anchor(cap_label, 0.5, 0.0, -300, 120, 600, 30)
	cap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_bar = ProgressBar.new()
	cap_bar.max_value = 1.0
	cap_bar.show_percentage = false
	cap_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfill := StyleBoxFlat.new()
	cfill.bg_color = Color(1.0, 0.75, 0.2)
	cap_bar.add_theme_stylebox_override("fill", cfill)
	root.add_child(cap_bar)
	_anchor(cap_bar, 0.5, 0.0, -180, 155, 360, 16)

	msg_label = _label(root, 26, Vector2.ZERO)
	_anchor(msg_label, 0.5, 0.0, -400, 180, 800, 80)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD

	revive_label = _label(root, 20, Vector2.ZERO)
	_anchor(revive_label, 0.5, 0.5, -200, 50, 400, 30)
	revive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	revive_bar = ProgressBar.new()
	revive_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	revive_bar.show_percentage = false
	revive_bar.max_value = 1.0
	root.add_child(revive_bar)
	_anchor(revive_bar, 0.5, 0.5, -120, 85, 240, 14)

	down_label = _label(root, 34, Vector2.ZERO)
	_anchor(down_label, 0.5, 0.5, -400, -160, 800, 100)
	down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	down_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3))

	feed_box = VBoxContainer.new()
	feed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	feed_box.position = Vector2(-380, 150)
	feed_box.custom_minimum_size = Vector2(360, 0)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)

	dmg_ind = Control.new()
	root.add_child(dmg_ind)
	_anchor(dmg_ind, 0.5, 0.5, 0, 0, 0, 0)
	dmg_ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dmg_poly = Polygon2D.new()
	dmg_poly.polygon = PackedVector2Array([Vector2(-26, -95), Vector2(26, -95), Vector2(0, -125)])
	dmg_poly.color = Color(1, 0.15, 0.1, 0.0)
	dmg_ind.add_child(dmg_poly)

	var sr := _panel(root)
	score_panel = sr[0]
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 20)
	sr[1].add_child(score_label)
	score_panel.visible = false

	_build_pause(root)
	_build_end(root)


## Explicit anchor + offsets so placement never depends on the parent's size at creation time.
func _anchor(c: Control, ax: float, ay: float, ox: float, oy: float, w: float, h: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_right = ox + w
	c.offset_top = oy
	c.offset_bottom = oy + h


func _label(parent: Control, size: int, pos: Vector2, preset: int = Control.PRESET_TOP_LEFT) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _panel(root: Control) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return [panel, box]


func _button(box: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 44)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _build_pause(root: Control) -> void:
	var r := _panel(root)
	pause_panel = r[0]
	var box: VBoxContainer = r[1]
	var t := Label.new()
	t.text = "  PAUSED  "
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 32)
	box.add_child(t)
	var sl := Label.new()
	sl.text = "Mouse sensitivity"
	box.add_child(sl)
	sens_slider = HSlider.new()
	sens_slider.min_value = 0.0005
	sens_slider.max_value = 0.008
	sens_slider.step = 0.0001
	sens_slider.value = Game.mouse_sensitivity
	sens_slider.value_changed.connect(func(v): Game.mouse_sensitivity = v)
	box.add_child(sens_slider)
	Game.build_control_options(box)
	var crow := HBoxContainer.new()
	box.add_child(crow)
	var cl := Label.new()
	cl.text = "Class (applies next respawn / if full HP):"
	crow.add_child(cl)
	var cls_opt := OptionButton.new()
	for i in TrooperClass.NAMES.size():
		cls_opt.add_item(TrooperClass.NAMES[i])
	cls_opt.selected = Game.trooper_cls()
	cls_opt.item_selected.connect(func(i):
		Game.save["cls"] = i
		Game.write_save()
		var lp2 = world.local_player() if world else null
		if lp2 != null and lp2.state == 0 and lp2.health >= lp2.max_health * 0.95:
			lp2.apply_class(i)
		elif lp2 != null:
			lp2.cls = i
	)
	crow.add_child(cls_opt)
	_button(box, "Resume", _resume)
	_button(box, "Leave Mission", func(): Game.write_save(); Game.return_to_menu(""))
	pause_panel.visible = false


func _build_end(root: Control) -> void:
	var r := _panel(root)
	end_panel = r[0]
	var box: VBoxContainer = r[1]
	end_title = Label.new()
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_size_override("font_size", 44)
	box.add_child(end_title)
	end_stats = Label.new()
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_stats.add_theme_font_size_override("font_size", 20)
	box.add_child(end_stats)
	again_btn = _button(box, "Play Again (same squad)", func(): Game.start_mission())
	wait_label = Label.new()
	wait_label.text = "Waiting for the host to restart..."
	wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(wait_label)
	_button(box, "Back to Menu (Armory)", func(): Game.return_to_menu(""))
	end_panel.visible = false


func is_blocking() -> bool:
	return pause_panel.visible or end_panel.visible


func _resume() -> void:
	pause_panel.visible = false
	Game.write_save()
	if not Game.online:
		get_tree().paused = false
	if not Game.is_headless():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_web_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _open_pause() -> void:
	if end_panel.visible or pause_panel.visible:
		return
	pause_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Game.online:
		get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not end_panel.visible:
		if pause_panel.visible:
			_resume()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()


func show_message(text: String) -> void:
	if msg_label == null:
		return
	msg_label.text = text
	msg_time = 4.0


func hit_marker(shielded: bool) -> void:
	hit_time = 0.15
	cross.color = Color(0.4, 0.7, 1.0) if shielded else Color(1, 0.3, 0.2)
	Game.play_sfx("hit", null, -10.0)


func add_feed(text: String, color: Color = Color.WHITE) -> void:
	if feed_box == null:
		return
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_color_override("font_color", color)
	feed_box.add_child(l)
	while feed_box.get_child_count() > 6:
		var old := feed_box.get_child(0)
		feed_box.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func damage_from(pos: Vector3) -> void:
	dmg_from = pos
	dmg_time = 1.2


func damage_flash() -> void:
	flash.color.a = 0.35


func show_pvp_end(text: String, won: bool, credits: int, kills: int) -> void:
	pause_panel.visible = false
	end_panel.visible = true
	end_title.text = text
	end_title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0) if won else Color(1, 0.6, 0.3))
	end_stats.text = "%s\nYour kills: %d\nCredits earned: %d   (Total: %d)\n\n%s" % [
		"Victory!" if won else "Defeat - get them next round.", kills, credits, int(Game.save["credits"]), _scoreboard_text()]
	var can_restart: bool = multiplayer.is_server() or Game.server_is_dedicated
	again_btn.visible = can_restart
	wait_label.visible = not can_restart


func _scoreboard_text() -> String:
	var lines := []
	if world.versus and not world.ffa:
		lines.append("RED %d  -  %d BLUE      (first to %d)" % [world.team_scores.x, world.team_scores.y, world.pvp_target])
	else:
		lines.append("FREE-FOR-ALL      (first to %d kills)" % world.pvp_target)
	lines.append("")
	lines.append("%-18s %-6s %5s %5s" % ["TROOPER", "TEAM", "K", "D"])
	var rows := []
	for pid in world.players.keys():
		var sc: Vector2i = world.pvp_scores.get(pid, Vector2i.ZERO)
		rows.append([sc.x, pid])
	rows.sort()
	rows.reverse()
	for r in rows:
		var p = world.players[r[1]]
		var sc2: Vector2i = world.pvp_scores.get(r[1], Vector2i.ZERO)
		var tn := "-" if world.ffa else ("RED" if p.team == 0 else "BLUE")
		lines.append("%-18s %-6s %5d %5d" % [p.display_name.substr(0, 18), tn, sc2.x, sc2.y])
	return "\n".join(PackedStringArray(lines))


func show_end(win: bool, credits: int, kills: int) -> void:
	pause_panel.visible = false
	end_panel.visible = true
	end_title.text = "MISSION COMPLETE" if win else "MISSION FAILED"
	end_title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0) if win else Color(1, 0.35, 0.3))
	end_stats.text = "%s\nDroids destroyed: %d\nCredits earned: %d   (Total: %d)\nSpend credits in the Armory from the main menu." % [
		"The gunship extracted your squad. Good work, trooper!" if win else "Your squad was overrun.",
		kills, credits, int(Game.save["credits"])]
	var can_restart: bool = multiplayer.is_server() or Game.server_is_dedicated
	again_btn.visible = can_restart
	wait_label.visible = not can_restart


func _process(delta: float) -> void:
	_fps_tick()
	# Web: browser steals Esc to exit pointer lock. When capture drops mid-mission, open pause
	# so Resume (or P/M) can recapture the mouse.
	if OS.has_feature("web") and Game.control_mode == 0 and not end_panel.visible and not pause_panel.visible:
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if _web_was_captured and not captured:
			_open_pause()
		_web_was_captured = captured
	elif pause_panel.visible:
		_web_was_captured = false
	msg_time -= delta
	msg_label.modulate.a = clampf(msg_time, 0.0, 1.0)
	hit_time -= delta
	if hit_time <= 0.0:
		cross.color = Color(1, 1, 1, 0.95)
	flash.color.a = maxf(0.0, flash.color.a - delta * 0.8)
	dmg_time -= delta
	var lpi = world.local_player()
	if dmg_time > 0.0 and lpi != null:
		var to: Vector3 = dmg_from - lpi.global_position
		var fwd: Vector3 = -lpi.global_transform.basis.z
		dmg_ind.rotation = Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z))
		dmg_poly.color.a = clampf(dmg_time, 0.0, 0.85)
	else:
		dmg_poly.color.a = 0.0

	# Objective
	var lp = world.local_player()
	if lp != null:
		cross.aiming = lp.is_aiming
		cross.on_target = lp.crosshair_on_enemy
		cross.visible = lp.state == 0 and not end_panel.visible
	var t := ""
	cap_label.text = ""
	cap_bar.visible = false
	score_panel.visible = world.versus and Input.is_action_pressed("scoreboard") and not end_panel.visible
	if score_panel.visible:
		score_label.text = _scoreboard_text()
	if world.versus:
		var mins := int(maxf(world.pvp_time, 0.0)) / 60
		var secs := int(maxf(world.pvp_time, 0.0)) % 60
		if world.ffa:
			var mine: Vector2i = world.pvp_scores.get(multiplayer.get_unique_id(), Vector2i.ZERO)
			t = "FREE-FOR-ALL   your kills: %d   first to %d   %d:%02d" % [mine.x, world.pvp_target, mins, secs]
		else:
			var my_team := "RED" if lp != null and lp.team == 0 else "BLUE"
			var mname := "TEAM DEATHMATCH"
			if world.koth:
				mname = "KING OF THE HILL"
			elif world.ctf:
				mname = "CAPTURE THE FLAG"
			t = "%s   RED %d - %d BLUE   first to %d   %d:%02d\nYou are on %s team. Friendly fire is off." % [
				mname, world.team_scores.x, world.team_scores.y, world.pvp_target, mins, secs, my_team]
			if world.koth and lp != null:
				var hz: Vector3 = world._koth_zone()
				var hstate := "nobody holds it"
				if world.koth_owner >= 0:
					hstate = ("RED" if world.koth_owner == 0 else "BLUE") + " team is scoring"
				elif world.koth_mask == 3:
					hstate = "CONTESTED"
				t += "\nThe Hill: %s  -  %s" % [hstate, _direction_text(lp, hz)]
			elif world.ctf and lp != null:
				var enemy_t: int = 1 - clampi(lp.team, 0, 1)
				if world.flag_carrier[enemy_t] == lp.peer_id:
					t += "\nYOU HAVE THE FLAG! Bring it home  -  %s" % _direction_text(lp, world.flag_home[clampi(lp.team, 0, 1)])
				else:
					t += "\nEnemy flag: %s  -  %s" % ["carried by your team" if world.flag_carrier[enemy_t] != 0 else "grab it", _direction_text(lp, world.flag_pos[enemy_t])]
				if world.flag_carrier[clampi(lp.team, 0, 1)] != 0:
					t += "\nYOUR FLAG IS TAKEN! Stop the carrier!"
		t += "\nHold Tab for the scoreboard"
	elif world.phase < 3:
		t = "OBJECTIVE: Capture all 3 command posts, any order  (%d/3)" % world.phase
		if world.hold:
			t = "HOLD THE LINE: take and hold Post %s against the droid assault  (%d%%)" % [world.POST_NAMES[world.hold_post], int(world.post_progress[world.hold_post] * 100.0)]
		if lp != null:
			var zone: int = world.post_at(lp.global_position)
			if zone >= 0 and world.post_captured[zone]:
				t += "\nPost %s is secured. Move to another post." % world.POST_NAMES[zone]
			elif zone >= 0:
				cap_bar.visible = true
				cap_bar.value = world.post_progress[zone]
				if world.post_contested[zone]:
					cap_label.text = "POST %s CONTESTED - clear the droids! %d%%" % [world.POST_NAMES[zone], int(world.post_progress[zone] * 100.0)]
					cap_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
				else:
					cap_label.text = "CAPTURING POST %s: %d%%" % [world.POST_NAMES[zone], int(world.post_progress[zone] * 100.0)]
					cap_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
			var near: int = world.nearest_open_post(lp.global_position)
			if near >= 0 and zone < 0:
				t += "\nNearest open post: %s (%d%%)  -  %s" % [world.POST_NAMES[near], int(world.post_progress[near] * 100.0),
					_direction_text(lp, world.POSTS[near])]
	elif world.phase == 3:
		if world.timer <= 0.0:
			var me = world.local_player()
			var d: float = world._flat_dist(me.global_position, world.LZ) if me != null else 0.0
			t = "GUNSHIP LANDED! Board at the LZ (%dm)%s" % [int(d), "  - ABOARD, waiting for squad" if d < world.BOARD_RADIUS else ""]
		else:
			t = "SURVIVE! Gunship extraction in %ds" % int(ceil(world.timer))
	if not world.versus:
		t += "\nDroids destroyed: %d    Credits earned: %d    Droids active: %d" % [world.kills, world.earned,
			world.enemies.size()]
	obj_label.text = t

	# Squad with rank icons
	var sbox = get_meta("squad_box") if has_meta("squad_box") else null
	if sbox != null:
		var sig := ""
		for p in world.players.values():
			sig += "%d:%d:%d:%s;" % [p.peer_id, int(p.health), p.state, p.display_name]
		if _hud_cache.get("squad") != sig:
			_hud_cache["squad"] = sig
			for c in sbox.get_children():
				c.queue_free()
			var title := Label.new()
			title.text = "SQUAD"
			title.add_theme_font_size_override("font_size", 16)
			sbox.add_child(title)
			for p in world.players.values():
				var row := HBoxContainer.new()
				var ic := TextureRect.new()
				ic.custom_minimum_size = Vector2(16, 16)
				ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				ic.texture = Game.rank_icon(Game.peer_rank(p.peer_id))
				row.add_child(ic)
				var st := "%d HP" % int(p.health)
				if p.state == 1: st = "DOWNED"
				elif p.state == 2: st = "KIA"
				var lb := Label.new()
				lb.text = "%s  %s" % [p.display_name, st]
				lb.add_theme_font_size_override("font_size", 15)
				row.add_child(lb)
				sbox.add_child(row)
	else:
		var s := "SQUAD\n"
		for p in world.players.values():
			var st2 := "%d HP" % int(p.health)
			if p.state == 1: st2 = "DOWNED"
			elif p.state == 2: st2 = "KIA"
			s += "%s  %s\n" % [p.display_name, st2]
		squad_label.text = s

	if lp == null:
		return
	var hp_key := Vector2i(int(lp.health), int(lp.max_health))
	if _hud_cache.get("hp") != hp_key:
		_hud_cache["hp"] = hp_key
		health_bar.max_value = lp.max_health
		health_bar.value = lp.health
		health_label.text = "HEALTH %d / %d" % [int(lp.health), int(lp.max_health)]
	var rk := Game.local_rank()
	var rkey := "%d|%s|%d" % [rk, Game.player_name, lp.cls]
	if _hud_cache.get("rankui") != rkey:
		_hud_cache["rankui"] = rkey
		if rank_rect != null:
			rank_rect.texture = Game.rank_icon(rk)
		if rank_name_label != null:
			var cname := str(TrooperClass.NAMES[clampi(lp.cls, 0, 3)])
			rank_name_label.text = "%s  ·  %s" % [Game.player_name, cname]
	# Vehicle hull bar
	if lp.in_mech >= 0 and lp.in_mech < world.mech_hp.size():
		var mi: int = lp.in_mech
		var vkey := Vector2i(int(world.mech_hp[mi]), int(world.mech_max_hp[mi]))
		if _hud_cache.get("veh") != vkey:
			_hud_cache["veh"] = vkey
			veh_bar.visible = true
			veh_label.visible = true
			veh_bar.max_value = world.mech_max_hp[mi]
			veh_bar.value = world.mech_hp[mi]
			veh_label.text = "%s HULL  %d / %d" % [world.vehicle_name(mi), int(world.mech_hp[mi]), int(world.mech_max_hp[mi])]
	else:
		veh_bar.visible = false
		veh_label.visible = false
		_hud_cache.erase("veh")
	var wname := str(Game.class_weapon(lp.weapon).get("name", "BLASTER"))
	var ammo := "%d / %d" % [lp.mag, lp.mag_size]
	if lp.reloading > 0.0:
		ammo = "RELOADING..."
	var akey := "%s|%s|%d|%s" % [wname, ammo, lp.grenades, lp.cls]
	if _hud_cache.get("ammo") != akey:
		_hud_cache["ammo"] = akey
		var heat := ""
		if lp.in_mech >= 0 and lp.veh_heat > 0.05:
			heat = "\nHEAT %d%%" % int(lp.veh_heat * 100.0)
		ammo_label.text = "%s  [%d/2]\n%s\nGrenades: %d%s" % [wname, lp.weapon + 1, ammo, lp.grenades, heat]

	_update_controls_hint(lp)

	if lp.state == 1:
		down_label.text = "YOU ARE DOWN\nBleeding out in %ds - a squadmate can revive you" % int(ceil(lp.bleed))
	elif lp.state == 2 and world.versus:
		down_label.text = "ELIMINATED - respawning in %ds" % int(ceil(lp.respawn_t))
	elif lp.state == 2:
		down_label.text = "KIA - spectating until the mission ends"
	else:
		down_label.text = ""
	if lp.revive_target != null:
		revive_label.text = "Hold E to revive %s" % lp.revive_target.display_name
		revive_bar.visible = lp.revive_progress > 0.0
		revive_bar.value = lp.revive_progress / lp.REVIVE_TIME
	else:
		revive_bar.visible = false
		if lp.in_mech >= 0:
			revive_label.text = "Piloting mech  -  E to exit"
		elif world.mech_near(lp.global_position) >= 0:
			revive_label.text = "Press E to enter mech"
		else:
			revive_label.text = ""


func _direction_text(lp, target: Vector3) -> String:
	var to: Vector3 = target - lp.global_position
	to.y = 0.0
	var dist := to.length()
	if dist < world.CAPTURE_RADIUS:
		return ">> IN ZONE - hold it! <<"
	var fwd: Vector3 = -lp.global_transform.basis.z
	var ang := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z)))
	var dir := "ahead"
	if absf(ang) > 135.0:
		dir = "behind you"
	elif ang > 30.0:
		dir = "to your right"
	elif ang < -30.0:
		dir = "to your left"
	return "Post is %dm %s" % [int(dist), dir]


# ---- FPS counter (F3 toggles, on by default)
var _fps_label: Label
var _menu_btn: Button
var _web_was_captured := false
var _f3_was := false


func _fps_tick() -> void:
	if _menu_btn == null:
		_menu_btn = Button.new()
		_menu_btn.text = "Menu [P]"
		_menu_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_menu_btn.offset_left = -118
		_menu_btn.offset_top = 8
		_menu_btn.offset_right = -12
		_menu_btn.offset_bottom = 36
		_menu_btn.focus_mode = Control.FOCUS_NONE
		_menu_btn.pressed.connect(_open_pause)
		add_child(_menu_btn)
	_menu_btn.visible = not end_panel.visible
	if _fps_label == null:
		_fps_label = Label.new()
		_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_fps_label.offset_left = -110
		_fps_label.offset_top = 42
		_fps_label.offset_right = -12
		_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		_fps_label.add_theme_font_size_override("font_size", 16)
		add_child(_fps_label)
	var f3 := Input.is_physical_key_pressed(KEY_F3)
	if f3 and not _f3_was:
		_fps_label.visible = not _fps_label.visible
	_f3_was = f3
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()



## Compact live control-key strip — dirty-checked, class/context aware.
func _update_controls_hint(lp) -> void:
	if controls_hint == null or lp == null:
		return
	if lp.state != 0 or end_panel.visible:
		if controls_hint.visible:
			controls_hint.visible = false
			_hud_cache.erase("ctrl")
		return
	controls_hint.visible = true
	var parts: Array = []
	# Context overrides first
	var near_revive = lp.revive_target != null
	var near_veh := -1
	if lp.in_mech < 0 and world != null:
		near_veh = world.mech_near(lp.global_position)
	if lp.in_mech >= 0:
		parts.append("[LMB] Fire")
		if lp.veh_vtype == 2:
			var scd: int = int(ceil(lp.veh_shell_cd))
			parts.append("[G/RMB] Shell READY" if scd <= 0 else "[G/RMB] Shell %ds" % scd)
		parts.append("[E] Exit")
		parts.append("[V] View")
		parts.append("[Shift] Boost")
	elif near_revive:
		parts.append("[Hold E] Revive")
		parts.append(_weapon_swap_pill(lp))
		parts.append(_class_action_pill(lp))
	elif near_veh >= 0:
		parts.append("[E] Board %s" % world.vehicle_name(near_veh))
		parts.append(_weapon_swap_pill(lp))
		parts.append(_class_action_pill(lp))
	else:
		parts.append(_weapon_swap_pill(lp))
		parts.append(_class_action_pill(lp))
		if lp.is_crouching:
			parts.append("[C/Z] Stand")
		else:
			parts.append("[C/Z] Crouch")
			if lp.cls == 0:
				parts.append("[Sprint+C] Slide")
		if lp.grenades > 0:
			parts.append("[G] Grenade (%d)" % lp.grenades)
		else:
			parts.append("[G] Grenade (0)")
		parts.append("[V] 1st/3rd")
		if lp.emote_id > 0:
			parts.append("[Move] Stop Emote")
		else:
			parts.append("[B/5-8] Emote")
	var text := "   ".join(parts)
	# Dirty key: text + cooldown seconds buckets
	var cmd_s: int = int(ceil(lp.cmd_cd)) if lp.cls == 3 else 0
	var shell_s: int = int(ceil(lp.veh_shell_cd)) if lp.in_mech >= 0 and lp.veh_vtype == 2 else 0
	var key := "%s|%d|%d|%d|%d|%d|%d|%d" % [text, lp.cls, lp.weapon, lp.grenades, int(lp.is_crouching), cmd_s, shell_s, lp.emote_id]
	key += "|%d|%d" % [lp.in_mech, near_veh]
	key += "|1" if near_revive else "|0"
	if _hud_cache.get("ctrl") == key:
		return
	_hud_cache["ctrl"] = key
	controls_hint.text = text


func _weapon_swap_pill(lp) -> String:
	var other: int = 1 - lp.weapon
	var w: Dictionary = Game.class_weapon(other)
	# Prefer explicit slot keys; [3] cycles
	var short: String = str(w.get("name", "Weapon")).split(" ")[0]
	return "[%d/%d] %s" % [other + 1, 3, short]


func _class_action_pill(lp) -> String:
	match lp.cls:
		1:  # Heavy
			var k: String = str(Game.class_weapon(lp.weapon).get("kind", ""))
			if k == "z6":
				return "[Hold LMB] Spin-Up"
			return "[LMB] Splash"
		2:  # Sniper
			if str(Game.class_weapon(lp.weapon).get("kind", "")) == "sniper":
				return "[RMB] 2.8x Scope"
			return "[RMB] Aim"
		3:  # Officer
			if lp.cmd_cd <= 0.0:
				return "[X] Battle Cmd READY"
			return "[X] Cmd %ds" % int(ceil(lp.cmd_cd))
		_:
			return "[RMB] Aim"
