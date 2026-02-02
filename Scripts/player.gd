extends CharacterBody2D

# Movement
const SPEED = 160
const JUMP_FORCE = -400
const GRAVITY = 900
const FALL_GRAVITY = 1200
const MAX_FALL_SPEED = 800
const JUMP_CUT_MULT = 0.35

# Crouch
const CROUCH_SPEED_MULT = 0.4
const CROUCH_SCALE = 0.5
const CROUCH_LOCKOUT = 0.15

# Timers
const COYOTE_TIME = 0.12
const JUMP_BUFFER = 0.12

# Wall movement
const WALL_SLIDE_SPEED = 10000
const WALL_SLIDE_GRAVITY = 3000
const WALL_STICK_TIME = 0.08
const WALL_COYOTE_TIME = 0.04

# Wall jump (away from wall)
const WALL_JUMP_FORCE = Vector2(200, -340)
const WALL_JUMP_LOCK = 0.15

# Wall hop (toward wall)
const WALL_HOP_FORCE = Vector2(200, -380)
const WALL_HOP_LOCK = 0.18

# Dash
const DASH_SPEED = 600
const DASH_DURATION = 0.15
const DASH_BUFFER = 0.1
const ALLOW_DIAGONAL_DASH = true
const GROUND_DASH_COOLDOWN = 0.8

# Dash momentum
const DASH_MOMENTUM_SPEED = 500
const DASH_MOMENTUM_WINDOW = 0.15
const DASH_MOMENTUM_IFRAME = 0.1
const MOMENTUM_JUMP_FORCE_MULT = 1.15


# Timers
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var wall_coyote_timer = 0.0
var wall_hop_timer = 0.0
var wall_jump_timer = 0.0
var wall_stick_timer = 0.0
var crouch_lockout_timer = 0.0

# States
var wall_sticking = false
var wall_dir = 0
var last_wall_dir = 0
var is_crouching = false

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

# Collision shape references
@onready var collision_shape = $CollisionShape2D
var original_height = 0.0


func _ready():
	# Store original height
	if collision_shape and collision_shape.shape:
		if collision_shape.shape is RectangleShape2D:
			original_height = collision_shape.shape.size.y
		elif collision_shape.shape is CapsuleShape2D:
			original_height = collision_shape.shape.height


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
	crouch_lockout_timer -= delta
	
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
	
	# Remember direction
	if move_dir != 0:
		last_move_dir = move_dir
	
	# Update wall info EARLY so we can use it
	if on_wall and not on_floor:
		wall_dir = get_wall_dir()
		last_wall_dir = wall_dir
	
	# Calculate if holding toward wall EARLY
	var holding_toward_wall = false
	if on_wall:
		holding_toward_wall = (input_left and wall_dir == -1) or (input_right and wall_dir == 1)
	
	
	# === CROUCH ===
	
	# Only crouch on ground with Delay
	if on_floor and input_down and not is_dashing and crouch_lockout_timer <= 0:
		if not is_crouching:
			is_crouching = true
			update_crouch_shape(true)
	else:
		if is_crouching:
			# Check if there's room to stand up
			if can_stand_up():
				is_crouching = false
				update_crouch_shape(false)
	
	
	# === DASH ===
	
	if Input.is_action_just_pressed("ui_dash"):
		dash_buffer_timer = DASH_BUFFER
	
	# Start dash (can't dash while on wall)
	if dash_buffer_timer > 0 and has_dash and not is_dashing and not on_wall:
		# Check ground dash cooldown
		if on_floor and ground_dash_cooldown_timer > 0:
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
			
			# Vertical direction
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
			# CHANGE: Make down dash infinite
			if was_diagonal_dash:
				dash_timer = 999.0
			else:
				dash_timer = DASH_DURATION
			dash_buffer_timer = 0
			wall_sticking = false
			coyote_timer = 0
			wall_coyote_timer = 0
			has_dash = false
			has_dash_momentum = false
			momentum_iframe_timer = 0
			momentum_jump_used = false
			
			# Set ground cooldown
			if last_dash_was_grounded:
				ground_dash_cooldown_timer = GROUND_DASH_COOLDOWN
			
			# Uncrouch when dashing if Available
			if is_crouching and can_stand_up():
				is_crouching = false
				update_crouch_shape(false)
	
	
	# === DASHING STATE ===
	
	if is_dashing:
		dash_timer -= delta
		velocity = dash_direction * DASH_SPEED
		
		# Cancel dash if hit wall
		if on_wall and not on_floor:
			is_dashing = false
			velocity.x = 0
			velocity.y = 0
		
		# Cancel dash early if diagonal dash hits ground
		elif on_floor and was_diagonal_dash:
			is_dashing = false
			has_dash_momentum = true
			dash_momentum_direction = dash_direction.x
			ground_touch_timer = DASH_MOMENTUM_WINDOW
			momentum_iframe_timer = DASH_MOMENTUM_IFRAME
			momentum_jump_used = false
			crouch_lockout_timer = CROUCH_LOCKOUT  # Prevent crouching briefly
			velocity.x = dash_direction.x * SPEED * 0.5
			velocity.y = 0
		
		# Normal dash end (CHANGE: only for horizontal dash)
		elif dash_timer <= 0 and not was_diagonal_dash:
			is_dashing = false
			velocity.x = dash_direction.x * SPEED * 0.5
			velocity.y = dash_direction.y * SPEED * 0.5
	
	
	# === NORMAL MOVEMENT ===
	
	else:
		# Cancel momentum if hit wall
		if on_wall and not on_floor and has_dash_momentum:
			has_dash_momentum = false
			ground_touch_timer = 0
			momentum_iframe_timer = 0
			momentum_jump_used = false
			velocity.x = 0
		
		# Refund dash on ground
		if on_floor and not has_dash:
			has_dash = true
		
		# Refund dash on wall
		if on_wall and not on_floor and not has_dash:
			has_dash = true
		
		# Check for directional cancel during momentum
		if has_dash_momentum:
			# Cancel if holding opposite direction
			if move_dir != 0 and sign(move_dir) != sign(dash_momentum_direction):
				has_dash_momentum = false
				ground_touch_timer = 0
				momentum_iframe_timer = 0
				momentum_jump_used = false
			# Cancel if not holding any direction (letting go)
			elif move_dir == 0:
				has_dash_momentum = false
				ground_touch_timer = 0
				momentum_iframe_timer = 0
				momentum_jump_used = false
		
		# Momentum cancellation
		if has_dash_momentum:
			if not on_floor:
				momentum_iframe_timer = DASH_MOMENTUM_IFRAME
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
		
		# Update wall coyote time
		if on_wall and not on_floor:
			wall_coyote_timer = WALL_COYOTE_TIME
		
		
		# === JUMPING ===
		
		if Input.is_action_just_pressed("ui_jump"):
			jump_buffer_timer = JUMP_BUFFER
			# Add brief crouch lockout after any jump
			crouch_lockout_timer = CROUCH_LOCKOUT
		
		# Wall jumps
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
		
		# Ground jump
		elif jump_buffer_timer > 0 and coyote_timer > 0 and not momentum_jump_used and not is_crouching:
			# Apply dash momentum
			if ground_touch_timer > 0 and has_dash_momentum:
				velocity.y = JUMP_FORCE * MOMENTUM_JUMP_FORCE_MULT
				velocity.x = dash_momentum_direction * DASH_MOMENTUM_SPEED
				momentum_iframe_timer = DASH_MOMENTUM_IFRAME
				momentum_jump_used = true
				has_dash = true  # Refund dash on momentum jump
			else:
				# Normal jump without momentum
				velocity.y = JUMP_FORCE
				has_dash_momentum = false
				ground_touch_timer = 0
				momentum_iframe_timer = 0
			
			jump_buffer_timer = 0
			coyote_timer = 0
		
		
		# === WALL STICK ===
		
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
				velocity.y = 0  # Keep at 0 during stick
				if wall_stick_timer <= 0:
					wall_sticking = false
		
		
		# === JUMP CUT ===
		
		if Input.is_action_just_released("ui_jump") and velocity.y < 0:
			velocity.y *= JUMP_CUT_MULT
		
		
		# === GRAVITY ===
		
		if not wall_sticking:
			var is_wall_sliding = on_wall and not on_floor and velocity.y >= 0 and holding_toward_wall
			
			if is_wall_sliding:
				# Apply wall slide gravity
				velocity.y += WALL_SLIDE_GRAVITY * delta
				# Cap at wall slide speed
				if velocity.y > WALL_SLIDE_SPEED:
					velocity.y = WALL_SLIDE_SPEED
			else:
				# Apply normal gravity
				if velocity.y < 0:
					velocity.y += GRAVITY * delta
				else:
					velocity.y += FALL_GRAVITY * delta
				
				# Cap at normal fall speed
				if velocity.y > MAX_FALL_SPEED:
					velocity.y = MAX_FALL_SPEED
		
		
		# === HORIZONTAL MOVEMENT ===
		
		# Apply crouch speed multiplier
		var current_speed = SPEED
		if is_crouching:
			current_speed *= CROUCH_SPEED_MULT
		
		if wall_hop_timer > 0:
			# Locked during first half of wall hop
			if wall_hop_timer < WALL_HOP_LOCK * 0.5:
				velocity.x = lerp(velocity.x, move_dir * current_speed, delta * 8.0)
		
		elif wall_jump_timer > 0:
			# Slight lock on wall jump
			if wall_jump_timer < WALL_JUMP_LOCK * 0.3:
				velocity.x = lerp(velocity.x, move_dir * current_speed, delta * 10.0)
		
		# Keep momentum if active
		elif has_dash_momentum:
			velocity.x = dash_momentum_direction * DASH_MOMENTUM_SPEED
		
		else:
			velocity.x = move_dir * current_speed
	
	
	move_and_slide()


func can_stand_up():
	if not is_crouching or not collision_shape or not collision_shape.shape:
		return true
	
	# Check Head Space
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	
	# Temporary Shape
	var test_shape
	if collision_shape.shape is RectangleShape2D:
		test_shape = RectangleShape2D.new()
		test_shape.size = Vector2(collision_shape.shape.size.x, original_height)
	elif collision_shape.shape is CapsuleShape2D:
		test_shape = CapsuleShape2D.new()
		test_shape.radius = collision_shape.shape.radius
		test_shape.height = original_height
	else:
		return true  # Unknown shape type, allow standing
	
	query.shape = test_shape
	query.collision_mask = collision_mask
	query.exclude = [self]
	
	query.transform = global_transform
	
	var result = space_state.intersect_shape(query, 1)
	
	return result.size() == 0


func update_crouch_shape(crouching: bool):
	if not collision_shape or not collision_shape.shape:
		return
	
	if collision_shape.shape is RectangleShape2D:
		if crouching:
			var old_height = collision_shape.shape.size.y
			collision_shape.shape.size.y = original_height * CROUCH_SCALE
			# Move the shape up so the bottom stays in place
			var height_diff = old_height - collision_shape.shape.size.y
			collision_shape.position.y -= height_diff / 2
		else:
			collision_shape.shape.size.y = original_height
			collision_shape.position.y = 0  # Reset to original position
			
	elif collision_shape.shape is CapsuleShape2D:
		if crouching:
			var old_height = collision_shape.shape.height
			collision_shape.shape.height = original_height * CROUCH_SCALE
			# Move the shape up so the bottom stays in place
			var height_diff = old_height - collision_shape.shape.height
			collision_shape.position.y -= height_diff / 2
		else:
			collision_shape.shape.height = original_height
			collision_shape.position.y = 0  # Reset to original position


func get_wall_dir():
	if is_on_wall_only():
		return -sign(get_wall_normal().x)
	return 0
