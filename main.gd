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
var lives: int = 3
var is_paused: bool = false
var arena_flash_timer: float = 0.0
var is_game_over: bool = false
var game_over_timer: float = 0.0

# Obstacles
var blocks: Array[Dictionary] = []
var block_size: float = 40.0
var block_style: StyleBoxFlat
var damage_queue: Array[Dictionary] = []

# Powerups
var field_powerups: Array[Dictionary] = []
var active_powerups: Array[Dictionary] = []
var splash_text_timer: float = 0.0
var splash_text: String = ""

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
    lives = 3
    is_game_over = false
    blocks.clear()
    damage_queue.clear()
    field_powerups.clear()
    active_powerups.clear()
    splash_text_timer = 0.0
    
    # Shoot the ball in a random direction
    var random_angle = randf_range(0, TAU)
    ball_vel = Vector2(cos(random_angle), sin(random_angle)) * ball_speed

func get_rounded_triangle_points(draw_pos: Vector2, size: float) -> PackedVector2Array:
    var r = size * 0.3 # corner radius
    # Triangle centers
    var c1 = draw_pos + Vector2(0, -size + r)
    var c2 = draw_pos + Vector2(-size + r, size - r)
    var c3 = draw_pos + Vector2(size - r, size - r)
    
    var all_pts = PackedVector2Array()
    var steps = 12
    for i in range(steps):
        var ang = (i / float(steps)) * TAU
        var dir = Vector2(cos(ang), sin(ang))
        all_pts.append(c1 + dir * r)
        all_pts.append(c2 + dir * r)
        all_pts.append(c3 + dir * r)
        
    return Geometry2D.convex_hull(all_pts)

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
            
            if roll <= 0.15: # 15% Life
                type = "life"
                max_hp = 1
            elif roll <= 0.30: # 15% Mine
                type = "mine"
                max_hp = 1
            elif roll <= 0.55: # 25% Orange
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
    var multi_count = 0
    for p in active_powerups:
        if p.type == "2x":
            multi_count += 1
    var current_multiplier = int(pow(2, multi_count))
    
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
                        score += 1 * current_multiplier
                    elif b.type == "orange":
                        score += 2 * current_multiplier
                    elif b.type == "life":
                        if lives < 3:
                            lives += 1
                    # Mines add 0 score
                    
                    # Mine AoE Explosion Logic
                    if b.type == "mine":
                        for j in range(blocks.size()):
                            if j != idx:
                                var other = blocks[j]
                                if (other.state == "normal" or other.state == "spawning") and other.pos.distance_to(b.pos) <= block_size * 3.0:
                                    queue_damage(j, 1)

func predict_trajectory(max_bounces: int) -> Array[Vector2]:
    var points: Array[Vector2] = []
    points.append(ball_pos)
    
    var sim_pos = ball_pos
    var sim_vel = ball_vel
    var sim_delta = 0.016
    var bounces = 0
    var max_steps = 300 # Roughly 4.8 seconds of simulation
    
    for step in range(max_steps):
        sim_pos += sim_vel * sim_delta
        var bounced = false
        
        # Block check
        for b in blocks:
            if b.state == "normal" or b.state == "spawning":
                var half_size = block_size / 2.0
                var rect_min = b.pos - Vector2(half_size, half_size)
                var rect_max = b.pos + Vector2(half_size, half_size)
                
                var closest = sim_pos.clamp(rect_min, rect_max)
                if sim_pos.distance_to(closest) <= ball_radius:
                    if b.type == "life":
                        continue
                        
                    var normal = Vector2.ZERO
                    if sim_pos == closest:
                        normal = (sim_pos - b.pos).normalized()
                    else:
                        normal = (sim_pos - closest).normalized()
                        
                    if sim_vel.dot(normal) < 0:
                        sim_vel = sim_vel.bounce(normal)
                        bounced = true
                        break
                        
        if not bounced:
            # Arena check
            if sim_pos.distance_to(center) >= arena_radius - ball_radius:
                var normal = (center - sim_pos).normalized()
                if sim_vel.dot(normal) < 0:
                    sim_vel = sim_vel.bounce(normal)
                    bounced = true
                    
        if bounced:
            points.append(sim_pos)
            bounces += 1
            if bounces >= max_bounces:
                break
                
    if bounces < max_bounces:
        points.append(sim_pos)
        
    return points

func _input(event):
    if event.is_action_pressed("ui_accept"): # Press Space/Enter to pause
        is_paused = !is_paused
        
    if is_paused or is_game_over:
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
        
    if is_game_over:
        game_over_timer -= delta
        if game_over_timer <= 0.0:
            start_game()
        queue_redraw()
        return
        
    # Keyboard movement (Left/Right arrows or A/D) (Inverted)
    var input_axis = Input.get_axis("ui_left", "ui_right")
    if input_axis != 0.0:
        paddle_angle -= input_axis * delta * 4.0
        
    if arena_flash_timer > 0.0:
        arena_flash_timer -= delta * 3.0
        
    if splash_text_timer > 0.0:
        splash_text_timer -= delta * 1.5
        
    # Process active powerups
    for i in range(active_powerups.size() - 1, -1, -1):
        active_powerups[i].timer -= delta
        if active_powerups[i].timer <= 0.0:
            active_powerups.remove_at(i)
            
    # Process field powerups animations & collisions
    for i in range(field_powerups.size() - 1, -1, -1):
        var p = field_powerups[i]
        p.anim_timer += delta
        if p.pos.distance_to(ball_pos) <= ball_radius + 22.0: # Powerup hit radius
            var roll = randf()
            var picked_type = "2x"
            if roll < 0.25: picked_type = "2x"
            elif roll < 0.50: picked_type = "trajectory"
            elif roll < 0.75: picked_type = "twin"
            else: picked_type = "triplet"
            
            active_powerups.append({"type": picked_type, "timer": 10.0})
            
            if picked_type == "2x": splash_text = "2X"
            elif picked_type == "trajectory": splash_text = "PATH"
            elif picked_type == "twin": splash_text = "TWIN"
            elif picked_type == "triplet": splash_text = "TRIPLET"
            
            splash_text_timer = 1.0
            field_powerups.remove_at(i)
        
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
        elif b.state == "normal" and b.type == "life":
            b.anim_timer += delta
    
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
            var dist_block = ball_pos.distance_to(closest)
            
            if dist_block <= ball_radius:
                if b.type == "life":
                    queue_damage(i, 1)
                    continue
                    
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
        
        # Build list of active paddle angles
        var has_twin = false
        var has_triplet = false
        for p in active_powerups:
            if p.type == "twin": has_twin = true
            elif p.type == "triplet": has_triplet = true
            
        var active_angles = [paddle_angle]
        if has_twin:
            active_angles.append(paddle_angle + PI)
        if has_triplet:
            active_angles.append(paddle_angle + deg_to_rad(120.0))
            active_angles.append(paddle_angle - deg_to_rad(120.0))
            
        var is_hit = false
        for ang in active_angles:
            var diff = wrapf(angle_to_ball - ang, -PI, PI)
            if abs(diff) <= paddle_width / 2.0:
                is_hit = true
                break
                
        if not is_hit:
            if lives > 0:
                lives -= 1
                arena_flash_timer = 1.0
                is_hit = true
                
        if is_hit:
            var normal = (center - ball_pos).normalized()
            ball_vel = ball_vel.bounce(normal)
            
            # Variance
            var variance = randf_range(-0.15, 0.15)
            ball_vel = ball_vel.rotated(variance)
            
            ball_speed += 10.0
            ball_vel = ball_vel.normalized() * ball_speed
            ball_pos = center + (normal * -(arena_radius - ball_radius - 1))
            
            var multi_count = 0
            for p in active_powerups:
                if p.type == "2x": multi_count += 1
            var current_multiplier = int(pow(2, multi_count))
            score += 1 * current_multiplier # point per paddle bounce
            
            # Handle block and powerup spawning based on successful paddle hits
            paddle_hits += 1
            if paddle_hits == 2:
                spawn_blocks(1)
            elif paddle_hits > 2:
                var roll = randf()
                if roll <= 0.05:
                    spawn_blocks(2)
                elif roll <= 0.30:
                    spawn_blocks(1)
                    
                # Temporarily increased to 25% chance to spawn Powerup for easier testing
                if randf() <= 0.25:
                    var r = randf_range(0, 200)
                    var ang = randf_range(0, TAU)
                    var p_pos = center + Vector2(cos(ang), sin(ang)) * r
                    field_powerups.append({"pos": p_pos, "anim_timer": 0.0})
        else:
            # Missed completely (0 lives left)
            is_game_over = true
            game_over_timer = 0.5 # Fade out duration
            
    queue_redraw()

func _get_blink_alpha(time: float) -> float:
    if time > 3.0:
        return 1.0
    var freq = lerp(20.0, 5.0, time / 3.0)
    var blink = abs(sin(time * freq))
    var fade = clamp(time, 0.0, 1.0)
    return blink * fade

func _draw():
    var fade_alpha = 1.0
    if is_game_over:
        fade_alpha = max(0.0, game_over_timer / 0.5)

    # Background
    draw_rect(get_viewport_rect(), Color.BLACK)
    
    # Draw Blocks
    for b in blocks:
        var size_mult = 1.0
        var alpha = 1.0
        
        if b.state == "spawning":
            alpha = abs(sin(b.anim_timer * TAU * 3.0))
        elif b.state == "disintegrating":
            size_mult = 1.0 + (1.0 - b.anim_timer) * 0.6
            alpha = b.anim_timer
            
        alpha *= fade_alpha
            
        var current_size = block_size * size_mult
        
        # If Life block, custom draw
        if b.type == "life":
            var pulse = 1.0
            if b.state == "normal": pulse = 1.0 + sin(b.anim_timer * 10.0) * 0.15
            var l_size = (current_size * 0.5) * pulse
            var life_color = Color("00ff00")
            life_color.a *= alpha
            draw_circle(b.pos, l_size, life_color)
            var black_color = Color.BLACK
            black_color.a *= alpha
            draw_circle(b.pos, l_size - 4.0, black_color)
            continue
            
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
        
        # If it's a mine, draw a rotated under-layer to make it spikey
        if b.type == "mine":
            draw_set_transform(b.pos, PI/4, Vector2.ONE)
            var rect_centered = Rect2(-Vector2(current_size/2.0, current_size/2.0), Vector2(current_size, current_size))
            draw_style_box(block_style, rect_centered)
            draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
            
        # Draw the standard orientation block
        draw_style_box(block_style, rect)
        
        # Explosion logic for mines
        if b.type == "mine" and b.state == "disintegrating":
            var expl_radius = (block_size * 3.0) * (1.0 - b.anim_timer)
            var expl_color = Color(1, 0, 0, alpha)
            draw_circle(b.pos, expl_radius, expl_color)
        
        # Draw "Cracked" lines based on missing HP
        if b.state != "disintegrating" and b.type != "mine":
            var missing_hp = b.max_hp - b.hp
            var crack_color = Color(0, 0, 0, alpha)
            if missing_hp >= 1:
                draw_line(b.pos + Vector2(-current_size*0.3, -current_size*0.4), b.pos + Vector2(current_size*0.1, current_size*0.1), crack_color, 3.0)
            if missing_hp >= 2:
                draw_line(b.pos + Vector2(current_size*0.1, current_size*0.1), b.pos + Vector2(-current_size*0.2, current_size*0.4), crack_color, 2.0)
                
    # Arena Outline
    var arena_color = Color.WHITE
    if arena_flash_timer > 0.0:
        arena_color = Color.RED.lerp(Color.WHITE, 1.0 - arena_flash_timer)
    arena_color.a *= fade_alpha
    draw_arc(center, arena_radius, 0, TAU, 128, arena_color, 2.0, true)
    
    # Trajectory Powerup Drawing
    var has_trajectory = false
    var has_twin = false
    var has_triplet = false
    var max_twin_time = 0.0
    var max_triplet_time = 0.0
    for p in active_powerups:
        if p.type == "trajectory": has_trajectory = true
        elif p.type == "twin":
            has_twin = true
            max_twin_time = max(max_twin_time, p.timer)
        elif p.type == "triplet":
            has_triplet = true
            max_triplet_time = max(max_triplet_time, p.timer)
            
    if has_trajectory and not is_game_over:
        var path = predict_trajectory(2)
        if path.size() > 1:
            var path_color = Color.LIGHT_GRAY
            path_color.a *= fade_alpha
            for i in range(path.size() - 1):
                draw_dashed_line(path[i], path[i+1], path_color, 2.0, 10.0)
    
    # Draw Field Powerups with Rounded Geometry
    for p in field_powerups:
        var pulse = 1.0 + sin(p.anim_timer * 5.0) * 0.2
        var bob = sin(p.anim_timer * 3.0) * 5.0
        var draw_pos = p.pos + Vector2(0, bob)
        var p_size = 22.0 * pulse
        
        var neon_blue = Color("00ffff")
        
        # Draw Neon Glow Layer (Rounded)
        var glow_points = get_rounded_triangle_points(draw_pos, p_size * 1.4)
        var glow_color = neon_blue
        glow_color.a = 0.3 * fade_alpha
        draw_colored_polygon(glow_points, glow_color)
        
        # Draw Core Triangle (Rounded)
        var points = get_rounded_triangle_points(draw_pos, p_size)
        var core_color = neon_blue
        core_color.a *= fade_alpha
        draw_colored_polygon(points, core_color)
    
    # Draw Red Ball
    var ball_color = Color.RED
    ball_color.a *= fade_alpha
    draw_circle(ball_pos, ball_radius, ball_color)
    
    # Draw Paddles
    var paddle_color = Color("00ff00")
    paddle_color.a *= fade_alpha
    
    # Main Paddle
    var start_angle = paddle_angle - paddle_width / 2.0
    var end_angle = paddle_angle + paddle_width / 2.0
    draw_arc(center, arena_radius, start_angle, end_angle, 64, paddle_color, paddle_thickness, true)
    
    # Twin Clone
    if has_twin:
        var clone_color = Color.BLUE
        clone_color.a *= fade_alpha * _get_blink_alpha(max_twin_time)
        var ang = paddle_angle + PI
        draw_arc(center, arena_radius, ang - paddle_width / 2.0, ang + paddle_width / 2.0, 64, clone_color, paddle_thickness, true)
        
    # Triplet Clones
    if has_triplet:
        var clone_color = Color.BLUE
        clone_color.a *= fade_alpha * _get_blink_alpha(max_triplet_time)
        var ang1 = paddle_angle + deg_to_rad(120.0)
        draw_arc(center, arena_radius, ang1 - paddle_width / 2.0, ang1 + paddle_width / 2.0, 64, clone_color, paddle_thickness, true)
        var ang2 = paddle_angle - deg_to_rad(120.0)
        draw_arc(center, arena_radius, ang2 - paddle_width / 2.0, ang2 + paddle_width / 2.0, 64, clone_color, paddle_thickness, true)
    
    var default_font = ThemeDB.fallback_font
    
    # Draw Splash Text
    if splash_text_timer > 0.0:
        var f_size = 128
        var s_size = default_font.get_string_size(splash_text, HORIZONTAL_ALIGNMENT_CENTER, -1, f_size)
        var s_pos = center - Vector2(s_size.x / 2.0, -s_size.y / 4.0)
        var splash_color = Color(1, 1, 1, splash_text_timer * fade_alpha)
        draw_string(default_font, s_pos, splash_text, HORIZONTAL_ALIGNMENT_CENTER, -1, f_size, splash_color)
    
    # Draw Score
    var font_size = 64
    var text_size = default_font.get_string_size(str(score), HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
    var text_pos = center - Vector2(text_size.x / 2.0, -text_size.y / 4.0)
    var score_color = Color.WHITE
    score_color.a *= fade_alpha
    draw_string(default_font, text_pos, str(score), HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, score_color)
    
    # Draw Lives HUD
    var hud_center = Vector2(50, 50)
    var hud_radius = 15.0
    var arc_length = (TAU / 3.0) - 0.2
    var hud_color = Color("00ff00")
    hud_color.a *= fade_alpha
    for i in range(lives):
        var arc_start = i * (TAU / 3.0)
        var arc_end = arc_start + arc_length
        draw_arc(hud_center, hud_radius, arc_start, arc_end, 16, hud_color, 4.0, true)
        
    # Draw Powerup Timers HUD
    var right_x = get_viewport_rect().size.x - 150
    var y_offset = 50
    var timer_color = Color.WHITE
    timer_color.a *= fade_alpha
    for p in active_powerups:
        var title = "2x"
        if p.type == "trajectory": title = "Path"
        elif p.type == "twin": title = "Twin"
        elif p.type == "triplet": title = "Trip"
        var time_str = "%s: 00:%02d" % [title, int(p.timer)]
        draw_string(default_font, Vector2(right_x, y_offset), time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, timer_color)
        y_offset += 40
    
    # Pause Overlay
    if is_paused:
        draw_rect(get_viewport_rect(), Color(0, 0, 0, 0.5))
        var pause_text = "PAUSED"
        var pause_size = default_font.get_string_size(pause_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 48)
        var pause_pos = center - Vector2(pause_size.x / 2.0, arena_radius + 50)
        draw_string(default_font, pause_pos, pause_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 48, Color.WHITE)
