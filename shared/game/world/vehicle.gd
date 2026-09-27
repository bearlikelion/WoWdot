class_name Vehicle
extends RefCounted

# The player boarded, left or changed seats on a vehicle, or took or lost its controls.
signal changed

const SEATS: int = 8
const SEAT_FLAG_CAN_SWITCH: int = 0x04000000

# The vehicle the player drives, or 0; movement goes out under its guid while set.
var driving: int = 0
# The vehicle the player sits in, driving or not, and the seat it holds there.
var riding: int = 0
var seat: int = -1

var _session: WowSession
var _vehicles: WowDBC
var _seats: WowDBC


func _init(session: WowSession) -> void:
	_session = session
	session.packet_received.connect(_on_packet_received)
	session.object_moved.connect(_on_object_moved)
	session.objects_destroyed.connect(func(_guids: PackedInt64Array) -> void: _update_riding())


## The vehicle whose bars and seats the player sees: the one it sits in, or else the one it drives.
func current() -> int:
	return riding if riding else driving


func leave() -> void:
	_session.send_packet("CMSG_REQUEST_VEHICLE_EXIT", PackedByteArray())


# The server checks the seat is free and that the player's own seat lets it move.
func switch_seat(to_seat: int) -> void:
	var payload: PackedByteArray = PacketReader.pack_guid(current())
	payload.append(to_seat)
	_session.send_packet("CMSG_REQUEST_VEHICLE_SWITCH_SEAT", payload)


## Who sits in a seat of the current vehicle, or 0.
func occupant(seat_index: int) -> int:
	var vehicle: int = current()
	for guid: int in _session.get_object_guids():
		var transport: Dictionary = _session.get_object_transport(guid)
		if transport.get("guid", 0) == vehicle and transport.get("seat", -1) == seat_index:
			return guid
	return 0


## Vehicle.dbc's VehicleUIIndicator for the seat map, or 0 for a vehicle that shows none.
func indicator() -> int:
	var row: int = _vehicle_row()
	return _vehicles.get_uint(row, "SeatIndicatorType") if row >= 0 else 0


## The seat a VehicleUIIndSeat virtual index names: counted from 1 over the seats the vehicle has.
func virtual_seat(virtual_index: int) -> int:
	var row: int = _vehicle_row()
	if row < 0:
		return -1
	var counted: int = 0
	for i: int in SEATS:
		if _vehicles.get_uint(row, "SeatID%d" % i) != 0:
			counted += 1
			if counted == virtual_index:
				return i
	return -1


func can_switch_seats() -> bool:
	var row: int = _vehicle_row()
	if row < 0 or seat < 0 or seat >= SEATS:
		return false
	var seat_row: int = _seats.find(_vehicles.get_uint(row, "SeatID%d" % seat))
	return seat_row >= 0 and _seats.get_uint(seat_row, "Flags") & SEAT_FLAG_CAN_SWITCH != 0


func _vehicle_row() -> int:
	if _vehicles == null:
		_vehicles = WowDBC.open(WowAssets.archive, "Vehicle")
		_seats = WowDBC.open(WowAssets.archive, "VehicleSeat")
	var vehicle_id: int = _session.get_object_vehicle_id(current())
	return _vehicles.find(vehicle_id) if vehicle_id else -1


func _on_object_moved(guid: int, _movement: Dictionary) -> void:
	if guid == _session.get_player_guid():
		_update_riding()
	elif riding and _session.get_object_transport(guid).get("guid", 0) == riding:
		changed.emit()


# A boat carries the player as a transport too; only a unit with a vehicle id is a vehicle.
func _update_riding() -> void:
	var transport: Dictionary = _session.get_object_transport(_session.get_player_guid())
	var now: int = transport.get("guid", 0)
	if now and _session.get_object_vehicle_id(now) == 0:
		now = 0
	var now_seat: int = transport.get("seat", -1) if now else -1
	if now == riding and now_seat == seat:
		return
	riding = now
	seat = now_seat
	changed.emit()


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode != "SMSG_CLIENT_CONTROL_UPDATE" or not PacketReader.wotlk:
		return
	var reader: PacketReader = PacketReader.new(payload)
	var guid: int = reader.packed_guid()
	var allowed: bool = reader.u8() != 0
	var me: int = _session.get_player_guid()
	var now: int = driving
	if guid == me and allowed:
		now = 0
	elif guid != me and allowed:
		now = guid
	if now == driving:
		return
	driving = now
	var mover: int = driving if driving else me
	_session.set_mover(mover)
	# The stock client names its new mover back, which AzerothCore checks against its own.
	var named: PackedByteArray = PackedByteArray()
	named.resize(8)
	named.encode_u64(0, mover)
	_session.send_packet("CMSG_SET_ACTIVE_MOVER", named)
	changed.emit()
