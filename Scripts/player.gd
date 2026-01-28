extends CharacterBody2D

# Movement
const SPEED = 160
const JUMP_FORCE = -400
const GRAVITY = 900
const FALL_GRAVITY = 1200
const MAX_FALL_SPEED = 800
const JUMP_CUT_MULT = 0.35

# Timers
const COYOTE_TIME = 0.12
const JUMP_BUFFER = 0.12

# Wall movement
const WALL_SLIDE_SPEED = 400
const WALL_STICK_TIME = 0.08
const WALL_COYOTE_TIME = 0.04

# Wall jump (away from wall)
const WALL_JUMP_FORCE = Vector2(200, -340)
const WALL_JUMP_LOCK = 0.15

# Wall hop (toward wall)
const WALL_HOP_FORCE = Vector2(200, -380)
const WALL_HOP_LOCK = 0.18

# Dash
const DASH_SPEED = 650
const DASH_DURATION = 0.2
const DASH_BUFFER = 0.1
const ALLOW_DIAGONAL_DASH = true
const GROUND_DASH_COOLDOWN = 0.8

# Dash momentum
const DASH_MOMENTUM_SPEED = 500
const DASH_MOMENTUM_WINDOW = 0.15
const DASH_MOMENTUM_IFRAME = 0.1


# Timers
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var wall_coyote_timer = 0.0
var wall_hop_timer = 0.0
var wall_jump_timer = 0.0
var wall_stick_timer = 0.0

# States
var wall_sticking = false
var wall_dir = 0
var last_wall_dir = 0

# Dash
var dash_timer = 0.0
var dash_direction = Vector2.ZERO
var is_dashing = false
var dash_buffer_timer = 0.0
var last_move_dir = 1.0
var has_dash = true
var ground_dash_cooldown_timer = 0.0
var last_dash_was_grounded = false

# Dash momentum
var has_dash_momentum = false
var dash_momentum_direction = 0.0
var ground_touch_timer = 0.0
var momentum_iframe_timer = 0.0
var was_diagonal_dash = false
var momentum_jump_used = false


func _physics_process(delta):
	# Update all timers
	coyote_timer -= delta
	jump_buffer_timer -= delta
	wall_coyote_timer -= delta
	wall_hop_timer -= delta
	wall_jump_timer -= delta
	dash_buffer_timer -= delta
	ground_touch_timer -= delta
	momentum_iframe_timer -= delta
	ground_dash_cooldown_timer -= delta
	
	# Check ground and wall
	var on_floor = is_on_floor()
	var on_wall = is_on_wall_only()
	
	# Get input
	var input_left = Input.is_action_pressed("ui_left")
	var input_right = Input.is_action_pressed("ui_right")
	var input_up = Input.is_action_pressed("ui_up")
	var input_down = Input.is_action_pressed("ui_down")
	
	# Calculate movement direction
	var move_dir = 0.0
	if input_right and not input_left:
		move_dir = 1.0
	elif input_left and not input_right:
		move_dir = -1.0
	
	# Remember which way we're facing
	if move_dir != 0:
		last_move_dir = move_dir
	
	
	# === DASH ===
	
	if Input.is_action_just_pressed("ui_dash"):
		dash_buffer_timer = DASH_BUFFER
	
	# Start dash (can't dash while on wall)
	if dash_buffer_timer > 0 and has_dash and not is_dashing and not on_wall:
		# Check ground dash cooldown only if on ground
		if on_floor and ground_dash_cooldown_timer > 0:
			# Can't dash yet
			pass
		else:
			var dash_x = 0.0
			var dash_y = 0.0
			
			# Horizontal direction
			if input_right and not input_left:
				dash_x = 1.0
			elif input_left and not input_right:
				dash_x = -1.0
			else:
				dash_x = last_move_dir
			
			# Vertical direction (only down, disabled during momentum cancel)
			if ALLOW_DIAGONAL_DASH and not has_dash_momentum:
				# Only allow down diagonal, not up
				if input_down and not input_up:
					dash_y = 1.0
			
			dash_direction = Vector2(dash_x, dash_y).normalized()
			
			# Check if diagonal
			was_diagonal_dash = abs(dash_direction.y) > 0.1
			
			# Track if this dash started on ground
			last_dash_was_grounded = on_floor
			
			# Activate dash
			is_dashing = true
			dash_timer = DASH_DURATION
			dash_buffer_timer = 0
			wall_sticking = false
			coyote_timer = 0
			wall_coyote_timer = 0
			has_dash = false
			has_dash_momentum = false
			momentum_iframe_timer = 0
			momentum_jump_used = false
			
			# Set ground cooldown if dashing from ground
			if last_dash_was_grounded:
				ground_dash_cooldown_timer = GROUND_DASH_COOLDOWN
	
	
	# === DASHING STATE ===
	
	if is_dashing:
		dash_timer -= delta
		velocity = dash_direction * DASH_SPEED
		
		# Cancel dash early if diagonal dash hits ground
		if on_floor and was_diagonal_dash:
			is_dashing = false
			has_dash_momentum = true
			dash_momentum_direction = dash_direction.x
			ground_touch_timer = DASH_MOMENTUM_WINDOW
			momentum_iframe_timer = DASH_MOMENTUM_IFRAME
			momentum_jump_used = false
			velocity.x = dash_direction.x * SPEED * 0.5
			velocity.y = 0
		
		# Normal dash end
		elif dash_timer <= 0:
			is_dashing = false
			velocity.x = dash_direction.x * SPEED * 0.5
			velocity.y = dash_direction.y * SPEED * 0.5
	
	
	# === NORMAL MOVEMENT ===
	
	else:
		# Refund dash on ground (only if not on cooldown)
		if on_floor and not has_dash:
			has_dash = true
		
		# Refund dash on wall
		if on_wall and not on_floor and not has_dash:
			has_dash = true
		
		# Check for directional cancel during momentum
		if has_dash_momentum and move_dir != 0:
			# If trying to move opposite direction, cancel momentum
			if sign(move_dir) != sign(dash_momentum_direction):
				has_dash_momentum = false
				ground_touch_timer = 0
				momentum_iframe_timer = 0
				momentum_jump_used = false
		
		# Momentum cancellation logic
		if has_dash_momentum:
			# If we're in the air, reset iframe
			if not on_floor:
				momentum_iframe_timer = DASH_MOMENTUM_IFRAME
			# If we touch ground and iframe expired, cancel momentum
			elif on_floor and momentum_iframe_timer <= 0:
				has_dash_momentum = false
				ground_touch_timer = 0
				momentum_jump_used = false
		
		# Reset states on floor
		if on_floor:
			coyote_timer = COYOTE_TIME
			wall_coyote_timer = 0
			wall_sticking = false
			wall_hop_timer = 0
			wall_jump_timer = 0
		
		# Update wall info
		if on_wall and not on_floor:
			wall_dir = get_wall_dir()
			last_wall_dir = wall_dir
			wall_coyote_timer = WALL_COYOTE_TIME
		
		
		# === JUMPING ===
		
		if Input.is_action_just_pressed("ui_jump"):
			jump_buffer_timer = JUMP_BUFFER
		
		# Wall jumps (always allowed, cancels momentum)
		if jump_buffer_timer > 0 and wall_coyote_timer > 0:
			var is_holding_toward_wall = (input_left and last_wall_dir == -1) or (input_right and last_wall_dir == 1)
			
			# Wall hop (holding toward wall)
			if is_holding_toward_wall:
				velocity.x = -last_wall_dir * WALL_HOP_FORCE.x
				velocity.y = WALL_HOP_FORCE.y
				wall_hop_timer = WALL_HOP_LOCK
				wall_jump_timer = 0
				jump_buffer_timer = 0
				wall_coyote_timer = 0
				wall_sticking = false
				has_dash_momentum = false
				ground_touch_timer = 0
				momentum_iframe_timer = 0
				momentum_jump_used = false
			
			# Wall jump (away or neutral)
			else:
				velocity.x = -last_wall_dir * WALL_JUMP_FORCE.x
				velocity.y = WALL_JUMP_FORCE.y
				wall_jump_timer = WALL_JUMP_LOCK
				wall_hop_timer = 0
				jump_buffer_timer = 0
				wall_coyote_timer = 0
				wall_sticking = false
				has_dash_momentum = false
				ground_touch_timer = 0
				momentum_iframe_timer = 0
				momentum_jump_used = false
		
		# Ground jump (blocked if momentum jump already used)
		elif jump_buffer_timer > 0 and coyote_timer > 0 and not momentum_jump_used:
			velocity.y = JUMP_FORCE
			jump_buffer_timer = 0
			coyote_timer = 0
			
			# Apply dash momentum if jumping within window
			if ground_touch_timer > 0 and has_dash_momentum:
				velocity.x = dash_momentum_direction * DASH_MOMENTUM_SPEED
				momentum_iframe_timer = DASH_MOMENTUM_IFRAME
				momentum_jump_used = true
				has_dash = true  # Refund dash on momentum jump
		
		
		# === WALL STICK ===
		
		var holding_toward_wall = (input_left and wall_dir == -1) or (input_right and wall_dir == 1)
		
		# Start wall stick
		if on_wall and not on_floor and not wall_sticking and wall_hop_timer <= 0 and wall_jump_timer <= 0 and holding_toward_wall:
			wall_sticking = true
			wall_stick_timer = WALL_STICK_TIME
		
		# Wall stick active
		if wall_sticking:
			if not holding_toward_wall:
				wall_sticking = false
			else:
				wall_stick_timer -= delta
				velocity.y = 0
				if wall_stick_timer <= 0:
					wall_sticking = false
		
		
		# === JUMP CUT ===
		
		if Input.is_action_just_released("ui_jump") and velocity.y < 0:
			velocity.y *= JUMP_CUT_MULT
		
		
		# === GRAVITY ===
		
		if not wall_sticking:
			if velocity.y < 0:
				velocity.y += GRAVITY * delta
			else:
				velocity.y += FALL_GRAVITY * delta
			
			# Cap fall speed
			if velocity.y > MAX_FALL_SPEED:
				velocity.y = MAX_FALL_SPEED
		
		
		# === HORIZONTAL MOVEMENT ===
		
		if wall_hop_timer > 0:
			# Locked during first half of wall hop
			if wall_hop_timer < WALL_HOP_LOCK * 0.5:
				velocity.x = lerp(velocity.x, move_dir * SPEED, delta * 8.0)
		
		elif wall_jump_timer > 0:
			# Slight lock on wall jump
			if wall_jump_timer < WALL_JUMP_LOCK * 0.3:
				velocity.x = lerp(velocity.x, move_dir * SPEED, delta * 10.0)
		
		# Keep momentum if active
		elif has_dash_momentum:
			velocity.x = dash_momentum_direction * DASH_MOMENTUM_SPEED
		
		else:
			velocity.x = move_dir * SPEED
		
		
		# === WALL SLIDE ===
		
		if on_wall and not on_floor and not wall_sticking and velocity.y > 0:
			velocity.y = min(velocity.y, WALL_SLIDE_SPEED)
	
	
	move_and_slide()


func get_wall_dir():
	if is_on_wall_only():
		return -sign(get_wall_normal().x)
	return 0
