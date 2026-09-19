class_name SpellBook
extends Control

signal close_requested
signal spell_used(spell_id: int)

const SPELLS_PER_PAGE: int = 12
const MAX_SKILL_LINE_TABS: int = 8
# Each SpellButton's id: the left column holds page slots 1 to 6, the right one 7 to 12.
const BUTTON_IDS: Array[int] = [1, 7, 2, 8, 3, 9, 4, 10, 5, 11, 6, 12]
# PASSIVE_SPELL_FONT_COLOR (0.77, 0.64, 0) as a tint over GameFontNormal's gold.
const PASSIVE_TINT: Color = Color(0.77, 0.78, 1.0)
const PASSIVE_HIGHLIGHT: String = "Interface\\Buttons\\UI-PassiveHighlight.blp"
const WHEEL_BUTTONS: Array[MouseButton] = [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]

var _tabs: Array[Dictionary] = []
var _tab: int = 0
var _pages: Dictionary[int, int] = {}
var _buttons: Array[SpellButton] = []
var _passive_highlight: WowTexture = WowTexture.new()
var _normal_highlight: Texture2D

@onready var _prev: BaseButton = %SpellBookPrevPageButton
@onready var _next: BaseButton = %SpellBookNextPageButton


func _ready() -> void:
	_passive_highlight.file = PASSIVE_HIGHLIGHT
	for i: int in BUTTON_IDS.size():
		var button: SpellButton = get_node("%%SpellButton%d" % (i + 1))
		_buttons.append(button)
		button.pressed.connect(_on_spell_pressed.bind(button))
		button.mouse_entered.connect(_on_spell_entered.bind(button))
		button.mouse_exited.connect(_hide_tooltip.bind(button))
	var highlight: TextureRect = _buttons[0].get_node("HighlightTexture")
	_normal_highlight = highlight.texture
	for i: int in MAX_SKILL_LINE_TABS:
		var tab: WowButton = get_node("%%SpellBookSkillLineTab%d" % (i + 1))
		tab.pressed.connect(_select_tab.bind(i))
		tab.mouse_entered.connect(_on_tab_entered.bind(tab, i))
		tab.mouse_exited.connect(_hide_tooltip.bind(tab))
	# The book tabs switch to the pet book, which waits on pets.
	for i: int in 3:
		(get_node("%%SpellBookFrameTabButton%d" % (i + 1)) as CanvasItem).hide()
	_prev.pressed.connect(_turn_page.bind(-1))
	_next.pressed.connect(_turn_page.bind(1))
	%SpellBookCloseButton.pressed.connect(close_requested.emit)
	WowClient.session.spells_changed.connect(refresh)
	WowClient.cooldowns.changed.connect(_update_cooldowns)
	visibility_changed.connect(refresh)


func _gui_input(event: InputEvent) -> void:
	var wheel: InputEventMouseButton = event as InputEventMouseButton
	if wheel and wheel.pressed and wheel.button_index in WHEEL_BUTTONS:
		accept_event()
		_turn_page(-1 if wheel.button_index == MOUSE_BUTTON_WHEEL_UP else 1)


# SpellBookFrame_Update and SpellButton_UpdateButton for the selected tab and page.
func refresh() -> void:
	if not is_visible_in_tree():
		return
	_tabs = WowAssets.spells.book_tabs(WowClient.session.get_known_spells())
	_tab = mini(_tab, _tabs.size() - 1)
	for i: int in MAX_SKILL_LINE_TABS:
		var tab: WowButton = get_node("%%SpellBookSkillLineTab%d" % (i + 1))
		tab.visible = i < _tabs.size()
		if tab.visible:
			var icon: TextureRect = tab.get_node("NormalTexture")
			icon.texture = _tabs[i]["icon"]
			tab.checked = i == _tab
	var spells: Array[int] = []
	spells.assign(_tabs[_tab]["spells"])
	var page_count: int = maxi(ceili(spells.size() / float(SPELLS_PER_PAGE)), 1)
	var page: int = clampi(_pages.get(_tab, 0), 0, page_count - 1)
	_pages[_tab] = page
	for i: int in _buttons.size():
		var index: int = page * SPELLS_PER_PAGE + BUTTON_IDS[i] - 1
		_show_spell(_buttons[i], spells[index] if index < spells.size() else 0)
	%SpellBookPageText.text = WowStrings.get_text("PAGE_NUMBER") % (page + 1)
	_prev.disabled = page == 0
	_next.disabled = page == page_count - 1
	_update_cooldowns()


func _show_spell(button: SpellButton, spell: int) -> void:
	button.spell_id = spell
	button.disabled = spell == 0
	var prefix: String = "%" + button.name
	var icon: TextureRect = get_node(prefix + "IconTexture")
	var spell_name: Label = get_node(prefix + "SpellName")
	var rank: Label = get_node(prefix + "SubSpellName")
	for part: CanvasItem in [icon, spell_name, rank]:
		part.visible = spell != 0
	if spell == 0:
		return
	var passive: bool = WowAssets.spells.is_passive(spell)
	icon.texture = WowAssets.spells.icon(spell)
	spell_name.text = WowAssets.spells.spell_name(spell)
	spell_name.self_modulate = PASSIVE_TINT if passive else Color.WHITE
	rank.text = WowAssets.spells.rank(spell)
	var border: CanvasItem = button.get_node("NormalTexture")
	var highlight: TextureRect = button.get_node("HighlightTexture")
	border.self_modulate = Color.BLACK if passive else Color.WHITE
	highlight.texture = _passive_highlight if passive else _normal_highlight


func _update_cooldowns() -> void:
	for button: SpellButton in _buttons:
		var cooldown: WowCooldown = get_node("%" + button.name + "Cooldown")
		var timer: Vector2i = WowClient.cooldowns.get_cooldown(button.spell_id) \
		if button.spell_id else Vector2i.ZERO
		if timer.x + timer.y > Time.get_ticks_msec():
			cooldown.start(timer.x, timer.y)
		else:
			cooldown.stop()


func _select_tab(tab: int) -> void:
	_tab = tab
	refresh()


func _turn_page(step: int) -> void:
	_pages[_tab] = _pages.get(_tab, 0) + step
	refresh()


# SpellButton_OnClick casts; passive spells do nothing.
func _on_spell_pressed(button: SpellButton) -> void:
	if button.spell_id and not WowAssets.spells.is_passive(button.spell_id):
		spell_used.emit(button.spell_id)


func _on_spell_entered(button: SpellButton) -> void:
	if button.spell_id and GameTooltip.current:
		GameTooltip.current.set_spell(button, button.spell_id, GameTooltip.TooltipAnchor.RIGHT)


func _on_tab_entered(tab: WowButton, index: int) -> void:
	if GameTooltip.current and index < _tabs.size():
		GameTooltip.current.begin(tab, GameTooltip.TooltipAnchor.RIGHT, tab)
		GameTooltip.current.add_line(_tabs[index]["name"])
		GameTooltip.current.present()


func _hide_tooltip(owner: Control) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(owner)
