class_name DbcDump
extends SceneTree

# Prints each named DBC's columns for its first rows, to place them in dbc_layouts.json:
# godot --headless --path . --script tools/dbc_dump.gd -- ChrRaces Faction

const ROWS: int = 2
# DBC_DUMP_ROWS picks how many rows to print.


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("name a DBC table")
		return quit(1)
	for name: String in args:
		_dump(name)
	quit()


# A name may carry the row to print, as Spell:133.
func _dump(name: String) -> void:
	var wanted: int = int(name.get_slice(":", 1)) if name.contains(":") else -1
	name = name.get_slice(":", 0)
	var rows: int = int(OS.get_environment("DBC_DUMP_ROWS")) if not OS.get_environment("DBC_DUMP_ROWS").is_empty() else ROWS
	var table: WowDBC = WowDBC.open(WowLoader.get_shared().get_archive(), name)
	if table == null:
		return
	print("%s: %d rows, %d fields" % [name, table.row_count(), table.field_count()])
	var first: int = table.find(wanted) if wanted >= 0 else 0
	for row: int in range(first, mini(first + rows, table.row_count())):
		var line: PackedStringArray = []
		for col: int in table.field_count():
			var text: String = table.get_string(row, col)
			var number: int = table.get_uint(row, col)
			var real: float = table.get_float(row, col)
			if not OS.get_environment("DBC_DUMP_RAW").is_empty():
				if number != 0:
					line.append("%d:%d" % [col, number])
			elif not text.is_empty():
				line.append("%d:'%s'" % [col, text])
			elif number != 0:
				line.append("%d:%d" % [col, number] if is_equal_approx(real, float(number))
						else "%d:%d/%.3f" % [col, number, real])
		print("  row %d: %s" % [row, " ".join(line)])
