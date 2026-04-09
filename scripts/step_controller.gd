class_name StepController
extends Control

@export var grid: BaseGrid
@export var visualizer: GridVisualizer
@export var map_gen: MapGeneration

var _current_step: int = 0
var _step_label: Label
var _prev_button: Button
var _next_button: Button
var _reset_button: Button
var _run_all_button: Button
var _seed_input: SpinBox
var _generate_button: Button
var _noise_rect: TextureRect

func _ready() -> void:
	_build_ui()
	_current_step = OrganicGrid.TOTAL_STEPS
	# Wait for MapGeneration to finish (it awaits one frame after grid).
	await get_tree().process_frame
	await get_tree().process_frame
	_refresh_noise_preview()
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

	# --- Grid Steps ---
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

	# --- Map Generation ---
	vbox.add_child(HSeparator.new())

	var map_label := Label.new()
	map_label.text = "Map Generation"
	map_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(map_label)

	var seed_hbox := HBoxContainer.new()
	seed_hbox.add_theme_constant_override("separation", 6)

	var seed_label := Label.new()
	seed_label.text = "Seed:"
	seed_hbox.add_child(seed_label)

	_seed_input = SpinBox.new()
	_seed_input.min_value = 0
	_seed_input.max_value = 99999
	_seed_input.step = 1
	_seed_input.value = map_gen.noise_seed if map_gen else 0
	_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_hbox.add_child(_seed_input)

	vbox.add_child(seed_hbox)

	_generate_button = Button.new()
	_generate_button.text = "Generate Map"
	_generate_button.pressed.connect(_on_generate)
	vbox.add_child(_generate_button)

	# --- Visibility Toggles ---
	vbox.add_child(HSeparator.new())

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

	# --- Noise Preview ---
	vbox.add_child(HSeparator.new())

	var noise_label := Label.new()
	noise_label.text = "Noise Preview"
	noise_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(noise_label)

	_noise_rect = TextureRect.new()
	_noise_rect.custom_minimum_size = Vector2(180, 180)
	_noise_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_noise_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vbox.add_child(_noise_rect)

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
	map_gen.reset()
	for step in range(1, _current_step + 1):
		grid.run_step(step)
	visualizer.refresh()
	_update_ui()


func _on_reset() -> void:
	_current_step = 0
	grid.reset()
	map_gen.reset()
	visualizer.refresh()
	_update_ui()


func _on_run_all() -> void:
	grid.reset()
	map_gen.reset()
	grid.run_all()
	_current_step = OrganicGrid.TOTAL_STEPS
	map_gen.regenerate()
	_refresh_noise_preview()
	visualizer.refresh()
	_update_ui()


func _on_generate() -> void:
	if not map_gen:
		return
	map_gen.noise_seed = int(_seed_input.value)
	# Ensure grid is fully built before generating.
	if _current_step < OrganicGrid.TOTAL_STEPS:
		grid.reset()
		grid.run_all()
		_current_step = OrganicGrid.TOTAL_STEPS
	map_gen.regenerate()
	_refresh_noise_preview()
	visualizer.refresh()
	_update_ui()


func _refresh_noise_preview() -> void:
	if map_gen and _noise_rect:
		_noise_rect.texture = map_gen.generate_noise_preview()


func _update_ui() -> void:
	if _current_step == 0:
		_step_label.text = "Step: (none)"
	else:
		_step_label.text = "Step: " + OrganicGrid.STEP_NAMES[_current_step - 1]

	_prev_button.disabled = _current_step <= 0
	_next_button.disabled = _current_step >= OrganicGrid.TOTAL_STEPS
	_generate_button.disabled = _current_step < OrganicGrid.TOTAL_STEPS

	if map_gen:
		_seed_input.value = map_gen.noise_seed
