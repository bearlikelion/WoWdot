class_name MoneyFrame
extends Control

const COPPER_PER_SILVER: int = 100
const COPPER_PER_GOLD: int = 10000
# MoneyFrame_Update: each coin is its text plus the 13 unit icon, 4 apart, laid out from the right.
const ICON_WIDTH: float = 13.0
const SPACING: float = 4.0

@onready var _coins: Array[Control] = [%CopperButton, %SilverButton, %GoldButton]


func set_money(copper: int) -> void:
	var amounts: Array[int] = [
		copper % COPPER_PER_SILVER,
		(copper % COPPER_PER_GOLD) / COPPER_PER_SILVER,
		copper / COPPER_PER_GOLD,
	]
	var right: float = _coins[0].position.x + _coins[0].size.x
	for i: int in _coins.size():
		var coin: Control = _coins[i]
		var label: Label = coin.get_node("Text")
		label.text = str(amounts[i])
		# Copper always shows; silver and gold only once there is some of them or of a larger coin.
		coin.visible = i == 0 or amounts.slice(i).any(func(amount: int) -> bool: return amount > 0)
		if not coin.visible:
			continue
		var width: float = label.get_minimum_size().x + ICON_WIDTH
		coin.size.x = width
		coin.position.x = right - width
		label.position.x = 0.0
		label.size.x = width - ICON_WIDTH
		right = coin.position.x - SPACING
