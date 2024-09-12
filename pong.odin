package pong

import "core:fmt"
import "vendor:raylib"
import "core:math"
import "core:math/rand"

/*
    --- Data Types ---
*/

EState :: enum {
    MAIN_MENU,
    TRANSITION,
    GAMEPLAY
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

ESpecialType :: enum {
    SHOOT,
    PUNCH,
    ENLARGE,
    _COUNT
}

EPaddleSide :: enum {
    LEFT  = -1,
    RIGHT = +1
}

EMenuOption :: enum {
    START_GAME,
    TOGGLE_FC,
    DEBUG_MODE,
    QUIT
}

menu_options :: [EMenuOption]cstring {
    .START_GAME = "START",
    .TOGGLE_FC  = "TOGGLE FULLSCREEN",
    .DEBUG_MODE = "DEBUG",
    .QUIT       = "QUIT"
}

Ball :: struct {
    pos        : vec2,
    dir        : vec2,
    size       : vec2,
    speed      : f32,
    speed_mult : f32,
    color      : raylib.Color
}

Special :: struct {
    special_shoots_forward : bool,
    special_dist              : f32,
    special_speed             : f32,
    special_speed_recover     : f32,
    special_wait_time         : f32,
    special_size_mult_add     : vec2,
    special_hit_power         : f32, /* Multiplier */
    special_move_func         : ESpecialFunc,
    special_size_func         : ESpecialFunc,
    special_move_func_recover : ESpecialFunc,
    special_size_func_recover : ESpecialFunc,
    special_cooldown_time     : f32,
}

Paddle :: struct {
    pos       : vec2,
    size      : vec2, /* Base paddle size */
    speed     : f32,
    side      : EPaddleSide,
    color     : raylib.Color,
    size_mult : vec2,

    hit_ball_t : f32, // Timer set to 1.0 when hit ball @unused

    special_type   : ESpecialType,
    special_state  : ESpecialState,
    special_t      : f32,
    special_wait_t : f32,
    special_cooldown_t : f32,
}

PlayerKeyBinds :: struct {
    move_up      : raylib.KeyboardKey,
    move_down    : raylib.KeyboardKey,
    special_move : raylib.KeyboardKey,
}

GameState :: struct {
    balls                 : [dynamic]Ball,
    paddle_l              : Paddle,
    paddle_r              : Paddle,
    points_l              : i32,
    points_r              : i32,
    game_time_min         : i32,
    game_time_sec         : f32,
    points_l_flash_t      : f32,
    points_r_flash_t      : f32,
    game_time_min_flash_t : f32,
    game_time_sec_flash_t : f32,
    game_time_elapsed     : f32,
    font_size_t           : f32, /* @unused */
}

MenuState :: struct {
    menu_logo_pos           : vec2,
    menu_logo_dir           : vec2,
    menu_opt_selected_idx   : i32,
    menu_opt_delta          : i32, /* For rotation */
    menu_apply_selected_opt : bool, /* @hack Because can't use Pressed in update_and_draw... */
    menu_opt_angle_offset   : f32,
}

TransitionState :: struct {
    transition_t      : f32,
    transition_target : EState
}

/*
    --- Globals ---
*/

GAME_WIDTH           :: i32(960)
GAME_HEIGHT          :: i32(540)
GAME_FONT_SIZE       :: i32(40)
GAME_FONT_SIZE_MAX   :: i32(60)
GAME_DEF_BALL_SPEED  :: 480.0
GAME_DEF_BALL_SIZE   :: vec2{ 16.0, 16.0 }
GAME_DEF_PADDLE_SIZE :: vec2{ 8.0, 128.0 }
GAME_PADDLE_OFFSET   :: 16.0
GAME_MATCH_TIME_MIN  :: 5
GAME_MATCH_TIME_SEC  :: 0.95

MENU_LOGO_FONT_SIZE :: 40
MENU_LOGO_TITLE     :: "Pongg"
MENU_LOGO_SPEED     :: 96.0
MENU_LOGO_COLOR     :: raylib.Color{ 255, 255, 255, 16 }
MENU_OPT_RADIUS     :: 170.0 // 116.0
MENU_OPT_FONT_SIZE  :: 30
MENU_OPT_COLOR      :: raylib.Color{ 255, 255, 255, 64 }
MENU_OPT_COLOR_HOT  :: raylib.Color{ 255, 255, 255, 192 }

TRANSITION_TIME :: 1.5

INIT_WINDOW_WIDTH  :: i32(1920 / 2)
INIT_WINDOW_HEIGHT :: i32(1080 / 2)
INIT_WINDOW_TITLE  :: cstring("Pong")
INIT_WINDOW_VSYNC  :: true
DEF_BG_COLOR       :: raylib.Color{ 32, 32, 32, 255 }

g_state      : EState = .MAIN_MENU
g_specials   : [ESpecialType._COUNT]Special
g_game       : GameState
g_menu       : MenuState
g_transition : TransitionState
g_binds_l    : PlayerKeyBinds
g_binds_r    : PlayerKeyBinds
g_debug_draw : bool = false
g_close_window : bool = false

/*
    --- Procedures ---
*/

setup_paddle_l :: proc() {
    p := &g_game.paddle_l
    p.pos        = vec2{ GAME_PADDLE_OFFSET, f32(GAME_HEIGHT) * 0.5 - GAME_DEF_PADDLE_SIZE.y * 0.5 }
    p.size       = GAME_DEF_PADDLE_SIZE
    p.size_mult  = vec2{ 1.0, 1.0 }
    p.speed      = 512
    p.side       = .LEFT
    p.color      = { 177, 77, 127, 255 }
    p.special_type  = .SHOOT
    p.special_state = .NONE
    p.special_t     = 0.0
    p.special_cooldown_t = 0.0
}

setup_paddle_r :: proc() {
    p := &g_game.paddle_r
    p.size  = GAME_DEF_PADDLE_SIZE
    p.pos   = vec2{ f32(GAME_WIDTH) - GAME_PADDLE_OFFSET - p.size.x, f32(GAME_HEIGHT) * 0.5 - GAME_DEF_PADDLE_SIZE.y * 0.5 }
    p.speed = 723
    p.size_mult = vec2{ 1.0, 1.0 }
    p.side  = .RIGHT
    p.color = { 111, 133, 187, 255 }
    p.special_type  = .PUNCH
    p.special_state = .NONE
    p.special_t     = 0.0
    p.special_cooldown_t = 0.0
}

add_ball :: proc() -> ^Ball {
    ball : Ball
    ball.size = GAME_DEF_BALL_SIZE
    ball.pos  = vec2{ f32(GAME_WIDTH) / 2.0 - ball.size.x / 2.0, f32(GAME_HEIGHT) / 2.0 - ball.size.y / 2.0 }
    ball.dir  = (rand.uint32() % 2 == 0) ? vec2{ 1.0, 0.0 } : vec2{ -1.0, 0.0 }
    ball.speed = GAME_DEF_BALL_SPEED
    ball.speed_mult = 1.0
    ball.color = { 255, 255, 255, 255 }
    append_elem(&g_game.balls, ball)
    return &g_game.balls[len(g_game.balls) - 1]
}

/* Initialize GameState structure */
init_game :: proc() {
    setup_paddle_l()
    setup_paddle_r()
    g_game.points_l      = 0
    g_game.points_r      = 0
    g_game.game_time_min = GAME_MATCH_TIME_MIN
    g_game.game_time_sec = GAME_MATCH_TIME_SEC
    g_game.points_l_flash_t      = 0.0
    g_game.points_r_flash_t      = 0.0
    g_game.game_time_min_flash_t = 0.0
    g_game.game_time_sec_flash_t = 0.0
    g_game.game_time_elapsed     = 0.0
    g_game.font_size_t           = 0.0
}

/* Start new game */
start_game_session :: proc() {
    init_game()
    clear(&g_game.balls)
    add_ball()
}

add_points_l :: proc(amount : i32 = 1) {
    g_game.points_l += amount
    g_game.points_l_flash_t = 1.0
}

add_points_r :: proc(amount : i32 = 1) {
    g_game.points_r += amount
    g_game.points_r_flash_t = 1.0
}

/* Initialize MenuState structure */
init_menu :: proc() {
    g_menu.menu_logo_pos           = vec2{ f32(GAME_WIDTH / 2), f32(GAME_HEIGHT / 2) }
    g_menu.menu_logo_dir           = norm(vec2{ 1.0, 1.0 })
    g_menu.menu_opt_selected_idx   = 0
    g_menu.menu_opt_delta          = 0
    g_menu.menu_apply_selected_opt = false
    g_menu.menu_opt_angle_offset   = 0
}

/* Call when changing back to menu */
setup_menu :: proc() {
    init_menu()
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

/* Initialize special abilities / Can be done compile time? */
init_specials :: proc() {
    /* SHOOT */ {
        sp := &g_specials[ESpecialType.SHOOT]
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
        sp.special_cooldown_time = 0.5
    }

    /* PUNCH */ {
        sp := &g_specials[ESpecialType.PUNCH]
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
        sp.special_cooldown_time = 1.5
    }

    /* ENLARGE */ {
        sp := &g_specials[ESpecialType.ENLARGE]
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
        sp.special_cooldown_time = 0.5
    }
}

aabb :: proc(a_pos, a_size : vec2, b_pos, b_size : vec2) -> bool {
    return !(a_pos.x >= (b_pos.x + b_size.x) 
        ||  (a_pos.x + a_size.x) <= b_pos.x 
        ||   a_pos.y >= (b_pos.y + b_size.y) 
        ||  (a_pos.y + a_size.y) <= b_pos.y)
}

get_paddle_collider :: proc(paddle : Paddle) -> (vec2, vec2) {
    size := mult(paddle.size, paddle.size_mult)

    pos : vec2
    pos.y = paddle.pos.y - (size.y - paddle.size.y) * 0.5
    if paddle.side == .LEFT {
        pos.x = paddle.pos.x
    } else {
        pos.x = paddle.pos.x - (size.x - paddle.size.x)
    }
    return pos, size
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

update_ball :: proc(ball : ^Ball, delta_time : f32) {
    window_w := f32(GAME_WIDTH)
    window_h := f32(GAME_HEIGHT)
    
    ball.pos = add(ball.pos, mult_f(ball.dir, (ball.speed * ball.speed_mult) * delta_time))

    /* Check for collision with sides */ {
        if ball.pos.x <= 0.0 {
            ball.pos.x = 0.0
            ball.dir.x *= -1.0

            add_points_r(1)
        }
    
        if ball.pos.y <= 0.0 {
            ball.pos.y = 0.0
            ball.dir.y *= -1.0
        }
    
        if (ball.pos.x + ball.size.x) >= window_w {
            ball.pos.x = window_w - ball.size.x
            ball.dir.x *= -1

            add_points_l(1)
        }
    
        if (ball.pos.y + ball.size.y) >= window_h {
            ball.pos.y = window_h - ball.size.y
            ball.dir.y *= -1
        }
    }
}

draw_ball :: proc(ball : Ball) {
    ball_color := ball.color
    ball_center := add(ball.pos, mult_f(ball.size, 0.5))
    ball_radius := mult_f(ball.size, 0.5)
    raylib.DrawEllipse(i32(ball_center.x), i32(ball_center.y), ball_radius.x, ball_radius.y, ball_color)

    if g_debug_draw {
        /* Rectangle */
        r_color := ball.color
        r_color.a = 0x42
        raylib.DrawRectangle(i32(ball.pos.x), i32(ball.pos.y), i32(ball.size.x), i32(ball.size.y), r_color)

        /* Direction */
        line_col := raylib.Color{ 188, 188, 166, 255 }
        line_len :: 48.0
        line_start := add(ball.pos, mult_f(ball.size, 0.5))
        line_end := add(line_start, mult_f(ball.dir, line_len))
        raylib.DrawLine(i32(line_start.x), i32(line_start.y), i32(line_end.x), i32(line_end.y), line_col)
    }
}

draw_paddle :: proc(paddle : Paddle) {
    /* If recovers, draw not fully opaque */
    paddle_color := paddle.color
    if paddle.special_state == .RECOVER {
        paddle_color.a = 128
    }

    /* Do blinking to indicate cooldown */
    if paddle.special_cooldown_t > 0.0 {
        cosine := math.cos(g_game.game_time_elapsed * 10.0) * 0.5 + 0.5
        paddle_color.a = 32 + u8(cosine * 164.0)
    }

    draw_pos, draw_size := get_paddle_collider(paddle)
    raylib.DrawRectangle(i32(draw_pos.x), i32(draw_pos.y), i32(draw_size.x), i32(draw_size.y), paddle_color)

    /* Base size */
    if g_debug_draw {
        raylib.DrawRectangle(i32(paddle.pos.x), i32(paddle.pos.y), i32(paddle.size.x), i32(paddle.size.y), { 255, 255, 255, 32 })
    }
}

update_paddle_special :: proc(paddle : ^Paddle, delta_time : f32) {
    special := g_specials[paddle.special_type]

    switch paddle.special_state {
        case .NONE: {
            /* Update special cooldown */
            if paddle.special_cooldown_t > 0.0 {
                paddle.special_cooldown_t -= delta_time
            }

            for &ball in g_game.balls {
                ball_x_dir := i32(math.sign(ball.dir.x))
        
                /* Check for collision with paddle if the ball moves towards it */
                if ball_x_dir == i32(paddle.side) {
                    if check_collision(paddle, &ball) {
                        perc, hit := get_ball_paddle_hit_perc(paddle^, ball)
                        assert(hit)
        
                        p_pos, p_size := get_paddle_collider(paddle^)
                        if paddle.side == .LEFT {
                            ball.pos.x = p_pos.x + p_size.x
                        } else {
                            ball.pos.x = p_pos.x - ball.size.x
                        }

                        // @TODO Angle
                        ball.dir.x *= -1
                        ball.dir.y = ((perc - 0.5) * 2.0)
                        ball.dir = norm(ball.dir)
                        ball.speed_mult = 1.0
                    }
                }
            }
        }

        case ESpecialState.SPECIAL: {
            /* Update special timer */
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
    
            for &ball in g_game.balls {
                if !check_collision(paddle, &ball) {
                    continue
                }

                p_pos, p_size := get_paddle_collider(paddle^)

                col_side := get_ball_collision_side(paddle^, ball)
                if col_side != 0 {

                    /* Put ball close to paddle */
                    if col_side == 1 {
                        ball.pos.y = p_pos.y + p_size.y
                    } else {
                        ball.pos.y = p_pos.y - ball.size.y
                    }

                    // @TODO Angles
                    ball.dir.x = math.sign(ball.dir.x)
                    ball.dir.y = f32(col_side)
                    ball.dir = norm(ball.dir)
                    continue
                }

                if(paddle.side == .LEFT) {
                    ball.pos.x = p_pos.x + p_size.x
                } else {
                    ball.pos.x = p_pos.x - ball.size.x
                }

                special_dir := -f32(paddle.side)

                if special.special_shoots_forward {
                    ball.dir = vec2{ special_dir, 0.0 }
                } else {
                    perc, hit := get_ball_paddle_hit_perc(paddle^, ball)
                    assert(hit)

                    ball.dir.x = special_dir
                    ball.dir.y = ((perc - 0.5) * 2.0)
                    ball.dir = norm(ball.dir)

                    paddle.hit_ball_t = 1.0
                }

                ball.speed_mult = special.special_hit_power
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
                paddle.special_cooldown_t = special.special_cooldown_time
            }
        }
    }

    move_func := paddle.special_state == .RECOVER ? special.special_move_func_recover : special.special_move_func
    size_func := paddle.special_state == .RECOVER ? special.special_size_func_recover : special.special_size_func

    size_perc_t := special_func(paddle.special_t, size_func)
    paddle.size_mult = add(vec2_make(1.0), mult(special.special_size_mult_add, vec2_make(size_perc_t)))

    /* Update paddle x pos */
    if paddle.special_state == .NONE {
        if paddle.side == .LEFT {
            paddle.pos.x = GAME_PADDLE_OFFSET
        } else {
            paddle.pos.x = f32(GAME_WIDTH) - GAME_PADDLE_OFFSET - paddle.size.x
        }
    } else {
        move_perc_t := special_func(paddle.special_t, move_func)

        if paddle.side == .LEFT {
            paddle.pos.x = GAME_PADDLE_OFFSET + special.special_dist * move_perc_t
        } else {
            paddle.pos.x = f32(GAME_WIDTH) - GAME_PADDLE_OFFSET - paddle.size.x - special.special_dist * move_perc_t
        }
    }
}

update_paddle :: proc(paddle : ^Paddle, binds : PlayerKeyBinds, delta_time : f32) {
    /* Special move */
    if raylib.IsKeyDown(binds.special_move) {
        if paddle.special_state == .NONE && paddle.special_cooldown_t <= 0.0 {
            paddle.special_state = .SPECIAL
            paddle.special_t     = 0.0
        }
    }

    /* Move in Y-Axis */
    dir : f32 = 0.0
    if raylib.IsKeyDown(binds.move_up)   { dir -= 1.0 }
    if raylib.IsKeyDown(binds.move_down) { dir += 1.0 }
    paddle.pos.y += dir * paddle.speed * delta_time
    paddle.pos.y = clamp(paddle.pos.y, 0.0, f32(GAME_HEIGHT) - paddle.size.y)

    /* Update special move */
    NUM_UPDATES    :: 8
    one_delta_time := delta_time / f32(NUM_UPDATES)

    for idx in 1..=NUM_UPDATES {
        update_paddle_special(paddle, one_delta_time)
    }
}

update_and_draw_ui :: proc(delta_time : f32) {
    full_window_y := i32(GAME_HEIGHT)
    half_window_x := i32(GAME_WIDTH / 2)

    if g_game.font_size_t > 0.0 {
        g_game.font_size_t -= 1.0 * delta_time
    } else {
        g_game.font_size_t = 0.0
    }
    font_size : i32 = GAME_FONT_SIZE + cast(i32)(g_game.font_size_t * cast(f32)(GAME_FONT_SIZE_MAX - GAME_FONT_SIZE))

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

        update_flash_timer(delta_time, &g_game.points_l_flash_t)
        update_flash_timer(delta_time, &g_game.points_r_flash_t)
        update_flash_timer(delta_time, &g_game.game_time_sec_flash_t)
        update_flash_timer(delta_time, &g_game.game_time_min_flash_t)
    }

    PADDING_X          :: 8
    TEXT_COLOR_A_BASE  :: 48
    TEXT_COLOR_A_FLASH :: 255

    get_text_color :: proc(a : u8) -> raylib.Color {
        return { 0xFF, 0xFF, 0xFF, a }
    }

    /* Draw points for left player */ {
        text_color := get_text_color(TEXT_COLOR_A_BASE + u8(g_game.points_l_flash_t * f32(TEXT_COLOR_A_FLASH - TEXT_COLOR_A_BASE)))

        str_points_l := fmt.ctprintf("%v", g_game.points_l)
        str_points_l_w := raylib.MeasureText(str_points_l, font_size)
        raylib.DrawText(str_points_l, half_window_x - str_points_l_w - PADDING_X, 0, font_size, text_color)
    }

    /* Draw points for right player */ {
        text_color := get_text_color(TEXT_COLOR_A_BASE + u8(g_game.points_r_flash_t * f32(TEXT_COLOR_A_FLASH - TEXT_COLOR_A_BASE)))

        str_points_r := fmt.ctprintf("%v", g_game.points_r)
        str_points_r_w := raylib.MeasureText(str_points_r, font_size)
        raylib.DrawText(str_points_r, half_window_x + PADDING_X, 0, font_size, text_color)
    }

    /* Draw game time */ {
        text_y_bottom := full_window_y - font_size

        text_color     := get_text_color(TEXT_COLOR_A_BASE + u8(0.0 * f32(TEXT_COLOR_A_FLASH - TEXT_COLOR_A_BASE)))
        text_color_min := get_text_color(TEXT_COLOR_A_BASE + u8(g_game.game_time_min_flash_t * f32(TEXT_COLOR_A_FLASH - TEXT_COLOR_A_BASE)))
        text_color_sec := get_text_color(TEXT_COLOR_A_BASE + u8(g_game.game_time_sec_flash_t * f32(TEXT_COLOR_A_FLASH - TEXT_COLOR_A_BASE)))

        /* Minutes */
        str_game_time_min   := fmt.ctprintf("%02d", g_game.game_time_min)
        str_game_time_min_w := raylib.MeasureText(str_game_time_min, font_size)
        raylib.DrawText(str_game_time_min, half_window_x - str_game_time_min_w - PADDING_X, text_y_bottom, font_size, text_color_min)

        /* Seconds */
        str_game_time_sec   := fmt.ctprintf("%02d", i32(math.floor(g_game.game_time_sec)))
        str_game_time_sec_w := raylib.MeasureText(str_game_time_sec, font_size)
        raylib.DrawText(str_game_time_sec, half_window_x + PADDING_X, text_y_bottom, font_size, text_color_sec)

        /* : */
        raylib.DrawText(":", half_window_x - raylib.MeasureText(":", font_size) / 2, text_y_bottom, font_size, text_color)
    }

    if g_debug_draw {
        raylib.DrawFPS(0, full_window_y - 16)

        window_right := f32(GAME_WIDTH)
        debug_text_color := raylib.Color{ 188, 188, 166, 128 }

        debug_font_size :: 20
        for &ball in g_game.balls {
            str := fmt.ctprintf("%.1f,%.1f", ball.pos.x, ball.pos.y)
            raylib.DrawText(str, i32(ball.pos.x + ball.size.x * 0.5 - f32(raylib.MeasureText(str, debug_font_size) / 2)), i32(ball.pos.y - debug_font_size), debug_font_size, debug_text_color)
        }

        /* L paddle */ {
            p_pos, p_size := get_paddle_collider(g_game.paddle_l)

            strl := fmt.ctprintf("%f", p_pos.x)
            raylib.DrawText(strl, GAME_PADDLE_OFFSET, i32(g_game.paddle_l.pos.y) - debug_font_size, debug_font_size, debug_text_color)

            strr := fmt.ctprintf("%f", p_pos.x + p_size.x)
            raylib.DrawText(strr, GAME_PADDLE_OFFSET, i32(g_game.paddle_l.pos.y + g_game.paddle_l.size.y), debug_font_size, debug_text_color)
        }

        /* R paddle */ {
            p_pos, p_size := get_paddle_collider(g_game.paddle_r)

            strl := fmt.ctprintf("%f", p_pos.x + p_size.x)
            raylib.DrawText(strl, i32(window_right - GAME_PADDLE_OFFSET - f32(raylib.MeasureText(strl, debug_font_size))), i32(g_game.paddle_r.pos.y) - debug_font_size, debug_font_size, debug_text_color)

            strr := fmt.ctprintf("%f", p_pos.x)
            raylib.DrawText(strr, i32(window_right - GAME_PADDLE_OFFSET - f32(raylib.MeasureText(strr, debug_font_size))), i32(g_game.paddle_r.pos.y + g_game.paddle_r.size.y), debug_font_size, debug_text_color)
        }
    }
}

game_over :: proc() {
    change_to_state_transition(.MAIN_MENU)
}

update_and_draw_game :: proc(delta_time : f32) {
    g_game.game_time_elapsed += delta_time

    last_game_time_min := g_game.game_time_min
    last_game_time_sec := i32(math.floor(g_game.game_time_sec))

    /* Update game time */
    g_game.game_time_sec -= delta_time
    if g_game.game_time_sec <= 0.0 {
        g_game.game_time_min -= 1
        g_game.game_time_sec += 60.0
    }

    now_game_time_sec := i32(math.floor(g_game.game_time_sec))

    if g_game.game_time_min < 0 {
        game_over()
        return
    }

    /* Set ui flash timers */
    if last_game_time_min != g_game.game_time_min {
        g_game.game_time_min_flash_t = 1.0
    } 
    if last_game_time_sec != now_game_time_sec {
        g_game.game_time_sec_flash_t = 1.0

        /* Add new ball every ~30 seconds */
        if now_game_time_sec == 30 || now_game_time_sec == 0 {
            add_ball()
        }
    }


    /* Divide delta time and do multiple steps to improve accuracy, hacky? */
    UPDATE_STEPS :: 4
    update_step_dt := delta_time / f32(UPDATE_STEPS)
    for step in 0..<4 {
        /* Update paddles */ {
            update_paddle(&g_game.paddle_l, g_binds_l, update_step_dt)
            update_paddle(&g_game.paddle_r, g_binds_r, update_step_dt)
        }

        for &ball in g_game.balls {
            update_ball(&ball, update_step_dt)
        }
    }

    /* Draw game */ {
        camera : raylib.Camera2D
        camera.zoom = f32(raylib.GetScreenWidth()) / f32(GAME_WIDTH) // @HACK
    
        raylib.ClearBackground(DEF_BG_COLOR)
        raylib.BeginDrawing()
        raylib.BeginMode2D(camera)
    
        for &ball in g_game.balls {
            draw_ball(ball)
        }
    
        draw_paddle(g_game.paddle_l)
        draw_paddle(g_game.paddle_r)
    
        update_and_draw_ui(delta_time)
        
        raylib.EndMode2D()
        raylib.EndDrawing()
    }
}

change_menu_selection :: proc(delta : i32) {
    assert(delta == -1 || delta == 1)

    g_menu.menu_opt_selected_idx += delta
    g_menu.menu_opt_delta += delta

    if g_menu.menu_opt_selected_idx < 0 {
        g_menu.menu_opt_selected_idx = len(menu_options) - 1
    } else if g_menu.menu_opt_selected_idx >= len(menu_options) {
        g_menu.menu_opt_selected_idx = 0
    }
}

update_and_draw_menu :: proc(delta_time : f32) {
    screen_w := GAME_WIDTH
    screen_h := GAME_HEIGHT

    /* Update logo pos */
    g_menu.menu_logo_pos = add(g_menu.menu_logo_pos, mult_f(g_menu.menu_logo_dir, delta_time * MENU_LOGO_SPEED))
    menu_logo_size : vec2 = { f32(raylib.MeasureText(MENU_LOGO_TITLE, MENU_LOGO_FONT_SIZE)), f32(MENU_LOGO_FONT_SIZE) }

    /* Check for logo collision with sides */ {
        region_r := f32(GAME_WIDTH)
        region_b := f32(GAME_HEIGHT)
        region_x := f32(0.0)
        region_y := f32(0.0)

        if g_menu.menu_logo_pos.x <= region_x {
            g_menu.menu_logo_pos.x = region_x
            g_menu.menu_logo_dir.x *= -1.0
        }
    
        if g_menu.menu_logo_pos.y <= region_y {
            g_menu.menu_logo_pos.y = region_y
            g_menu.menu_logo_dir.y *= -1.0
        }
    
        if (g_menu.menu_logo_pos.x + menu_logo_size.x) >= region_r {
            g_menu.menu_logo_pos.x = region_r - menu_logo_size.x
            g_menu.menu_logo_dir.x *= -1
        }
    
        if (g_menu.menu_logo_pos.y + menu_logo_size.y) >= region_b {
            g_menu.menu_logo_pos.y = region_b - menu_logo_size.y
            g_menu.menu_logo_dir.y *= -1
        }
    }

    /* Apply selected menu option */
    if g_menu.menu_apply_selected_opt {
        switch EMenuOption(g_menu.menu_opt_selected_idx) {
            case .START_GAME: {
                change_to_state_transition(.GAMEPLAY)
            }

            case .TOGGLE_FC: {
                raylib.ToggleBorderlessWindowed()
            }

            case .DEBUG_MODE: {
                g_debug_draw = !g_debug_draw
            }

            case .QUIT: {
                g_close_window = true
                return
            }
        }

        // eh
        g_menu.menu_apply_selected_opt = false
    }

    /* Draw menu */ {
        camera : raylib.Camera2D
        camera.zoom = f32(raylib.GetScreenWidth()) / f32(GAME_WIDTH) // @HACK

        raylib.ClearBackground(DEF_BG_COLOR)
        raylib.BeginDrawing()
        raylib.BeginMode2D(camera)
    
        center_x :: i32(GAME_WIDTH  / 2)
        center_y :: i32(GAME_HEIGHT / 2)

        /* Draw menu logo */ {
            logo_color := MENU_LOGO_COLOR
            logo_str_w := raylib.MeasureText(MENU_LOGO_TITLE, MENU_LOGO_FONT_SIZE)

            /* Is logo in menu radius */
            if dist(vec2{ f32(center_x), f32(center_y) }, add(g_menu.menu_logo_pos, vec2{ f32(logo_str_w / 2), f32(MENU_LOGO_FONT_SIZE / 2) })) < MENU_OPT_RADIUS {
                logo_color.a = 255
            }    

            raylib.DrawText(MENU_LOGO_TITLE, i32(g_menu.menu_logo_pos.x), i32(g_menu.menu_logo_pos.y), MENU_LOGO_FONT_SIZE, logo_color)    
        }


        /* Draw menu options */
        for &option, idx in menu_options {
            opt_str_w := raylib.MeasureText(option, MENU_OPT_FONT_SIZE)

            EPS       :: f32(0.01)
            ONE_ANGLE :: f32((PI * 2.0) / f32(len(menu_options)))

            /* Update menu rotation */ {
                angle_target := f32(g_menu.menu_opt_delta) * ONE_ANGLE
                if math.abs(angle_target - g_menu.menu_opt_angle_offset) < EPS {
                    g_menu.menu_opt_angle_offset = angle_target
                } else {
                    g_menu.menu_opt_angle_offset = math.lerp(g_menu.menu_opt_angle_offset, angle_target, delta_time * 0.75)
                }
            }

            angle_offset : f32 = -g_menu.menu_opt_angle_offset
            opt_x := i32(math.sin(angle_offset + ONE_ANGLE * f32(idx)) * MENU_OPT_RADIUS) + center_x - opt_str_w / 2
            opt_y := i32(math.cos(angle_offset + ONE_ANGLE * f32(idx)) * MENU_OPT_RADIUS) + center_y - MENU_OPT_FONT_SIZE / 2

            opt_draw_color := g_menu.menu_opt_selected_idx == i32(idx) ? MENU_OPT_COLOR_HOT : MENU_OPT_COLOR
                
            raylib.DrawText(option, opt_x, opt_y, MENU_OPT_FONT_SIZE, opt_draw_color)
        }

        /* Draw menu circle */
        raylib.DrawCircle(center_x, center_y, MENU_OPT_RADIUS, { 255, 255, 255, 32 })

        if g_debug_draw {
            raylib.DrawFPS(0, i32(screen_h - 16))
        }

        raylib.EndMode2D()
        raylib.EndDrawing()
    }
}

update_and_draw_transition :: proc(delta_time : f32) {
    g_transition.transition_t += delta_time
    if g_transition.transition_t >= TRANSITION_TIME {
        switch g_transition.transition_target {
            case .TRANSITION: {
                assert(false) // Can't happen
            }

            case .MAIN_MENU: {
                change_to_state_main_menu()
            }

            case .GAMEPLAY: {
                change_to_state_gameplay()
            }
        }
    }

    center_x := GAME_WIDTH  / 2
    center_y := GAME_HEIGHT / 2

    t_minus_one_to_one := (g_transition.transition_t / TRANSITION_TIME * 2.0) - 1.0
    // perc := special_func(t_minus_one_to_one, .SQRT)
    perc := square_f(t_minus_one_to_one) * 2.0 * t_minus_one_to_one * (t_minus_one_to_one / 2.0)
    clear_color := DEF_BG_COLOR
    clear_color.x = u8(perc * f32(DEF_BG_COLOR.x))
    clear_color.y = u8(perc * f32(DEF_BG_COLOR.y))
    clear_color.z = u8(perc * f32(DEF_BG_COLOR.z))

    camera : raylib.Camera2D
    camera.zoom = f32(raylib.GetScreenWidth()) / f32(GAME_WIDTH) // @HACK

    raylib.ClearBackground(clear_color)
    raylib.BeginDrawing()
    raylib.BeginMode2D(camera)

    if g_debug_draw {
        font_size  := i32(60)
        text_color := raylib.Color{ 255, 255, 255, 255 }
        str := fmt.ctprintf("%.2f | %.2f", g_transition.transition_t, TRANSITION_TIME)
        str_w := raylib.MeasureText(str, font_size)
        raylib.DrawText(str, center_x - str_w / 2, center_y - font_size / 2, font_size, text_color)
    }

    raylib.EndMode2D()
    raylib.EndDrawing()
}

change_to_state_gameplay :: proc(start_new : bool = true) {
    g_state = .GAMEPLAY
    if start_new {
        start_game_session()
    }
}

change_to_state_main_menu :: proc() {
    g_state = .MAIN_MENU
    setup_menu()
}

change_to_state_transition :: proc(state : EState) {
    assert(state != .TRANSITION)

    g_state = .TRANSITION
    g_transition.transition_target = state
    g_transition.transition_t      = 0.0
}

main :: proc() {
    /* Set window config flags */
    if INIT_WINDOW_VSYNC { raylib.SetConfigFlags({ raylib.ConfigFlag.VSYNC_HINT }) }

    raylib.InitWindow(INIT_WINDOW_WIDTH, INIT_WINDOW_HEIGHT, INIT_WINDOW_TITLE)
    raylib.SetExitKey(raylib.KeyboardKey(0))

    // @HACK
    if INIT_WINDOW_WIDTH == 1920 {
        raylib.ToggleFullscreen()
    }

    /* Set key binds */ {
        g_binds_l.move_up      = .UP
        g_binds_l.move_down    = .DOWN
        g_binds_l.special_move = .SPACE
    
        g_binds_r.move_up      = .PAGE_UP
        g_binds_r.move_down    = .PAGE_DOWN
        g_binds_r.special_move = .HOME
    }

    init_specials()
    init_menu()
    init_game()

    for !raylib.WindowShouldClose() {
        /* IsKeyPressed before polling events, idk why @check */ {
            if g_state == .GAMEPLAY {
                if raylib.IsKeyPressed(.ESCAPE) { change_to_state_transition(.MAIN_MENU) }
            }

            // @todo @move
            if g_state == .MAIN_MENU {
                if raylib.IsKeyPressed(.LEFT)   { change_menu_selection(-1) }
                if raylib.IsKeyPressed(.RIGHT)  { change_menu_selection(+1) }
                if raylib.IsKeyPressed(.ENTER)  { g_menu.menu_apply_selected_opt = true }
                if raylib.IsKeyPressed(.ESCAPE) { g_close_window = true }
            }
        }
        raylib.PollInputEvents()

        delta_time := raylib.GetFrameTime()

        if g_debug_draw {
            if raylib.IsKeyDown(raylib.KeyboardKey.LEFT_CONTROL) { delta_time *= 0.1 }
        }

        switch g_state {
            case .MAIN_MENU: {
                update_and_draw_menu(delta_time)
            }
            case .GAMEPLAY: {
                update_and_draw_game(delta_time)
            }
            case .TRANSITION: {
                update_and_draw_transition(delta_time)
            }
        }
        
        if g_close_window {
            raylib.CloseWindow()
        }
    }
}
