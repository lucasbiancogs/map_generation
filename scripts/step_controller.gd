class_name StepController
extends Control

@export var grid_path: NodePath

var _current_step: int = 0
var _step_label: Label
var _prev_button: Button
var _next_button: Button
var _reset_button: Button
var _run_all_button: Button


var grid: OrganicGrid


func _ready() -> void:
	grid = get_node(grid_path) as OrganicGrid
	_build_ui()
	# Grid runs all steps on its own _ready. Show final state.
	_current_step = OrganicGrid.TOTAL_STEPS
	_update_ui()


func _build_ui() -> void:
	# Anchor to top-left with some margin.
	var panel := PanelContainer.new()
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 10
	panel.offset_top = 10

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_step_label)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	_prev_button = Button.new()
	_prev_button.text = "< Prev"
	_prev_button.pressed.connect(_on_prev)
	hbox.add_child(_prev_button)

	_next_button = Button.new()
	_next_button.text = "Next >"
	_next_button.pressed.connect(_on_next)
	hbox.add_child(_next_button)

	vbox.add_child(hbox)

	var hbox2 := HBoxContainer.new()
	hbox2.add_theme_constant_override("separation", 6)

	_reset_button = Button.new()
	_reset_button.text = "Reset"
	_reset_button.pressed.connect(_on_reset)
	hbox2.add_child(_reset_button)

	_run_all_button = Button.new()
	_run_all_button.text = "Run All"
	_run_all_button.pressed.connect(_on_run_all)
	hbox2.add_child(_run_all_button)

	vbox.add_child(hbox2)

	panel.add_child(vbox)
	add_child(panel)


func _on_next() -> void:
	if _current_step >= OrganicGrid.TOTAL_STEPS:
		return
	_current_step += 1
	grid.run_step(_current_step)
	_update_ui()


func _on_prev() -> void:
	if _current_step <= 0:
		return
	# Re-run from scratch up to the previous step.
	_current_step -= 1
	grid.reset()
	for step in range(1, _current_step + 1):
		grid.run_step(step)
	if _current_step == 0:
		grid._clear_visualization()
	_update_ui()


func _on_reset() -> void:
	_current_step = 0
	grid.reset()
	_update_ui()


func _on_run_all() -> void:
	grid.reset()
	grid.run_all()
	_current_step = OrganicGrid.TOTAL_STEPS
	_update_ui()


func _update_ui() -> void:
	if _current_step == 0:
		_step_label.text = "Step: (none)"
	else:
		_step_label.text = "Step: " + OrganicGrid.STEP_NAMES[_current_step - 1]

	_prev_button.disabled = _current_step <= 0
	_next_button.disabled = _current_step >= OrganicGrid.TOTAL_STEPS
