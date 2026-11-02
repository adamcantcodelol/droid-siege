extends Control
## Crosshair drawn with lines at the exact center of the screen (full-rect, ignores mouse).

var aiming := false
var color := Color(1, 1, 1, 0.95)
var on_target := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var gap := 5.0 if aiming else 9.0
	var length := 16.0 if aiming else 11.0
	var w := 3.0 if aiming else 2.0
	var col := Color(1, 0.35, 0.25) if on_target and color == Color(1, 1, 1, 0.95) else color
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var a: Vector2 = c + d * gap
		var b: Vector2 = c + d * (gap + length)
		draw_line(a, b, Color(0, 0, 0, 0.85), w + 2.5)
		draw_line(a, b, col, w)
	draw_circle(c, (2.5 if aiming else 2.0) + 1.2, Color(0, 0, 0, 0.85))
	draw_circle(c, 2.5 if aiming else 2.0, col)
	if aiming:
		draw_arc(c, gap + length + 6.0, 0, TAU, 40, Color(col.r, col.g, col.b, 0.5), 1.5)
