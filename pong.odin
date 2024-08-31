package pong

import "core:fmt"
import "vendor:raylib"
import "core:math"
import "core:math/rand"

init_window_size_x : i32 = 1920 / 2
init_window_size_y : i32 = 1080 / 2
init_window_title  : cstring = "Pong"

DEBUG_DRAW :: true

get_game_width :: proc() -> i32 {
    return 960
}

get_game_height :: proc() -> i32 {
    return 540
}

EGameState :: enum {
    MAIN_MENU,
    GAMEPLAY
}

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

def_bg_color    := raylib.Color{ 32, 32, 32, 255 }
def_ball_speed  : f32 = 256.0
def_ball_size   := vec2{ 16.0, 16.0 }
def_paddle_size := vec2{ 8.0, 128.0 }

balls    : [dynamic] Ball
paddle_l : Paddle
paddle_r : Paddle
specials : [ESpecialType._COUNT] Special

game_state : EGameState = .MAIN_MENU

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
    return aabb(p_pos, p_size, ball.pos, ball.size)
}

get_ball_paddle_hit_perc :: proc(paddle : Paddle, ball : Ball) -> (f32, bool) {
    p_pos, p_size := get_paddle_collider(paddle)

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

/* Doesn't check for y-axis collision */
/* Returns 0 if collision with front of paddle or no collision, and -1 or 1 if collision with side */
get_ball_collision_side :: proc(paddle : Paddle, ball : Ball) -> i32 {
    p_pos, p_size := get_paddle_collider(paddle)

    if paddle.side == .LEFT {
        paddle_x_surface := p_pos.x + p_size.x
        diff := ball.pos.x - paddle_x_surface

        // @todo
    } else {
        paddle_x_surface := p_pos.x
        diff := ball.pos.x + ball.size.x - paddle_x_surface

        if diff < ball.size.x * 0.5 {
            return 0
        } else {
            perc, hit := get_ball_paddle_hit_perc(paddle, ball)
            if perc < 0.5 {
                return -1
            } else {
                return 1
            }
        }
    }
    
    return 0
}

add_ball :: proc() -> ^Ball {
    /* Default params */
    ball : Ball
    ball.size = def_ball_size
    ball.pos  = vec2{ cast(f32)get_game_width() / 2.0 - ball.size.x / 2.0, cast(f32)get_game_height() / 2.0 - ball.size.y / 2.0 }
    ball.dir  = vec2{ 1.0, 0.0 }
    ball.speed = def_ball_speed
    ball.speed_mult = 1.0
    ball.color = { 255, 255, 255, 255 }
    append_elem(&balls, ball)
    return &balls[len(balls) - 1]
}

update_ball :: proc(ball : ^Ball, delta_time : f32) {
    window_r := cast(f32) get_game_width()
    window_h := cast(f32) get_game_height()
    
    next_pos := add(ball.pos, mult_f(ball.dir, (ball.speed * ball.speed_mult) * delta_time))
    next_dir := ball.dir;

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
    if DEBUG_DRAW {
        r_color := ball.color
        r_color.a = 0x42
        raylib.DrawRectangle(auto_cast ball.pos.x, auto_cast ball.pos.y, auto_cast ball.size.x, auto_cast ball.size.y, r_color)
    }

    /* Direction */
    if DEBUG_DRAW {
        line_col := raylib.Color{ 188, 188, 166, 255 }
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

            for &ball in balls {
                ball_x_dir  := cast(int) math.sign(ball.dir.x)
                paddle_side := paddle.side == .LEFT ? -1 : +1
        
                /* Check for collision with paddle if the ball moves towards it */
                if ball_x_dir == paddle_side {
                    if check_collision(paddle, &ball) {
                        perc, hit := get_ball_paddle_hit_perc(paddle^, ball)
                        assert(hit)
        
                        p_pos, p_size := get_paddle_collider(paddle^)
                        if paddle.side == .LEFT {
                            ball.pos.x = p_pos.x + p_size.x
                        } else {
                            ball.pos.x = p_pos.x - ball.size.x
                        }

                        ball.dir.x *= -1
                        ball.dir.y = ((perc - 0.5) * 2.0)
                        ball.dir = norm(ball.dir)
                        ball.speed_mult = 1.0
                    }
                }
            }
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

                    col_side := get_ball_collision_side(paddle^, ball)
                    if col_side != 0 {
                        // ball.dir = vec2{ 0.0, cast(f32)col_side }
                        if col_side == 1 {
                            ball.pos.y = p_pos.y + p_size.y
                        } else {
                            ball.pos.y = p_pos.y - ball.size.y
                        }
                        ball.dir.x = auto_cast math.sign(ball.dir.x)
                        ball.dir.y = auto_cast col_side
                        ball.dir = norm(ball.dir)
                        continue
                    }

                    
                    if(paddle.side == .LEFT) {
                        ball.pos.x = p_pos.x + p_size.x
                    } else {
                        ball.pos.x = p_pos.x - ball.size.x
                    }
                    ball.speed_mult = special.special_hit_power

                    perc, hit := get_ball_paddle_hit_perc(paddle^, ball)

                    if special.special_shoots_forward {
                        ball.dir = vec2{ special_dir, 0.0 }
                    } else {
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

    window_right := cast(f32)get_game_width()

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

    screen_height := cast(f32)get_game_height()

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
    full_window_y := get_game_height()
    half_window_x := get_game_width() / 2

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

        window_right := cast(f32)get_game_width()
        debug_text_color := raylib.Color{ 188, 188, 166, 128 }

        debug_font_size :: 20
        for &ball in balls {
            str := fmt.ctprintf("%.1f,%.1f", ball.pos.x, ball.pos.y)
            raylib.DrawText(str, cast(i32)(ball.pos.x + ball.size.x * 0.5 - cast(f32)(raylib.MeasureText(str, debug_font_size) / 2)), auto_cast ball.pos.y - debug_font_size, debug_font_size, debug_text_color)
        }

        /* L paddle */ {
            p_pos, p_size := get_paddle_collider(paddle_l)

            strl := fmt.ctprintf("%f", p_pos.x)
            raylib.DrawText(strl, auto_cast paddle_offset, auto_cast paddle_l.pos.y - debug_font_size, debug_font_size, debug_text_color)

            strr := fmt.ctprintf("%f", p_pos.x + p_size.x)
            raylib.DrawText(strr, auto_cast paddle_offset, auto_cast(paddle_l.pos.y + paddle_l.size.y), debug_font_size, debug_text_color)
        }

        /* R paddle */ {
            p_pos, p_size := get_paddle_collider(paddle_r)

            strl := fmt.ctprintf("%f", p_pos.x + p_size.x)
            raylib.DrawText(strl, auto_cast(window_right - paddle_offset - cast(f32)raylib.MeasureText(strl, debug_font_size)), auto_cast paddle_r.pos.y - debug_font_size, debug_font_size, debug_text_color)

            strr := fmt.ctprintf("%f", p_pos.x)
            raylib.DrawText(strr, auto_cast(window_right - paddle_offset - cast(f32)raylib.MeasureText(strr, debug_font_size)), auto_cast(paddle_r.pos.y + paddle_r.size.y), debug_font_size, debug_text_color)
        }
    }
}

update_and_draw_game :: proc(delta_time : f32) {
    last_game_time_min : i32 = game_time_min
    last_game_time_sec : i32 = cast(i32)math.floor(game_time_sec)

    /* Update game time */
    game_time_sec += delta_time
    if game_time_sec >= 60.0 {
        game_time_min += 1
        game_time_sec -= 60.0
    }

    /* Set ui flash timers */
    if last_game_time_min != game_time_min {
        game_time_min_flash_t = 1.0

        /* @TEMP */
        new_ball := add_ball()
        theta : f32 = rand.float32() * PI * 2.0
        new_ball.dir = vec2{ math.sin(theta), math.cos(theta) }

    } else if last_game_time_sec != cast(i32)math.floor(game_time_sec) {
        game_time_sec_flash_t = 1.0
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

    /* Draw game */ {
        camera : raylib.Camera2D
        camera.zoom = cast(f32)raylib.GetScreenWidth() / cast(f32)get_game_width() // @HACK
    
        raylib.ClearBackground(def_bg_color)
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

menu_logo_font_size :: 60
menu_logo_title :: "Pongg"
menu_logo_speed :: 128.0 + 64.0
menu_logo_color :: raylib.Color{ 255, 255, 255, 64 }
menu_logo_pos : vec2
menu_logo_dir : vec2 = { 1, 1 }

// @hack Because can't use Pressed in update_and_draw...
menu_apply_selected_opt : bool = false

menu_opt_selected_idx := 0

menu_options : []cstring = {
    "START GAME",
    "QUIT"
}

change_menu_selection :: proc(delta : int) {
    assert(delta == -1 || delta == 1)

    menu_opt_selected_idx += delta

    if menu_opt_selected_idx < 0 {
        menu_opt_selected_idx = len(menu_options) - 1
    } else if menu_opt_selected_idx >= len(menu_options) {
        menu_opt_selected_idx = 0
    }
}

update_and_draw_menu :: proc(delta_time : f32) {
    menu_logo_pos = add(menu_logo_pos, mult_f(menu_logo_dir, delta_time * menu_logo_speed))
    menu_logo_size : vec2 = { auto_cast raylib.MeasureText(menu_logo_title, menu_logo_font_size), auto_cast menu_logo_font_size }

    screen_w := get_game_width()
    screen_h := get_game_height()

    /* Check for collision with sides */ {
        region_r := cast(f32)get_game_width()
        region_b := cast(f32)get_game_height()
        region_x := cast(f32)0
        region_y := cast(f32)0

        if menu_logo_pos.x <= region_x {
            menu_logo_pos.x = region_x
            menu_logo_dir.x *= -1.0
        }
    
        if menu_logo_pos.y <= region_y {
            menu_logo_pos.y = region_y
            menu_logo_dir.y *= -1.0
        }
    
        if (menu_logo_pos.x + menu_logo_size.x) >= region_r {
            menu_logo_pos.x = region_r - menu_logo_size.x
            menu_logo_dir.x *= -1
        }
    
        if (menu_logo_pos.y + menu_logo_size.y) >= region_b {
            menu_logo_pos.y = region_b - menu_logo_size.y
            menu_logo_dir.y *= -1
        }
    }

    if menu_apply_selected_opt {
        switch menu_opt_selected_idx {
            case 0: {
                game_state = .GAMEPLAY
            }

            case 1: {
                raylib.CloseWindow()
                return
            }
        }

        menu_apply_selected_opt = false
    }

    /* Draw menu */ {
        camera : raylib.Camera2D
        camera.zoom = 1.0 // @todo
    
        raylib.ClearBackground(def_bg_color)
        raylib.BeginDrawing()
        raylib.BeginMode2D(camera)
    
        center_x := get_game_width() / 2

        
        menu_text_color : raylib.Color = { 255, 255, 255, 255 }

        raylib.DrawText(menu_logo_title, auto_cast menu_logo_pos.x, auto_cast menu_logo_pos.y, menu_logo_font_size, menu_logo_color)
        
        

        opt_font_size  :: 30
        opt_text_color :: raylib.Color{ 255, 255, 255, 255 }

        for &option, idx in menu_options {
            text_color := opt_text_color
            if menu_opt_selected_idx == idx {
                text_color = { 255, 255, 0, 255 }
            }
            raylib.DrawText(option, 0, auto_cast idx * opt_font_size + 32, opt_font_size, text_color)
        }

        if DEBUG_DRAW {
            raylib.DrawFPS(0, screen_h - 16)
        }

        raylib.EndMode2D()
        raylib.EndDrawing()
    }
}

main :: proc() {
    // raylib.SetConfigFlags({ raylib.ConfigFlag.WINDOW_RESIZABLE });
    raylib.SetConfigFlags({ raylib.ConfigFlag.VSYNC_HINT })
    raylib.InitWindow(init_window_size_x, init_window_size_y, init_window_title)

    if init_window_size_x == 1920 { // @HACK
        raylib.ToggleFullscreen()
    }

    init_specials()

    /* Add ball(s) */ 
    add_ball()

    /* Init left paddle */ {
        p := &paddle_l
        p.pos   = vec2{ paddle_offset, 0.0 }
        p.size  = def_paddle_size
        p.size_mult = vec2{ 1.0, 1.0 }
        p.speed = 512
        p.side  = .LEFT
        p.color = { 177, 77, 127, 255 }
        p.special_type  = .SHOOT
        p.special_state = .NONE
        p.special_t     = 0.0
    }

    /* Init right paddle */ {
        window_right := cast(f32)get_game_width()

        p := &paddle_r
        p.size  = def_paddle_size
        p.pos   = vec2{ window_right - paddle_offset - p.size.x, 0.0 }
        p.speed = 723
        p.size_mult = vec2{ 1.0, 1.0 }
        p.side  = .RIGHT
        p.color = { 111, 133, 187, 255 }
        p.special_type  = .PUNCH
        p.special_state = .NONE
        p.special_t     = 0.0
    }

    for !raylib.WindowShouldClose() {

        /* IsKeyPressed before polling events, idk why @check */ {
            if raylib.IsKeyPressed(.F1) { game_state = .MAIN_MENU }
            if raylib.IsKeyPressed(.F2) { game_state = .GAMEPLAY }

            // @todo @move
            if game_state == .MAIN_MENU {
                if raylib.IsKeyPressed(.DOWN)  { change_menu_selection(-1) }
                if raylib.IsKeyPressed(.UP)    { change_menu_selection(+1) }
                if raylib.IsKeyPressed(.ENTER) { menu_apply_selected_opt = true }
            }
        }
        raylib.PollInputEvents()

        delta_time := raylib.GetFrameTime()

        if raylib.IsKeyDown(raylib.KeyboardKey.LEFT_CONTROL) { delta_time *= 0.1 }
        

        switch game_state {
            case .MAIN_MENU: {
                update_and_draw_menu(delta_time)
            }
            case .GAMEPLAY: {
                update_and_draw_game(delta_time)
            }
        }

    }
}