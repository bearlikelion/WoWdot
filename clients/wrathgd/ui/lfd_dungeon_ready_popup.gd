class_name LFDDungeonReadyPopup
extends Control

const MEMBERS: int = 5
const WAITING: String = "Interface\\RaidFrame\\ReadyCheck-Waiting.blp"
const READY: String = "Interface\\RaidFrame\\ReadyCheck-Ready.blp"
const NOT_READY: String = "Interface\\RaidFrame\\ReadyCheck-NotReady.blp"

@onready var _finder: DungeonFinder = WowClient.dungeon_finder


func _ready() -> void:
	%LFDDungeonReadyDialogEnterDungeonButton.pressed.connect(_finder.answer_proposal.bind(true))
	%LFDDungeonReadyDialogLeaveQueueButton.pressed.connect(_finder.answer_proposal.bind(false))
	%LFDDungeonReadyDialogCloseButton.pressed.connect(hide)
	%LFDDungeonReadyStatusCloseButton.pressed.connect(hide)
	%LFDDungeonReadyDialogInstanceInfoFrame.hide()
	%LFDDungeonReadyDialogRandomInProgressFrame.hide()
	%LFDDungeonReadyDialogRewardsFrame.hide()
	_finder.proposal_updated.connect(refresh)


func refresh() -> void:
	var proposal: Dictionary = _finder.proposal
	if proposal.get("state", -1) != DungeonFinder.ProposalState.INITIATING:
		hide()
		return
	var players: Array = proposal["players"]
	var me: Dictionary = {}
	for player: Dictionary in players:
		if player["self"]:
			me = player
	show()
	%LFDDungeonReadyDialog.visible = not me.get("answered", false)
	%LFDDungeonReadyStatus.visible = me.get("answered", false)
	var role: DungeonFinder.Role = LFGArt.main_role(me.get("role", 0))
	%LFDDungeonReadyDialogLabel.text = WowStrings.get_text("RANDOM_DUNGEON_IS_READY")
	%LFDDungeonReadyDialogRoleLabel.text = WowStrings.get_text(LFGArt.NAMES[role])
	LFGArt.icon(%LFDDungeonReadyDialogRoleIconTexture, role)
	%LFDDungeonReadyDialogRoleIconLeaderIcon.visible = \
			me.get("role", 0) & DungeonFinder.Role.LEADER != 0
	for i: int in MEMBERS:
		var button: Control = get_node("%%LFDDungeonReadyStatusPlayer%d" % (i + 1))
		button.visible = i < players.size()
		if not button.visible:
			continue
		var player: Dictionary = players[i]
		var status: WowTexture = WowTexture.new()
		status.file = WAITING if not player["answered"] \
				else READY if player["accepted"] else NOT_READY
		var prefix: String = "%%LFDDungeonReadyStatusPlayer%d" % (i + 1)
		(get_node(prefix + "StatusIcon") as TextureRect).texture = status
		LFGArt.icon(get_node(prefix + "Texture"), LFGArt.main_role(player["role"]))

