class_name StepController
extends Control

@export var grid: BaseGrid
@export var visualizer: GridVisualizer

var _current_step: int = 0
var _step_label: Label
var _prev_button: Button
var _next_button: Button
var _reset_button: Button
var _run_all_button: Button

func _ready() -> void:
	_build_ui()
	_current_step = OrganicGrid.TOTAL_STEPS
	# Wait for MapGeneration to finish (it awaits one frame after grid).
	await get_tree().process_frame
	await get_tree().process_frame
	visualizer.refresh()
	_update_ui()


func _build_ui() -> void:
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

	# Visibility toggles.
	var sep := HSeparator.new()
	vbox.add_child(sep)

	var toggles_label := Label.new()
	toggles_label.text = "Visibility"
	toggles_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(toggles_label)

	_add_toggle(vbox, "Grid Wireframe", visualizer.show_grid_wireframe, func(toggled: bool):
		visualizer.show_grid_wireframe = toggled
		visualizer.refresh()
	)
	_add_toggle(vbox, "Points", visualizer.show_points, func(toggled: bool):
		visualizer.show_points = toggled
		visualizer.refresh()
	)
	_add_toggle(vbox, "Tile Edges", visualizer.show_tile_edges, func(toggled: bool):
		visualizer.show_tile_edges = toggled
		visualizer.refresh()
	)
	_add_toggle(vbox, "Connectivity", visualizer.show_connectivity, func(toggled: bool):
		visualizer.show_connectivity = toggled
		visualizer.refresh()
	)
	_add_toggle(vbox, "Height Map", visualizer.show_height_map, func(toggled: bool):
		visualizer.show_height_map = toggled
		visualizer.refresh()
	)
	_add_toggle(vbox, "Tile Layers", visualizer.show_tile_layers, func(toggled: bool):
		visualizer.show_tile_layers = toggled
		visualizer.refresh()
	)

	panel.add_child(vbox)
	add_child(panel)


func _add_toggle(parent: Control, label: String, default_on: bool, callback: Callable) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = default_on
	cb.toggled.connect(callback)
	parent.add_child(cb)


func _on_next() -> void:
	if _current_step >= OrganicGrid.TOTAL_STEPS:
		return
	_current_step += 1
	grid.run_step(_current_step)
	visualizer.refresh()
	_update_ui()


func _on_prev() -> void:
	if _current_step <= 0:
		return
	_current_step -= 1
	grid.reset()
	for step in range(1, _current_step + 1):
		grid.run_step(step)
	visualizer.refresh()
	_update_ui()


func _on_reset() -> void:
	_current_step = 0
	grid.reset()
	visualizer.refresh()
	_update_ui()


func _on_run_all() -> void:
	grid.reset()
	grid.run_all()
	_current_step = OrganicGrid.TOTAL_STEPS
	visualizer.refresh()
	_update_ui()


func _update_ui() -> void:
	if _current_step == 0:
		_step_label.text = "Step: (none)"
	else:
		_step_label.text = "Step: " + OrganicGrid.STEP_NAMES[_current_step - 1]

	_prev_button.disabled = _current_step <= 0
	_next_button.disabled = _current_step >= OrganicGrid.TOTAL_STEPS
