class_name VehicleSeatIndicator
extends Control

const BUTTONS: int = 8
# VehicleSeatIndicator_SetUpVehicle hard-codes the art's size.
const ART_SIZE: float = 128.0
const HIGHLIGHT_ALPHA: float = 0.5
const PULSE_SECONDS: float = 2.0

# Each shown button's seat on the vehicle, as the wire numbers them.
var _button_seats: Array[int] = []
var _indicator: int = 0
var _pulsed: bool = false
var _indicators: WowDBC
var _indicator_seats: WowDBC


func _ready() -> void:
	_indicators = WowDBC.open(WowAssets.archive, "VehicleUIIndicator")
	_indicator_seats = WowDBC.open(WowAssets.archive, "VehicleUIIndSeat")
	for i: int in BUTTONS:
		var button: BaseButton = _button(i)
		button.pressed.connect(_on_seat_pressed.bind(i))
		button.mouse_entered.connect(_on_seat_hovered.bind(i))
		button.mouse_exited.connect(_on_seat_left.bind(i))
		var highlight: CanvasItem = _part(i, "Highlight")
		highlight.hide()
		highlight.modulate.a = HIGHLIGHT_ALPHA
	WowClient.vehicle.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var vehicle: Vehicle = WowClient.vehicle
	var indicator: int = vehicle.indicator() if vehicle.riding else 0
	visible = indicator != 0
	if not visible:
		_indicator = 0
		_pulsed = false
		return
	if indicator != _indicator:
		_set_up(indicator)
	var me: int = WowClient.session.get_player_guid()
	for i: int in _button_seats.size():
		var occupant: int = vehicle.occupant(_button_seats[i])
		_part(i, "PlayerIcon").visible = occupant == me
		_part(i, "AllyIcon").visible = occupant != 0 and occupant != me
		if occupant == me and not _pulsed:
			_pulsed = true
			_pulse(_part(i, "PulseTexture"))


# VehicleSeatIndicator_SetUpVehicle: the vehicle's seat map, a button centred on each seat.
func _set_up(indicator: int) -> void:
	_indicator = indicator
	var row: int = _indicators.find(indicator)
	var texture: WowTexture = WowTexture.new()
	texture.file = _indicators.get_string(row, "BackgroundTexture") if row >= 0 else ""
	(%VehicleSeatIndicatorBackgroundTexture as TextureRect).texture = texture
	_button_seats.clear()
	for seat_row: int in _indicator_seats.row_count():
		if _indicator_seats.get_uint(seat_row, "VehicleUIIndicatorID") != indicator \
		or _button_seats.size() >= BUTTONS:
			continue
		var button: Control = _button(_button_seats.size())
		var center: Vector2 = Vector2(
			_indicator_seats.get_float(seat_row, "XPos"),
			_indicator_seats.get_float(seat_row, "YPos"),
		) * ART_SIZE
		button.position = center - button.size / 2.0
		_button_seats.append(
			WowClient.vehicle.virtual_seat(_indicator_seats.get_uint(seat_row, "VirtualSeatIndex"))
		)
	for i: int in BUTTONS:
		_button(i).visible = i < _button_seats.size()


# SeatIndicator_Pulse: the player's seat flashes for two seconds once it sits down.
func _pulse(pulse: CanvasItem) -> void:
	pulse.show()
	var tween: Tween = create_tween()
	tween.tween_method(
		func(elapsed: float) -> void: pulse.modulate.a = absf(sin(elapsed * TAU)),
		0.0, PULSE_SECONDS, PULSE_SECONDS,
	)
	tween.tween_callback(pulse.hide)


func _button(index: int) -> BaseButton:
	return get_node("%%VehicleSeatIndicatorButton%d" % (index + 1))


func _part(index: int, part: String) -> CanvasItem:
	return get_node("%%VehicleSeatIndicatorButton%d%s" % [index + 1, part])


func _on_seat_pressed(index: int) -> void:
	WowClient.vehicle.switch_seat(_button_seats[index])


# VehicleSeatIndicatorButton_OnEnter: an occupied seat names who sits there; a free one lights up.
func _on_seat_hovered(index: int) -> void:
	var occupant: int = WowClient.vehicle.occupant(_button_seats[index])
	if occupant:
		if GameTooltip.current:
			GameTooltip.current.set_text(
				_button(index), WowClient.session.get_object_name(occupant)
			)
		return
	_part(index, "Highlight").visible = WowClient.vehicle.can_switch_seats()


func _on_seat_left(index: int) -> void:
	_part(index, "Highlight").hide()
	if GameTooltip.current:
		GameTooltip.current.hide_for(_button(index))
