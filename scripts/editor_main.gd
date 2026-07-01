extends Node3D

enum EditMode { BLOCK, CHARACTER }
enum ToolType { PENCIL, BOX, ERASER, BOX_ERASE, EXTRUDE, LINE, RECT, OVAL, SMOOTH_EDGE, PAINT, BUCKET, EYEDROP }

const BLOCK_RES := 32
const CHAR_RES := 64
var CELL_SIZE := 1.0 / BLOCK_RES
const PANEL_WIDTH := 180

var edit_mode: int = EditMode.BLOCK
var grid_x := 32
var grid_y := 32
var grid_z := 32

var cells: Array = []
var current_tool: int = ToolType.PENCIL
var current_type: int = CellTypes.Type.SOLID
var current_orientation: int = 0
var current_color: int = CellTypes.encode_rgb565(CellTypes.FAVORITES[0])
var current_file_path := ""
var floor_y: int = 0
var ceiling_y: int = -1
var _ceiling_locked := false
var _unsaved_changes := false
var _mesh_dirty := false
var _pending_action := ""
var _flat_color_mode := false
var _preview_mode := false
var _preview_light: DirectionalLight3D
var _undo_stack: Array = []
const MAX_UNDO := 50
var _mirror_x := false
var _mirror_z := false
var _center_draw := 0  # 0=off, 1=voxel center, 2=joint center
var _show_axis_overlay := false
var axis_overlay_x: MeshInstance3D
var axis_overlay_z: MeshInstance3D
var mirror_cursor_instance: MeshInstance3D
var center_joint_marker: MeshInstance3D
var _rect_btn: Button
var _oval_btn: Button
var _floor_hit_pos := Vector3.ZERO
var _joint_center := Vector2i(-1, -1)

var box_start := Vector3i(-1, -1, -1)
var box_active := false

var extrude_active := false
var extrude_cells: Array = []
var extrude_normal := Vector3i.ZERO
var extrude_depth := 0
var extrude_start_mouse := Vector2.ZERO
var extrude_pixels_per_cell := 1.0
var extrude_screen_dir := Vector2.ZERO

var smooth_active := false
var smooth_start := Vector3i(-1, -1, -1)
var smooth_edge_dir := Vector3i.ZERO
var smooth_normal_a := Vector3i.ZERO
var smooth_normal_b := Vector3i.ZERO
var smooth_path: Array = []
var smooth_start_mouse := Vector2.ZERO
var smooth_edge_screen_dir := Vector2.ZERO
var smooth_pixels_per_cell := 1.0

var place_cell := Vector3i(-1, -1, -1)
var target_cell := Vector3i(-1, -1, -1)
var _hit_normal := Vector3i.ZERO

const CHUNK_SIZE := 16
var _chunk_container: Node3D
var _chunk_meshes: Dictionary = {}
var _dirty_chunks: Dictionary = {}
var grid_mesh_instance: MeshInstance3D
var _cached_opaque_mat: ShaderMaterial
var _cached_cutout_mat: ShaderMaterial
var cursor_mesh_instance: MeshInstance3D
var box_preview_instance: MeshInstance3D

var ui_layer: CanvasLayer
var panel: PanelContainer
var coord_label: Label
var dims_label: Label
var file_label: Label
var orient_container: HBoxContainer
var orient_label: Label
var floor_slider: HSlider
var floor_value_label: Label
var ceiling_slider: HSlider
var ceiling_value_label: Label
var ceiling_lock_btn: CheckButton

var mode_group: ButtonGroup
var tool_group: ButtonGroup
var type_group: ButtonGroup
var color_group: ButtonGroup
var _color_picker_btn: ColorPickerButton

var menu_bar: MenuBar
var file_menu: PopupMenu
var edit_menu: PopupMenu
var view_menu: PopupMenu
var view_cube: Control
var preview_light_container: VBoxContainer

var save_dialog: FileDialog
var open_dialog: FileDialog
var import_dialog: FileDialog
var import_block_dialog: FileDialog
var export_dialog: FileDialog
var import_front_dialog: FileDialog
var import_side_dialog: FileDialog
var confirm_dialog: ConfirmationDialog
var smooth_dialog: ConfirmationDialog
var smooth_depth_spin: SpinBox
var sprite_wizard: AcceptDialog
var block_tex_wizard: AcceptDialog
var _block_tex_faces: Dictionary
var _block_tex_has_alpha: bool
var _block_tex_is_octagon: bool
var _block_tex_octagon_footprint: int = 0
var _block_tex_format_label: Label
var _block_tex_previews: Dictionary
var _block_tex_preview_grid: GridContainer
var _block_tex_hint_label: Label
var _front_image: Image
var _side_image: Image
var _wizard_flip_front: CheckButton
var _wizard_flip_side: CheckButton
var _wizard_front_label: Label
var _wizard_side_label: Label
var _wizard_front_preview: TextureRect
var _wizard_side_preview: TextureRect
var _wizard_front_size_label: Label
var _wizard_side_size_label: Label

@onready var camera: Camera3D = $Camera3D

# ─── Lifecycle ───

func _ready() -> void:
	_init_cells()
	_setup_scene()
	_setup_ui()
	_rebuild_mesh()
	_rebuild_grid()
	_rebuild_axis_overlay()
	_center_camera()
	_generate_presets()

func _process(_delta: float) -> void:
	if _mesh_dirty:
		_mesh_dirty = false
		_rebuild_mesh_now()
	if camera and view_cube:
		view_cube.set_orientation(camera.yaw, camera.pitch)

func _generate_presets() -> void:
	DirAccess.make_dir_recursive_absolute("res://definitions")
	ResourceSaver.save(VoxelDefinition.create_male(), "res://definitions/male.res", ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(VoxelDefinition.create_female(), "res://definitions/female.res", ResourceSaver.FLAG_COMPRESS)

func _center_camera() -> void:
	camera.pivot = Vector3(grid_x, grid_y, grid_z) * CELL_SIZE * 0.5

func _clear_chunks() -> void:
	for mi: MeshInstance3D in _chunk_meshes.values():
		mi.queue_free()
	_chunk_meshes.clear()
	_dirty_chunks.clear()

func _init_cells() -> void:
	_clear_chunks()
	cells.resize(grid_x)
	for x in range(grid_x):
		cells[x] = []
		cells[x].resize(grid_y)
		for y in range(grid_y):
			cells[x][y] = []
			cells[x][y].resize(grid_z)
			for z in range(grid_z):
				cells[x][y][z] = CellTypes.empty_cell()

# ─── Scene Setup ───

func _setup_scene() -> void:
	_chunk_container = Node3D.new()
	add_child(_chunk_container)
	_invalidate_materials()

	grid_mesh_instance = MeshInstance3D.new()
	add_child(grid_mesh_instance)

	cursor_mesh_instance = MeshInstance3D.new()
	add_child(cursor_mesh_instance)
	cursor_mesh_instance.visible = false

	box_preview_instance = MeshInstance3D.new()
	add_child(box_preview_instance)
	box_preview_instance.visible = false
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(1, 1, 0, 0.6)
	box_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box_mat.no_depth_test = true
	box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box_preview_instance.material_override = box_mat

	axis_overlay_x = MeshInstance3D.new()
	add_child(axis_overlay_x)
	axis_overlay_x.visible = false
	var ax_mat := StandardMaterial3D.new()
	ax_mat.albedo_color = Color(1, 0.2, 0.2, 0.15)
	ax_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ax_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ax_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	axis_overlay_x.material_override = ax_mat

	axis_overlay_z = MeshInstance3D.new()
	add_child(axis_overlay_z)
	axis_overlay_z.visible = false
	var az_mat := StandardMaterial3D.new()
	az_mat.albedo_color = Color(0.2, 0.2, 1, 0.15)
	az_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	az_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	az_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	axis_overlay_z.material_override = az_mat

	mirror_cursor_instance = MeshInstance3D.new()
	add_child(mirror_cursor_instance)
	mirror_cursor_instance.visible = false

	center_joint_marker = MeshInstance3D.new()
	add_child(center_joint_marker)
	center_joint_marker.visible = false
	var jm_mat := StandardMaterial3D.new()
	jm_mat.albedo_color = Color(1, 1, 0, 0.8)
	jm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	jm_mat.no_depth_test = true
	center_joint_marker.material_override = jm_mat

# ─── UI Panel ───

const MENU_HEIGHT := 24

func _setup_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	# Menu bar
	menu_bar = MenuBar.new()
	menu_bar.position = Vector2.ZERO
	menu_bar.size = Vector2(1920, MENU_HEIGHT)
	ui_layer.add_child(menu_bar)

	file_menu = PopupMenu.new()
	file_menu.name = "File"
	file_menu.add_item("New", 0, KEY_MASK_CTRL | KEY_N)
	file_menu.add_item("Open...", 1, KEY_MASK_CTRL | KEY_O)
	file_menu.add_item("Save", 2, KEY_MASK_CTRL | KEY_S)
	file_menu.add_item("Save As...", 7, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S)
	file_menu.add_separator()
	file_menu.add_item("Import PNG...", 3, KEY_MASK_CTRL | KEY_I)
	file_menu.add_item("Import Block Texture...", 5)
	file_menu.add_item("Import Character Sprites...", 4)
	file_menu.add_separator()
	file_menu.add_item("Export OBJ...", 6)
	file_menu.id_pressed.connect(_on_file_menu)

	menu_bar.add_child(file_menu)

	edit_menu = PopupMenu.new()
	edit_menu.name = "Edit"
	edit_menu.add_item("Undo", 0, KEY_MASK_CTRL | KEY_Z)
	edit_menu.id_pressed.connect(_on_edit_menu)
	menu_bar.add_child(edit_menu)

	view_menu = PopupMenu.new()
	view_menu.name = "View"
	view_menu.add_check_item("Flat Colors", 0)
	view_menu.add_check_item("Preview Lighting", 1)
	view_menu.add_separator()
	view_menu.add_check_item("Axis Overlay", 2)
	view_menu.add_separator()
	view_menu.add_check_item("Mirror X", 3)
	view_menu.add_check_item("Mirror Z", 4)
	view_menu.id_pressed.connect(_on_view_menu)
	menu_bar.add_child(view_menu)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 0.92)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8

	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.position = Vector2(0, MENU_HEIGHT)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 1080 - MENU_HEIGHT)
	ui_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "PrismCraft Editor"
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# Mode
	_add_section_label(vbox, "Mode")
	mode_group = ButtonGroup.new()
	var mode_row := _add_button_row(vbox, ["Block", "Character"], mode_group)
	mode_row[0].button_pressed = true
	mode_group.pressed.connect(_on_mode_pressed)

	vbox.add_child(HSeparator.new())

	# Tool
	_add_section_label(vbox, "Tool")
	tool_group = ButtonGroup.new()
	var tool_row1 := _add_button_row(vbox, ["Pencil", "Paint", "Bucket"], tool_group)
	var tool_row2 := _add_button_row(vbox, ["Eraser", "Box Erase", "Eyedrop"], tool_group)
	var _tool_row_fill := _add_button_row(vbox, ["Box Fill"], tool_group)
	var _tool_row3 := _add_button_row(vbox, ["Extrude", "Smooth"], tool_group)
	var tool_row4 := _add_button_row(vbox, ["Line", "Rect", "Oval"], tool_group)
	_rect_btn = tool_row4[1]
	_oval_btn = tool_row4[2]
	_rect_btn.gui_input.connect(_on_shape_btn_gui_input)
	_oval_btn.gui_input.connect(_on_shape_btn_gui_input)
	tool_row1[0].button_pressed = true
	tool_group.pressed.connect(_on_tool_pressed)

	vbox.add_child(HSeparator.new())

	# Cell Type
	_add_section_label(vbox, "Cell Type")
	type_group = ButtonGroup.new()
	var type_row := _add_button_row(vbox, ["Solid", "Prism"], type_group)
	type_row[0].button_pressed = true
	type_group.pressed.connect(_on_type_pressed)

	orient_container = HBoxContainer.new()
	orient_container.visible = false
	vbox.add_child(orient_container)
	var orient_prev := Button.new()
	orient_prev.text = "<"
	orient_prev.custom_minimum_size = Vector2(30, 0)
	orient_prev.pressed.connect(func(): _cycle_orientation(-1))
	orient_container.add_child(orient_prev)
	orient_label = Label.new()
	orient_label.text = CellTypes.get_orientation_name(0)
	orient_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	orient_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orient_container.add_child(orient_label)
	var orient_next := Button.new()
	orient_next.text = ">"
	orient_next.custom_minimum_size = Vector2(30, 0)
	orient_next.pressed.connect(func(): _cycle_orientation(1))
	orient_container.add_child(orient_next)

	vbox.add_child(HSeparator.new())

	# Color
	_add_section_label(vbox, "Color")
	_color_picker_btn = ColorPickerButton.new()
	_color_picker_btn.custom_minimum_size = Vector2(0, 28)
	_color_picker_btn.color = CellTypes.decode_color(current_color)
	_color_picker_btn.edit_alpha = false
	_color_picker_btn.color_changed.connect(_on_color_picker_changed)
	vbox.add_child(_color_picker_btn)

	color_group = ButtonGroup.new()
	var fav_grid := GridContainer.new()
	fav_grid.columns = 8
	vbox.add_child(fav_grid)
	for i in range(CellTypes.FAVORITES.size()):
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = color_group
		btn.custom_minimum_size = Vector2(20, 18)
		var ns := StyleBoxFlat.new()
		ns.bg_color = CellTypes.FAVORITES[i]
		ns.border_color = Color(0.3, 0.3, 0.3)
		ns.set_border_width_all(1)
		ns.set_content_margin_all(0)
		btn.add_theme_stylebox_override("normal", ns)
		btn.add_theme_stylebox_override("hover", ns)
		var ps := StyleBoxFlat.new()
		ps.bg_color = CellTypes.FAVORITES[i]
		ps.border_color = Color.WHITE
		ps.set_border_width_all(2)
		ps.set_content_margin_all(0)
		btn.add_theme_stylebox_override("pressed", ps)
		if i == 0:
			btn.button_pressed = true
		fav_grid.add_child(btn)
	color_group.pressed.connect(_on_color_pressed)

	vbox.add_child(HSeparator.new())

	# Floor
	_add_section_label(vbox, "Floor Layer")
	var floor_row := HBoxContainer.new()
	vbox.add_child(floor_row)
	var floor_down := Button.new()
	floor_down.text = "-"
	floor_down.custom_minimum_size = Vector2(28, 0)
	floor_down.pressed.connect(func(): _set_floor(floor_y - 1))
	floor_row.add_child(floor_down)
	floor_slider = HSlider.new()
	floor_slider.min_value = 0
	floor_slider.max_value = grid_y - 1
	floor_slider.step = 1
	floor_slider.value = 0
	floor_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_slider.value_changed.connect(func(v: float): _set_floor(int(v)))
	floor_row.add_child(floor_slider)
	var floor_up := Button.new()
	floor_up.text = "+"
	floor_up.custom_minimum_size = Vector2(28, 0)
	floor_up.pressed.connect(func(): _set_floor(floor_y + 1))
	floor_row.add_child(floor_up)
	floor_value_label = Label.new()
	floor_value_label.text = "Y = 0"
	vbox.add_child(floor_value_label)

	# Ceiling
	_add_section_label(vbox, "Ceiling Layer")
	var ceiling_row := HBoxContainer.new()
	vbox.add_child(ceiling_row)
	var ceiling_down := Button.new()
	ceiling_down.text = "-"
	ceiling_down.custom_minimum_size = Vector2(28, 0)
	ceiling_down.pressed.connect(func(): _set_ceiling(ceiling_y - 1))
	ceiling_row.add_child(ceiling_down)
	ceiling_slider = HSlider.new()
	ceiling_slider.min_value = -1
	ceiling_slider.max_value = grid_y - 1
	ceiling_slider.step = 1
	ceiling_slider.value = -1
	ceiling_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ceiling_slider.value_changed.connect(func(v: float): _set_ceiling(int(v)))
	ceiling_row.add_child(ceiling_slider)
	var ceiling_up := Button.new()
	ceiling_up.text = "+"
	ceiling_up.custom_minimum_size = Vector2(28, 0)
	ceiling_up.pressed.connect(func(): _set_ceiling(ceiling_y + 1))
	ceiling_row.add_child(ceiling_up)
	ceiling_value_label = Label.new()
	ceiling_value_label.text = "Off"
	vbox.add_child(ceiling_value_label)
	ceiling_lock_btn = CheckButton.new()
	ceiling_lock_btn.text = "Lock to Floor"
	ceiling_lock_btn.toggled.connect(func(on: bool): _set_ceiling_lock(on))
	vbox.add_child(ceiling_lock_btn)

	vbox.add_child(HSeparator.new())

	# File info
	file_label = Label.new()
	file_label.text = "File: (unsaved)"
	file_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(file_label)

	coord_label = Label.new()
	coord_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(coord_label)

	dims_label = Label.new()
	dims_label.add_theme_font_size_override("font_size", 11)
	dims_label.add_theme_color_override("font_color", Color(1, 1, 0.5))
	vbox.add_child(dims_label)

	vbox.add_child(HSeparator.new())

	# Preview lighting controls (hidden until preview mode enabled)
	preview_light_container = VBoxContainer.new()
	preview_light_container.add_theme_constant_override("separation", 2)
	preview_light_container.visible = false
	vbox.add_child(preview_light_container)

	var light_title := Label.new()
	light_title.text = "Light Direction"
	light_title.add_theme_font_size_override("font_size", 12)
	light_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	preview_light_container.add_child(light_title)

	var yaw_label := Label.new()
	yaw_label.text = "Rotation"
	yaw_label.add_theme_font_size_override("font_size", 11)
	preview_light_container.add_child(yaw_label)
	var yaw_slider := HSlider.new()
	yaw_slider.name = "YawSlider"
	yaw_slider.min_value = -180
	yaw_slider.max_value = 180
	yaw_slider.step = 5
	yaw_slider.value = -45
	yaw_slider.value_changed.connect(func(_v: float): _update_preview_light())
	preview_light_container.add_child(yaw_slider)

	var pitch_label := Label.new()
	pitch_label.text = "Height"
	pitch_label.add_theme_font_size_override("font_size", 11)
	preview_light_container.add_child(pitch_label)
	var pitch_slider := HSlider.new()
	pitch_slider.name = "PitchSlider"
	pitch_slider.min_value = -80
	pitch_slider.max_value = -5
	pitch_slider.step = 5
	pitch_slider.value = -45
	pitch_slider.value_changed.connect(func(_v: float): _update_preview_light())
	preview_light_container.add_child(pitch_slider)

	# Help at bottom of screen
	var help := Label.new()
	help.position = Vector2(PANEL_WIDTH + 10, 1050)
	help.add_theme_font_size_override("font_size", 11)
	help.text = "Up/Down: Floor | Shift+Up/Down: Ceiling | Tab: Toggle Type | Q/E: Rotate Prism | Ctrl+Z: Undo | Esc: Cancel"
	ui_layer.add_child(help)

	# View cube
	view_cube = preload("res://scripts/view_cube.gd").new()
	view_cube.position = Vector2(1920 - 110, MENU_HEIGHT + 10)
	view_cube.size = Vector2(100, 100)
	view_cube.view_changed.connect(_on_view_cube_changed)
	ui_layer.add_child(view_cube)

	# File dialogs
	save_dialog = FileDialog.new()
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_RESOURCES
	save_dialog.add_filter("*.res ; Voxel Definition (compressed)")
	save_dialog.add_filter("*.tres ; Voxel Definition (text)")
	save_dialog.title = "Save Definition"
	save_dialog.size = Vector2i(700, 500)
	save_dialog.file_selected.connect(_on_save_file_selected)
	add_child(save_dialog)

	open_dialog = FileDialog.new()
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_RESOURCES
	open_dialog.add_filter("*.res, *.tres ; Voxel Definition")
	open_dialog.title = "Open Definition"
	open_dialog.size = Vector2i(700, 500)
	open_dialog.file_selected.connect(_on_open_file_selected)
	add_child(open_dialog)

	import_dialog = FileDialog.new()
	import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_dialog.add_filter("*.png ; PNG Image")
	import_dialog.title = "Import PNG as Face"
	import_dialog.size = Vector2i(700, 500)
	import_dialog.file_selected.connect(_on_import_file_selected)
	add_child(import_dialog)

	import_block_dialog = FileDialog.new()
	import_block_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_block_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_block_dialog.add_filter("*.png ; PNG Image")
	import_block_dialog.title = "Import Block Texture"
	import_block_dialog.size = Vector2i(700, 500)
	import_block_dialog.file_selected.connect(_on_block_texture_selected)
	add_child(import_block_dialog)

	export_dialog = FileDialog.new()
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.add_filter("*.obj ; Wavefront OBJ")
	export_dialog.title = "Export OBJ"
	export_dialog.size = Vector2i(700, 500)
	export_dialog.file_selected.connect(_on_export_obj_selected)
	add_child(export_dialog)

	import_front_dialog = FileDialog.new()
	import_front_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_front_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_front_dialog.add_filter("*.png ; PNG Image")
	import_front_dialog.title = "Step 1: Select Front Sprite"
	import_front_dialog.size = Vector2i(700, 500)
	import_front_dialog.file_selected.connect(_on_front_sprite_selected)
	add_child(import_front_dialog)

	import_side_dialog = FileDialog.new()
	import_side_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_side_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_side_dialog.add_filter("*.png ; PNG Image")
	import_side_dialog.title = "Step 2: Select Side Sprite"
	import_side_dialog.size = Vector2i(700, 500)
	import_side_dialog.file_selected.connect(_on_side_sprite_selected)
	add_child(import_side_dialog)

	_setup_sprite_wizard()
	_setup_block_tex_wizard()
	_setup_smooth_dialog()

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Unsaved Changes"
	confirm_dialog.dialog_text = "You have unsaved changes. Do you want to save first?"
	confirm_dialog.ok_button_text = "Discard"
	confirm_dialog.size = Vector2i(360, 120)
	confirm_dialog.add_button("Save", true, "save_first")
	confirm_dialog.confirmed.connect(_on_confirm_discard)
	confirm_dialog.custom_action.connect(_on_confirm_save_first)
	add_child(confirm_dialog)

func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	parent.add_child(lbl)

func _add_button_row(parent: VBoxContainer, names: Array, group: ButtonGroup) -> Array[Button]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var buttons: Array[Button] = []
	for n in names:
		var btn := Button.new()
		btn.text = n
		btn.toggle_mode = true
		btn.button_group = group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 28)
		row.add_child(btn)
		buttons.append(btn)
	return buttons

# ─── Panel Callbacks ───

func _on_view_cube_changed(yaw: float, pitch: float) -> void:
	if camera:
		camera.yaw = yaw
		camera.pitch = pitch
		camera._update_transform()

func _on_edit_menu(id: int) -> void:
	match id:
		0: _undo()

func _on_view_menu(id: int) -> void:
	match id:
		0: _toggle_flat_color_mode()
		1: _toggle_preview_mode()
		2: _toggle_axis_overlay()
		3: _toggle_mirror_x()
		4: _toggle_mirror_z()

func _toggle_flat_color_mode() -> void:
	_flat_color_mode = not _flat_color_mode
	view_menu.set_item_checked(0, _flat_color_mode)
	_invalidate_materials()
	_rebuild_mesh()

func _toggle_preview_mode() -> void:
	_preview_mode = not _preview_mode
	view_menu.set_item_checked(1, _preview_mode)
	preview_light_container.visible = _preview_mode
	if _preview_mode:
		if not _preview_light:
			_preview_light = DirectionalLight3D.new()
			_preview_light.shadow_enabled = true
			add_child(_preview_light)
		_preview_light.visible = true
		_update_preview_light()
	else:
		if _preview_light:
			_preview_light.visible = false
	_invalidate_materials()
	_rebuild_mesh()

func _update_preview_light() -> void:
	if not _preview_light:
		return
	var yaw_slider := preview_light_container.get_node("YawSlider") as HSlider
	var pitch_slider := preview_light_container.get_node("PitchSlider") as HSlider
	var yaw := deg_to_rad(yaw_slider.value) if yaw_slider else deg_to_rad(-45.0)
	var pitch := deg_to_rad(pitch_slider.value) if pitch_slider else deg_to_rad(-45.0)
	var center := Vector3(grid_x, grid_y, grid_z) * CELL_SIZE * 0.5
	_preview_light.position = center
	_preview_light.rotation = Vector3(pitch, yaw, 0)

func _toggle_axis_overlay() -> void:
	_show_axis_overlay = not _show_axis_overlay
	view_menu.set_item_checked(view_menu.get_item_index(2), _show_axis_overlay)
	_update_axis_overlay_visibility()

func _toggle_mirror_x() -> void:
	_mirror_x = not _mirror_x
	view_menu.set_item_checked(view_menu.get_item_index(3), _mirror_x)
	_update_axis_overlay_visibility()
	_update_raycast()

func _toggle_mirror_z() -> void:
	_mirror_z = not _mirror_z
	view_menu.set_item_checked(view_menu.get_item_index(4), _mirror_z)
	_update_axis_overlay_visibility()
	_update_raycast()

func _update_axis_overlay_visibility() -> void:
	axis_overlay_x.visible = _show_axis_overlay or _mirror_x
	axis_overlay_z.visible = _show_axis_overlay or _mirror_z

func _rebuild_axis_overlay() -> void:
	var wy := grid_y * CELL_SIZE
	var wx := grid_x * CELL_SIZE
	var wz := grid_z * CELL_SIZE
	var cx := grid_x / 2.0 * CELL_SIZE
	var cz := grid_z / 2.0 * CELL_SIZE

	var im_x := ImmediateMesh.new()
	im_x.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im_x.surface_add_vertex(Vector3(cx, 0, 0))
	im_x.surface_add_vertex(Vector3(cx, wy, 0))
	im_x.surface_add_vertex(Vector3(cx, wy, wz))
	im_x.surface_add_vertex(Vector3(cx, 0, 0))
	im_x.surface_add_vertex(Vector3(cx, wy, wz))
	im_x.surface_add_vertex(Vector3(cx, 0, wz))
	im_x.surface_end()
	axis_overlay_x.mesh = im_x

	var im_z := ImmediateMesh.new()
	im_z.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im_z.surface_add_vertex(Vector3(0, 0, cz))
	im_z.surface_add_vertex(Vector3(0, wy, cz))
	im_z.surface_add_vertex(Vector3(wx, wy, cz))
	im_z.surface_add_vertex(Vector3(0, 0, cz))
	im_z.surface_add_vertex(Vector3(wx, wy, cz))
	im_z.surface_add_vertex(Vector3(wx, 0, cz))
	im_z.surface_end()
	axis_overlay_z.mesh = im_z

func _on_shape_btn_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_center_draw = (_center_draw + 1) % 3
		var suffix := ""
		match _center_draw:
			1: suffix = " (C)"
			2: suffix = " (J)"
		_rect_btn.text = "Rect" + suffix
		_oval_btn.text = "Oval" + suffix
		center_joint_marker.visible = false

func _compute_center_draw(center: Vector3i, end_cell: Vector3i, constrain: bool) -> Array:
	if _center_draw == 0 or not current_tool in [ToolType.RECT, ToolType.OVAL]:
		return [center, end_cell, constrain]

	if _center_draw == 1:
		var dx := absi(end_cell.x - center.x)
		var dz := absi(end_cell.z - center.z)
		if constrain:
			var r := maxi(dx, dz)
			dx = r
			dz = r
		var start := Vector3i(center.x - dx, floor_y, center.z - dz)
		var end := Vector3i(center.x + dx, floor_y, center.z + dz)
		return [start, end, false]

	# Joint center mode (_center_draw == 2)
	var jx := _joint_center.x
	var jz := _joint_center.y
	var dx: int
	var dz: int
	if end_cell.x >= jx:
		dx = end_cell.x - jx + 1
	else:
		dx = jx - end_cell.x
	if end_cell.z >= jz:
		dz = end_cell.z - jz + 1
	else:
		dz = jz - end_cell.z
	if constrain:
		var r := maxi(dx, dz)
		dx = r
		dz = r
	var start := Vector3i(jx - dx, floor_y, jz - dz)
	var end := Vector3i(jx + dx - 1, floor_y, jz + dz - 1)
	return [start, end, false]

func _compute_joint_center(cell: Vector3i) -> Vector2i:
	var local_x := _floor_hit_pos.x / CELL_SIZE - cell.x
	var local_z := _floor_hit_pos.z / CELL_SIZE - cell.z
	var jx := cell.x if local_x < 0.5 else cell.x + 1
	var jz := cell.z if local_z < 0.5 else cell.z + 1
	return Vector2i(jx, jz)

func _update_joint_marker() -> void:
	if _center_draw != 2 or not current_tool in [ToolType.RECT, ToolType.OVAL]:
		center_joint_marker.visible = false
		if not box_active:
			_joint_center = Vector2i(-1, -1)
		return

	if box_active:
		center_joint_marker.visible = false
		return

	# Match the shape-draw reference: fall back to the geometry cell so the
	# marker still shows when hovering voxels below others (place_cell invalid).
	var shape_ref := place_cell if _in_bounds(place_cell) else target_cell
	if not _in_bounds(shape_ref):
		center_joint_marker.visible = false
		return
	var cell := Vector3i(shape_ref.x, floor_y, shape_ref.z)
	if not _in_bounds(cell):
		center_joint_marker.visible = false
		return

	_joint_center = _compute_joint_center(cell)
	var jx_world := _joint_center.x * CELL_SIZE
	var jz_world := _joint_center.y * CELL_SIZE
	var jy_world := float(floor_y) * CELL_SIZE

	var im := ImmediateMesh.new()
	var arm := CELL_SIZE * 0.4
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(Vector3(jx_world - arm, jy_world + 0.001, jz_world))
	im.surface_add_vertex(Vector3(jx_world + arm, jy_world + 0.001, jz_world))
	im.surface_add_vertex(Vector3(jx_world, jy_world + 0.001, jz_world - arm))
	im.surface_add_vertex(Vector3(jx_world, jy_world + 0.001, jz_world + arm))
	im.surface_add_vertex(Vector3(jx_world, jy_world - arm, jz_world))
	im.surface_add_vertex(Vector3(jx_world, jy_world + arm, jz_world))
	im.surface_end()
	center_joint_marker.mesh = im
	center_joint_marker.visible = not box_active

func _mirror_pos_x(pos: Vector3i) -> Vector3i:
	return Vector3i(grid_x - 1 - pos.x, pos.y, pos.z)

func _mirror_pos_z(pos: Vector3i) -> Vector3i:
	return Vector3i(pos.x, pos.y, grid_z - 1 - pos.z)

func _mirror_orientation_x(orientation: int) -> int:
	var axis: int = orientation / 4
	var corner: int = orientation % 4
	if axis == 1:
		return orientation
	var new_corner: int
	match corner:
		0: new_corner = 1
		1: new_corner = 0
		2: new_corner = 3
		_: new_corner = 2
	return axis * 4 + new_corner

func _mirror_orientation_z(orientation: int) -> int:
	var axis: int = orientation / 4
	var corner: int = orientation % 4
	if axis == 2:
		return orientation
	var new_corner: int
	match corner:
		0: new_corner = 3
		1: new_corner = 2
		2: new_corner = 1
		_: new_corner = 0
	return axis * 4 + new_corner

func _place_with_mirror(pos: Vector3i, cell_type: int, orientation: int, color: int) -> void:
	if _in_bounds(pos):
		cells[pos.x][pos.y][pos.z] = CellTypes.make_cell(cell_type, orientation, color)
	if _mirror_x:
		var mx := _mirror_pos_x(pos)
		if _in_bounds(mx):
			var mo := _mirror_orientation_x(orientation) if cell_type == CellTypes.Type.PRISM else orientation
			cells[mx.x][mx.y][mx.z] = CellTypes.make_cell(cell_type, mo, color)
	if _mirror_z:
		var mz := _mirror_pos_z(pos)
		if _in_bounds(mz):
			var mo := _mirror_orientation_z(orientation) if cell_type == CellTypes.Type.PRISM else orientation
			cells[mz.x][mz.y][mz.z] = CellTypes.make_cell(cell_type, mo, color)
	if _mirror_x and _mirror_z:
		var mxz := _mirror_pos_x(_mirror_pos_z(pos))
		if _in_bounds(mxz):
			var mo := orientation
			if cell_type == CellTypes.Type.PRISM:
				mo = _mirror_orientation_x(_mirror_orientation_z(orientation))
			cells[mxz.x][mxz.y][mxz.z] = CellTypes.make_cell(cell_type, mo, color)

func _erase_with_mirror(pos: Vector3i) -> void:
	if _in_bounds(pos):
		cells[pos.x][pos.y][pos.z] = CellTypes.empty_cell()
	if _mirror_x:
		var mx := _mirror_pos_x(pos)
		if _in_bounds(mx):
			cells[mx.x][mx.y][mx.z] = CellTypes.empty_cell()
	if _mirror_z:
		var mz := _mirror_pos_z(pos)
		if _in_bounds(mz):
			cells[mz.x][mz.y][mz.z] = CellTypes.empty_cell()
	if _mirror_x and _mirror_z:
		var mxz := _mirror_pos_x(_mirror_pos_z(pos))
		if _in_bounds(mxz):
			cells[mxz.x][mxz.y][mxz.z] = CellTypes.empty_cell()

func _bucket_fill(start: Vector3i) -> void:
	var start_cell: Array = cells[start.x][start.y][start.z]
	var match_color: int = start_cell[2]
	if match_color == current_color:
		return
	_push_undo()
	var queue: Array[Vector3i] = [start]
	var visited := {}
	visited[start] = true
	while not queue.is_empty():
		var pos: Vector3i = queue.pop_front()
		var cell: Array = cells[pos.x][pos.y][pos.z]
		for fi in range(2, 8):
			if cell[fi] == match_color:
				cell[fi] = current_color
		for d in [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
			var np: Vector3i = pos + d
			if not _in_bounds(np) or visited.has(np):
				continue
			var nc: Array = cells[np.x][np.y][np.z]
			if nc[0] == CellTypes.Type.EMPTY:
				continue
			if nc[2] == match_color:
				visited[np] = true
				queue.append(np)
	_mark_dirty()
	_rebuild_mesh()

func _eyedrop_color(target: Vector3i) -> void:
	var cell: Array = cells[target.x][target.y][target.z]
	var picked_color: int
	if cell[0] == CellTypes.Type.PRISM:
		picked_color = cell[2]
	else:
		var face_normal := _hit_normal
		if face_normal == Vector3i.ZERO:
			picked_color = cell[2]
		else:
			var fi := CellTypes.face_index_from_normal(face_normal)
			picked_color = cell[fi]
	current_color = picked_color
	_color_picker_btn.color = CellTypes.decode_color(picked_color)

func _draw_mirror_cursors(cursor_pos: Vector3i) -> void:
	if not _mirror_x and not _mirror_z:
		mirror_cursor_instance.visible = false
		return

	var positions: Array[Vector3i] = []
	if _mirror_x:
		positions.append(_mirror_pos_x(cursor_pos))
	if _mirror_z:
		positions.append(_mirror_pos_z(cursor_pos))
	if _mirror_x and _mirror_z:
		positions.append(_mirror_pos_x(_mirror_pos_z(cursor_pos)))

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	for mpos in positions:
		if not _in_bounds(mpos):
			continue
		var margin := CELL_SIZE * 0.02
		var pos := Vector3(mpos) * CELL_SIZE - Vector3.ONE * margin
		var size := CELL_SIZE + margin * 2.0
		var c: Array[Vector3] = [
			pos, pos + Vector3(size, 0, 0), pos + Vector3(size, 0, size), pos + Vector3(0, 0, size),
			pos + Vector3(0, size, 0), pos + Vector3(size, size, 0),
			pos + Vector3(size, size, size), pos + Vector3(0, size, size),
		]
		for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
			im.surface_add_vertex(c[e[0]])
			im.surface_add_vertex(c[e[1]])

	im.surface_end()
	mirror_cursor_instance.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 1, 1, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mirror_cursor_instance.material_override = mat
	mirror_cursor_instance.visible = true

func _on_file_menu(id: int) -> void:
	match id:
		0: _new()
		1: _open()
		2: _save()
		3: _import_png()
		4: _import_character_sprites()
		5: _import_block_texture()
		6: _export_obj()
		7: _save_as()

func _on_mode_pressed(btn: BaseButton) -> void:
	var target_mode := EditMode.BLOCK if btn.text == "Block" else EditMode.CHARACTER
	if target_mode == edit_mode:
		return
	if _unsaved_changes:
		_pending_action = "mode_block" if target_mode == EditMode.BLOCK else "mode_character"
		var buttons := mode_group.get_buttons()
		buttons[0].button_pressed = edit_mode == EditMode.BLOCK
		buttons[1].button_pressed = edit_mode == EditMode.CHARACTER
		confirm_dialog.popup_centered()
		return
	_do_set_edit_mode(target_mode)

func _on_tool_pressed(btn: BaseButton) -> void:
	# Rect/Oval buttons append a center-draw suffix (" (C)"/" (J)") to their
	# text, so match on the base name to keep the tool selection working.
	var tool_name: String = btn.text
	if tool_name.ends_with(" (C)") or tool_name.ends_with(" (J)"):
		tool_name = tool_name.substr(0, tool_name.length() - 4)
	match tool_name:
		"Pencil": current_tool = ToolType.PENCIL
		"Paint": current_tool = ToolType.PAINT
		"Bucket": current_tool = ToolType.BUCKET
		"Box Fill": current_tool = ToolType.BOX
		"Eraser": current_tool = ToolType.ERASER
		"Box Erase": current_tool = ToolType.BOX_ERASE
		"Eyedrop": current_tool = ToolType.EYEDROP
		"Extrude": current_tool = ToolType.EXTRUDE
		"Line": current_tool = ToolType.LINE
		"Rect": current_tool = ToolType.RECT
		"Oval": current_tool = ToolType.OVAL
		"Smooth": current_tool = ToolType.SMOOTH_EDGE
	_cancel_box()
	_cancel_extrude()
	_cancel_smooth()

func _on_type_pressed(btn: BaseButton) -> void:
	if btn.text == "Solid":
		current_type = CellTypes.Type.SOLID
		orient_container.visible = false
	else:
		current_type = CellTypes.Type.PRISM
		orient_container.visible = true
	_update_raycast()

func _on_color_pressed(btn: BaseButton) -> void:
	var buttons := color_group.get_buttons()
	for i in range(buttons.size()):
		if buttons[i] == btn:
			current_color = CellTypes.encode_rgb565(CellTypes.FAVORITES[i])
			break

func _on_color_picker_changed(color: Color) -> void:
	current_color = CellTypes.encode_rgb565(color)

func _cycle_orientation(delta: int) -> void:
	current_orientation = (current_orientation + delta) % 12
	if current_orientation < 0:
		current_orientation += 12
	orient_label.text = CellTypes.get_orientation_name(current_orientation)
	_update_raycast()

func _set_floor(y: int) -> void:
	floor_y = clampi(y, 0, grid_y - 1)
	floor_slider.set_value_no_signal(floor_y)
	floor_value_label.text = "Y = %d" % floor_y
	if _ceiling_locked:
		var old_ceiling := ceiling_y
		ceiling_y = floor_y
		ceiling_slider.set_value_no_signal(ceiling_y)
		ceiling_value_label.text = "Y = %d" % ceiling_y
		# The mesh bakes top faces for the ceiling layer, so moving the locked
		# ceiling must rebuild the old and new ceiling layers (otherwise the
		# revealed voxels render as hollow "phantoms").
		if old_ceiling != ceiling_y:
			_mark_layer_chunks_dirty(old_ceiling)
			_mark_layer_chunks_dirty(ceiling_y)
		_update_ceiling_uniforms()
	_rebuild_grid()

func _set_ceiling(y: int) -> void:
	var old_ceiling := ceiling_y
	ceiling_y = clampi(y, -1, grid_y - 1)
	ceiling_slider.set_value_no_signal(ceiling_y)
	# The mesh bakes top faces for the ceiling layer, so the old and new
	# ceiling layers must be rebuilt when the ceiling moves.
	if old_ceiling != ceiling_y:
		_mark_layer_chunks_dirty(old_ceiling)
		_mark_layer_chunks_dirty(ceiling_y)
	if ceiling_y < 0:
		ceiling_value_label.text = "Off"
	else:
		ceiling_value_label.text = "Y = %d" % ceiling_y
	if _ceiling_locked and ceiling_y >= 0:
		floor_y = ceiling_y
		floor_slider.set_value_no_signal(floor_y)
		floor_value_label.text = "Y = %d" % floor_y
	_update_ceiling_uniforms()
	_rebuild_grid()

func _set_ceiling_lock(on: bool) -> void:
	_ceiling_locked = on
	if on and ceiling_y < 0:
		_set_ceiling(floor_y)
	elif on and ceiling_y != floor_y:
		_set_floor(ceiling_y)

func _set_edit_mode(mode: int) -> void:
	if mode == edit_mode:
		return
	if _unsaved_changes:
		_pending_action = "mode_block" if mode == EditMode.BLOCK else "mode_character"
		confirm_dialog.popup_centered()
		return
	_do_set_edit_mode(mode)

func _do_set_edit_mode(mode: int) -> void:
	edit_mode = mode
	_undo_stack.clear()
	if edit_mode == EditMode.BLOCK:
		grid_x = 32; grid_y = 32; grid_z = 32
		CELL_SIZE = 1.0 / BLOCK_RES
	else:
		grid_x = 64; grid_y = 128; grid_z = 64
		CELL_SIZE = 1.0 / CHAR_RES
	current_file_path = ""
	_unsaved_changes = false
	place_cell = Vector3i(-1, -1, -1)
	target_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	_cancel_box()
	floor_y = 0
	floor_slider.max_value = grid_y - 1
	floor_slider.set_value_no_signal(0)
	floor_value_label.text = "Y = 0"
	ceiling_y = -1
	ceiling_slider.max_value = grid_y - 1
	ceiling_slider.set_value_no_signal(-1)
	ceiling_value_label.text = "Off"
	_ceiling_locked = false
	ceiling_lock_btn.set_pressed_no_signal(false)
	_init_cells()
	_rebuild_mesh()
	_rebuild_grid()
	_rebuild_axis_overlay()
	_center_camera()
	_update_file_label()

# ─── Input ───

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_Z: _undo(); get_viewport().set_input_as_handled(); return
				KEY_S:
					if event.shift_pressed:
						_save_as()
					else:
						_save()
					get_viewport().set_input_as_handled(); return
				KEY_O: _open(); get_viewport().set_input_as_handled(); return
				KEY_N: _new(); get_viewport().set_input_as_handled(); return
				KEY_I: _import_png(); get_viewport().set_input_as_handled(); return

		match event.keycode:
			KEY_TAB:
				_toggle_type()
				get_viewport().set_input_as_handled()
			KEY_Q: _cycle_orientation(-1)
			KEY_E: _cycle_orientation(1)
			KEY_UP:
				if event.shift_pressed:
					_set_ceiling(ceiling_y + 1)
				else:
					_set_floor(floor_y + 1)
			KEY_DOWN:
				if event.shift_pressed:
					_set_ceiling(ceiling_y - 1)
				else:
					_set_floor(floor_y - 1)
			KEY_ESCAPE:
				_cancel_box()
				_cancel_extrude()
				_cancel_smooth()
			KEY_1: _select_color(0)
			KEY_2: _select_color(1)
			KEY_3: _select_color(2)
			KEY_4: _select_color(3)
			KEY_5: _select_color(4)
			KEY_6: _select_color(5)
			KEY_7: _select_color(6)
			KEY_8: _select_color(7)

	if event is InputEventKey and event.keycode == KEY_SHIFT:
		if box_active and current_tool in [ToolType.LINE, ToolType.RECT, ToolType.OVAL]:
			_update_box_preview()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if current_tool == ToolType.EXTRUDE:
					_extrude_start(event.position)
				elif current_tool == ToolType.SMOOTH_EDGE:
					_smooth_edge_start(event.position)
				else:
					_on_left_click()
			else:
				if extrude_active:
					_extrude_finish()
				elif smooth_active:
					_smooth_edge_finish()
		if not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if camera and not camera.was_orbit_drag():
				_on_right_click()

	if event is InputEventMouseMotion:
		if extrude_active:
			_extrude_update(event.position)
		elif smooth_active:
			_smooth_edge_update(event.position)
		else:
			_update_raycast()

func _toggle_type() -> void:
	if current_type == CellTypes.Type.SOLID:
		current_type = CellTypes.Type.PRISM
		orient_container.visible = true
	else:
		current_type = CellTypes.Type.SOLID
		orient_container.visible = false
	var buttons := type_group.get_buttons()
	buttons[0].button_pressed = current_type == CellTypes.Type.SOLID
	buttons[1].button_pressed = current_type == CellTypes.Type.PRISM
	_update_raycast()

func _select_color(idx: int) -> void:
	if idx < CellTypes.FAVORITES.size():
		current_color = CellTypes.encode_rgb565(CellTypes.FAVORITES[idx])
		var buttons := color_group.get_buttons()
		if idx < buttons.size():
			buttons[idx].button_pressed = true

# ─── Raycasting ───

func _update_raycast() -> void:
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	if mouse_pos.x < PANEL_WIDTH or mouse_pos.y < MENU_HEIGHT:
		return
	if view_cube and Rect2(view_cube.position, view_cube.size).has_point(mouse_pos):
		return

	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	place_cell = Vector3i(-1, -1, -1)
	target_cell = Vector3i(-1, -1, -1)
	_hit_normal = Vector3i.ZERO

	var geo_dist := INF
	var floor_dist := INF

	# Geometry raycast via grid traversal
	var result := _grid_raycast(from, dir)

	if not result.is_empty():
		var hit_pos: Vector3 = result["position"]
		var hit_normal: Vector3 = result["normal"]
		geo_dist = from.distance_to(hit_pos)
		target_cell = result["cell"]
		_hit_normal = Vector3i(hit_normal)
		var adj := target_cell + Vector3i(hit_normal)
		if _in_bounds(adj) and cells[adj.x][adj.y][adj.z][0] == CellTypes.Type.EMPTY:
			place_cell = adj

	# Floor plane raycast
	var floor_world_y := floor_y * CELL_SIZE
	if abs(dir.y) > 0.0001:
		var t := (floor_world_y - from.y) / dir.y
		if t > 0:
			floor_dist = t * dir.length()
			var hit := from + dir * t
			_floor_hit_pos = hit
			var fc := _world_to_cell(hit)
			fc.y = floor_y
			if _in_bounds(fc):
				if floor_dist < geo_dist and cells[fc.x][fc.y][fc.z][0] == CellTypes.Type.EMPTY:
					place_cell = fc
				elif geo_dist == INF:
					place_cell = fc

	# Discard geometry hit outside floor/ceiling bounds and fall back to floor plane
	var geo_oob := false
	if target_cell.y >= 0 and target_cell.y < floor_y:
		geo_oob = true
	if ceiling_y >= 0 and target_cell.y >= 0 and target_cell.y > ceiling_y:
		geo_oob = true
	if geo_oob:
		target_cell = Vector3i(-1, -1, -1)
		place_cell = Vector3i(-1, -1, -1)
		if floor_dist < INF:
			var fc := _world_to_cell(_floor_hit_pos)
			fc.y = floor_y
			if _in_bounds(fc):
				place_cell = fc
	if place_cell.y >= 0 and place_cell.y < floor_y:
		place_cell = Vector3i(-1, -1, -1)
	if ceiling_y >= 0 and place_cell.y >= 0 and place_cell.y > ceiling_y:
		place_cell = Vector3i(-1, -1, -1)
	if not _in_bounds(place_cell) and floor_dist < INF:
		var fc2 := _world_to_cell(_floor_hit_pos)
		fc2.y = floor_y
		if _in_bounds(fc2) and cells[fc2.x][fc2.y][fc2.z][0] == CellTypes.Type.EMPTY:
			place_cell = fc2

	# Update cursor display
	var cursor_pos: Vector3i
	if current_tool == ToolType.ERASER or current_tool == ToolType.BOX_ERASE or current_tool == ToolType.EXTRUDE or current_tool == ToolType.SMOOTH_EDGE or current_tool == ToolType.PAINT:
		cursor_pos = target_cell
	else:
		cursor_pos = place_cell

	if _in_bounds(cursor_pos):
		_draw_cursor(cursor_pos)
		cursor_mesh_instance.visible = true
		coord_label.text = "Cell: (%d, %d, %d)" % [cursor_pos.x, cursor_pos.y, cursor_pos.z]
		_draw_mirror_cursors(cursor_pos)
	else:
		cursor_mesh_instance.visible = false
		mirror_cursor_instance.visible = false
		coord_label.text = ""

	_update_joint_marker()
	_update_box_preview()

func _world_to_cell(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(world_pos.x / CELL_SIZE)),
		int(floor(world_pos.y / CELL_SIZE)),
		int(floor(world_pos.z / CELL_SIZE))
	)

func _in_bounds(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < grid_x and pos.y >= 0 and pos.y < grid_y and pos.z >= 0 and pos.z < grid_z

func _grid_raycast(from: Vector3, dir: Vector3) -> Dictionary:
	var s := CELL_SIZE
	var grid_end := Vector3(grid_x * s, grid_y * s, grid_z * s)
	var t_near := 0.0
	var t_far := 100.0
	for ax in range(3):
		if abs(dir[ax]) < 1e-8:
			if from[ax] < 0.0 or from[ax] > grid_end[ax]:
				return {}
		else:
			var t0 := -from[ax] / dir[ax]
			var t1 := (grid_end[ax] - from[ax]) / dir[ax]
			if t0 > t1:
				var tmp := t0; t0 = t1; t1 = tmp
			t_near = maxf(t_near, t0)
			t_far = minf(t_far, t1)
			if t_near > t_far:
				return {}

	var entry := from + dir * maxf(t_near - 1e-4, 0.0)
	var cx := int(floor(entry.x / s))
	var cy := int(floor(entry.y / s))
	var cz := int(floor(entry.z / s))
	cx = clampi(cx, 0, grid_x - 1)
	cy = clampi(cy, 0, grid_y - 1)
	cz = clampi(cz, 0, grid_z - 1)

	var y_min := floor_y
	var y_max := ceiling_y if ceiling_y >= 0 else grid_y - 1

	var step_x := 1 if dir.x >= 0 else -1
	var step_y := 1 if dir.y >= 0 else -1
	var step_z := 1 if dir.z >= 0 else -1

	var t_max_x: float = ((cx + (1 if step_x > 0 else 0)) * s - from.x) / dir.x if abs(dir.x) > 1e-8 else INF
	var t_max_y: float = ((cy + (1 if step_y > 0 else 0)) * s - from.y) / dir.y if abs(dir.y) > 1e-8 else INF
	var t_max_z: float = ((cz + (1 if step_z > 0 else 0)) * s - from.z) / dir.z if abs(dir.z) > 1e-8 else INF

	var t_delta_x: float = abs(s / dir.x) if abs(dir.x) > 1e-8 else INF
	var t_delta_y: float = abs(s / dir.y) if abs(dir.y) > 1e-8 else INF
	var t_delta_z: float = abs(s / dir.z) if abs(dir.z) > 1e-8 else INF

	var normal := Vector3i.ZERO
	var max_steps := grid_x + grid_y + grid_z
	for _i in range(max_steps):
		if cy < y_min or cy > y_max:
			if (step_y > 0 and cy > y_max) or (step_y < 0 and cy < y_min):
				break
			if t_max_y < t_max_x and t_max_y < t_max_z:
				cy += step_y; t_max_y += t_delta_y; normal = Vector3i(0, -step_y, 0)
				continue
			elif t_max_x < t_max_z:
				cx += step_x; t_max_x += t_delta_x; normal = Vector3i(-step_x, 0, 0)
				continue
			else:
				cz += step_z; t_max_z += t_delta_z; normal = Vector3i(0, 0, -step_z)
				continue
		if cx >= 0 and cx < grid_x and cz >= 0 and cz < grid_z:
			if cells[cx][cy][cz][0] != CellTypes.Type.EMPTY:
				var t_hit := maxf(t_near, 0.0)
				if normal != Vector3i.ZERO:
					if t_max_x - t_delta_x > t_max_y - t_delta_y:
						if t_max_x - t_delta_x > t_max_z - t_delta_z:
							t_hit = t_max_x - t_delta_x
						else:
							t_hit = t_max_z - t_delta_z
					else:
						if t_max_y - t_delta_y > t_max_z - t_delta_z:
							t_hit = t_max_y - t_delta_y
						else:
							t_hit = t_max_z - t_delta_z
				var hit_pos := from + dir * t_hit
				return {"position": hit_pos, "normal": Vector3(normal), "cell": Vector3i(cx, cy, cz)}

		if t_max_x < t_max_y:
			if t_max_x < t_max_z:
				cx += step_x; t_max_x += t_delta_x; normal = Vector3i(-step_x, 0, 0)
			else:
				cz += step_z; t_max_z += t_delta_z; normal = Vector3i(0, 0, -step_z)
		else:
			if t_max_y < t_max_z:
				cy += step_y; t_max_y += t_delta_y; normal = Vector3i(0, -step_y, 0)
			else:
				cz += step_z; t_max_z += t_delta_z; normal = Vector3i(0, 0, -step_z)

	return {}

# ─── Click Actions ───

func _on_left_click() -> void:
	match current_tool:
		ToolType.PENCIL:
			if _in_bounds(place_cell):
				_push_undo()
				_place_with_mirror(place_cell, current_type, current_orientation, current_color)
				_mark_dirty()
				_mark_mirror_chunks_dirty(place_cell)
		ToolType.BOX:
			if not box_active:
				if _in_bounds(place_cell):
					box_start = place_cell
					box_active = true
			else:
				if _in_bounds(place_cell):
					_fill_region(box_start, place_cell, current_type, current_orientation, current_color)
				_cancel_box()
		ToolType.ERASER:
			if _in_bounds(target_cell) and cells[target_cell.x][target_cell.y][target_cell.z][0] != CellTypes.Type.EMPTY:
				_push_undo()
				_erase_with_mirror(target_cell)
				_mark_dirty()
				_mark_mirror_chunks_dirty(target_cell)
		ToolType.PAINT:
			if _in_bounds(target_cell) and cells[target_cell.x][target_cell.y][target_cell.z][0] != CellTypes.Type.EMPTY:
				var face_normal := _hit_normal
				if face_normal == Vector3i.ZERO:
					return
				var fi := CellTypes.face_index_from_normal(face_normal)
				_push_undo()
				cells[target_cell.x][target_cell.y][target_cell.z][fi] = current_color
				if _mirror_x:
					var mx := _mirror_pos_x(target_cell)
					if _in_bounds(mx):
						cells[mx.x][mx.y][mx.z][fi] = current_color
				if _mirror_z:
					var mz := _mirror_pos_z(target_cell)
					if _in_bounds(mz):
						cells[mz.x][mz.y][mz.z][fi] = current_color
				if _mirror_x and _mirror_z:
					var mxz := _mirror_pos_x(_mirror_pos_z(target_cell))
					if _in_bounds(mxz):
						cells[mxz.x][mxz.y][mxz.z][fi] = current_color
				_mark_dirty()
				_mark_mirror_chunks_dirty(target_cell)
		ToolType.BUCKET:
			if _in_bounds(target_cell) and cells[target_cell.x][target_cell.y][target_cell.z][0] != CellTypes.Type.EMPTY:
				_bucket_fill(target_cell)
		ToolType.EYEDROP:
			if _in_bounds(target_cell) and cells[target_cell.x][target_cell.y][target_cell.z][0] != CellTypes.Type.EMPTY:
				_eyedrop_color(target_cell)
		ToolType.BOX_ERASE:
			if not box_active:
				if _in_bounds(target_cell):
					box_start = target_cell
					box_active = true
			else:
				if _in_bounds(target_cell):
					_clear_region(box_start, target_cell)
				_cancel_box()
		ToolType.LINE, ToolType.RECT, ToolType.OVAL:
			var shape_ref := place_cell if _in_bounds(place_cell) else target_cell
			var floor_cell := Vector3i(shape_ref.x, floor_y, shape_ref.z)
			if not box_active:
				if _in_bounds(floor_cell):
					box_start = floor_cell
					if _center_draw == 2 and current_tool in [ToolType.RECT, ToolType.OVAL]:
						_joint_center = _compute_joint_center(floor_cell)
					box_active = true
			else:
				if _in_bounds(floor_cell):
					_push_undo()
					var constrain := Input.is_key_pressed(KEY_SHIFT)
					var result := _compute_center_draw(box_start, floor_cell, constrain)
					var shape_cells: Array
					match current_tool:
						ToolType.LINE: shape_cells = _get_line_cells(result[0], result[1], result[2])
						ToolType.RECT: shape_cells = _get_rect_cells(result[0], result[1], result[2])
						ToolType.OVAL: shape_cells = _get_oval_cells(result[0], result[1], result[2])
					for cell in shape_cells:
						_place_with_mirror(cell, current_type, current_orientation, current_color)
					_mark_dirty()
					_rebuild_mesh()
				_cancel_box()

func _on_right_click() -> void:
	if box_active:
		_cancel_box()

func _cancel_box() -> void:
	box_active = false
	box_start = Vector3i(-1, -1, -1)
	_joint_center = Vector2i(-1, -1)
	dims_label.text = ""
	if not extrude_active and not smooth_active:
		box_preview_instance.visible = false

func _cancel_extrude() -> void:
	if not extrude_active:
		return
	extrude_active = false
	extrude_cells.clear()
	extrude_depth = 0
	box_preview_instance.visible = false
	var mat := box_preview_instance.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 0, 0.6)

func _cancel_smooth() -> void:
	if not smooth_active:
		return
	smooth_active = false
	smooth_path.clear()
	box_preview_instance.visible = false
	var mat := box_preview_instance.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 0, 0.6)

func _smooth_edge_start(mouse_pos: Vector2) -> void:
	if not camera or mouse_pos.x < PANEL_WIDTH:
		return

	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var result := _grid_raycast(from, dir)

	if result.is_empty():
		return

	var hit_pos: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var cell: Vector3i = result["cell"]

	if not _in_bounds(cell) or cells[cell.x][cell.y][cell.z][0] != CellTypes.Type.SOLID:
		return

	var edge := _detect_edge(hit_pos, hit_normal, cell)
	if edge.is_empty():
		return

	smooth_start = cell
	smooth_normal_a = edge["normal_a"]
	smooth_normal_b = edge["normal_b"]
	smooth_edge_dir = _get_edge_direction(smooth_normal_a, smooth_normal_b)
	smooth_active = true
	smooth_start_mouse = mouse_pos

	var world_center := Vector3(cell) * CELL_SIZE + Vector3(0.5, 0.5, 0.5) * CELL_SIZE
	var screen_a := camera.unproject_position(world_center)
	var screen_b := camera.unproject_position(world_center + Vector3(smooth_edge_dir) * CELL_SIZE)
	var screen_delta := screen_b - screen_a
	if screen_delta.length() < 0.1:
		smooth_edge_screen_dir = Vector2.RIGHT
		smooth_pixels_per_cell = 20.0
	else:
		smooth_edge_screen_dir = screen_delta.normalized()
		smooth_pixels_per_cell = screen_delta.length()

	smooth_path = [cell]
	_draw_smooth_preview()

func _smooth_edge_update(mouse_pos: Vector2) -> void:
	var delta := mouse_pos - smooth_start_mouse
	var projected := delta.dot(smooth_edge_screen_dir)
	var cell_count := int(round(projected / smooth_pixels_per_cell))

	if cell_count >= 0:
		smooth_path = _trace_edge_path(smooth_start, 1, smooth_normal_a, smooth_normal_b, cell_count)
	else:
		smooth_path = _trace_edge_path(smooth_start, -1, smooth_normal_a, smooth_normal_b, -cell_count)
	_draw_smooth_preview()

func _smooth_edge_finish() -> void:
	if smooth_path.is_empty():
		_cancel_smooth()
		return
	smooth_active = false
	smooth_depth_spin.value = 1
	smooth_dialog.popup_centered()

func _detect_edge(hit_pos: Vector3, hit_normal: Vector3, cell: Vector3i) -> Dictionary:
	var n := Vector3i(int(round(hit_normal.x)), int(round(hit_normal.y)), int(round(hit_normal.z)))
	var cell_origin := Vector3(cell) * CELL_SIZE
	var local := hit_pos - cell_origin

	var tangent_axes: Array[Vector3i] = []
	if n.x != 0:
		tangent_axes = [Vector3i(0, 1, 0), Vector3i(0, 0, 1)]
	elif n.y != 0:
		tangent_axes = [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]
	else:
		tangent_axes = [Vector3i(1, 0, 0), Vector3i(0, 1, 0)]

	var best_dist := INF
	var best_edge_normal := Vector3i.ZERO

	for t in tangent_axes:
		var axis_local: float
		if t.x != 0: axis_local = local.x
		elif t.y != 0: axis_local = local.y
		else: axis_local = local.z

		if axis_local < best_dist:
			best_dist = axis_local
			best_edge_normal = -t
		if CELL_SIZE - axis_local < best_dist:
			best_dist = CELL_SIZE - axis_local
			best_edge_normal = t

	var neighbor := cell + best_edge_normal
	var neighbor_solid: bool = _in_bounds(neighbor) and cells[neighbor.x][neighbor.y][neighbor.z][0] != CellTypes.Type.EMPTY
	if neighbor_solid:
		return {}

	return { "normal_a": n, "normal_b": best_edge_normal }

func _get_edge_direction(na: Vector3i, nb: Vector3i) -> Vector3i:
	var cross := Vector3(na).cross(Vector3(nb))
	if abs(cross.x) > 0.5: return Vector3i(1, 0, 0)
	elif abs(cross.y) > 0.5: return Vector3i(0, 1, 0)
	else: return Vector3i(0, 0, 1)

func _is_edge_cell(pos: Vector3i, na: Vector3i, nb: Vector3i) -> bool:
	if not _in_bounds(pos) or cells[pos.x][pos.y][pos.z][0] != CellTypes.Type.SOLID:
		return false
	var na_neighbor := pos + na
	var na_exposed: bool = not _in_bounds(na_neighbor) or cells[na_neighbor.x][na_neighbor.y][na_neighbor.z][0] == CellTypes.Type.EMPTY
	var nb_neighbor := pos + nb
	var nb_exposed: bool = not _in_bounds(nb_neighbor) or cells[nb_neighbor.x][nb_neighbor.y][nb_neighbor.z][0] == CellTypes.Type.EMPTY
	return na_exposed and nb_exposed

func _trace_edge_path(start: Vector3i, direction: int, na: Vector3i, nb: Vector3i, extent: int) -> Array:
	var edge_dir := _get_edge_direction(na, nb)
	var step := edge_dir * direction
	var perp_offsets: Array[Vector3i] = [-na, na, -nb, nb]

	var path: Array = [start]
	var current := start
	for i in range(1, extent + 1):
		var next := current + step
		if _is_edge_cell(next, na, nb):
			path.append(next)
			current = next
			continue
		var found := false
		for offset in perp_offsets:
			var candidate := next + offset
			if _is_edge_cell(candidate, na, nb):
				path.append(candidate)
				current = candidate
				found = true
				break
		if not found:
			break
	return path

func _draw_smooth_preview() -> void:
	if smooth_path.is_empty():
		box_preview_instance.visible = false
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for cell in smooth_path:
		var pos := Vector3(cell) * CELL_SIZE
		var s := CELL_SIZE
		var c: Array[Vector3] = [
			pos, pos + Vector3(s, 0, 0), pos + Vector3(s, 0, s), pos + Vector3(0, 0, s),
			pos + Vector3(0, s, 0), pos + Vector3(s, s, 0),
			pos + Vector3(s, s, s), pos + Vector3(0, s, s),
		]
		for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
			im.surface_add_vertex(c[e[0]])
			im.surface_add_vertex(c[e[1]])
	im.surface_end()
	box_preview_instance.mesh = im
	var mat := box_preview_instance.material_override as StandardMaterial3D
	mat.albedo_color = Color(0, 1, 1, 0.8)
	box_preview_instance.visible = true

func _get_smooth_orientation(na: Vector3i, nb: Vector3i) -> int:
	var cross := Vector3(na).cross(Vector3(nb))
	var axis: int
	if abs(cross.x) > 0.5: axis = 1
	elif abs(cross.y) > 0.5: axis = 0
	else: axis = 2

	var u_val: float
	var v_val: float
	match axis:
		0: u_val = na.x + nb.x; v_val = na.z + nb.z
		1: u_val = na.y + nb.y; v_val = na.z + nb.z
		_: u_val = na.x + nb.x; v_val = na.y + nb.y

	var corner: int
	if u_val > 0 and v_val > 0: corner = 0
	elif u_val < 0 and v_val > 0: corner = 1
	elif u_val < 0 and v_val < 0: corner = 2
	else: corner = 3

	return axis * 4 + corner

func _setup_smooth_dialog() -> void:
	smooth_dialog = ConfirmationDialog.new()
	smooth_dialog.title = "Smooth Edge"
	smooth_dialog.ok_button_text = "Apply"
	smooth_dialog.size = Vector2i(250, 100)
	smooth_dialog.confirmed.connect(_on_smooth_apply)
	smooth_dialog.canceled.connect(_on_smooth_cancel)
	add_child(smooth_dialog)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	smooth_dialog.add_child(hbox)

	var lbl := Label.new()
	lbl.text = "Depth:"
	hbox.add_child(lbl)

	smooth_depth_spin = SpinBox.new()
	smooth_depth_spin.min_value = 1
	smooth_depth_spin.max_value = 5
	smooth_depth_spin.step = 1
	smooth_depth_spin.value = 1
	hbox.add_child(smooth_depth_spin)

func _on_smooth_apply() -> void:
	if smooth_path.is_empty():
		return

	var depth := int(smooth_depth_spin.value)
	var orientation := _get_smooth_orientation(smooth_normal_a, smooth_normal_b)

	_push_undo()

	for ep in smooth_path:
		for i in range(depth):
			# Remove cells between the edge and the prism line
			for j in range(depth - 1 - i):
				var remove_pos: Vector3i = ep - smooth_normal_a * i - smooth_normal_b * j
				if _in_bounds(remove_pos):
					cells[remove_pos.x][remove_pos.y][remove_pos.z] = CellTypes.empty_cell()
			# Place prism at the chamfer surface
			var prism_pos: Vector3i = ep - smooth_normal_a * i - smooth_normal_b * (depth - 1 - i)
			if _in_bounds(prism_pos) and cells[prism_pos.x][prism_pos.y][prism_pos.z][0] != CellTypes.Type.EMPTY:
				var old_color: int = cells[prism_pos.x][prism_pos.y][prism_pos.z][2]
				cells[prism_pos.x][prism_pos.y][prism_pos.z] = CellTypes.make_cell(CellTypes.Type.PRISM, orientation, old_color)

	smooth_path.clear()
	box_preview_instance.visible = false
	var mat := box_preview_instance.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 0, 0.6)
	_mark_dirty()
	_rebuild_mesh()

func _on_smooth_cancel() -> void:
	smooth_path.clear()
	box_preview_instance.visible = false
	var mat := box_preview_instance.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 0, 0.6)

func _extrude_start(mouse_pos: Vector2) -> void:
	if not camera or mouse_pos.x < PANEL_WIDTH:
		return

	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var result := _grid_raycast(from, dir)

	if result.is_empty():
		return

	var hit_pos: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	var cell: Vector3i = result["cell"]

	if not _in_bounds(cell) or cells[cell.x][cell.y][cell.z][0] == CellTypes.Type.EMPTY:
		return

	var normal := Vector3i(
		int(round(hit_normal.x)),
		int(round(hit_normal.y)),
		int(round(hit_normal.z))
	)
	if normal == Vector3i.ZERO:
		return

	extrude_normal = normal
	extrude_cells = _find_coplanar_surface(cell, normal)
	if extrude_cells.is_empty():
		return

	extrude_depth = 0
	extrude_active = true
	extrude_start_mouse = mouse_pos

	var world_center := Vector3(cell) * CELL_SIZE + Vector3(0.5, 0.5, 0.5) * CELL_SIZE
	var screen_a := camera.unproject_position(world_center)
	var screen_b := camera.unproject_position(world_center + Vector3(normal) * CELL_SIZE)
	var screen_delta := screen_b - screen_a
	if screen_delta.length() < 0.1:
		extrude_pixels_per_cell = 20.0
		extrude_screen_dir = Vector2.UP
	else:
		extrude_pixels_per_cell = screen_delta.length()
		extrude_screen_dir = screen_delta.normalized()

func _extrude_update(mouse_pos: Vector2) -> void:
	var delta := mouse_pos - extrude_start_mouse
	var projected := delta.dot(extrude_screen_dir)
	var new_depth := int(round(projected / extrude_pixels_per_cell))
	if new_depth != extrude_depth:
		extrude_depth = new_depth
		_draw_extrude_preview()

func _extrude_finish() -> void:
	if extrude_depth != 0:
		_push_undo()
	if extrude_depth > 0:
		for d in range(1, extrude_depth + 1):
			for cell in extrude_cells:
				var nc: Vector3i = cell + extrude_normal * d
				if _in_bounds(nc):
					var src: Array = cells[cell.x][cell.y][cell.z]
					cells[nc.x][nc.y][nc.z] = src.duplicate()
	elif extrude_depth < 0:
		for d in range(0, -extrude_depth):
			for cell in extrude_cells:
				var rc: Vector3i = cell - extrude_normal * d
				if _in_bounds(rc):
					cells[rc.x][rc.y][rc.z] = CellTypes.empty_cell()

	var did_change := extrude_depth != 0
	extrude_active = false
	extrude_cells.clear()
	extrude_depth = 0
	box_preview_instance.visible = false
	var mat := box_preview_instance.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 0, 0.6)

	if did_change:
		_mark_dirty()
		_rebuild_mesh()

func _find_coplanar_surface(start: Vector3i, normal: Vector3i) -> Array:
	var result: Array = []
	var visited := {}
	var queue: Array = [start]
	visited[start] = true
	var face_ci := CellTypes.face_index_from_normal(normal)
	var start_color: int = cells[start.x][start.y][start.z][face_ci]

	var dirs: Array = []
	if normal.x != 0:
		dirs = [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	elif normal.y != 0:
		dirs = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	else:
		dirs = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

	while queue.size() > 0:
		var cell: Vector3i = queue.pop_front()
		if not _in_bounds(cell):
			continue
		if cells[cell.x][cell.y][cell.z][0] == CellTypes.Type.EMPTY:
			continue
		if cells[cell.x][cell.y][cell.z][face_ci] != start_color:
			continue
		var face_neighbor: Vector3i = cell + normal
		if _in_bounds(face_neighbor) and cells[face_neighbor.x][face_neighbor.y][face_neighbor.z][0] != CellTypes.Type.EMPTY:
			continue
		result.append(cell)
		for d in dirs:
			var adj: Vector3i = cell + d
			if not visited.has(adj):
				visited[adj] = true
				queue.append(adj)

	return result

func _draw_extrude_preview() -> void:
	if extrude_depth == 0:
		box_preview_instance.visible = false
		return

	var mn := Vector3i(999, 999, 999)
	var mx := Vector3i(-1, -1, -1)

	if extrude_depth > 0:
		for d in range(1, extrude_depth + 1):
			for cell in extrude_cells:
				var nc: Vector3i = cell + extrude_normal * d
				if _in_bounds(nc):
					mn = Vector3i(mini(mn.x, nc.x), mini(mn.y, nc.y), mini(mn.z, nc.z))
					mx = Vector3i(maxi(mx.x, nc.x), maxi(mx.y, nc.y), maxi(mx.z, nc.z))
	else:
		for d in range(0, -extrude_depth):
			for cell in extrude_cells:
				var rc: Vector3i = cell - extrude_normal * d
				if _in_bounds(rc):
					mn = Vector3i(mini(mn.x, rc.x), mini(mn.y, rc.y), mini(mn.z, rc.z))
					mx = Vector3i(maxi(mx.x, rc.x), maxi(mx.y, rc.y), maxi(mx.z, rc.z))

	if mx.x < 0:
		box_preview_instance.visible = false
		return

	var world_mn := Vector3(mn) * CELL_SIZE
	var world_mx := Vector3(mx + Vector3i.ONE) * CELL_SIZE

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var c: Array[Vector3] = [
		world_mn,
		Vector3(world_mx.x, world_mn.y, world_mn.z),
		Vector3(world_mx.x, world_mn.y, world_mx.z),
		Vector3(world_mn.x, world_mn.y, world_mx.z),
		Vector3(world_mn.x, world_mx.y, world_mn.z),
		Vector3(world_mx.x, world_mx.y, world_mn.z),
		world_mx,
		Vector3(world_mn.x, world_mx.y, world_mx.z),
	]
	for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()

	box_preview_instance.mesh = im
	var mat := box_preview_instance.material_override as StandardMaterial3D
	if extrude_depth > 0:
		mat.albedo_color = Color(0, 1, 0, 0.6)
	else:
		mat.albedo_color = Color(1, 0, 0, 0.6)
	box_preview_instance.visible = true

func _fill_region(a: Vector3i, b: Vector3i, cell_type: int, orientation: int, color_idx: int) -> void:
	_push_undo()
	var mn := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var mx := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	for x in range(maxi(0, mn.x), mini(grid_x, mx.x + 1)):
		for y in range(maxi(0, mn.y), mini(grid_y, mx.y + 1)):
			for z in range(maxi(0, mn.z), mini(grid_z, mx.z + 1)):
				_place_with_mirror(Vector3i(x, y, z), cell_type, orientation, color_idx)
	_mark_dirty()
	_rebuild_mesh()

func _clear_region(a: Vector3i, b: Vector3i) -> void:
	_push_undo()
	var mn := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var mx := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	for x in range(maxi(0, mn.x), mini(grid_x, mx.x + 1)):
		for y in range(maxi(0, mn.y), mini(grid_y, mx.y + 1)):
			for z in range(maxi(0, mn.z), mini(grid_z, mx.z + 1)):
				_erase_with_mirror(Vector3i(x, y, z))
	_mark_dirty()
	_rebuild_mesh()

# ─── Shape Tools ───

func _get_line_cells(start: Vector3i, end: Vector3i, constrain: bool) -> Array:
	var ax := start.x
	var az := start.z
	var bx := end.x
	var bz := end.z
	if constrain:
		var dx := absi(bx - ax)
		var dz := absi(bz - az)
		if dx >= dz:
			bz = az
		else:
			bx = ax

	var result: Array = []
	var dx := absi(bx - ax)
	var dz := absi(bz - az)
	var sx := 1 if ax < bx else -1
	var sz := 1 if az < bz else -1
	var err := dx - dz
	var x := ax
	var z := az
	while true:
		var cell := Vector3i(x, floor_y, z)
		if _in_bounds(cell):
			result.append(cell)
		if x == bx and z == bz:
			break
		var e2 := 2 * err
		if e2 > -dz:
			err -= dz
			x += sx
		if e2 < dx:
			err += dx
			z += sz
	return result

func _get_rect_cells(start: Vector3i, end: Vector3i, constrain: bool) -> Array:
	var x1 := start.x
	var z1 := start.z
	var x2 := end.x
	var z2 := end.z
	if constrain:
		var dx := absi(x2 - x1)
		var dz := absi(z2 - z1)
		var side := maxi(dx, dz)
		x2 = x1 + side * (1 if x2 >= x1 else -1)
		z2 = z1 + side * (1 if z2 >= z1 else -1)

	var mn_x := mini(x1, x2)
	var mx_x := maxi(x1, x2)
	var mn_z := mini(z1, z2)
	var mx_z := maxi(z1, z2)

	var result: Array = []
	var seen := {}
	for x in range(mn_x, mx_x + 1):
		for z in [mn_z, mx_z]:
			var cell := Vector3i(x, floor_y, z)
			if _in_bounds(cell) and not seen.has(cell):
				result.append(cell)
				seen[cell] = true
	for z in range(mn_z + 1, mx_z):
		for x in [mn_x, mx_x]:
			var cell := Vector3i(x, floor_y, z)
			if _in_bounds(cell) and not seen.has(cell):
				result.append(cell)
				seen[cell] = true
	return result

func _get_oval_cells(start: Vector3i, end: Vector3i, constrain: bool) -> Array:
	var x1 := start.x
	var z1 := start.z
	var x2 := end.x
	var z2 := end.z
	if constrain:
		var dx := absi(x2 - x1)
		var dz := absi(z2 - z1)
		var side := maxi(dx, dz)
		x2 = x1 + side * (1 if x2 >= x1 else -1)
		z2 = z1 + side * (1 if z2 >= z1 else -1)

	var mn_x := mini(x1, x2)
	var mx_x := maxi(x1, x2)
	var mn_z := mini(z1, z2)
	var mx_z := maxi(z1, z2)

	var a := (mx_x - mn_x) / 2.0
	var b := (mx_z - mn_z) / 2.0
	var cx := (mn_x + mx_x) / 2.0
	var cz := (mn_z + mx_z) / 2.0

	if a < 0.5 and b < 0.5:
		var cell := Vector3i(int(round(cx)), floor_y, int(round(cz)))
		if _in_bounds(cell):
			return [cell]
		return []
	if a < 0.5 or b < 0.5:
		return _get_line_cells(start, end, false)

	var result: Array = []
	var seen := {}
	var steps := int(max(a, b) * 8)
	if steps < 32:
		steps = 32
	for i in range(steps):
		var angle := TAU * i / steps
		var px := int(round(cx + a * cos(angle)))
		var pz := int(round(cz + b * sin(angle)))
		var cell := Vector3i(px, floor_y, pz)
		if _in_bounds(cell) and not seen.has(cell):
			result.append(cell)
			seen[cell] = true
	return result

# ─── Cursor Drawing ───

func _get_prism_vertices(origin: Vector3, s: float, orientation: int) -> Array:
	var axis: int = orientation / 4
	var corner: int = orientation % 4
	var tri_2d: Array[Vector2]
	match corner:
		0: tri_2d = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
		1: tri_2d = [Vector2(1, 0), Vector2(1, 1), Vector2(0, 0)]
		2: tri_2d = [Vector2(1, 1), Vector2(0, 1), Vector2(1, 0)]
		_: tri_2d = [Vector2(0, 1), Vector2(0, 0), Vector2(1, 1)]
	var p_near: Array[Vector3] = []
	var p_far: Array[Vector3] = []
	for uv in tri_2d:
		match axis:
			0:
				p_near.append(origin + Vector3(uv.x * s, 0, uv.y * s))
				p_far.append(origin + Vector3(uv.x * s, s, uv.y * s))
			1:
				p_near.append(origin + Vector3(0, uv.x * s, uv.y * s))
				p_far.append(origin + Vector3(s, uv.x * s, uv.y * s))
			_:
				p_near.append(origin + Vector3(uv.x * s, uv.y * s, 0))
				p_far.append(origin + Vector3(uv.x * s, uv.y * s, s))
	return [p_near, p_far]

func _draw_cursor(cell_pos: Vector3i) -> void:
	var margin := CELL_SIZE * 0.02
	var pos := Vector3(cell_pos) * CELL_SIZE - Vector3.ONE * margin
	var size := CELL_SIZE + margin * 2.0

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var is_erase := current_tool == ToolType.ERASER or current_tool == ToolType.BOX_ERASE
	if is_erase or current_type == CellTypes.Type.SOLID:
		var c: Array[Vector3] = [
			pos, pos + Vector3(size, 0, 0), pos + Vector3(size, 0, size), pos + Vector3(0, 0, size),
			pos + Vector3(0, size, 0), pos + Vector3(size, size, 0),
			pos + Vector3(size, size, size), pos + Vector3(0, size, size),
		]
		for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
			im.surface_add_vertex(c[e[0]])
			im.surface_add_vertex(c[e[1]])
	else:
		var verts := _get_prism_vertices(pos, size, current_orientation)
		var p_near: Array = verts[0]
		var p_far: Array = verts[1]
		for i in range(3):
			im.surface_add_vertex(p_near[i]); im.surface_add_vertex(p_near[(i + 1) % 3])
			im.surface_add_vertex(p_far[i]); im.surface_add_vertex(p_far[(i + 1) % 3])
			im.surface_add_vertex(p_near[i]); im.surface_add_vertex(p_far[i])

	im.surface_end()
	cursor_mesh_instance.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.RED if is_erase else Color.WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	cursor_mesh_instance.material_override = mat

func _update_box_preview() -> void:
	if not box_active:
		box_preview_instance.visible = false
		dims_label.text = ""
		return

	var end_cell: Vector3i
	if current_tool in [ToolType.BOX, ToolType.LINE, ToolType.RECT, ToolType.OVAL]:
		end_cell = place_cell if _in_bounds(place_cell) else target_cell
	else:
		end_cell = target_cell

	if current_tool in [ToolType.LINE, ToolType.RECT, ToolType.OVAL]:
		end_cell = Vector3i(end_cell.x, floor_y, end_cell.z)

	if not _in_bounds(end_cell):
		box_preview_instance.visible = false
		dims_label.text = ""
		return

	if current_tool in [ToolType.LINE, ToolType.RECT, ToolType.OVAL]:
		var constrain := Input.is_key_pressed(KEY_SHIFT)
		var result := _compute_center_draw(box_start, end_cell, constrain)
		var shape_cells: Array
		match current_tool:
			ToolType.LINE: shape_cells = _get_line_cells(result[0], result[1], result[2])
			ToolType.RECT: shape_cells = _get_rect_cells(result[0], result[1], result[2])
			ToolType.OVAL: shape_cells = _get_oval_cells(result[0], result[1], result[2])
		var s: Vector3i = result[0]
		var e: Vector3i = result[1]
		var w := absi(e.x - s.x) + 1
		var h := absi(e.z - s.z) + 1
		dims_label.text = "Size: %d x %d  (%d cells)" % [w, h, shape_cells.size()]
		_draw_shape_preview(shape_cells)
		return

	var sx := mini(box_start.x, end_cell.x)
	var sy := mini(box_start.y, end_cell.y)
	var sz := mini(box_start.z, end_cell.z)
	var ex := maxi(box_start.x, end_cell.x)
	var ey := maxi(box_start.y, end_cell.y)
	var ez := maxi(box_start.z, end_cell.z)
	dims_label.text = "Size: %d x %d x %d" % [ex - sx + 1, ey - sy + 1, ez - sz + 1]

	var mn := Vector3(sx, sy, sz) * CELL_SIZE
	var mx := Vector3(ex + 1, ey + 1, ez + 1) * CELL_SIZE

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var c: Array[Vector3] = [
		mn, Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), mx, Vector3(mn.x, mx.y, mx.z),
	]
	for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()
	box_preview_instance.mesh = im
	box_preview_instance.visible = true

func _draw_shape_preview(shape_cells: Array) -> void:
	if shape_cells.is_empty():
		box_preview_instance.visible = false
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for cell in shape_cells:
		var pos := Vector3(cell) * CELL_SIZE
		var s := CELL_SIZE
		var c: Array[Vector3] = [
			pos, pos + Vector3(s, 0, 0), pos + Vector3(s, 0, s), pos + Vector3(0, 0, s),
			pos + Vector3(0, s, 0), pos + Vector3(s, s, 0),
			pos + Vector3(s, s, s), pos + Vector3(0, s, s),
		]
		for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
			im.surface_add_vertex(c[e[0]])
			im.surface_add_vertex(c[e[1]])
	im.surface_end()
	box_preview_instance.mesh = im
	var mat := box_preview_instance.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 0, 0.6)
	box_preview_instance.visible = true

# ─── File Operations ───

func _save() -> void:
	if current_file_path.is_empty():
		save_dialog.current_dir = "res://definitions"
		save_dialog.popup_centered()
	else:
		_save_to_path(current_file_path)

func _save_as() -> void:
	if not current_file_path.is_empty():
		save_dialog.current_dir = current_file_path.get_base_dir()
		save_dialog.current_file = current_file_path.get_file().get_basename() + ".res"
	else:
		save_dialog.current_dir = "res://definitions"
	save_dialog.popup_centered()

func _open() -> void:
	if _unsaved_changes:
		_pending_action = "open"
		confirm_dialog.popup_centered()
		return
	open_dialog.current_dir = "res://definitions"
	open_dialog.popup_centered()

func _new() -> void:
	if _unsaved_changes:
		_pending_action = "new"
		confirm_dialog.popup_centered()
		return
	_do_new()

func _do_new() -> void:
	current_file_path = ""
	_undo_stack.clear()
	_cancel_box()
	place_cell = Vector3i(-1, -1, -1)
	target_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	_init_cells()
	_unsaved_changes = false
	_rebuild_mesh()
	_update_file_label()

func _save_to_path(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var def := VoxelDefinition.new()
	def.set_from_cells(cells, grid_x, grid_y, grid_z, edit_mode)
	# Binary .res honours FLAG_COMPRESS (lossless); the mostly-empty cell grid
	# shrinks from ~14 MB to ~30 KB. Text .tres ignores the flag but still works.
	if ResourceSaver.save(def, path, ResourceSaver.FLAG_COMPRESS) == OK:
		current_file_path = path
		_unsaved_changes = false
		_update_file_label()

func _on_save_file_selected(path: String) -> void:
	if not path.ends_with(".res") and not path.ends_with(".tres"):
		path += ".res"
	_save_to_path(path)
	if not _pending_action.is_empty():
		_execute_pending_action()

func _on_open_file_selected(path: String) -> void:
	_load_from_path(path)

func _import_png() -> void:
	import_dialog.popup_centered()

func _on_import_file_selected(path: String) -> void:
	var image := Image.new()
	if image.load(path) != OK:
		return

	if image.get_width() != grid_x or image.get_height() != grid_y:
		image.resize(grid_x, grid_y, Image.INTERPOLATE_NEAREST)

	var has_alpha := CellTypes.image_has_alpha(image)
	_push_undo()
	for px in range(image.get_width()):
		for py in range(image.get_height()):
			var color := image.get_pixel(px, py)
			if color.a < 0.5:
				continue
			var cell_x := px
			var cell_y := grid_y - 1 - py
			if cell_x >= 0 and cell_x < grid_x and cell_y >= 0 and cell_y < grid_y:
				var encoded: int
				if has_alpha:
					encoded = CellTypes.encode_rgb5551(color)
				else:
					encoded = CellTypes.encode_rgb565(color)
				cells[cell_x][cell_y][0] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, encoded)

	_mark_dirty()
	_rebuild_mesh()

func _import_block_texture() -> void:
	if _unsaved_changes:
		_pending_action = "import_block"
		confirm_dialog.popup_centered()
		return
	_do_import_block_texture()

func _do_import_block_texture() -> void:
	if edit_mode != EditMode.BLOCK:
		_do_set_edit_mode(EditMode.BLOCK)
		var buttons := mode_group.get_buttons()
		buttons[0].button_pressed = true
	import_block_dialog.popup_centered()

func _on_block_texture_selected(path: String) -> void:
	var image := Image.new()
	if image.load(path) != OK:
		return

	var w := image.get_width()
	var h := image.get_height()
	var layout := CellTypes.validate_block_texture(w, h, grid_x, grid_y)
	if layout == "":
		_show_texture_size_error(w, h)
		return

	var faces := {}
	var format_name := ""
	var is_octagon := false
	var octagon_fp := 0
	var tile_w := grid_x
	var tile_h := grid_y

	if layout == "octagon_full" or layout == "octagon_half":
		is_octagon = true
		octagon_fp = tile_w if layout == "octagon_full" else tile_w / 2
		var c := CellTypes.octagon_chamfer(octagon_fp)
		var aw := octagon_fp - 2 * c
		format_name = "Full Octagon (%d×%d)" % [w, h] if layout == "octagon_full" else "Half Octagon (%d×%d)" % [w, h]
		var face_keys := ["east", "ne", "north", "nw", "west", "sw", "south", "se", "cap"]
		var face_widths := [aw, c, aw, c, aw, c, aw, c, octagon_fp]
		var col := 0
		for i in range(9):
			var fw: int = face_widths[i]
			var fh: int = octagon_fp if i == 8 else h
			faces[face_keys[i]] = image.get_region(Rect2i(col, 0, fw, fh))
			col += fw
	elif layout == "net":
		format_name = "6-Face Net (%d×%d)" % [w, h]
		var regions := {
			"top": Rect2i(0, 0, tile_w, tile_h),
			"front": Rect2i(tile_w, 0, tile_w, tile_h),
			"right": Rect2i(tile_w * 2, 0, tile_w, tile_h),
			"bottom": Rect2i(0, tile_h, tile_w, tile_h),
			"back": Rect2i(tile_w, tile_h, tile_w, tile_h),
			"left": Rect2i(tile_w * 2, tile_h, tile_w, tile_h),
		}
		for key in regions:
			var r: Rect2i = regions[key]
			faces[key] = image.get_region(r)
	elif layout == "column":
		format_name = "Column / Log (%d×%d)" % [w, h]
		var sides_img := image.get_region(Rect2i(0, 0, tile_w, tile_h))
		var cap_img := image.get_region(Rect2i(tile_w, 0, tile_w, tile_h))
		faces["front"] = sides_img
		faces["back"] = sides_img
		faces["right"] = sides_img
		faces["left"] = sides_img
		faces["top"] = cap_img
		faces["bottom"] = cap_img
	else:
		format_name = "Uniform (%d×%d)" % [w, h]
		faces["front"] = image
		faces["back"] = image
		faces["right"] = image
		faces["left"] = image
		faces["top"] = image
		faces["bottom"] = image

	_block_tex_faces = faces
	_block_tex_has_alpha = CellTypes.image_has_alpha(image)
	_block_tex_is_octagon = is_octagon
	_block_tex_octagon_footprint = octagon_fp
	var color_mode := "RGB5551" if _block_tex_has_alpha else "RGB565"
	_block_tex_format_label.text = "Detected: " + format_name + "  |  Color: " + color_mode

	_rebuild_block_tex_preview(is_octagon)
	for key in faces:
		if key in _block_tex_previews:
			var tex := ImageTexture.create_from_image(faces[key])
			_block_tex_previews[key].texture = tex

	block_tex_wizard.popup_centered()

func _show_texture_size_error(w: int, h: int) -> void:
	var full_w := CellTypes.octagon_atlas_width(grid_x)
	var half_w := CellTypes.octagon_atlas_width(grid_x / 2)
	var msg := "Unsupported texture size: %d×%d\n\nLegal sizes:\n" % [w, h]
	msg += "  %d×%d  — Uniform cube\n" % [grid_x, grid_y]
	msg += "  %d×%d  — Column cube\n" % [grid_x * 2, grid_y]
	msg += "  %d×%d  — 6-face net cube\n" % [grid_x * 3, grid_y * 2]
	msg += "  %d×%d — Full octagon (F=%d)\n" % [full_w, grid_y, grid_x]
	msg += "  %d×%d  — Half octagon (F=%d)\n" % [half_w, grid_y, grid_x / 2]
	var dlg := AcceptDialog.new()
	dlg.title = "Unsupported Texture Size"
	dlg.dialog_text = msg
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()

func _setup_block_tex_wizard() -> void:
	block_tex_wizard = AcceptDialog.new()
	block_tex_wizard.title = "Import Block Texture"
	block_tex_wizard.ok_button_text = "Apply"
	block_tex_wizard.confirmed.connect(_on_block_tex_apply)
	add_child(block_tex_wizard)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	block_tex_wizard.add_child(vbox)

	_block_tex_format_label = Label.new()
	_block_tex_format_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_block_tex_format_label)

	vbox.add_child(HSeparator.new())

	_block_tex_previews = {}
	_block_tex_preview_grid = GridContainer.new()
	_block_tex_preview_grid.columns = 3
	_block_tex_preview_grid.add_theme_constant_override("h_separation", 12)
	_block_tex_preview_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(_block_tex_preview_grid)

	_rebuild_block_tex_preview(false)

	vbox.add_child(HSeparator.new())
	_block_tex_hint_label = Label.new()
	_block_tex_hint_label.text = "Supported: 32x32, 64x32, 96x64, 124x32 (full oct), 60x32 (half oct)"
	_block_tex_hint_label.add_theme_font_size_override("font_size", 11)
	_block_tex_hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_block_tex_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_block_tex_hint_label)

func _rebuild_block_tex_preview(octagon: bool) -> void:
	for child in _block_tex_preview_grid.get_children():
		_block_tex_preview_grid.remove_child(child)
		child.queue_free()
	_block_tex_previews.clear()

	var names: Array
	var labels: Array
	if octagon:
		_block_tex_preview_grid.columns = 3
		names = ["east", "ne", "north", "nw", "west", "sw", "south", "se", "cap"]
		labels = ["East (+X)", "NE", "North (+Z)", "NW", "West (-X)", "SW", "South (-Z)", "SE", "Cap (Top/Bot)"]
	else:
		_block_tex_preview_grid.columns = 3
		names = ["top", "front", "right", "bottom", "back", "left"]
		labels = ["Top (+Y)", "Front (+Z)", "Right (+X)", "Bottom (-Y)", "Back (-Z)", "Left (-X)"]

	for i in range(names.size()):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		_block_tex_preview_grid.add_child(col)

		var lbl := Label.new()
		lbl.text = labels[i]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lbl)

		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(80, 80) if octagon else Vector2(96, 96)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		col.add_child(tex_rect)

		_block_tex_previews[names[i]] = tex_rect

func _on_block_tex_apply() -> void:
	if _block_tex_faces.is_empty():
		return

	var faces := _block_tex_faces
	_block_tex_faces = {}

	if _block_tex_is_octagon:
		_apply_octagon_block(faces, _block_tex_octagon_footprint)
		return

	var face_keys := ["top", "bottom", "right", "left", "front", "back"]
	var face_indices := [CellTypes.FACE_TOP, CellTypes.FACE_BOTTOM, CellTypes.FACE_RIGHT, CellTypes.FACE_LEFT, CellTypes.FACE_FRONT, CellTypes.FACE_BACK]

	var use_alpha := _block_tex_has_alpha
	var color_maps := {}
	var color_counts := {}
	for key in face_keys:
		var img: Image = faces[key]
		var cmap: Array = []
		cmap.resize(img.get_width())
		for u in range(img.get_width()):
			cmap[u] = []
			cmap[u].resize(img.get_height())
			for v in range(img.get_height()):
				var pixel := img.get_pixel(u, v)
				if not use_alpha and pixel.a < 0.5:
					cmap[u][v] = -1
				else:
					var encoded: int
					if use_alpha:
						encoded = CellTypes.encode_rgb5551(pixel)
					else:
						encoded = CellTypes.encode_rgb565(pixel)
					cmap[u][v] = encoded
					color_counts[encoded] = color_counts.get(encoded, 0) + 1
		color_maps[key] = cmap

	var fill_color := 0
	var best_count := 0
	for idx in color_counts:
		if color_counts[idx] > best_count:
			best_count = color_counts[idx]
			fill_color = idx

	if use_alpha:
		var fc := CellTypes.decode_color(fill_color)
		fill_color = CellTypes.encode_rgb5551(Color(fc.r, fc.g, fc.b, 0.0))

	_push_undo()
	_init_cells()

	if use_alpha:
		for x in range(grid_x):
			for y in range(grid_y):
				for z in range(grid_z):
					if x == 0 or x == grid_x - 1 or y == 0 or y == grid_y - 1 or z == 0 or z == grid_z - 1:
						cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill_color)
	else:
		for x in range(grid_x):
			for y in range(grid_y):
				for z in range(grid_z):
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill_color)

	_apply_face_texture(color_maps["front"], CellTypes.FACE_FRONT,
		func(u: int, v: int) -> Vector3i:
			return Vector3i(u, grid_y - 1 - v, grid_z - 1),
		func(u: int, v: int) -> Vector3i:
			return Vector3i(u, grid_y - 1 - v, grid_z - 1))

	_apply_face_texture(color_maps["back"], CellTypes.FACE_BACK,
		func(u: int, v: int) -> Vector3i:
			return Vector3i(grid_x - 1 - u, grid_y - 1 - v, 0),
		func(u: int, v: int) -> Vector3i:
			return Vector3i(grid_x - 1 - u, grid_y - 1 - v, 0))

	_apply_face_texture(color_maps["right"], CellTypes.FACE_RIGHT,
		func(u: int, v: int) -> Vector3i:
			return Vector3i(grid_x - 1, grid_y - 1 - v, grid_z - 1 - u),
		func(u: int, v: int) -> Vector3i:
			return Vector3i(grid_x - 1, grid_y - 1 - v, grid_z - 1 - u))

	_apply_face_texture(color_maps["left"], CellTypes.FACE_LEFT,
		func(u: int, v: int) -> Vector3i:
			return Vector3i(0, grid_y - 1 - v, u),
		func(u: int, v: int) -> Vector3i:
			return Vector3i(0, grid_y - 1 - v, u))

	_apply_face_texture(color_maps["top"], CellTypes.FACE_TOP,
		func(u: int, v: int) -> Vector3i:
			return Vector3i(u, grid_y - 1, v),
		func(u: int, v: int) -> Vector3i:
			return Vector3i(u, grid_y - 1, v))

	_apply_face_texture(color_maps["bottom"], CellTypes.FACE_BOTTOM,
		func(u: int, v: int) -> Vector3i:
			return Vector3i(u, 0, grid_z - 1 - v),
		func(u: int, v: int) -> Vector3i:
			return Vector3i(u, 0, grid_z - 1 - v))

	if use_alpha:
		_erase_fully_transparent_cells()

	_mark_dirty()
	_rebuild_mesh()

func _apply_octagon_block(faces: Dictionary, footprint: int) -> void:
	var use_alpha := _block_tex_has_alpha
	var c := CellTypes.octagon_chamfer(footprint)
	var gx := grid_x
	var gy := grid_y
	var gz := grid_z
	var ox := (gx - footprint) / 2
	var oz := (gz - footprint) / 2

	var oct_keys := ["east", "ne", "north", "nw", "west", "sw", "south", "se", "cap"]
	var color_maps := {}
	for key in oct_keys:
		var img: Image = faces[key]
		var cmap: Array = []
		cmap.resize(img.get_width())
		for u in range(img.get_width()):
			cmap[u] = []
			cmap[u].resize(img.get_height())
			for v in range(img.get_height()):
				var pixel := img.get_pixel(u, v)
				var encoded: int
				if use_alpha:
					encoded = CellTypes.encode_rgb5551(pixel)
				else:
					encoded = CellTypes.encode_rgb565(pixel)
				cmap[u][v] = encoded
		color_maps[key] = cmap

	var cap_map: Array = color_maps["cap"]
	var cap_color_counts := {}
	for u in range(cap_map.size()):
		for v in range(cap_map[u].size()):
			var cv: int = cap_map[u][v]
			cap_color_counts[cv] = cap_color_counts.get(cv, 0) + 1
	var fill_color := 0
	var best_count := 0
	for idx in cap_color_counts:
		if cap_color_counts[idx] > best_count:
			best_count = cap_color_counts[idx]
			fill_color = idx

	if use_alpha:
		var fc := CellTypes.decode_color(fill_color)
		fill_color = CellTypes.encode_rgb5551(Color(fc.r, fc.g, fc.b, 0.0))

	_push_undo()
	_init_cells()

	var fp := footprint
	for lx in range(fp):
		for y in range(gy):
			for lz in range(fp):
				var x := ox + lx
				var z := oz + lz
				var in_octagon := true
				var corner_type := -1
				if lx + lz < c:
					in_octagon = false
					if lx + lz == c - 1:
						corner_type = 0
				elif (fp - 1 - lx) + lz < c:
					in_octagon = false
					if (fp - 1 - lx) + lz == c - 1:
						corner_type = 1
				elif (fp - 1 - lx) + (fp - 1 - lz) < c:
					in_octagon = false
					if (fp - 1 - lx) + (fp - 1 - lz) == c - 1:
						corner_type = 2
				elif lx + (fp - 1 - lz) < c:
					in_octagon = false
					if lx + (fp - 1 - lz) == c - 1:
						corner_type = 3

				if not in_octagon:
					if corner_type >= 0:
						var orientation: int
						match corner_type:
							0: orientation = 2
							1: orientation = 3
							2: orientation = 0
							_: orientation = 1
						cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, orientation, fill_color)
					# else: already empty from _init_cells
				else:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill_color)

	var x_max := ox + fp - 1
	var z_max := oz + fp - 1
	_apply_octagon_side(color_maps["east"], gy,
		func(i: int, v: int) -> Vector3i: return Vector3i(x_max, gy - 1 - v, oz + c + i),
		CellTypes.FACE_RIGHT)
	_apply_octagon_side(color_maps["west"], gy,
		func(i: int, v: int) -> Vector3i: return Vector3i(ox, gy - 1 - v, z_max - c - i),
		CellTypes.FACE_LEFT)
	_apply_octagon_side(color_maps["north"], gy,
		func(i: int, v: int) -> Vector3i: return Vector3i(x_max - c - i, gy - 1 - v, z_max),
		CellTypes.FACE_FRONT)
	_apply_octagon_side(color_maps["south"], gy,
		func(i: int, v: int) -> Vector3i: return Vector3i(ox + c + i, gy - 1 - v, oz),
		CellTypes.FACE_BACK)

	_apply_octagon_diag_color(color_maps["ne"], gy, c, 2, ox, oz, fp)
	_apply_octagon_diag_color(color_maps["nw"], gy, c, 3, ox, oz, fp)
	_apply_octagon_diag_color(color_maps["sw"], gy, c, 0, ox, oz, fp)
	_apply_octagon_diag_color(color_maps["se"], gy, c, 1, ox, oz, fp)

	for lx in range(fp):
		for lz in range(fp):
			var x := ox + lx
			var z := oz + lz
			if cells[x][0][z][0] == CellTypes.Type.SOLID:
				cells[x][0][z][CellTypes.FACE_BOTTOM] = cap_map[lx][fp - 1 - lz]
			if cells[x][gy - 1][z][0] == CellTypes.Type.SOLID:
				cells[x][gy - 1][z][CellTypes.FACE_TOP] = cap_map[lx][lz]

	if use_alpha:
		_erase_fully_transparent_cells()

	_mark_dirty()
	_rebuild_mesh()

func _apply_octagon_side(color_map: Array, gy: int, pos_fn: Callable, face_idx: int) -> void:
	var face_w: int = color_map.size()
	for i in range(face_w):
		for v in range(gy):
			var ci: int = color_map[i][v]
			var p: Vector3i = pos_fn.call(i, v)
			cells[p.x][p.y][p.z][face_idx] = ci

func _apply_octagon_diag_color(color_map: Array, gy: int, chamfer: int, corner_type: int, ox: int, oz: int, fp: int) -> void:
	var prism_positions: Array = []
	for lx in range(fp):
		for lz in range(fp):
			var on_edge := false
			match corner_type:
				0: on_edge = (lx + lz == chamfer - 1)
				1: on_edge = ((fp - 1 - lx) + lz == chamfer - 1)
				2: on_edge = ((fp - 1 - lx) + (fp - 1 - lz) == chamfer - 1)
				3: on_edge = (lx + (fp - 1 - lz) == chamfer - 1)
			if on_edge:
				prism_positions.append(Vector2i(ox + lx, oz + lz))

	match corner_type:
		0: prism_positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
		1: prism_positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x)
		2: prism_positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x)
		3: prism_positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)

	for idx in range(prism_positions.size()):
		var pos: Vector2i = prism_positions[idx]
		for y in range(gy):
			var ci: int = color_map[idx][gy - 1 - y]
			cells[pos.x][y][pos.y][2] = ci

func _erase_fully_transparent_cells() -> void:
	for x in range(grid_x):
		for y in range(grid_y):
			for z in range(grid_z):
				var cell: Array = cells[x][y][z]
				if cell[0] == CellTypes.Type.EMPTY:
					continue
				var all_transparent := true
				for fi in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
					var cv: int = cell[fi]
					if not CellTypes.is_rgb5551(cv) or CellTypes.decode_rgb5551(cv).a >= CellTypes.ALPHA_THRESHOLD:
						all_transparent = false
						break
				if all_transparent:
					cells[x][y][z] = CellTypes.empty_cell()

func _apply_face_texture(color_map: Array, face_idx: int, erase_pos: Callable, color_pos: Callable) -> void:
	var w: int = color_map.size()
	var h: int = color_map[0].size()
	for u in range(w):
		for v in range(h):
			var ci: int = color_map[u][v]
			if ci == -1:
				var p: Vector3i = erase_pos.call(u, v)
				cells[p.x][p.y][p.z] = CellTypes.empty_cell()
			else:
				var p: Vector3i = color_pos.call(u, v)
				cells[p.x][p.y][p.z][face_idx] = ci

func _export_obj() -> void:
	export_dialog.current_dir = "res://definitions"
	export_dialog.popup_centered()

func _on_export_obj_selected(path: String) -> void:
	var face_count := MeshExporter.export_obj(path, cells, grid_x, grid_y, grid_z, CELL_SIZE)
	if face_count > 0:
		dims_label.text = "Exported %d faces" % face_count
	else:
		dims_label.text = "Export failed"

func _import_character_sprites() -> void:
	if _unsaved_changes:
		_pending_action = "import_sprites"
		confirm_dialog.popup_centered()
		return
	_do_import_character_sprites()

func _do_import_character_sprites() -> void:
	if edit_mode != EditMode.CHARACTER:
		_do_set_edit_mode(EditMode.CHARACTER)
		var buttons := mode_group.get_buttons()
		buttons[1].button_pressed = true
	_front_image = null
	import_front_dialog.popup_centered()

func _on_front_sprite_selected(path: String) -> void:
	_front_image = Image.new()
	if _front_image.load(path) != OK:
		_front_image = null
		return
	_wizard_front_label.text = "Front: " + path.get_file()
	import_side_dialog.popup_centered()

func _on_side_sprite_selected(path: String) -> void:
	if _front_image == null:
		return
	_side_image = Image.new()
	if _side_image.load(path) != OK:
		_side_image = null
		return
	_wizard_front_label.text = "Front"
	_wizard_side_label.text = "Side"
	_wizard_front_preview.texture = ImageTexture.create_from_image(_front_image)
	_wizard_front_preview.flip_h = false
	_wizard_front_preview.custom_minimum_size = Vector2(_front_image.get_width() * 2, _front_image.get_height() * 2)
	_wizard_side_preview.texture = ImageTexture.create_from_image(_side_image)
	_wizard_side_preview.flip_h = false
	_wizard_side_preview.custom_minimum_size = Vector2(_side_image.get_width() * 2, _side_image.get_height() * 2)
	var front_perfect := _front_image.get_width() == grid_x and _front_image.get_height() == grid_y
	var side_perfect := _side_image.get_width() == grid_z and _side_image.get_height() == grid_y
	_wizard_front_size_label.text = "%dx%d" % [_front_image.get_width(), _front_image.get_height()]
	if front_perfect:
		_wizard_front_size_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	else:
		_wizard_front_size_label.text += " (will scale to %dx%d)" % [grid_x, grid_y]
		_wizard_front_size_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	_wizard_side_size_label.text = "%dx%d" % [_side_image.get_width(), _side_image.get_height()]
	if side_perfect:
		_wizard_side_size_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	else:
		_wizard_side_size_label.text += " (will scale to %dx%d)" % [grid_z, grid_y]
		_wizard_side_size_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	_wizard_flip_side.button_pressed = false
	sprite_wizard.popup_centered()

func _setup_sprite_wizard() -> void:
	sprite_wizard = AcceptDialog.new()
	sprite_wizard.title = "Character Sprite Import"
	sprite_wizard.ok_button_text = "Generate"
	sprite_wizard.confirmed.connect(_on_wizard_generate)
	add_child(sprite_wizard)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	sprite_wizard.add_child(vbox)

	# Image previews side by side
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 12)
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(preview_row)

	# Front column
	var front_col := VBoxContainer.new()
	front_col.add_theme_constant_override("separation", 2)
	preview_row.add_child(front_col)
	_wizard_front_label = Label.new()
	_wizard_front_label.text = "Front"
	_wizard_front_label.add_theme_font_size_override("font_size", 13)
	_wizard_front_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	front_col.add_child(_wizard_front_label)
	_wizard_front_preview = TextureRect.new()
	_wizard_front_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wizard_front_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wizard_front_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	front_col.add_child(_wizard_front_preview)
	_wizard_front_size_label = Label.new()
	_wizard_front_size_label.add_theme_font_size_override("font_size", 10)
	_wizard_front_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	front_col.add_child(_wizard_front_size_label)

	# Side column with Front/Back edge labels
	var side_col := VBoxContainer.new()
	side_col.add_theme_constant_override("separation", 2)
	preview_row.add_child(side_col)
	_wizard_side_label = Label.new()
	_wizard_side_label.text = "Side"
	_wizard_side_label.add_theme_font_size_override("font_size", 13)
	_wizard_side_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side_col.add_child(_wizard_side_label)
	var side_outer := HBoxContainer.new()
	side_outer.add_theme_constant_override("separation", 4)
	side_col.add_child(side_outer)
	var side_left_lbl := Label.new()
	side_left_lbl.text = "F\nr\no\nn\nt"
	side_left_lbl.add_theme_font_size_override("font_size", 10)
	side_left_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	side_left_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	side_outer.add_child(side_left_lbl)
	_wizard_side_preview = TextureRect.new()
	_wizard_side_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wizard_side_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wizard_side_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	side_outer.add_child(_wizard_side_preview)
	var side_right_lbl := Label.new()
	side_right_lbl.text = "B\na\nc\nk"
	side_right_lbl.add_theme_font_size_override("font_size", 10)
	side_right_lbl.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
	side_right_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	side_outer.add_child(side_right_lbl)
	_wizard_side_size_label = Label.new()
	_wizard_side_size_label.add_theme_font_size_override("font_size", 10)
	_wizard_side_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side_col.add_child(_wizard_side_size_label)

	vbox.add_child(HSeparator.new())

	# Flip control for side sprite only
	_wizard_flip_front = CheckButton.new()
	_wizard_flip_side = CheckButton.new()
	_wizard_flip_side.text = "Flip side sprite"
	_wizard_flip_side.toggled.connect(func(_on: bool): _wizard_side_preview.flip_h = _wizard_flip_side.button_pressed)
	vbox.add_child(_wizard_flip_side)

	var hint := Label.new()
	hint.text = "Flip so the character's face points toward the \"Front\" label. Front sprite determines colors."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

func _on_wizard_generate() -> void:
	if _front_image == null or _side_image == null:
		return

	var front := _front_image
	var side := _side_image
	_front_image = null
	_side_image = null

	if front.get_width() != grid_x or front.get_height() != grid_y:
		front.resize(grid_x, grid_y, Image.INTERPOLATE_NEAREST)
	if side.get_width() != grid_z or side.get_height() != grid_y:
		side.resize(grid_z, grid_y, Image.INTERPOLATE_NEAREST)

	var flip_side := _wizard_flip_side.button_pressed

	_push_undo()
	_init_cells()

	var front_has_alpha := CellTypes.image_has_alpha(front)
	var side_has_alpha := CellTypes.image_has_alpha(side)
	for x in range(grid_x):
		for y in range(grid_y):
			var front_pixel := front.get_pixel(grid_x - 1 - x, grid_y - 1 - y)
			if front_pixel.a < 0.5:
				continue
			var color_idx: int
			if front_has_alpha:
				color_idx = CellTypes.encode_rgb5551(front_pixel)
			else:
				color_idx = CellTypes.encode_rgb565(front_pixel)
			for z in range(grid_z):
				var sz := z if flip_side else (grid_z - 1 - z)
				var side_pixel := side.get_pixel(sz, grid_y - 1 - y)
				if side_pixel.a >= 0.5:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, color_idx)

	# Recolor left/right surfaces from side sprite
	for y in range(grid_y):
		for z in range(grid_z):
			var sz := z if flip_side else (grid_z - 1 - z)
			var side_pixel := side.get_pixel(sz, grid_y - 1 - y)
			if side_pixel.a < 0.5:
				continue
			var side_color: int
			if side_has_alpha:
				side_color = CellTypes.encode_rgb5551(side_pixel)
			else:
				side_color = CellTypes.encode_rgb565(side_pixel)
			for x in range(grid_x):
				if cells[x][y][z][0] != CellTypes.Type.EMPTY:
					cells[x][y][z][CellTypes.FACE_LEFT] = side_color
					break
			for x in range(grid_x - 1, -1, -1):
				if cells[x][y][z][0] != CellTypes.Type.EMPTY:
					cells[x][y][z][CellTypes.FACE_RIGHT] = side_color
					break

	_ground_cells()
	_mark_dirty()
	_rebuild_mesh()

func _ground_cells() -> void:
	var min_y := grid_y
	for x in range(grid_x):
		for y in range(grid_y):
			if y >= min_y:
				break
			for z in range(grid_z):
				if cells[x][y][z][0] != CellTypes.Type.EMPTY:
					min_y = y
					break
	if min_y <= 0 or min_y >= grid_y:
		return
	for y in range(grid_y):
		var src_y := y + min_y
		for x in range(grid_x):
			for z in range(grid_z):
				if src_y < grid_y:
					cells[x][y][z] = cells[x][src_y][z].duplicate()
				else:
					cells[x][y][z] = CellTypes.empty_cell()


func _load_from_path(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var def := ResourceLoader.load(path) as VoxelDefinition
	if not def:
		return
	edit_mode = def.edit_mode
	grid_x = def.grid_x
	grid_y = def.grid_y
	grid_z = def.grid_z
	CELL_SIZE = 1.0 / CHAR_RES if edit_mode == EditMode.CHARACTER else 1.0 / BLOCK_RES
	cells = def.to_cells()
	current_file_path = path
	_unsaved_changes = false
	_undo_stack.clear()
	_cancel_box()
	place_cell = Vector3i(-1, -1, -1)
	target_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	floor_y = 0
	floor_slider.max_value = grid_y - 1
	floor_slider.set_value_no_signal(0)
	floor_value_label.text = "Y = 0"
	ceiling_y = -1
	ceiling_slider.max_value = grid_y - 1
	ceiling_slider.set_value_no_signal(-1)
	ceiling_value_label.text = "Off"
	_ceiling_locked = false
	ceiling_lock_btn.set_pressed_no_signal(false)
	var buttons := mode_group.get_buttons()
	buttons[0].button_pressed = edit_mode == EditMode.BLOCK
	buttons[1].button_pressed = edit_mode == EditMode.CHARACTER
	_rebuild_mesh()
	_rebuild_grid()
	_rebuild_axis_overlay()
	_center_camera()
	_update_file_label()

func _update_file_label() -> void:
	var name := current_file_path.get_file() if not current_file_path.is_empty() else "(unsaved)"
	file_label.text = "File: " + name + (" *" if _unsaved_changes else "")

func _push_undo() -> void:
	var snapshot: Array = []
	snapshot.resize(grid_x)
	for x in range(grid_x):
		snapshot[x] = []
		snapshot[x].resize(grid_y)
		for y in range(grid_y):
			snapshot[x][y] = []
			snapshot[x][y].resize(grid_z)
			for z in range(grid_z):
				snapshot[x][y][z] = cells[x][y][z].duplicate()
	_undo_stack.append(snapshot)
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	cells = _undo_stack.pop_back()
	_rebuild_mesh()
	if _undo_stack.is_empty():
		_unsaved_changes = false
		_update_file_label()

func _mark_dirty() -> void:
	if not _unsaved_changes:
		_unsaved_changes = true
		_update_file_label()

func _on_confirm_discard() -> void:
	_unsaved_changes = false
	_execute_pending_action()

func _on_confirm_save_first(_action: StringName) -> void:
	confirm_dialog.hide()
	if current_file_path.is_empty():
		save_dialog.current_dir = "res://definitions"
		save_dialog.popup_centered()
	else:
		_save_to_path(current_file_path)
		_execute_pending_action()

func _execute_pending_action() -> void:
	var action := _pending_action
	_pending_action = ""
	match action:
		"new": _do_new()
		"open":
			open_dialog.current_dir = "res://definitions"
			open_dialog.popup_centered()
		"mode_block":
			_do_set_edit_mode(EditMode.BLOCK)
			var buttons := mode_group.get_buttons()
			buttons[0].button_pressed = true
		"mode_character":
			_do_set_edit_mode(EditMode.CHARACTER)
			var buttons := mode_group.get_buttons()
			buttons[1].button_pressed = true
		"import_sprites": _do_import_character_sprites()
		"import_block": _do_import_block_texture()
		"quit": get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _unsaved_changes:
			_pending_action = "quit"
			confirm_dialog.popup_centered()
		else:
			get_tree().quit()

# ─── Mesh Building ───

func _mark_mirror_chunks_dirty(pos: Vector3i) -> void:
	_mark_chunk_dirty_at(pos.x, pos.y, pos.z)
	if _mirror_x:
		var mx := _mirror_pos_x(pos)
		if _in_bounds(mx):
			_mark_chunk_dirty_at(mx.x, mx.y, mx.z)
	if _mirror_z:
		var mz := _mirror_pos_z(pos)
		if _in_bounds(mz):
			_mark_chunk_dirty_at(mz.x, mz.y, mz.z)
	if _mirror_x and _mirror_z:
		var mxz := _mirror_pos_x(_mirror_pos_z(pos))
		if _in_bounds(mxz):
			_mark_chunk_dirty_at(mxz.x, mxz.y, mxz.z)

func _rebuild_mesh() -> void:
	for cx in range(ceili(float(grid_x) / CHUNK_SIZE)):
		for cy in range(ceili(float(grid_y) / CHUNK_SIZE)):
			for cz in range(ceili(float(grid_z) / CHUNK_SIZE)):
				_dirty_chunks[Vector3i(cx, cy, cz)] = true
	_mesh_dirty = true

func _mark_layer_chunks_dirty(layer_y: int) -> void:
	if layer_y < 0 or layer_y >= grid_y:
		return
	var cy := layer_y / CHUNK_SIZE
	for cx in range(ceili(float(grid_x) / CHUNK_SIZE)):
		for cz in range(ceili(float(grid_z) / CHUNK_SIZE)):
			_dirty_chunks[Vector3i(cx, cy, cz)] = true
	_mesh_dirty = true

func _mark_chunk_dirty_at(x: int, y: int, z: int) -> void:
	var key := Vector3i(x / CHUNK_SIZE, y / CHUNK_SIZE, z / CHUNK_SIZE)
	_dirty_chunks[key] = true
	_mesh_dirty = true
	var lx := x % CHUNK_SIZE
	var ly := y % CHUNK_SIZE
	var lz := z % CHUNK_SIZE
	if lx == 0 and key.x > 0:
		_dirty_chunks[key + Vector3i(-1, 0, 0)] = true
	if lx == CHUNK_SIZE - 1 and (key.x + 1) * CHUNK_SIZE < grid_x:
		_dirty_chunks[key + Vector3i(1, 0, 0)] = true
	if ly == 0 and key.y > 0:
		_dirty_chunks[key + Vector3i(0, -1, 0)] = true
	if ly == CHUNK_SIZE - 1 and (key.y + 1) * CHUNK_SIZE < grid_y:
		_dirty_chunks[key + Vector3i(0, 1, 0)] = true
	if lz == 0 and key.z > 0:
		_dirty_chunks[key + Vector3i(0, 0, -1)] = true
	if lz == CHUNK_SIZE - 1 and (key.z + 1) * CHUNK_SIZE < grid_z:
		_dirty_chunks[key + Vector3i(0, 0, 1)] = true
	_mesh_dirty = true

func _rebuild_mesh_now() -> void:
	for key in _dirty_chunks:
		_rebuild_chunk(key)
	_dirty_chunks.clear()

func _rebuild_chunk(key: Vector3i) -> void:
	var x0 := key.x * CHUNK_SIZE
	var y0 := key.y * CHUNK_SIZE
	var z0 := key.z * CHUNK_SIZE
	var x1 := mini(x0 + CHUNK_SIZE, grid_x)
	var y1 := mini(y0 + CHUNK_SIZE, grid_y)
	var z1 := mini(z0 + CHUNK_SIZE, grid_z)
	var new_mesh := BlockMeshBuilder.build_chunk_mesh(cells, grid_x, grid_y, grid_z, x0, y0, z0, x1, y1, z1, CELL_SIZE, ceiling_y)
	var mi: MeshInstance3D
	if _chunk_meshes.has(key):
		mi = _chunk_meshes[key]
	else:
		mi = MeshInstance3D.new()
		_chunk_container.add_child(mi)
		_chunk_meshes[key] = mi
	mi.mesh = new_mesh
	if new_mesh and new_mesh.get_surface_count() > 0:
		mi.set_surface_override_material(0, _cached_opaque_mat)
		if new_mesh.get_surface_count() > 1:
			mi.set_surface_override_material(1, _cached_cutout_mat)
	_update_chunk_ceiling(mi)

func _invalidate_materials() -> void:
	_cached_opaque_mat = _make_ceiling_shader(false)
	_cached_cutout_mat = _make_ceiling_shader(true)
	for mi: MeshInstance3D in _chunk_meshes.values():
		var mesh: ArrayMesh = mi.mesh
		if mesh and mesh.get_surface_count() > 0:
			mi.set_surface_override_material(0, _cached_opaque_mat)
			if mesh.get_surface_count() > 1:
				mi.set_surface_override_material(1, _cached_cutout_mat)
	_update_ceiling_uniforms()

func _make_ceiling_shader(cutout: bool) -> ShaderMaterial:
	var shader := Shader.new()
	var code := "shader_type spatial;\nrender_mode "
	if _preview_mode:
		code += "diffuse_lambert"
	else:
		code += "unshaded"
	if cutout:
		code += ", cull_disabled"
	code += ";\nuniform float ceiling_clip = -1.0;\n"
	code += "varying vec3 world_pos;\n"
	code += "varying vec3 world_normal;\n"
	code += "void vertex() {\n\tworld_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n\tworld_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;\n}\n"
	code += "void fragment() {\n"
	code += "\tif (ceiling_clip >= 0.0 && world_pos.y > ceiling_clip) { discard; }\n"
	# The cell above the ceiling keeps its downward-facing bottom face, which sits
	# exactly on the clip plane and isn't caught by the strict-greater test above.
	# Discard it so it can't z-fight with the baked top cap of the ceiling layer.
	code += "\tif (ceiling_clip >= 0.0 && world_pos.y > ceiling_clip - 0.001 && world_normal.y < -0.5) { discard; }\n"
	if not _preview_mode and not _flat_color_mode:
		code += "\tfloat ny = abs(NORMAL.y);\n"
		code += "\tfloat nx = abs(NORMAL.x);\n"
		code += "\tfloat nz = abs(NORMAL.z);\n"
		code += "\tfloat shade = 1.0;\n"
		code += "\tif (ny > 0.9) { shade = NORMAL.y > 0.0 ? 1.0 : 0.5; }\n"
		code += "\telse if (nx > nz) { shade = 0.8; }\n"
		code += "\telse { shade = 0.7; }\n"
		code += "\tALBEDO = COLOR.rgb * shade;\n"
	else:
		code += "\tALBEDO = COLOR.rgb;\n"
	if cutout:
		code += "\tALPHA = COLOR.a;\n\tALPHA_SCISSOR_THRESHOLD = %.1f;\n" % CellTypes.ALPHA_THRESHOLD
	code += "}\n"
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

func _update_ceiling_uniforms() -> void:
	var clip_val: float = -1.0
	if ceiling_y >= 0:
		clip_val = (ceiling_y + 1) * CELL_SIZE
	for mi: MeshInstance3D in _chunk_meshes.values():
		_update_chunk_ceiling_val(mi, clip_val)

func _update_chunk_ceiling(mi: MeshInstance3D) -> void:
	var clip_val: float = -1.0
	if ceiling_y >= 0:
		clip_val = (ceiling_y + 1) * CELL_SIZE
	_update_chunk_ceiling_val(mi, clip_val)

func _update_chunk_ceiling_val(mi: MeshInstance3D, clip_val: float) -> void:
	var mesh: ArrayMesh = mi.mesh
	if mesh:
		for si in range(mesh.get_surface_count()):
			var mat: ShaderMaterial = mi.get_surface_override_material(si)
			if mat:
				mat.set_shader_parameter("ceiling_clip", clip_val)

func _rebuild_grid() -> void:
	var im := ImmediateMesh.new()
	var wx := grid_x * CELL_SIZE
	var wy := grid_y * CELL_SIZE
	var wz := grid_z * CELL_SIZE
	var fy := floor_y * CELL_SIZE

	# Floor grid at current floor_y
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(Color(0.3, 0.7, 1.0, 0.35))
	for i in range(grid_x + 1):
		var t := i * CELL_SIZE
		im.surface_add_vertex(Vector3(t, fy, 0))
		im.surface_add_vertex(Vector3(t, fy, wz))
	for i in range(grid_z + 1):
		var t := i * CELL_SIZE
		im.surface_add_vertex(Vector3(0, fy, t))
		im.surface_add_vertex(Vector3(wx, fy, t))
	im.surface_end()

	# Bounding box edges
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(Color(0.3, 0.7, 1.0, 0.35))
	var c: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(wx, 0, 0), Vector3(wx, 0, wz), Vector3(0, 0, wz),
		Vector3(0, wy, 0), Vector3(wx, wy, 0), Vector3(wx, wy, wz), Vector3(0, wy, wz),
	]
	for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()

	if ceiling_y >= 0:
		var cy := (ceiling_y + 1) * CELL_SIZE
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		im.surface_set_color(Color(1.0, 0.4, 0.2, 0.5))
		for i in range(grid_x + 1):
			var t := i * CELL_SIZE
			im.surface_add_vertex(Vector3(t, cy, 0))
			im.surface_add_vertex(Vector3(t, cy, wz))
		for i in range(grid_z + 1):
			var t := i * CELL_SIZE
			im.surface_add_vertex(Vector3(0, cy, t))
			im.surface_add_vertex(Vector3(wx, cy, t))
		im.surface_end()

	grid_mesh_instance.mesh = im

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mesh_instance.material_override = mat
