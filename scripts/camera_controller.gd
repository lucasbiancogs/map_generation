class_name CameraController
extends Camera3D

## How fast the camera pans relative to mouse movement.
@export var pan_speed: float = 0.01
## Zoom speed per scroll step.
@export var zoom_speed: float = 1.0
## Minimum and maximum distance from the look-at point.
@export var min_distance: float = 1.0
@export var max_distance: float = 50.0
## Rotation speed in degrees per pixel of mouse movement.
@export var rotate_speed: float = 0.3
## Minimum and maximum pitch angle in degrees.
@export var min_pitch: float = 10.0
@export var max_pitch: float = 89.0

var _panning: bool = false
var _rotating: bool = false
var _look_at_point: Vector3 = Vector3.ZERO
var _distance: float
var _yaw: float
var _pitch: float


func _ready() -> void:
	var offset := global_position - _look_at_point
	_distance = offset.length()
	_pitch = rad_to_deg(asin(offset.y / _distance))
	_yaw = rad_to_deg(atan2(offset.x, offset.z))
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_RIGHT:
				_rotating = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_distance = maxf(_distance - zoom_speed, min_distance)
					_update_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_distance = minf(_distance + zoom_speed, max_distance)
					_update_transform()

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var delta: Vector2 = motion.relative

		if _rotating:
			_yaw -= delta.x * rotate_speed
			_pitch = clampf(_pitch + delta.y * rotate_speed, min_pitch, max_pitch)
			_update_transform()

		elif _panning:
			var right := basis.x.normalized()
			var forward := basis.z.normalized()
			right.y = 0.0
			right = right.normalized()
			forward.y = 0.0
			forward = forward.normalized()
			_look_at_point -= right * delta.x * pan_speed * _distance * 0.1
			_look_at_point -= forward * delta.y * pan_speed * _distance * 0.1
			_update_transform()

	elif event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		_yaw -= pan.delta.x * rotate_speed * 5.0
		_pitch = clampf(_pitch + pan.delta.y * rotate_speed * 5.0, min_pitch, max_pitch)
		_update_transform()

	elif event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		_distance = clampf(_distance / mag.factor, min_distance, max_distance)
		_update_transform()


func _update_transform() -> void:
	var pitch_rad := deg_to_rad(_pitch)
	var yaw_rad := deg_to_rad(_yaw)

	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * _distance

	global_position = _look_at_point + offset
	look_at(_look_at_point, Vector3.UP)
