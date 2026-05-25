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
var paddle_hits: int = 0
var is_paused: bool = false

# Obstacles
var blocks: Array[Dictionary] = []
var block_size: float = 40.0
var block_style: StyleBoxFlat
var damage_queue: Array[Dictionary] = []

func _ready():
    # Find the center of the screen
    center = get_viewport_rect().size / 2.0
    
    # Initialize the programmatic rounded square style
    block_style = StyleBoxFlat.new()
    block_style.corner_radius_top_left = 8
    block_style.corner_radius_top_right = 8
    block_style.corner_radius_bottom_right = 8
    block_style.corner_radius_bottom_left = 8
    
    start_game()

func start_game():
    ball_pos = center
    ball_speed = base_ball_speed
    score = 0
    paddle_hits = 0
    blocks.clear()
    damage_queue.clear()
    
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
            var roll = randf()
            var type = "yellow"
            var max_hp = 2
            
            if roll <= 0.15: # 15% Mine
                type = "mine"
                max_hp = 1
            elif roll <= 0.40: # 25% Orange
                type = "orange"
                max_hp = 3
                
            blocks.append({
                "pos": b_pos,
                "hp": max_hp,
                "max_hp": max_hp,
                "type": type,
                "anim_timer": 0.0,
                "state": "spawning" # spawning -> normal -> disintegrating
            })

func queue_damage(block_index: int, amount: int):
    damage_queue.append({"index": block_index, "amount": amount})

func process_damage():
    # Safely handle potential chain reactions (mines hitting mines)
    var safety_limit = 100
    var loops = 0
    while damage_queue.size() > 0 and loops < safety_limit:
        loops += 1
        var dmg = damage_queue.pop_front()
        var idx = dmg.index
        
        if idx >= 0 and idx < blocks.size():
            var b = blocks[idx]
            if b.state == "normal" or b.state == "spawning":
                b.hp -= dmg.amount
                if b.hp <= 0:
                    b.state = "disintegrating"
                    b.anim_timer = 1.0 # start fade out
                    
                    # Scoring Rules
                    if b.type == "yellow":
                        score += 1
                    elif b.type == "orange":
                        score += 2
                    # Mines add 0 score
                    
                    # Mine AoE Explosion Logic
                    if b.type == "mine":
                        for j in range(blocks.size()):
                            if j != idx:
                                var other = blocks[j]
                                if (other.state == "normal" or other.state == "spawning") and other.pos.distance_to(b.pos) <= block_size * 2.5:
                                    queue_damage(j, 1)

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
        
    # Keyboard movement (Left/Right arrows or A/D) (Inverted)
    var input_axis = Input.get_axis("ui_left", "ui_right")
    if input_axis != 0.0:
        paddle_angle -= input_axis * delta * 4.0
        
    # Process block state animations
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
    
    # Move the ball
    ball_pos += ball_vel * delta
    
    # Ball vs Blocks Collision (Circle vs AABB)
    for i in range(blocks.size()):
        var b = blocks[i]
        if b.state == "normal" or b.state == "spawning":
            var half_size = block_size / 2.0
            var rect_min = b.pos - Vector2(half_size, half_size)
            var rect_max = b.pos + Vector2(half_size, half_size)
            
            var closest = ball_pos.clamp(rect_min, rect_max)
            var dist = ball_pos.distance_to(closest)
            
            if dist <= ball_radius:
                # Bounce
                var normal = Vector2.ZERO
                if ball_pos == closest:
                    normal = (ball_pos - b.pos).normalized() # inside block fallback
                else:
                    normal = (ball_pos - closest).normalized()
                
                # Prevent getting stuck
                if ball_vel.dot(normal) < 0:
                    ball_vel = ball_vel.bounce(normal)
                    ball_pos = closest + normal * (ball_radius + 1.0)
                    ball_speed += 2.0
                    ball_vel = ball_vel.normalized() * ball_speed
                    
                    # Queue damage to this block
                    queue_damage(i, 1)
                    
    # Resolve all pending damage from ball hits and mine explosions
    process_damage()

    # Remove destroyed blocks
    for i in range(blocks_to_remove.size() - 1, -1, -1):
        blocks.remove_at(blocks_to_remove[i])
        
    # Arena/Paddle Collision Logic
    var dist = ball_pos.distance_to(center)
    if dist >= arena_radius - ball_radius:
        var angle_to_ball = (ball_pos - center).angle()
        var diff = wrapf(angle_to_ball - paddle_angle, -PI, PI)
        
        # If the ball hits the neon green arc
        if abs(diff) <= paddle_width / 2.0:
            var normal = (center - ball_pos).normalized()
            ball_vel = ball_vel.bounce(normal)
            
            # Variance
            var variance = randf_range(-0.15, 0.15)
            ball_vel = ball_vel.rotated(variance)
            
            ball_speed += 10.0
            ball_vel = ball_vel.normalized() * ball_speed
            ball_pos = center + (normal * -(arena_radius - ball_radius - 1))
            
            # Handle block spawning based on successful paddle hits
            paddle_hits += 1
            if paddle_hits == 2:
                spawn_blocks(1)
            elif paddle_hits > 2:
                var roll = randf()
                if roll <= 0.05:
                    spawn_blocks(2)
                elif roll <= 0.30:
                    spawn_blocks(1)
        else:
            # Missed
            start_game()
            
    queue_redraw()

func _draw():
    # Background
    draw_rect(get_viewport_rect(), Color.BLACK)
    
    # Arena Outline
    draw_arc(center, arena_radius, 0, TAU, 128, Color.WHITE, 4.0, true)
    
    # Draw Blocks
    for b in blocks:
        var size_mult = 1.0
        var alpha = 1.0
        
        if b.state == "spawning":
            alpha = abs(sin(b.anim_timer * TAU * 3.0))
        elif b.state == "disintegrating":
            size_mult = 1.0 + (1.0 - b.anim_timer) * 0.6
            alpha = b.anim_timer
            
        var current_size = block_size * size_mult
        var rect = Rect2(b.pos - Vector2(current_size/2.0, current_size/2.0), Vector2(current_size, current_size))
        
        # Assign Color based on Type
        var base_color = Color.YELLOW
        if b.type == "orange":
            base_color = Color.ORANGE
        elif b.type == "mine":
            base_color = Color("9932CC") # Purple
            
        var c = base_color
        c.a = alpha
        block_style.bg_color = c
        draw_style_box(block_style, rect)
        
        # Draw "Cracked" lines based on missing HP
        if b.state != "disintegrating":
            var missing_hp = b.max_hp - b.hp
            var crack_color = Color(0, 0, 0, alpha)
            if missing_hp >= 1:
                draw_line(b.pos + Vector2(-current_size*0.3, -current_size*0.4), b.pos + Vector2(current_size*0.1, current_size*0.1), crack_color, 3.0)
            if missing_hp >= 2:
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
    
    # Pause Overlay
    if is_paused:
        draw_rect(get_viewport_rect(), Color(0, 0, 0, 0.5))
        var pause_text = "PAUSED"
        var pause_size = default_font.get_string_size(pause_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 48)
        var pause_pos = center - Vector2(pause_size.x / 2.0, arena_radius + 50)
        draw_string(default_font, pause_pos, pause_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 48, Color.WHITE)
