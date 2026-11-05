extends Control
## Main menu: singleplayer, host/join, lobby, armory (upgrade shop).

var status: Label
var panels := {}
var name_edit: LineEdit
var port_edit: LineEdit
var ip_edit: LineEdit
var ws_edit: LineEdit
var code_edit: LineEdit
var mode_opt: OptionButton
var relay_edit: LineEdit
var lobby_label: Label
var lobby_info: Label
var start_btn: Button
var credits_label: Label
var shop_list: VBoxContainer
var shop_credits: Label
var help_controls: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.in_mission = false
	get_tree().paused = false
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.07, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = Color(0.75, 0.4, 0.15, 0.25)
	stripe.set_anchors_preset(Control.PRESET_FULL_RECT)
	stripe.anchor_top = 0.62
	stripe.anchor_bottom = 0.64
	add_child(stripe)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	var title := Label.new()
	title.text = "DROID SIEGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.6, 0.25, 0.05))
	outer.add_child(title)
	var sub := Label.new()
	sub.text = "Co-op clone trooper assault  -  1 to 4 players"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	outer.add_child(sub)

	var center := CenterContainer.new()
	outer.add_child(center)
	var holder := VBoxContainer.new()
	center.add_child(holder)

	panels["main"] = _build_main(holder)
	panels["mp"] = _build_mp(holder)
	panels["lobby"] = _build_lobby(holder)
	panels["shop"] = _build_shop(holder)
	panels["help"] = _build_help(holder)

	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD
	status.custom_minimum_size = Vector2(700, 0)
	status.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	var sc := CenterContainer.new()
	sc.add_child(status)
	outer.add_child(sc)

	Game.lobby_changed.connect(_refresh_lobby)
	Game.net_status.connect(_on_status)
	if Game.menu_message != "":
		status.text = Game.menu_message
		Game.menu_message = ""
	_show("main")


func _panel(holder: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	holder.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(460, 0)
	m.add_child(box)
	return box


func _btn(box: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _lbl(box: Control, text: String, size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(l)
	return l


func _show(which: String) -> void:
	for k in panels.keys():
		panels[k].get_parent().get_parent().visible = (k == which)
	if which == "main":
		credits_label.text = "Credits: %d    Missions: %d    Victories: %d    Grenades: %d" % [
			Game.save["credits"], Game.save["missions"], Game.save["wins"], Game.save["grenades"]]
	if which == "help":
		help_controls.text = "Current controls - " + Game.controls_help()
	if which == "shop":
		_refresh_shop()
	if which == "lobby":
		_refresh_lobby()


func _build_main(holder: Control) -> Control:
	var box := _panel(holder)
	_lbl(box, "Trooper name:")
	name_edit = LineEdit.new()
	name_edit.text = Game.player_name
	name_edit.max_length = 16
	name_edit.text_changed.connect(func(t): Game.player_name = t if t.strip_edges() != "" else "Trooper")
	box.add_child(name_edit)
	var row := HBoxContainer.new()
	box.add_child(row)
	var map_opt := OptionButton.new()
	map_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in Game.MAPS:
		map_opt.add_item("Map: " + m["name"])
	map_opt.selected = int(Game.settings["map"])
	map_opt.item_selected.connect(func(i): Game.settings["map"] = i; Game.write_save())
	row.add_child(map_opt)
	var solo_opt := OptionButton.new()
	solo_opt.add_item("Solo: Droid Siege")
	solo_opt.add_item("Solo: Horde Survival")
	solo_opt.selected = 1 if int(Game.settings.get("mode", 0)) == Game.HORDE else 0
	solo_opt.item_selected.connect(func(i): Game.settings["mode"] = Game.HORDE if i == 1 else 0; Game.write_save())
	row.add_child(solo_opt)
	var diff_opt := OptionButton.new()
	for d in Game.DIFFICULTIES:
		diff_opt.add_item(d["name"])
	diff_opt.selected = int(Game.settings["diff"])
	diff_opt.item_selected.connect(func(i): Game.settings["diff"] = i; Game.write_save())
	row.add_child(diff_opt)
	Game.build_control_options(box)
	_btn(box, "Singleplayer Mission", func(): Game.write_save(); Game.start_singleplayer())
	_btn(box, "Multiplayer (Host / Join)", func(): _show("mp"))
	_btn(box, "Armory (Upgrades & Grenades)", func(): _show("shop"))
	_btn(box, "How to Play", func(): _show("help"))
	_btn(box, "Quit", func(): Game.write_save(); get_tree().quit())
	credits_label = _lbl(box, "")
	return box


func _build_mp(holder: Control) -> Control:
	var box := _panel(holder)
	_lbl(box, "MULTIPLAYER (up to 4 troopers)", 22)
	_btn(box, "Host Game (get a room code)", _on_host_room)
	_lbl(box, "Got a code from a friend?")
	var row := HBoxContainer.new()
	box.add_child(row)
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "ROOM CODE"
	code_edit.max_length = 8
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.add_theme_font_size_override("font_size", 22)
	code_edit.text_submitted.connect(func(_t): _on_join_room())
	row.add_child(code_edit)
	var jb := Button.new()
	jb.text = "Join with Code"
	jb.custom_minimum_size = Vector2(160, 44)
	jb.pressed.connect(_on_join_room)
	row.add_child(jb)
	var adv_btn := Button.new()
	adv_btn.text = "Advanced (relay address, online server, direct IP)  v"
	adv_btn.flat = true
	box.add_child(adv_btn)
	var adv := VBoxContainer.new()
	adv.visible = false
	box.add_child(adv)
	adv_btn.pressed.connect(func(): adv.visible = not adv.visible)

	_lbl(adv, "Relay server address (leave empty to use the built-in one%s):" % ("" if Game.RELAY_URL == "" else ": " + Game.RELAY_URL), 13)
	relay_edit = LineEdit.new()
	relay_edit.text = str(Game.save.get("relay_url", ""))
	relay_edit.placeholder_text = "wss://your-relay.onrender.com"
	relay_edit.text_changed.connect(func(t): Game.save["relay_url"] = t.strip_edges(); Game.write_save())
	adv.add_child(relay_edit)

	_lbl(adv, "Dedicated online server (wss://...):", 13)
	ws_edit = LineEdit.new()
	ws_edit.text = str(Game.save.get("ws_url", ""))
	ws_edit.placeholder_text = "wss://your-droid-siege-server.example.com"
	adv.add_child(ws_edit)
	_btn(adv, "Join Dedicated Server", _on_join_ws)

	var direct := VBoxContainer.new()
	adv.add_child(direct)
	if Game.is_web():
		_lbl(adv, "Direct IP (ENet) is only available in the desktop version.", 13)
		direct.visible = false
	_lbl(direct, "Direct IP (same Wi-Fi only) - UDP port:", 13)
	port_edit = LineEdit.new()
	port_edit.text = str(Game.DEFAULT_PORT)
	direct.add_child(port_edit)
	_btn(direct, "Host Direct (no code)", _on_host)
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "Host LAN IP, e.g. 192.168.1.20"
	direct.add_child(ip_edit)
	_btn(direct, "Join Direct IP", _on_join)
	_btn(box, "Back", func(): _show("main"))
	return box


func _on_host_room() -> void:
	Game.write_save()
	var err := Game.host_room()
	if err != "":
		status.text = err
		return
	_show("lobby")


func _on_join_room() -> void:
	Game.write_save()
	var err := Game.join_room(code_edit.text)
	if err != "":
		status.text = err
		return
	status.text = "Joining room %s ..." % code_edit.text.strip_edges().to_upper()
	_show("lobby")


func _build_lobby(holder: Control) -> Control:
	var box := _panel(holder)
	_lbl(box, "SQUAD LOBBY", 22)
	lobby_label = _lbl(box, "")
	lobby_info = _lbl(box, "", 13)
	var mrow := HBoxContainer.new()
	box.add_child(mrow)
	var ml := Label.new()
	ml.text = "Mode:"
	mrow.add_child(ml)
	mode_opt = OptionButton.new()
	mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in Game.GAME_MODES:
		mode_opt.add_item(m)
	mode_opt.selected = int(Game.settings.get("mode", 0))
	mode_opt.item_selected.connect(func(i): Game.settings["mode"] = i; Game.write_save())
	mrow.add_child(mode_opt)
	start_btn = _btn(box, "Start Mission", func(): Game.write_save(); Game.start_mission())
	_btn(box, "Leave", func(): Game.leave_network(); _show("mp"))
	return box


func _build_shop(holder: Control) -> Control:
	var box := _panel(holder)
	_lbl(box, "ARMORY", 22)
	shop_credits = _lbl(box, "")
	shop_list = VBoxContainer.new()
	shop_list.add_theme_constant_override("separation", 8)
	box.add_child(shop_list)
	_btn(box, "Back", func(): _show("main"))
	return box


func _build_help(holder: Control) -> Control:
	var box := _panel(holder)
	_lbl(box, "HOW TO PLAY", 22)
	help_controls = _lbl(box, "", 14)
	help_controls.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	_lbl(box, "Capture command posts ALPHA, BRAVO and CHARLIE in any order by standing in their rings (more droids than troopers in a ring = CONTESTED, capture pauses). Then survive until the gunship arrives.\n\nB1 droids are weak. B2 super droids are tough. Droidekas roll in fast, then deploy a shield that blocks shots from the front: flank them, shoot them while rolling, or break the shield (grenades do double shield damage).\n\nDriveable walker parked by the drop point: Press E to enter mech, E again to exit. It is armoured, fires a heavy cannon, steers like on foot.\n\nIf every trooper is down, the mission fails. Earn credits and spend them in the Armory.", 14)
	_btn(box, "Back", func(): _show("main"))
	return box


func _refresh_shop() -> void:
	shop_credits.text = "Credits: %d" % Game.save["credits"]
	for c in shop_list.get_children():
		c.queue_free()
	for key in Game.UPGRADES.keys():
		var u: Dictionary = Game.UPGRADES[key]
		var lvl := int(Game.save[key])
		var row := HBoxContainer.new()
		var l := Label.new()
		l.custom_minimum_size = Vector2(300, 0)
		l.text = "%s  Lv %d/%d\n%s" % [u["label"], lvl, Game.MAX_LEVEL, u["desc"]]
		row.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 40)
		if lvl >= Game.MAX_LEVEL:
			b.text = "MAXED"
			b.disabled = true
		else:
			var cost := Game.upgrade_cost(key)
			b.text = "Buy (%d cr)" % cost
			b.disabled = int(Game.save["credits"]) < cost
			b.pressed.connect(func(): Game.buy_upgrade(key); _refresh_shop())
		row.add_child(b)
		shop_list.add_child(row)
	var grow := HBoxContainer.new()
	var gl := Label.new()
	gl.custom_minimum_size = Vector2(300, 0)
	gl.text = "Thermal Detonator  x%d/%d\nArea damage, wrecks droideka shields" % [Game.save["grenades"], Game.MAX_GRENADES]
	grow.add_child(gl)
	var gb := Button.new()
	gb.custom_minimum_size = Vector2(150, 40)
	gb.text = "Buy (%d cr)" % Game.GRENADE_COST
	gb.disabled = int(Game.save["credits"]) < Game.GRENADE_COST or int(Game.save["grenades"]) >= Game.MAX_GRENADES
	gb.pressed.connect(func(): Game.buy_grenade(); _refresh_shop())
	grow.add_child(gb)
	shop_list.add_child(grow)


func _on_host() -> void:
	Game.write_save()
	var err := Game.host_game(int(port_edit.text))
	if err != "":
		status.text = err
		return
	status.text = "Hosting on UDP port %s. Share your IP with your squad." % port_edit.text
	_show("lobby")


func _on_join_ws() -> void:
	Game.save["ws_url"] = ws_edit.text.strip_edges()
	Game.write_save()
	if ws_edit.text.strip_edges() == "":
		status.text = "Enter the online server address first (see README: Online server)."
		return
	var err := Game.join_ws(ws_edit.text)
	if err != "":
		status.text = err
		return
	status.text = "Connecting to %s ... (a sleeping free server can take up to a minute to wake)" % ws_edit.text
	_show("lobby")


func _on_join() -> void:
	Game.write_save()
	var err := Game.join_game(ip_edit.text, int(port_edit.text))
	if err != "":
		status.text = err
		return
	status.text = "Connecting to %s:%s ..." % [ip_edit.text, port_edit.text]
	_show("lobby")


func _on_status(msg: String) -> void:
	status.text = msg
	if not Game.online and Game._pending_relay == null and panels["lobby"].get_parent().get_parent().visible:
		_show("mp")


func _refresh_lobby() -> void:
	if lobby_label == null:
		return
	var t := ""
	var keys := Game.players.keys()
	keys.sort()
	for k in keys:
		t += "- %s%s\n" % [Game.players[k]["name"], "  (host)" if k == 1 else ""]
	if t == "":
		t = "(connecting...)" if Game.online or Game._pending_relay != null else "(not connected)"
	lobby_label.text = "Troopers (%d/4):\n%s" % [Game.players.size(), t]
	var is_host: bool = Game.online and multiplayer.is_server()
	start_btn.visible = is_host or (Game.server_is_dedicated and Game.online)
	mode_opt.get_parent().visible = start_btn.visible
	if is_host and Game.room_code != "":
		lobby_info.text = "ROOM CODE:  %s\nYour friends: Multiplayer > type the code > Join with Code." % Game.room_code
		lobby_info.add_theme_font_size_override("font_size", 20)
	elif is_host:
		var ips := PackedStringArray()
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
				ips.append(a)
		lobby_info.text = "Your IP addresses (share one):\n%s\nPort %s. Map and difficulty come from your main menu choice. Late joiners drop in at the landing zone. Press Start when your squad is in." % ["\n".join(ips), port_edit.text]
	elif Game.server_is_dedicated:
		lobby_info.text = "Online server. Any trooper can press Start Mission (uses your map/difficulty choice)."
	else:
		lobby_info.text = "Waiting for the host to start the mission..."
