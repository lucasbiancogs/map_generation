class_name CameraController
extends Camera3D

## How fast the camera pans relative to mouse movement.
@export var pan_speed: float = 0.01
## Zoom speed per scroll step.
@export var zoom_speed: float = 0.5
## Minimum and maximum distance from the look-at point.
@export var min_distance: float = 2.0
@export var max_distance: float = 30.0

var _dragging: bool = false
var _look_at_point: Vector3 = Vector3.ZERO
var _distance: float
var _camera_direction: Vector3


func _ready() -> void:
	# Derive initial state from current transform.
	_camera_direction = -basis.z.normalized()
	_distance = global_position.length()
	_look_at_point = global_position + _camera_direction * _distance
	# Snap look_at to the ground plane (y=0).
	_look_at_point.y = 0.0
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_distance = maxf(_distance - zoom_speed, min_distance)
			_update_transform()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_distance = minf(_distance + zoom_speed, max_distance)
			_update_transform()

	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		# Pan on the ground plane (XZ) using camera's local right and forward projected to XZ.
		var right := basis.x.normalized()
		var forward := basis.z.normalized()
		# Project to XZ plane.
		right.y = 0.0
		right = right.normalized()
		forward.y = 0.0
		forward = forward.normalized()

		var delta: Vector2 = motion.relative
		_look_at_point -= right * delta.x * pan_speed * _distance * 0.1
		_look_at_point -= forward * delta.y * pan_speed * _distance * 0.1
		_update_transform()


func _update_transform() -> void:
	global_position = _look_at_point - _camera_direction * _distance
	look_at(_look_at_point, Vector3.UP)
