package pong

import "core:math"

PI :: 3.14159265

vec2 :: struct {
	x, y : f32
}

vec2_make :: proc(v : f32) -> vec2 {
	return vec2{ v, v }
}

square :: proc(a : vec2) -> vec2 {
	return mult(a, a)
}

cube :: proc(a : vec2) -> vec2 {
	return mult(mult(a, a), a)
}

square_f :: proc(a : f32) -> f32 {
	return a * a
}

cube_f :: proc(a : f32) -> f32 {
	return a * a * a
}

add :: proc(a, b : vec2) -> vec2 {
	return vec2{
		a.x + b.x,
		a.y + b.y
	}
}

sub :: proc(a, b : vec2) -> vec2 {
	return vec2{
		a.x - b.x,
		a.y - b.y
	}
}

mult_f :: proc(a : vec2, b : f32) -> vec2 {
	return vec2{
		a.x * b,
		a.y * b
	}
}

mult :: proc(a, b : vec2) -> vec2 {
	return vec2{
		a.x * b.x,
		a.y * b.y
	}
}

dot :: proc(a, b : vec2) -> f32 {
	return a.x * b.x + a.y * b.y
}

length_sq :: proc(a : vec2) -> f32 {
	return dot(a, a)
}

length :: proc(a : vec2) -> f32 {
	return math.sqrt(length_sq(a))
}

norm :: proc(a : vec2) -> vec2 {
	a_len := length(a)
	return vec2{
		a.x / a_len,
		a.y / a_len
	}
}

dist :: proc(a, b : vec2) -> f32 {
	return length(sub(a, b))
}