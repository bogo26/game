extends "res://tests/test_case.gd"


func test_xp_curve_grows_with_level() -> void:
	var previous := 0
	for level in range(1, 40):
		var needed := XpCurve.xp_to_next(level)
		assert_true(needed > previous, "level %d needs more xp than level %d" % [level, level - 1])
		previous = needed


func test_xp_curve_scales_with_players() -> void:
	assert_true(XpCurve.xp_to_next(5, 4) > XpCurve.xp_to_next(5, 1))
	assert_eq(XpCurve.xp_to_next(5, 0), XpCurve.xp_to_next(5, 1), "player count clamps to 1")


func test_radial_deadzone() -> void:
	assert_eq(PlayerInput.radial_deadzone(Vector2(0.1, 0.1), 0.2), Vector2.ZERO)
	assert_vec_near(PlayerInput.radial_deadzone(Vector2(1, 0), 0.2), Vector2(1, 0))
	var half := PlayerInput.radial_deadzone(Vector2(0, 0.6), 0.2)
	assert_near(half.length(), 0.5, 0.0001, "rescaled past the deadzone")
	assert_near(half.x, 0.0)


func test_player_input_edges_and_repeat() -> void:
	var p := PlayerInput.new(0)
	p.device = PlayerInput.DEVICE_BOT
	p.poll(0.016)
	p.set_action(PlayerInput.Action.ATTACK, true)
	assert_true(p.just_pressed(PlayerInput.Action.ATTACK))
	p.poll(0.016)
	assert_true(p.is_down(PlayerInput.Action.ATTACK))
	assert_false(p.just_pressed(PlayerInput.Action.ATTACK), "held, not a new press")
	p.set_action(PlayerInput.Action.ATTACK, false)
	assert_true(p.just_released(PlayerInput.Action.ATTACK))

	# UI repeat: first press fires, then repeats after the delay.
	p.set_action(PlayerInput.Action.UI_DOWN, true)
	p.poll(0.0)
	var fired := 0
	for i in 60:  # one simulated second at 60 Hz
		p.poll(1.0 / 60.0)
		if p.ui_pressed(PlayerInput.Action.UI_DOWN):
			fired += 1
	assert_true(fired >= 5 and fired <= 8, "repeat count %d in 1s" % fired)
