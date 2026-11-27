## Rhythm Game briefing extension adding per-player difficulty selection inside %ExtraSlot.
extends "res://games/assets/GP_default_ui/briefing/briefing_view.gd"

@onready var _choice_row: HBoxContainer = %ChoiceRow
@onready var _choice_title: Label = %ChoiceTitle
@onready var _choice: OptionButton = %PlayerChoice


func _ready() -> void:
	_choice.get_popup().max_size = Vector2i(1920, 320)
	_choice.item_selected.connect(func(index: int) -> void: choice_selected.emit(_choice.get_item_text(index)))
	super._ready()


func set_choice(value: String) -> void:
	if not is_node_ready():
		return
	for index: int in range(_choice.item_count):
		if _choice.get_item_text(index) == value:
			_choice.select(index)
			return


func _shortcut_input(event: InputEvent) -> void:
	if _choice != null and _choice.get_popup().visible:
		return
	super._shortcut_input(event)


func _render_content() -> void:
	super._render_content()
	var choice_options: Array = _content.get("choice_options", [])
	var has_options: bool = not choice_options.is_empty()
	_choice_row.visible = has_options
	_extra_slot.visible = has_options
	_choice_title.text = str(_content.get("choice_label", "难度"))
	var chosen: String = _choice.get_item_text(_choice.selected) if _choice.selected >= 0 else str(_content.get("choice_default", ""))
	_choice.clear()
	for option: Variant in choice_options:
		_choice.add_item(str(option))
	set_choice(chosen)


func _render_state() -> void:
	super._render_state()
	_choice.disabled = not _can_submit_ready() or _local_ready
