package pong

import "core:fmt"
import "vendor:raylib"
import "core:math"

init_window_size_x : i32 = 960 / 1
init_window_size_y : i32 = 640 / 1
init_window_title  : cstring = "Pong"

Ball :: struct {
    pos    : vec2,
    dir    : vec2,
    size   : vec2,
    speed  : f32,
    color  : raylib.Color
}

ESpecialState :: enum {
    NONE,
    SPECIAL,
    RECOVER
}

paddle_offset : f32 = 16.0

EPaddleSide :: enum {
    LEFT,
    RIGHT
}

ESpecialFunc :: enum {
    LINEAR,
    SQUARE,
    CUBE
}
                        
Paddle :: struct {
    pos   : vec2,
    size  : vec2, // Base paddle size
    speed : f32,
    side  : EPaddleSide,
    color : raylib.Color,

    size_mult : vec2, // Paddle size multiplier, size.x expandse in one direction, size.y in both

    special_state : ESpecialState,
    special_t     : f32,
    special_dist  : f32,
    special_speed : f32,
    special_recover_speed : f32,
    special_size_mult_add : vec2,
    special_move_func : ESpecialFunc,
    special_size_func : ESpecialFunc,
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

aabb :: proc(a_pos, a_size : vec2, b_pos, b_size : vec2) -> bool {
    return !(a_pos.x >= (b_pos.x + b_size.x) || (a_pos.x + a_size.x) <= b_pos.x || a_pos.y >= (b_pos.y + b_size.y) || (a_pos.y + a_size.y) <= b_pos.y)
}

check_collision :: proc(paddle : ^Paddle, ball : ^Ball) -> bool {
    p_pos, p_size := get_paddle_collider(paddle^)
    return aabb(p_pos, p_size, ball.pos, ball.size)
}

// @todo Move pixel by pixel
update_paddle :: proc(paddle : ^Paddle, move_dir : i32, delta_time : f32) {
    paddle.pos.y += auto_cast move_dir * paddle.speed * delta_time
    paddle.pos.y = clamp(paddle.pos.y, 0.0, cast(f32)raylib.GetScreenHeight() - paddle.size.y)

    switch paddle.special_state {
        case .NONE: {
        }

        case ESpecialState.SPECIAL: {
            paddle.special_t += delta_time * paddle.special_speed
            if paddle.special_t >= 1.0 {
                paddle.special_state = .RECOVER
            }
    
            special_dir : f32 = paddle.side == .LEFT ? 1.0 : -1.0

            for &ball in balls {
                if check_collision(paddle, &ball) {
                    p_pos, p_size := get_paddle_collider(paddle^)
                    if(paddle.side == .LEFT) {
                        ball.pos.x = p_pos.x + p_size.x
                    } else {
                        ball.pos.x = p_pos.x - ball.size.x
                    }
                    ball.dir = vec2{ special_dir, 0.0 }
                }
            }
        }

        case .RECOVER: {
            paddle.special_t -= delta_time * paddle.special_recover_speed
            if paddle.special_t <= 0.0 {
                paddle.special_state = .NONE
                paddle.special_t = 0.0
            }
        }
    }

    size_perc := vec2{ paddle.special_t, paddle.special_t }
    if paddle.special_size_func == .SQUARE {
        size_perc = square(vec2{ paddle.special_t, paddle.special_t })
    } else if paddle.special_size_func == .CUBE {
        size_perc = cube(vec2{ paddle.special_t, paddle.special_t })
    }

    paddle.size_mult = add(vec2{ 1, 1 }, mult(paddle.special_size_mult_add, size_perc))

    window_right := cast(f32)raylib.GetScreenWidth()

    if paddle.special_state == .NONE {
        if paddle.side == .LEFT {
            paddle.pos.x = paddle_offset
        } else {
            paddle.pos.x = window_right - paddle_offset - paddle.size.x
        }
    } else {
        move_perc := paddle.special_t
        if paddle.special_move_func == .SQUARE {
            move_perc = square_f(paddle.special_t)
        } else if paddle.special_size_func == .CUBE {
            move_perc = cube_f(paddle.special_t)
        }

        if paddle.side == .LEFT {
            paddle.pos.x = paddle_offset + paddle.special_dist * move_perc
        } else {
            paddle.pos.x = window_right - paddle_offset - paddle.size.x - paddle.special_dist * move_perc
        }
    }
}

update_ball :: proc(ball : ^Ball, delta_time : f32) {
    window_r := cast(f32) raylib.GetScreenWidth()
    window_h := cast(f32) raylib.GetScreenHeight()
    
    next_pos := add(ball.pos, mult_f(ball.dir, ball.speed * delta_time))
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
                p_pos, p_size := get_paddle_collider(paddle^)
                if paddle.side == .LEFT {
                    next_pos.x = p_pos.x + p_size.x
                } else {
                    next_pos.x = p_pos.x - ball.size.x
                }
                next_dir.x *= -1
            }
        }
    }

    check_for_paddle(&paddle_l, ball, &next_pos, &next_dir)
    check_for_paddle(&paddle_r, ball, &next_pos, &next_dir)

    /* Check for collision with sides */ {
        if next_pos.x <= 0.0 {
            next_pos.x = 0.0
            next_dir.x *= -1.0
        }
    
        if next_pos.y <= 0.0 {
            next_pos.y = 0.0
            next_dir.y *= -1.0
        }
    
        if (next_pos.x + ball.size.x) >= window_r {
            next_pos.x = window_r - ball.size.x
            next_dir.x *= -1
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
    ball_center := add(ball.pos, mult_f(ball.size, 0.5))
    ball_radius := mult_f(ball.size, 0.5)
    raylib.DrawEllipse(auto_cast ball_center.x, auto_cast ball_center.y, auto_cast ball_radius.x, auto_cast ball_radius.y, ball.color)

    /* Rectangle */
    if false {
        r_color := ball.color
        r_color.a = 0x42
        raylib.DrawRectangle(auto_cast ball.pos.x, auto_cast ball.pos.y, auto_cast ball.size.x, auto_cast ball.size.y, r_color)
    }

    /* Direction */
    if true {
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
    if true {
        raylib.DrawRectangle(auto_cast paddle.pos.x, auto_cast paddle.pos.y, auto_cast paddle.size.x, auto_cast paddle.size.y, { 255, 255, 255, 32 })
    }
}

main :: proc() {
    raylib.SetConfigFlags({ raylib.ConfigFlag.VSYNC_HINT })
    raylib.InitWindow(init_window_size_x, init_window_size_y, init_window_title)

    background_color : raylib.Color = { 32, 32, 32, 255 }

    /* Add ball */ 
    num_balls := 333
    for i := 0; i < num_balls; i += 1 {
        ball : Ball;
        ball.size.x = 16.0
        ball.size.y = 16.0
        ball.pos.x  = cast(f32)raylib.GetScreenWidth()  * 0.5 - ball.size.x * 0.5
        ball.pos.y  = cast(f32)raylib.GetScreenHeight() * 0.5 - ball.size.y * 0.5
        angle := cast(f32)i * ((PI * 2.0) / cast(f32)num_balls)
        ball.dir.x  = math.sin(PI * 0.5 + angle)
        ball.dir.y  = math.cos(PI * 0.5 + angle)
        ball.speed  = 256.0
        ball.color  = (raylib.Color){ 255, 255, 255, 255 }

        append_elem(&balls, ball)
    }

    /* Init left paddle */ {
        p := &paddle_l
        p.pos   = vec2{ paddle_offset, 0.0 }
        p.size  = vec2{ 8.0, 128.0 }
        p.size_mult = vec2{ 1.0, 1.0 }
        p.speed = 512
        p.side  = .LEFT
        p.color = { 255, 32, 127, 255 }
        p.special_state = .NONE
        p.special_t     = 0.0
        p.special_dist  = 256.0
        p.special_speed = 6.0
        p.special_recover_speed = 1.0
        p.special_size_mult_add = vec2{ 0.4, -0.55 }
        p.special_move_func = .SQUARE
        p.special_size_func = .LINEAR
    }

    /* Init left paddle */ {
        p := &paddle_l
        p.pos   = vec2{ paddle_offset, 0.0 }
        p.size  = vec2{ 8.0, 128.0 }
        p.size_mult = vec2{ 1.0, 1.0 }
        p.speed = 512
        p.side  = .LEFT
        p.color = { 255, 32, 127, 255 }
        p.special_state = .NONE
        p.special_t     = 0.0
        p.special_dist  = 16.0
        p.special_speed = 0.6
        p.special_recover_speed = 6.0
        p.special_size_mult_add = vec2{ 0.0, 3.0 }
        p.special_move_func = .CUBE
        p.special_size_func = .LINEAR
    }

    /* Init right paddle */ {
        window_right := cast(f32)raylib.GetScreenWidth()

        p := &paddle_r
        p.size  = vec2{ 8.0, 96.0 }
        p.pos   = vec2{ window_right - paddle_offset - p.size.x, 0.0 }
        p.speed = 723
        p.size_mult = vec2{ 1.0, 1.0 }
        p.side  = .RIGHT
        p.color = { 255, 133, 127, 255 }
        p.special_state = .NONE
        p.special_t     = 0.0
        p.special_dist  = 0.0
        p.special_speed = 4.0
        p.special_recover_speed = 1.0
        p.special_size_mult_add = vec2{ 25.2, -0.75 }
        p.special_size_func = .CUBE
    }

    for !raylib.WindowShouldClose() {
        raylib.PollInputEvents()

        delta_time := raylib.GetFrameTime()

        if raylib.IsKeyDown(raylib.KeyboardKey.LEFT_CONTROL) { delta_time *= 0.1 }

        if raylib.IsKeyDown(raylib.KeyboardKey.SPACE) {
            if paddle_l.special_state == .NONE {
                paddle_l.special_state = .SPECIAL
                paddle_l.special_t  = 0.0
            }
        }

        if raylib.IsKeyDown(raylib.KeyboardKey.HOME) {
            if paddle_r.special_state == .NONE {
                paddle_r.special_state = .SPECIAL
                paddle_r.special_t  = 0.0
            }
        }

        move_dir   : i32 = 0
        r_move_dir : i32 = 0
        if raylib.IsKeyDown(raylib.KeyboardKey.UP)   { move_dir -= 1 }
        if raylib.IsKeyDown(raylib.KeyboardKey.DOWN) { move_dir += 1 }
        if raylib.IsKeyDown(raylib.KeyboardKey.PAGE_UP)   { r_move_dir -= 1 }
        if raylib.IsKeyDown(raylib.KeyboardKey.PAGE_DOWN) { r_move_dir += 1 }

        update_paddle(&paddle_l, move_dir,   delta_time)
        update_paddle(&paddle_r, r_move_dir, delta_time)

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


        full_window_y := raylib.GetScreenHeight()
        half_window_x := raylib.GetScreenWidth() / 2
        raylib.DrawLine(half_window_x, 0, half_window_x, full_window_y, raylib.Color{128, 128, 128, 255})

        raylib.DrawFPS(0, full_window_y - 16)
        
        // raylib.DrawText("POINTS", half_window_x + 4, 0, 20, { 255, 255 ,255 ,255 })
        // raylib.DrawText("POINTS", half_window_x - 133, 0, 20, { 255, 255 ,255 ,255 })

        raylib.EndMode2D()
        raylib.EndDrawing()
    }
}