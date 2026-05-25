extends Node2D

# Arena Setup
var center: Vector2
var arena_radius: float = 300.0

# Ball Setup
var ball_pos: Vector2
var ball_vel: Vector2
var ball_radius: float = 10.0
var base_ball_speed: float = 250.0
var ball_speed: float = 250.0

# Paddle Setup
var paddle_angle: float = 0.0 # In radians
var paddle_width: float = deg_to_rad(45.0)
var paddle_thickness: float = 12.0

# Game State
var score: int = 0
var is_paused: bool = false

# Obstacles
var blocks: Array[Dictionary] = []
var block_size: float = 40.0
var block_style: StyleBoxFlat

func _ready():
    # Find the center of the screen
    center = get_viewport_rect().size / 2.0
    
    # Initialize the programmatic rounded square style
    block_style = StyleBoxFlat.new()
    block_style.bg_color = Color.YELLOW
    block_style.corner_radius_top_left = 8
    block_style.corner_radius_top_right = 8
    block_style.corner_radius_bottom_right = 8
    block_style.corner_radius_bottom_left = 8
    
    start_game()

func start_game():
    ball_pos = center
    ball_speed = base_ball_speed
    score = 0
    blocks.clear()
    
    # Shoot the ball in a random direction
    var random_angle = randf_range(0, TAU)
    ball_vel = Vector2(cos(random_angle), sin(random_angle)) * ball_speed

func spawn_blocks(count: int):
    for i in range(count):
        var valid_pos = false
        var tries = 0
        var b_pos = Vector2.ZERO
        
        while not valid_pos and tries < 50:
            # Spawn near the middle (within a radius of 150)
            var r = randf_range(0, 150)
            var ang = randf_range(0, TAU)
            b_pos = center + Vector2(cos(ang), sin(ang)) * r
            
            # Check overlap with other blocks
            var overlap = false
            for b in blocks:
                if b.pos.distance_to(b_pos) < block_size * 1.5:
                    overlap = true
                    break
            
            # Check distance to ball to avoid spawning directly on it
            if b_pos.distance_to(ball_pos) < block_size * 2:
                overlap = true
                
            if not overlap:
                valid_pos = true
            tries += 1
            
        if valid_pos:
            blocks.append({
                "pos": b_pos,
                "hp": 2,
                "anim_timer": 0.0,
                "state": "spawning" # spawning -> normal -> disintegrating
            })

func _input(event):
    if event.is_action_pressed("ui_accept"): # Press Space/Enter to pause
        is_paused = !is_paused
        
    if is_paused:
        return
        
    # Standard mouse scroll wheel
    if event is InputEventMouseButton and event.is_pressed():
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            paddle_angle -= 0.15
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            paddle_angle += 0.15
    # Mac Trackpad scroll (Horizontal and Vertical)
    elif event is InputEventPanGesture:
        var raw_delta = event.delta.y + event.delta.x
        paddle_angle += sign(raw_delta) * pow(abs(raw_delta), 1.5) * 0.08

func _process(delta):
    if is_paused:
        queue_redraw()
        return
        
    # Keyboard movement (Left/Right arrows or A/D)
    var input_axis = Input.get_axis("ui_left", "ui_right")
    if input_axis != 0.0:
        paddle_angle -= input_axis * delta * 4.0
        
    # Block Logic & Collision
    var blocks_to_remove = []
    for i in range(blocks.size()):
        var b = blocks[i]
        
        if b.state == "spawning":
            b.anim_timer += delta * 1.5
            if b.anim_timer >= 1.0:
                b.state = "normal"
                b.anim_timer = 1.0
        elif b.state == "disintegrating":
            b.anim_timer -= delta * 3.0
            if b.anim_timer <= 0.0:
                blocks_to_remove.append(i)
                continue
                
        # Collision (Circle vs AABB)
        if b.state == "normal" or b.state == "spawning":
            var half_size = block_size / 2.0
            var rect_min = b.pos - Vector2(half_size, half_size)
            var rect_max = b.pos + Vector2(half_size, half_size)
            
            var closest = ball_pos.clamp(rect_min, rect_max)
            var dist = ball_pos.distance_to(closest)
            
            if dist <= ball_radius:
                # Hit Block
                b.hp -= 1
                if b.hp <= 0:
                    b.state = "disintegrating"
                    b.anim_timer = 1.0 # start fade out
                
                # Calculate bounce normal off flat edge or corner
                var normal = Vector2.ZERO
                if ball_pos == closest:
                    normal = (ball_pos - b.pos).normalized() # inside block fallback
                else:
                    normal = (ball_pos - closest).normalized()
                
                # Prevent getting stuck by only bouncing if moving into the block
                if ball_vel.dot(normal) < 0:
                    ball_vel = ball_vel.bounce(normal)
                    ball_pos = closest + normal * (ball_radius + 1.0)
                    # Tiny speedup for hitting obstacles
                    ball_speed += 2.0
                    ball_vel = ball_vel.normalized() * ball_speed

    # Remove destroyed blocks
    for i in range(blocks_to_remove.size() - 1, -1, -1):
        blocks.remove_at(blocks_to_remove[i])
        
    # Move the ball
    ball_pos += ball_vel * delta
    
    # Arena/Paddle Collision Logic
    var dist = ball_pos.distance_to(center)
    if dist >= arena_radius - ball_radius:
        var angle_to_ball = (ball_pos - center).angle()
        
        # Calculate angular difference between ball and paddle
        var diff = wrapf(angle_to_ball - paddle_angle, -PI, PI)
        
        # If the ball hits the neon green arc
        if abs(diff) <= paddle_width / 2.0:
            var normal = (center - ball_pos).normalized()
            ball_vel = ball_vel.bounce(normal)
            
            # ADD VARIANCE: slightly rotate the velocity to prevent straight loops
            var variance = randf_range(-0.15, 0.15)
            ball_vel = ball_vel.rotated(variance)
            
            # Increase speed on hit
            ball_speed += 10.0
            ball_vel = ball_vel.normalized() * ball_speed
            
            # Nudge the ball back inside the circle to prevent sticking
            ball_pos = center + (normal * -(arena_radius - ball_radius - 1))
            
            # Increment score & Handle block spawning
            score += 1
            if score == 2:
                spawn_blocks(1)
            elif score > 2:
                var roll = randf()
                if roll <= 0.05:
                    spawn_blocks(2)
                elif roll <= 0.30: # 5% to 30% = 25% chance
                    spawn_blocks(1)
        else:
            # Player missed, restart immediately
            start_game()
            
    # Force the engine to redraw the graphics every frame
    queue_redraw()

func _draw():
    # Draw Black Void Background
    draw_rect(get_viewport_rect(), Color.BLACK)
    
    # Draw White Arena Outline
    draw_arc(center, arena_radius, 0, TAU, 128, Color.WHITE, 4.0, true)
    
    # Draw Blocks
    for b in blocks:
        var size_mult = 1.0
        var alpha = 1.0
        
        if b.state == "spawning":
            # Rapid blink (blinks 3 times over 1 second)
            alpha = abs(sin(b.anim_timer * TAU * 3.0))
        elif b.state == "disintegrating":
            # Expand and fade
            size_mult = 1.0 + (1.0 - b.anim_timer) * 0.6
            alpha = b.anim_timer
            
        var current_size = block_size * size_mult
        var rect = Rect2(b.pos - Vector2(current_size/2.0, current_size/2.0), Vector2(current_size, current_size))
        
        var c = Color.YELLOW
        c.a = alpha
        block_style.bg_color = c
        draw_style_box(block_style, rect)
        
        # Draw "Cracked" lines if hp is 1
        if b.hp == 1 and b.state != "disintegrating":
            var crack_color = Color(0, 0, 0, alpha)
            draw_line(b.pos + Vector2(-current_size*0.3, -current_size*0.4), b.pos + Vector2(current_size*0.1, current_size*0.1), crack_color, 3.0)
            draw_line(b.pos + Vector2(current_size*0.1, current_size*0.1), b.pos + Vector2(-current_size*0.2, current_size*0.4), crack_color, 2.0)
    
    # Draw Red Ball
    draw_circle(ball_pos, ball_radius, Color.RED)
    
    # Draw Neon Green Paddle
    var start_angle = paddle_angle - paddle_width / 2.0
    var end_angle = paddle_angle + paddle_width / 2.0
    draw_arc(center, arena_radius, start_angle, end_angle, 64, Color("00ff00"), paddle_thickness, true)
    
    # Draw Score
    var default_font = ThemeDB.fallback_font
    var font_size = 64
    var text_size = default_font.get_string_size(str(score), HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
    var text_pos = center - Vector2(text_size.x / 2.0, -text_size.y / 4.0)
    draw_string(default_font, text_pos, str(score), HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)
    
    # Draw Pause Overlay
    if is_paused:
        draw_rect(get_viewport_rect(), Color(0, 0, 0, 0.5))
        var pause_text = "PAUSED"
        var pause_size = default_font.get_string_size(pause_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 48)
        var pause_pos = center - Vector2(pause_size.x / 2.0, arena_radius + 50)
        draw_string(default_font, pause_pos, pause_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 48, Color.WHITE)
