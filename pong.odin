package pong

import "core:fmt"
import "vendor:raylib"
import "core:math"
import "core:math/rand"

init_window_size_x : i32 = 960 / 1
init_window_size_y : i32 = 640 / 1
init_window_title  : cstring = "Pong"

DEBUG_DRAW :: true

Ball :: struct {
    pos    : vec2,
    dir    : vec2,
    size   : vec2,
    speed  : f32,
    speed_mult : f32,
    color  : raylib.Color
}

ESpecialState :: enum {
    NONE,
    SPECIAL,
    WAIT,
    RECOVER
}

ESpecialFunc :: enum {
    LINEAR,
    SQUARE,
    CUBE,
    EASE_IN_CIRC,
    EASE_OUT_CIRC,
    EASE_OUT_ELASTIC
}

special_func :: proc(value : f32, func : ESpecialFunc) -> f32 {
    switch func {
        case .LINEAR: return value
        case .SQUARE: return value * value
        case .CUBE:   return value * value * value
        case .EASE_IN_CIRC:  return 1.0 - math.sqrt(1.0 - math.pow(value, 2))
        case .EASE_OUT_CIRC: return math.sqrt(1.0 - math.pow(value - 1.0, 2))
        case .EASE_OUT_ELASTIC: return value == 0.0 ? 0.0 : value >= 1.0 ? 1.0 : math.pow(2.0, -10 * value) * math.sin((value * 10 - 0.75) * ((2.0 * 3.14159265) / 4.0)) + 1.0
    }
    assert(false)
    return 0.0
}

Special :: struct {
    special_shoots_forward : bool, // If shoots straight forward
    special_dist           : f32,
    special_speed          : f32,
    special_speed_recover  : f32,
    special_wait_time      : f32,
    special_size_mult_add  : vec2,
    special_hit_power      : f32, // Multiplier
    special_move_func      : ESpecialFunc,
    special_size_func      : ESpecialFunc,
    special_move_func_recover : ESpecialFunc,
    special_size_func_recover : ESpecialFunc,
}

ESpecialType :: enum {
    SHOOT,
    PUNCH,
    ENLARGE,
    _COUNT
}

init_specials :: proc() {
    /* SHOOT */ {
        sp := &specials[ESpecialType.SHOOT]
        sp.special_shoots_forward = false
        sp.special_dist           = 256.0
        sp.special_speed          = 6.0
        sp.special_speed_recover  = 1.0
        sp.special_wait_time      = 0.0
        sp.special_size_mult_add  = { -0.4, 0.25 }
        sp.special_hit_power      = 2.5
        sp.special_move_func      = .SQUARE
        sp.special_size_func      = .LINEAR        
        sp.special_move_func_recover = .SQUARE
        sp.special_size_func_recover = .LINEAR
    }

    /* PUNCH */ {
        sp := &specials[ESpecialType.PUNCH]
        sp.special_shoots_forward = true
        sp.special_dist           = 0.0
        sp.special_speed          = 0.5
        sp.special_speed_recover  = 3.0
        sp.special_wait_time      = 0.0
        sp.special_size_mult_add  = { 25.0, -0.6 }
        sp.special_hit_power      = 4.5
        sp.special_move_func      = .LINEAR
        sp.special_size_func      = .EASE_OUT_ELASTIC
        sp.special_move_func_recover = .LINEAR
        sp.special_size_func_recover = .LINEAR
    }

    /* ENLARGE */ {
        sp := &specials[ESpecialType.ENLARGE]
        sp.special_shoots_forward = false
        sp.special_dist           = 64.0
        sp.special_speed          = 0.3
        sp.special_speed_recover  = 8.0
        sp.special_wait_time      = 1.0
        sp.special_size_mult_add  = { 0.2, 3.0 }
        sp.special_hit_power      = 0.4
        sp.special_move_func      = .EASE_IN_CIRC
        sp.special_size_func      = .EASE_OUT_CIRC
        sp.special_move_func_recover = .EASE_IN_CIRC
        sp.special_size_func_recover = .EASE_OUT_CIRC
    }
}

EPaddleSide :: enum {
    LEFT,
    RIGHT
}

paddle_offset :: 16.0

Paddle :: struct {
    pos   : vec2,
    size  : vec2, // Base paddle size
    speed : f32,
    side  : EPaddleSide,
    color : raylib.Color,

    size_mult : vec2, // Paddle size multiplier, size.x expandse in one direction, size.y in both

    hit_ball_t : f32, // Timer set to 1.0 when hit ball @unused

    special_type   : ESpecialType,
    special_state  : ESpecialState,
    special_t      : f32,
    special_wait_t : f32
}

get_paddle_collider :: proc(paddle : Paddle) -> (vec2, vec2) {
    size := mult(paddle.size, paddle.size_mult)
    // pos  := sub(paddle.pos, mult_f(sub(size, paddle.size), 0.5))
    pos : vec2
    pos.y = paddle.pos.y - (size.y - paddle.size.y) * 0.5
    if paddle.side == .LEFT {
        pos.x = paddle.pos.x
    } else {
        pos.x = paddle.pos.x - (size.x - paddle.size.x)
    }
    return pos, size
}

balls    : [dynamic] Ball
paddle_l : Paddle
paddle_r : Paddle
specials : [ESpecialType._COUNT] Special

add_points_l :: proc(amount : i32 = 1) {
    points_l += amount
    points_l_flash_t = 1.0
}

add_points_r :: proc(amount : i32 = 1) {
    points_r += amount
    points_r_flash_t = 1.0
}

aabb :: proc(a_pos, a_size : vec2, b_pos, b_size : vec2) -> bool {
    return !(a_pos.x >= (b_pos.x + b_size.x) 
        ||  (a_pos.x + a_size.x) <= b_pos.x 
        ||   a_pos.y >= (b_pos.y + b_size.y) 
        ||  (a_pos.y + a_size.y) <= b_pos.y)
}

check_collision :: proc(paddle : ^Paddle, ball : ^Ball) -> bool {
    p_pos, p_size := get_paddle_collider(paddle^)
    p_size.x = paddle.size.x
    return aabb(p_pos, p_size, ball.pos, ball.size)
}

get_ball_paddle_hit_perc :: proc(ball : ^Ball, paddle : ^Paddle) -> (f32, bool) {
    p_pos, p_size := get_paddle_collider(paddle^)

    /* Add ball height to paddle height */
    p_pos.y  -= ball.size.y * 0.5
    p_size.y += ball.size.y

    /* Compare to ball center y */
    b_center := ball.pos.y + ball.size.y * 0.5

    if b_center < p_pos.y || b_center > (p_pos.y + p_size.y) {
        return 0.0, false
    }

    rel  := b_center - p_pos.y
    perc := rel / p_size.y

    return perc, true
}

update_ball :: proc(ball : ^Ball, delta_time : f32) {
    window_r := cast(f32) raylib.GetScreenWidth()
    window_h := cast(f32) raylib.GetScreenHeight()
    
    next_pos := add(ball.pos, mult_f(ball.dir, (ball.speed * ball.speed_mult) * delta_time))
    next_dir := ball.dir;

    check_for_paddle := proc(paddle : ^Paddle, ball : ^Ball, next_pos, next_dir : ^vec2) {
        /* Maybe recover state should be a time when ball doesn't bounce as a debuff of using special */
        if paddle.special_state == .RECOVER {
            return
        }

        ball_x_dir  := cast(int) math.sign(ball.dir.x)
        paddle_side := paddle.side == .LEFT ? -1 : +1

        /* Check for collision with paddle if moves towards it */
        if ball_x_dir == paddle_side {
            if check_collision(paddle, ball) {
                perc, hit := get_ball_paddle_hit_perc(ball, paddle)
                assert(hit)

                p_pos, p_size := get_paddle_collider(paddle^)
                if paddle.side == .LEFT {
                    next_pos.x = p_pos.x + p_size.x
                } else {
                    next_pos.x = p_pos.x - ball.size.x
                }
                // next_dir.x *= -1
                next_dir.x *= -1
                next_dir.y = ((perc - 0.5) * 2.0)
                next_dir^ = norm(next_dir^)
                ball.speed_mult = 1.0
            }
        }
    }

    // check_for_paddle(&paddle_l, ball, &next_pos, &next_dir)
    // check_for_paddle(&paddle_r, ball, &next_pos, &next_dir)

    // @temp Points

    /* Check for collision with sides */ {
        if next_pos.x <= 0.0 {
            next_pos.x = 0.0
            next_dir.x *= -1.0

            add_points_r(1)
        }
    
        if next_pos.y <= 0.0 {
            next_pos.y = 0.0
            next_dir.y *= -1.0
        }
    
        if (next_pos.x + ball.size.x) >= window_r {
            next_pos.x = window_r - ball.size.x
            next_dir.x *= -1

            add_points_l(1)
        }
    
        if (next_pos.y + ball.size.y) >= window_h {
            next_pos.y = window_h - ball.size.y
            next_dir.y *= -1
        }
    }

    ball.pos = next_pos
    ball.dir = next_dir
}

draw_ball :: proc(ball : Ball) {
    ball_color := ball.color
    // ball_color.x = u8((ball.speed_mult - 1.0) * 255.0)
    ball_color.a = 128
    ball_center := add(ball.pos, mult_f(ball.size, 0.5))
    ball_radius := mult_f(ball.size, 0.5)
    raylib.DrawEllipse(auto_cast ball_center.x, auto_cast ball_center.y, auto_cast ball_radius.x, auto_cast ball_radius.y, ball_color)

    /* Rectangle */
    if false {
        r_color := ball.color
        r_color.a = 0x42
        raylib.DrawRectangle(auto_cast ball.pos.x, auto_cast ball.pos.y, auto_cast ball.size.x, auto_cast ball.size.y, r_color)
    }

    /* Direction */
    if false {
        line_col := raylib.Color{ 0x44, 0xAA, 0x33, 0xFF }
        line_len : f32 = 48.0
        line_start := add(ball.pos, mult_f(ball.size, 0.5))
        line_end := add(line_start, mult_f(ball.dir, line_len))
        raylib.DrawLine(auto_cast line_start.x, auto_cast line_start.y, auto_cast line_end.x, auto_cast line_end.y, line_col)
    }
}

draw_paddle :: proc(paddle : Paddle) {

    /* If recovers, draw not fully opaque */
    paddle_color := paddle.color
    if paddle.special_state == .RECOVER {
        paddle_color.a = 128
    }

    draw_pos, draw_size := get_paddle_collider(paddle)
    raylib.DrawRectangle(auto_cast draw_pos.x, auto_cast draw_pos.y, auto_cast draw_size.x, auto_cast draw_size.y, paddle_color)

    /* Base size */
    if false {
        raylib.DrawRectangle(auto_cast paddle.pos.x, auto_cast paddle.pos.y, auto_cast paddle.size.x, auto_cast paddle.size.y, { 255, 255, 255, 32 })
    }
}

PlayerKeyBinds :: struct {
    move_up      : raylib.KeyboardKey,
    move_down    : raylib.KeyboardKey,
    special_move : raylib.KeyboardKey,
}

update_paddle_special :: proc(paddle : ^Paddle, delta_time : f32) {
    special := specials[paddle.special_type]

    switch paddle.special_state {
        case .NONE: {
        }

        case ESpecialState.SPECIAL: {
            paddle.special_t += delta_time * special.special_speed
            if paddle.special_t >= 1.0 {
                paddle.special_t = 1.0
                if special.special_wait_time > 0.0 {
                    paddle.special_state = .WAIT
                    paddle.special_wait_t = 0.0
                } else {
                    paddle.special_state = .RECOVER
                }
            }
    
            special_dir : f32 = paddle.side == .LEFT ? 1.0 : -1.0

            for &ball in balls {
                // @todo
                // can_be_hit : bool = int(math.sign(ball.dir.x)) != int(special_dir)

                if check_collision(paddle, &ball) {
                    p_pos, p_size := get_paddle_collider(paddle^)
                    if(paddle.side == .LEFT) {
                        ball.pos.x = p_pos.x + p_size.x
                    } else {
                        ball.pos.x = p_pos.x - ball.size.x
                    }
                    ball.speed_mult = special.special_hit_power

                    if special.special_shoots_forward {
                        ball.dir = vec2{ special_dir, 0.0 }
                    } else {
                        perc, hit := get_ball_paddle_hit_perc(&ball, paddle)
                        assert(hit)
                        ball.dir.x = special_dir
                        ball.dir.y = ((perc - 0.5) * 2.0)
                        ball.dir = norm(ball.dir)

                        paddle.hit_ball_t = 1.0
                    }
                }
            }
        }

        case .WAIT: {
            paddle.special_wait_t += delta_time
            if paddle.special_wait_t >= special.special_wait_time {
                paddle.special_state = .RECOVER
            }
        }

        case .RECOVER: {
            paddle.special_t -= delta_time * special.special_speed_recover
            if paddle.special_t <= 0.0 {
                paddle.special_state = .NONE
                paddle.special_t = 0.0
            }
        }
    }

    move_func := paddle.special_state == .RECOVER ? special.special_move_func_recover : special.special_move_func
    size_func := paddle.special_state == .RECOVER ? special.special_size_func_recover : special.special_size_func

    size_perc_t := special_func(paddle.special_t, size_func)
    size_perc := vec2{ size_perc_t, size_perc_t }
    
    paddle.size_mult = add(vec2{ 1, 1 }, mult(special.special_size_mult_add, size_perc))

    window_right := cast(f32)raylib.GetScreenWidth()

    if paddle.special_state == .NONE {
        if paddle.side == .LEFT {
            paddle.pos.x = paddle_offset
        } else {
            paddle.pos.x = window_right - paddle_offset - paddle.size.x
        }
    } else {
        move_perc_t := special_func(paddle.special_t, move_func)
        move_perc := move_perc_t

        if paddle.side == .LEFT {
            paddle.pos.x = paddle_offset + special.special_dist * move_perc
        } else {
            paddle.pos.x = window_right - paddle_offset - paddle.size.x - special.special_dist * move_perc
        }
    }
}

update_paddle :: proc(paddle : ^Paddle, binds : PlayerKeyBinds, delta_time : f32) {
    /* Special */
    if raylib.IsKeyDown(binds.special_move) {
        if paddle.special_state == .NONE {
            paddle.special_state = .SPECIAL
            paddle.special_t  = 0.0
        }
    }

    screen_height := cast(f32)raylib.GetScreenHeight()

    /* Move Y-Axis */
    dir : i32 = 0
    if raylib.IsKeyDown(binds.move_up)   { dir -= 1 }
    if raylib.IsKeyDown(binds.move_down) { dir += 1 }
    paddle.pos.y += auto_cast dir * paddle.speed * delta_time
    paddle.pos.y = clamp(paddle.pos.y, 0.0, screen_height - paddle.size.y)

    num_special_updates : i32 = 32
    part_delta_time := delta_time / cast(f32)num_special_updates

    for idx in 1..=num_special_updates {
        update_paddle_special(paddle, part_delta_time)
    }
}

game_time_min : i32 = 0;
game_time_sec : f32 = 0.0;
game_time_min_flash_t : f32 = 0.0
game_time_sec_flash_t : f32 = 0.0

points_l : i32 = 0
points_r : i32 = 0
points_l_flash_t : f32 = 0.0
points_r_flash_t : f32 = 0.0

font_size_base :: 40
font_size_max  :: 60
font_size_t : f32 = 0.0 // Maybe unused

update_and_draw_ui :: proc(delta_time : f32) {
    full_window_y := raylib.GetScreenHeight()
    half_window_x := raylib.GetScreenWidth() / 2

    /* Determine font size */
    if font_size_t > 0.0 {
        font_size_t -= 1.0 * delta_time
    } else {
        font_size_t = 0.0
    }
    font_size : i32 = font_size_base + cast(i32)(font_size_t * cast(f32)(font_size_max - font_size_base))

    /* Draw dividing line */ {
        y_top  := font_size
        y_size := full_window_y - font_size
        raylib.DrawLine(half_window_x, y_top, half_window_x, y_size, raylib.Color{128, 128, 128, 255})
    }

    /* Update text flash timers */ {
        update_flash_timer :: proc(delta_time : f32, timer : ^f32) {
            flash_speed :: 1.5
            if timer^ > 0.0 {
                timer^ -= flash_speed * delta_time
            } else {
                timer^ = 0.0
            }
        }

        update_flash_timer(delta_time, &points_l_flash_t)
        update_flash_timer(delta_time, &points_r_flash_t)
        update_flash_timer(delta_time, &game_time_sec_flash_t)
        update_flash_timer(delta_time, &game_time_min_flash_t)
    }

    padding_x          :: 8
    text_color_a_base  :: 48
    text_color_a_flash :: 255

    get_text_color :: proc(a : u8) -> raylib.Color {
        return { 0xFF, 0xFF, 0xFF, a }
    }

    /* Draw points for left player */ {
        text_color := get_text_color(text_color_a_base + u8(points_l_flash_t * f32(text_color_a_flash - text_color_a_base)))

        str_points_l := fmt.ctprintf("%v", points_l)
        str_points_l_w := raylib.MeasureText(str_points_l, font_size)
        raylib.DrawText(str_points_l, half_window_x - str_points_l_w - padding_x, 0, font_size, text_color)
    }

    /* Draw points for right player */ {
        text_color := get_text_color(text_color_a_base + u8(points_r_flash_t * f32(text_color_a_flash - text_color_a_base)))

        str_points_r := fmt.ctprintf("%v", points_r)
        str_points_r_w := raylib.MeasureText(str_points_r, font_size)
        raylib.DrawText(str_points_r, half_window_x + padding_x, 0, font_size, text_color)
    }

    /* Draw game time */ {
        text_y_bottom := full_window_y - font_size

        text_color     := get_text_color(text_color_a_base + u8(0.0 * f32(text_color_a_flash - text_color_a_base)))
        text_color_min := get_text_color(text_color_a_base + u8(game_time_min_flash_t * f32(text_color_a_flash - text_color_a_base)))
        text_color_sec := get_text_color(text_color_a_base + u8(game_time_sec_flash_t * f32(text_color_a_flash - text_color_a_base)))

        /* Minutes */
        str_game_time_min   := fmt.ctprintf("%02d", game_time_min)
        str_game_time_min_w := raylib.MeasureText(str_game_time_min, font_size)
        raylib.DrawText(str_game_time_min, half_window_x - str_game_time_min_w - padding_x, text_y_bottom, font_size, text_color_min)

        /* Seconds */
        str_game_time_sec   := fmt.ctprintf("%02d", cast(i32)math.floor(game_time_sec))
        str_game_time_sec_w := raylib.MeasureText(str_game_time_sec, font_size)
        raylib.DrawText(str_game_time_sec, half_window_x + padding_x, text_y_bottom, font_size, text_color_sec)

        /* : */
        raylib.DrawText(":", half_window_x - raylib.MeasureText(":", font_size) / 2, text_y_bottom, font_size, text_color)
    }

    if DEBUG_DRAW {
        raylib.DrawFPS(0, full_window_y - 16)
    }
}

main :: proc() {
    raylib.SetConfigFlags({ raylib.ConfigFlag.VSYNC_HINT })
    raylib.InitWindow(init_window_size_x, init_window_size_y, init_window_title)

    init_specials()

    background_color : raylib.Color = { 32, 32, 32, 255 }

    /* Add ball(s) */ 
    if false {
        num_balls := 3338
        for i := 0; i < num_balls; i += 1 {
            ball : Ball;
            ball.size.x = 16.0
            ball.size.y = 16.0
            ball.pos.x  = cast(f32)raylib.GetScreenWidth()  * 0.5 - ball.size.x * 0.5
            ball.pos.y  = cast(f32)raylib.GetScreenHeight() * 0.5 - ball.size.y * 0.5
            angle := cast(f32)i * ((PI * 2.0) / cast(f32)num_balls)
            ball.dir.x  = math.sin(PI * 0.5 + angle)
            ball.dir.y  = math.cos(PI * 0.5 + angle)
            ball.speed  = 356.0
            ball.speed_mult = 1.0
            ball.color  = (raylib.Color){ 255, 255, 255, 255 }
    
            append_elem(&balls, ball)
        }
    } else {
        ball : Ball;
        ball.size.x = 16.0
        ball.size.y = 16.0
        ball.pos.x  = cast(f32)raylib.GetScreenWidth()  * 0.5 - ball.size.x * 0.5
        ball.pos.y  = cast(f32)raylib.GetScreenHeight() * 0.5 - ball.size.y * 0.5
        ball.dir    = vec2{ 1.0, 0.0 }
        ball.speed  = 356.0
        ball.speed_mult = 1.0
        ball.color  = (raylib.Color){ 255, 255, 255, 255 }
        append_elem(&balls, ball)
    }

    paddle_size := vec2{ 8.0, 128.0 }

    /* Init left paddle */ {
        p := &paddle_l
        p.pos   = vec2{ paddle_offset, 0.0 }
        p.size  = paddle_size
        p.size_mult = vec2{ 1.0, 1.0 }
        p.speed = 512
        p.side  = .LEFT
        p.color = { 255, 32, 127, 255 }
        p.special_type  = .SHOOT
        p.special_state = .NONE
        p.special_t     = 0.0
    }

    /* Init right paddle */ {
        window_right := cast(f32)raylib.GetScreenWidth()

        p := &paddle_r
        p.size  = paddle_size
        p.pos   = vec2{ window_right - paddle_offset - p.size.x, 0.0 }
        p.speed = 723
        p.size_mult = vec2{ 1.0, 1.0 }
        p.side  = .RIGHT
        p.color = { 255, 133, 127, 255 }
        p.special_state = .NONE
        p.special_t     = 0.0
        p.special_type  = .PUNCH
    }

    for !raylib.WindowShouldClose() {
        raylib.PollInputEvents()
        delta_time := raylib.GetFrameTime()

        last_game_time_min : i32 = game_time_min
        last_game_time_sec : i32 = cast(i32)math.floor(game_time_sec)

        /* Update game time */
        game_time_sec += delta_time * 100.0
        if game_time_sec >= 60.0 {
            game_time_min += 1
            game_time_sec -= 60.0
        }

        /* Set ui flash timers */
        if last_game_time_min != game_time_min {
            game_time_min_flash_t = 1.0
        } else if last_game_time_sec != cast(i32)math.floor(game_time_sec) {
            game_time_sec_flash_t = 1.0

            theta : f32 = rand.float32() * PI * 2.0

            ball : Ball;
            ball.size.x = 16.0
            ball.size.y = 16.0
            ball.pos.x  = cast(f32)raylib.GetScreenWidth()  * 0.5 - ball.size.x * 0.5
            ball.pos.y  = cast(f32)raylib.GetScreenHeight() * 0.5 - ball.size.y * 0.5
            ball.dir    = vec2{ math.sin(theta), math.cos(theta) }
            ball.speed  = 356.0
            ball.speed_mult = 1.0
            ball.color  = (raylib.Color){ 255, 255, 255, 255 }
            append_elem(&balls, ball)
        }

        if DEBUG_DRAW {
            if raylib.IsKeyDown(raylib.KeyboardKey.LEFT_CONTROL) { delta_time *= 0.1 }
        }

        /* Update paddles */ {
            l_binds : PlayerKeyBinds
            l_binds.move_up      = .UP
            l_binds.move_down    = .DOWN
            l_binds.special_move = .SPACE

            r_binds : PlayerKeyBinds
            r_binds.move_up      = .PAGE_UP
            r_binds.move_down    = .PAGE_DOWN
            r_binds.special_move = .HOME

            update_paddle(&paddle_l, l_binds, delta_time)
            update_paddle(&paddle_r, r_binds, delta_time)
        }

        for &ball in balls {
            update_ball(&ball, delta_time)
        }

        camera : raylib.Camera2D
        camera.target = { }
        // camera.offset = { cast(f32)raylib.GetScreenWidth() * 0.5, cast(f32)raylib.GetScreenHeight() * 0.5 }
        camera.zoom = 1.0


        raylib.ClearBackground(background_color)
        raylib.BeginDrawing()
        raylib.BeginMode2D(camera)

        for &ball in balls {
            draw_ball(ball)
        }

        draw_paddle(paddle_l)
        draw_paddle(paddle_r)

        update_and_draw_ui(delta_time)

        
        raylib.EndMode2D()
        raylib.EndDrawing()
    }
}