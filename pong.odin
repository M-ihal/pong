package main

import "core:fmt"
import "vendor:raylib"
import "core:math"

init_window_size_x : i32 = 960 / 2
init_window_size_y : i32 = 640 / 2
init_window_title  : cstring = "Title"
background_color : raylib.Color = { 32, 32, 32, 255 }

vec2 :: struct {
	x, y : f32
}

add :: proc(a, b : vec2) -> vec2 {
	return vec2{
		a.x + b.x,
		a.y + b.y
	}
}

mult :: proc(a : vec2, b : f32) -> vec2 {
	return vec2{
		a.x * b,
		a.y * b
	}
}

dot :: proc(a, b : vec2) -> f32 {
	return a.x * b.x + a.y * b.y
}

len_sq :: proc(a : vec2) -> f32 {
	return dot(a, a)
}

len :: proc(a : vec2) -> f32 {
	return math.sqrt(len_sq(a))
}

norm :: proc(a : vec2) -> vec2 {
	a_len := len(a)
	return vec2{
		a.x / a_len,
		a.y / a_len
	}
}

Ball :: struct {
	pos    : vec2,
	dir    : vec2,
	size   : vec2,
	speed  : f32,
	color  : raylib.Color
}

Paddle :: struct {
	pos   : vec2,
	size  : vec2,
	speed : f32,
	color : raylib.Color,

	do_shoot : bool,
	shoot_t  : f32
}

aabb :: proc(a_pos, a_size : vec2, b_pos, b_size : vec2) -> bool {
	does_collide := !(a_pos.x >= (b_pos.x + b_size.x) || (a_pos.x + a_size.x) <= b_pos.x || a_pos.y >= (b_pos.y + b_size.y) || (a_pos.y + a_size.y) <= b_pos.y)
	return does_collide
}

update_paddle :: proc(paddle : ^Paddle, move_dir : i32, delta_time : f32) {
	if paddle.do_shoot {
		paddle.shoot_t += delta_time * 10.0
		if paddle.shoot_t >= 1.0 {
			paddle.do_shoot = false
			paddle.shoot_t = 0.0
		}

		shoot_dist : f32 = 32.0
		paddle.pos.x = 8.0 + shoot_dist * paddle.shoot_t
	}

	paddle.pos.y += auto_cast move_dir * paddle.speed * delta_time

	paddle.pos.y = clamp(paddle.pos.y, 0.0, cast(f32)raylib.GetScreenHeight() - paddle.size.y)
}

update_ball :: proc(ball : ^Ball, paddle : ^Paddle, delta_time : f32) {
	// todo  Go pixel by pixel

	ball.dir = norm(ball.dir)

	// Before move
	collides_with_paddle := aabb(ball.pos, ball.size, paddle.pos, paddle.size)

	next_pos := ball.pos;
	next_pos = add(next_pos, mult(ball.dir, ball.speed * delta_time))

	// After the move
	collided_with_paddle := aabb(next_pos, ball.size, paddle.pos, paddle.size)

	update_position := true

	is_to_the_right_of_paddle := (next_pos.x + ball.size.x * 0.0) >= (paddle.pos.x + paddle.size.x * 0.5);

	if collided_with_paddle && is_to_the_right_of_paddle {
		next_pos.x = paddle.pos.x + paddle.size.x
		if paddle.do_shoot && paddle.shoot_t > 0.0 {
			ball.dir.x *= -1
			ball.dir = norm(ball.dir)
			ball.dir.x *= 25.0
		} else {
			ball.dir.x *= -1
		}
	} else {
		if next_pos.x <= 0.0 || (next_pos.x + ball.size.x) >= cast(f32)raylib.GetScreenWidth() {
			update_position = false
			ball.dir.x *= -1
		}
	
		if next_pos.y < 0.0 || (next_pos.y + ball.size.y) >= cast(f32)raylib.GetScreenHeight() {
			ball.dir.y *= -1
		}
	}

	if update_position {
		ball.pos.x = next_pos.x	
		ball.pos.y = next_pos.y
	}
}

draw_ball :: proc(ball : Ball) {
	// void DrawCircle(int centerX, int centerY, float radius, Color color);       
	raylib.DrawRectangle(auto_cast ball.pos.x, auto_cast ball.pos.y, auto_cast ball.size.x, auto_cast ball.size.y, ball.color)

	line_col := raylib.Color{ 0x44, 0xAA, 0x33, 0xFF }
	line_len : f32 = 48.0
	line_start := add(ball.pos, mult(ball.size, 0.5))
	line_end := add(line_start, mult(ball.dir, line_len))
	raylib.DrawLine(auto_cast line_start.x, auto_cast line_start.y, auto_cast line_end.x, auto_cast line_end.y, line_col)
}

draw_paddle :: proc(paddle : Paddle) {
	raylib.DrawRectangle(auto_cast paddle.pos.x, auto_cast paddle.pos.y, auto_cast paddle.size.x, auto_cast paddle.size.y, paddle.color)
}

main :: proc() {
	raylib.InitWindow(init_window_size_x, init_window_size_y, init_window_title)

	balls : [dynamic]Ball

	/* Add ball */ {
		ball : Ball;
		ball.size.x = 12.0
		ball.size.y = 12.0
		ball.pos.x  = cast(f32)raylib.GetScreenWidth()  * 0.5 - ball.size.x * 0.5
		ball.pos.y  = cast(f32)raylib.GetScreenHeight() * 0.5 - ball.size.y * 0.5
		ball.dir.x  = +1.0
		ball.dir.y  = -1.0
		ball.speed  = 256.0
		ball.color  = (raylib.Color){ 255, 255, 255, 255 }

		append_elem(&balls, ball)
	}

	l_paddle : Paddle
	l_paddle.pos.x = 8
	l_paddle.pos.y = 0
	l_paddle.size.x = 8
	l_paddle.size.y = 64
	l_paddle.speed = 512
	l_paddle.color = { 255, 32, 127, 255 }

	r_paddle : Paddle
	r_paddle.size.x = 8
	r_paddle.size.y = 64
	r_paddle.pos.x = cast(f32)raylib.GetScreenWidth() - 8 - r_paddle.size.x
	r_paddle.pos.y = 0
	r_paddle.speed = 322
	r_paddle.color = { 255, 92, 32, 255 }

	for !raylib.WindowShouldClose() {
		raylib.PollInputEvents()

		delta_time := raylib.GetFrameTime()

		if raylib.IsKeyDown(raylib.KeyboardKey.LEFT_CONTROL) { delta_time *= 0.1 }

		if raylib.IsKeyDown(raylib.KeyboardKey.SPACE) { 
			l_paddle.shoot_t  = 0.0
			l_paddle.do_shoot = true
		}

		move_dir : i32 = 0
		if raylib.IsKeyDown(raylib.KeyboardKey.UP)   { move_dir -= 1 }
		if raylib.IsKeyDown(raylib.KeyboardKey.DOWN) { move_dir += 1 }
		update_paddle(&l_paddle, move_dir, delta_time)

		update_paddle(&r_paddle, move_dir, delta_time)

		for &ball in balls {
			update_ball(&ball, &l_paddle, delta_time)
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

		draw_paddle(l_paddle)
		draw_paddle(r_paddle)

		raylib.EndMode2D()
		raylib.EndDrawing()
	}
}