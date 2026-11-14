extends Node2D

@export var player: RigidBody2D
@export var hand_sprite: Node2D
@export var hand_open_texture: Texture2D
@export var hand_closed_texture: Texture2D
@export var arm_origin: Node2D
@onready var line: Line2D = $Line

@export_group("Shot")
@export var shoot_speed := 850.0
@export var hand_gravity := 500.0
@export var max_rope_length := 450.0
@export var retract_time := 0.2

@export_group("Reel")
@export var starting_reel_speed := 60.0
@export var reel_acceleration := 1300.0
@export var max_reel_speed := 950.0
@export var min_rope_length := 20.0

@export_group("Rope")
@export var rope_stiffness := 70.0
@export var rope_damping := 9.0
@export var max_stretch := 45.0
@export var rope_gravity := 150.0
@export var loose_hand_gravity := 500.0
@export var hand_drag_weight := 0.6
@export_range(0.0, 1.0) var rope_friction := 0.3
@export_range(0.0, 1.0) var rope_end_bounce := 0.1

@export_group("Rules")
@export var grab_after_rope_runs_out := true
@export_range(0.0, 180.0) var max_grab_steepness := 180.0
@export var wall_slide_speed := 0.0
@export var shots_allowed_in_air := -1
@export_range(10.0, 90.0) var max_ground_steepness := 50.0

@export_group("Look")
@export var wave_size := 16.0
@export var wave_fade_speed := 5.0
@export var wave_count := 3.0
@export var rotate_hand := true
@export var hand_rotation_offset := 90.0
@export_range(0.0, 1.2) var wrist_position := 0.75

const ROPE_POINT_COUNT := 24
const DRAW_SAMPLE_COUNT := 48

var is_shooting := false
var is_retracting := false
var shot_waiting := false
var retract_progress := 0.0
var retract_offsets := PackedVector2Array()
var is_holding := false
var rope_is_loose := false
var rope_is_taut := false
var rope_points := PackedVector2Array()
var previous_rope_points := PackedVector2Array()
var bend_points: Array = []
var rope_length := 0.0
var current_rope_length := -1.0
var reel_time := 0.0
var reel_speed := 0.0
var grab_point := Vector2.ZERO
var is_sliding := false
var wall_normal := Vector2.ZERO
var time_since_shot := 0.0
var wave_strength := 0.0
var time_since_on_ground := 0.0
var air_shots_left := 0
var previous_player_position := Vector2.ZERO

var corner_cache := {}
var probe_circle := CircleShape2D.new()
var shape_query := PhysicsShapeQueryParameters2D.new()


func _ready() -> void:
	rope_points.resize(ROPE_POINT_COUNT + 1)
	previous_rope_points.resize(ROPE_POINT_COUNT + 1)
	player.contact_monitor = true
	player.max_contacts_reported = 8
	air_shots_left = shots_allowed_in_air
	previous_player_position = player.global_position
	shape_query.shape = probe_circle
	for child in player.get_children():
		if child is Camera2D:
			child.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if is_retracting:
				shot_waiting = true
			else:
				try_shoot()
		else:
			shot_waiting = false
			start_retract()


func try_shoot() -> void:
	if can_shoot():
		if time_since_on_ground >= 0.1 and shots_allowed_in_air >= 0:
			air_shots_left -= 1
		shoot(get_global_mouse_position())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		start_retract()


func can_shoot() -> bool:
	if is_retracting:
		return false
	return shots_allowed_in_air < 0 or time_since_on_ground < 0.1 or air_shots_left > 0


func start_retract() -> void:
	if not is_shooting:
		return
	is_shooting = false
	is_holding = false
	is_retracting = true
	retract_progress = 0.0
	var player_position := player.global_position
	retract_offsets.resize(ROPE_POINT_COUNT + 1)
	for i in ROPE_POINT_COUNT + 1:
		retract_offsets[i] = rope_points[i] - player_position


func _update_retract(delta: float) -> void:
	retract_progress += delta / maxf(retract_time, 0.001)
	if retract_progress >= 1.0:
		is_retracting = false
		if shot_waiting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			try_shoot()
		shot_waiting = false
		return
	var remaining := 1.0 - retract_progress * retract_progress
	var player_position := player.global_position
	for i in ROPE_POINT_COUNT + 1:
		rope_points[i] = player_position + retract_offsets[i] * remaining
	wave_strength *= exp(-wave_fade_speed * delta)
	time_since_shot += delta


func shoot(target: Vector2) -> void:
	var player_position := player.global_position
	var velocity := (target - player_position).normalized() * shoot_speed + player.linear_velocity
	var step_time := 1.0 / Engine.physics_ticks_per_second
	for i in ROPE_POINT_COUNT + 1:
		var along := float(i) / ROPE_POINT_COUNT
		rope_points[i] = player_position
		previous_rope_points[i] = player_position - velocity * along * step_time
	is_shooting = true
	is_holding = false
	rope_is_loose = false
	is_sliding = false
	rope_is_taut = true
	bend_points = []
	rope_length = 0.0
	current_rope_length = -1.0
	reel_time = 0.0
	time_since_shot = 0.0
	wave_strength = wave_size
	previous_player_position = player_position


func _physics_process(delta: float) -> void:
	_update_ground_check(delta)
	if is_shooting:
		_update_arm(delta)
	elif is_retracting:
		_update_retract(delta)
	previous_player_position = player.global_position
	_draw_rope()


func _update_ground_check(delta: float) -> void:
	time_since_on_ground += delta
	var body_state := PhysicsServer2D.body_get_direct_state(player.get_rid())
	if body_state == null:
		return
	var ground_limit := cos(deg_to_rad(max_ground_steepness))
	for i in body_state.get_contact_count():
		if body_state.get_contact_local_normal(i).y <= -ground_limit:
			time_since_on_ground = 0.0
			air_shots_left = shots_allowed_in_air
			return


func _update_arm(delta: float) -> void:
	time_since_shot += delta
	wave_strength *= exp(-wave_fade_speed * delta)
	var player_position := player.global_position

	if is_holding:
		if is_sliding:
			_slide_hand(delta)
		if is_holding:
			reel_time += delta
			reel_speed = minf(max_reel_speed, starting_reel_speed + reel_acceleration * reel_time)
			if current_rope_length < 0.0 or current_rope_length - (rope_length - reel_speed * delta) <= max_stretch:
				rope_length = maxf(min_rope_length, rope_length - reel_speed * delta)

	var hand_index := ROPE_POINT_COUNT
	var old_hand_position := rope_points[hand_index]
	rope_points[0] = player_position
	previous_rope_points[0] = player_position

	if is_holding:
		rope_points[hand_index] = grab_point
		previous_rope_points[hand_index] = grab_point
	else:
		var gravity := loose_hand_gravity if rope_is_loose else hand_gravity
		var hand_velocity := (rope_points[hand_index] - previous_rope_points[hand_index]) * 0.999
		previous_rope_points[hand_index] = rope_points[hand_index]
		rope_points[hand_index] += hand_velocity + Vector2(0.0, gravity * delta * delta)
		if not rope_is_loose or grab_after_rope_runs_out:
			var hit := _raycast(old_hand_position, rope_points[hand_index])
			if not hit.is_empty() and not _try_grab(hit.position, hit.normal):
				var surface_normal: Vector2 = hit.normal
				var movement := rope_points[hand_index] - old_hand_position
				var into_surface := movement.dot(surface_normal)
				rope_points[hand_index] = (hit.position as Vector2) + surface_normal * 5.0
				previous_rope_points[hand_index] = rope_points[hand_index] - (movement - into_surface * surface_normal) * 0.3
				rope_is_loose = true
		if not is_holding and rope_is_loose:
			var contact := _push_point_out(hand_index, 5.0)
			if not contact.is_empty() and grab_after_rope_runs_out:
				_try_grab(contact.point, contact.normal)
			if not is_holding:
				rope_length = max_rope_length

	if rope_is_taut and not is_holding and rope_is_loose:
		_place_points_along_rope()
		rope_is_taut = false
	if rope_is_taut:
		_update_bends(previous_player_position, old_hand_position)
		var taut_length := _get_taut_rope_length()
		if not is_holding:
			rope_length = minf(max_rope_length, taut_length)
			if taut_length >= max_rope_length:
				rope_is_loose = true
				_place_points_along_rope()
				rope_is_taut = false
				_absorb_rope_snap()
			else:
				_place_points_along_rope()
				return
		else:
			current_rope_length = taut_length
			_place_points_along_rope()
			_pull_player(taut_length, delta)
			return

	_simulate_loose_rope(delta, old_hand_position)


func _absorb_rope_snap() -> void:
	var player_position := player.global_position
	for i in range(1, ROPE_POINT_COUNT + 1):
		var outward := rope_points[i] - player_position
		if outward.length() < 0.001:
			continue
		outward = outward.normalized()
		var velocity := rope_points[i] - previous_rope_points[i]
		var outward_speed := velocity.dot(outward)
		if outward_speed > 0.0:
			velocity -= outward * outward_speed * (1.0 - rope_end_bounce)
		previous_rope_points[i] = rope_points[i] - velocity


func _pull_player(taut_length: float, delta: float) -> void:
	var stretch := taut_length - rope_length
	if stretch <= 0.0:
		return
	var player_position := player.global_position
	var pull_target: Vector2 = bend_points[-1].position if bend_points.size() > 0 else grab_point
	var to_target := pull_target - player_position
	var distance := to_target.length()
	if distance < 0.001:
		return
	var pull_direction := to_target / distance
	var velocity := player.linear_velocity
	var speed_toward_target := velocity.dot(pull_direction)
	if stretch > max_stretch and speed_toward_target < 0.0:
		velocity -= pull_direction * speed_toward_target
		speed_toward_target = 0.0
	var wanted_speed := reel_speed if rope_length > min_rope_length else 0.0
	var acceleration := rope_stiffness * minf(stretch, max_stretch) - rope_damping * (speed_toward_target - wanted_speed)
	if stretch > max_stretch:
		acceleration += rope_stiffness * (stretch - max_stretch) * 4.0
	if acceleration > 0.0:
		velocity += pull_direction * acceleration * delta
	player.linear_velocity = velocity


func _try_grab(point: Vector2, surface_normal: Vector2) -> bool:
	var steepness := rad_to_deg(acos(clampf(-surface_normal.y, -1.0, 1.0)))
	var can_hold := steepness <= max_grab_steepness + 0.01
	var will_slide := not can_hold and wall_slide_speed > 0.0
	if not can_hold and not will_slide:
		return false
	is_holding = true
	current_rope_length = -1.0
	grab_point = point + surface_normal * 2.0
	reel_time = 0.0
	wave_strength = maxf(wave_strength, wave_size * 0.6)
	is_sliding = will_slide
	wall_normal = surface_normal
	rope_points[ROPE_POINT_COUNT] = grab_point
	previous_rope_points[ROPE_POINT_COUNT] = grab_point
	if not rope_is_taut:
		_find_bends_from_loose_rope()
		rope_is_taut = true
	rope_length = minf(max_rope_length, _get_taut_rope_length())
	return true


func _slide_hand(delta: float) -> void:
	var slide_direction := Vector2(-wall_normal.y, wall_normal.x)
	if slide_direction.y < 0.0:
		slide_direction = -slide_direction
	if slide_direction.y < 0.2:
		_let_go_of_wall(slide_direction)
		return
	var next_point := grab_point + slide_direction * wall_slide_speed * delta
	var surface_check := _raycast(next_point + wall_normal * 6.0, next_point - wall_normal * 6.0)
	if surface_check.is_empty() or (surface_check.normal as Vector2).dot(wall_normal) < 0.9:
		_let_go_of_wall(slide_direction)
		return
	grab_point = (surface_check.position as Vector2) + (surface_check.normal as Vector2) * 2.0


func _let_go_of_wall(slide_direction: Vector2) -> void:
	is_holding = false
	rope_is_loose = true
	is_sliding = false
	current_rope_length = -1.0
	var hand_index := ROPE_POINT_COUNT
	previous_rope_points[hand_index] = rope_points[hand_index] - slide_direction * wall_slide_speed / Engine.physics_ticks_per_second


func _raycast(from: Vector2, to: Vector2) -> Dictionary:
	if from.distance_squared_to(to) < 1e-6:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [player.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query)


func _get_corners(hit: Dictionary) -> Array:
	var collider = hit.collider
	if not (collider is CollisionObject2D):
		return []
	var shape_node: Object = collider.shape_owner_get_owner(collider.shape_find_owner(hit.shape))
	var cache_key := shape_node.get_instance_id()
	if corner_cache.has(cache_key):
		return corner_cache[cache_key]
	var outline := PackedVector2Array()
	if shape_node is CollisionPolygon2D:
		var shape_transform: Transform2D = shape_node.global_transform
		for vertex in shape_node.polygon:
			outline.append(shape_transform * vertex)
	elif shape_node is CollisionShape2D:
		var shape_transform: Transform2D = shape_node.global_transform
		var shape: Shape2D = shape_node.shape
		if shape is RectangleShape2D:
			var half_size: Vector2 = shape.size * 0.5
			for vertex in [Vector2(-half_size.x, -half_size.y), Vector2(half_size.x, -half_size.y), Vector2(half_size.x, half_size.y), Vector2(-half_size.x, half_size.y)]:
				outline.append(shape_transform * vertex)
		elif shape is ConvexPolygonShape2D:
			for vertex in shape.points:
				outline.append(shape_transform * vertex)
	var corners: Array = []
	var corner_count := outline.size()
	if corner_count >= 3:
		var edge_normals: Array[Vector2] = []
		for i in corner_count:
			var edge_start := outline[i]
			var edge_end := outline[(i + 1) % corner_count]
			var edge_normal := Vector2(edge_end.y - edge_start.y, edge_start.x - edge_end.x).normalized()
			if Geometry2D.is_point_in_polygon((edge_start + edge_end) * 0.5 + edge_normal * 0.5, outline):
				edge_normal = -edge_normal
			edge_normals.append(edge_normal)
		for i in corner_count:
			var corner_normal := edge_normals[(i - 1 + corner_count) % corner_count] + edge_normals[i]
			corner_normal = corner_normal.normalized() if corner_normal.length() > 0.001 else edge_normals[i]
			corners.append({"position": outline[i], "normal": corner_normal})
	corner_cache[cache_key] = corners
	return corners


func _find_corner(fixed_end: Vector2, free_end_before: Vector2, free_end_now: Vector2, hit: Dictionary):
	var corners := _get_corners(hit)
	if corners.is_empty():
		return null
	var hit_position: Vector2 = hit.position
	var candidates: Array = []
	for corner in corners:
		candidates.append((corner.position as Vector2) + (corner.normal as Vector2) * 3.0)
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(hit_position) < b.distance_squared_to(hit_position))
	candidates = candidates.slice(0, 12)
	var reachable: Array = []
	for candidate in candidates:
		if _raycast(fixed_end, candidate).is_empty() and _raycast(candidate, free_end_now).is_empty():
			reachable.append(candidate)
	if reachable.is_empty():
		return null
	var start_angle := (free_end_before - fixed_end).angle()
	var best_corner = null
	var smallest_turn := 1e9
	for candidate in reachable:
		if not Geometry2D.point_is_inside_triangle(candidate, fixed_end, free_end_before, free_end_now):
			continue
		var turn := absf(angle_difference(start_angle, ((candidate as Vector2) - fixed_end).angle()))
		if turn < smallest_turn:
			smallest_turn = turn
			best_corner = candidate
	if best_corner != null:
		return best_corner
	var shortest_detour := 1e18
	for candidate in reachable:
		var detour := fixed_end.distance_to(candidate) + (candidate as Vector2).distance_to(free_end_now)
		if detour < shortest_detour:
			shortest_detour = detour
			best_corner = candidate
	return best_corner


func _which_side(before: Vector2, corner: Vector2, after: Vector2) -> int:
	var cross := (corner.x - before.x) * (after.y - corner.y) - (corner.y - before.y) * (after.x - corner.x)
	return 1 if cross >= 0.0 else -1


func _is_known_bend(corner: Vector2) -> bool:
	for bend in bend_points:
		if (bend.position as Vector2).distance_to(corner) < 2.0:
			return true
	return false


func _update_bend_sides() -> void:
	var hand_position := rope_points[ROPE_POINT_COUNT]
	var player_position := player.global_position
	for k in bend_points.size():
		var before: Vector2 = bend_points[k - 1].position if k > 0 else hand_position
		var after: Vector2 = bend_points[k + 1].position if k < bend_points.size() - 1 else player_position
		bend_points[k].side = _which_side(before, bend_points[k].position, after)


func _update_bends(old_player_position: Vector2, old_hand_position: Vector2) -> void:
	var player_position := player.global_position
	var hand_position := rope_points[ROPE_POINT_COUNT]
	for _attempt in 4:
		if bend_points.is_empty():
			break
		var last_bend: Dictionary = bend_points[-1]
		var before: Vector2 = bend_points[-2].position if bend_points.size() > 1 else hand_position
		if _which_side(before, last_bend.position, player_position) != last_bend.side and _raycast(player_position, before).is_empty():
			bend_points.pop_back()
		else:
			break
	for _attempt in 4:
		var fixed_end: Vector2 = bend_points[-1].position if bend_points.size() > 0 else hand_position
		var hit := _raycast(player_position, fixed_end)
		if hit.is_empty():
			break
		var corner = _find_corner(fixed_end, old_player_position, player_position, hit)
		if corner == null or _is_known_bend(corner) or bend_points.size() >= 16:
			break
		bend_points.append({"position": corner, "side": _which_side(fixed_end, corner, player_position)})
	if not is_holding:
		for _attempt in 4:
			var fixed_end: Vector2 = bend_points[0].position if bend_points.size() > 0 else player_position
			var hit := _raycast(hand_position, fixed_end)
			if hit.is_empty():
				break
			var corner = _find_corner(fixed_end, old_hand_position, hand_position, hit)
			if corner == null or _is_known_bend(corner) or bend_points.size() >= 16:
				break
			bend_points.push_front({"position": corner, "side": 1})
			_update_bend_sides()


func _get_taut_rope_points() -> PackedVector2Array:
	var points := PackedVector2Array([player.global_position])
	for k in range(bend_points.size() - 1, -1, -1):
		points.append(bend_points[k].position)
	points.append(rope_points[ROPE_POINT_COUNT])
	return points


func _get_taut_rope_length() -> float:
	var points := _get_taut_rope_points()
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i].distance_to(points[i - 1])
	return length


func _place_points_along_rope() -> void:
	var taut_points := _get_taut_rope_points()
	var distance_so_far := PackedFloat32Array([0.0])
	for i in range(1, taut_points.size()):
		distance_so_far.append(distance_so_far[i - 1] + taut_points[i].distance_to(taut_points[i - 1]))
	var total_length: float = maxf(distance_so_far[distance_so_far.size() - 1], 0.001)
	var sag := 0.0
	if is_holding and rope_length > total_length:
		sag = minf(120.0, 0.5 * sqrt(rope_length * rope_length - total_length * total_length))
	rope_points[0] = player.global_position
	previous_rope_points[0] = rope_points[0]
	var segment := 1
	for i in range(1, ROPE_POINT_COUNT):
		var distance_along := float(i) / ROPE_POINT_COUNT * total_length
		while segment < taut_points.size() - 1 and distance_so_far[segment] < distance_along:
			segment += 1
		var segment_length: float = maxf(distance_so_far[segment] - distance_so_far[segment - 1], 0.001)
		var progress := (distance_along - distance_so_far[segment - 1]) / segment_length
		var old_position := rope_points[i]
		rope_points[i] = taut_points[segment - 1].lerp(taut_points[segment], progress) + Vector2(0.0, sag * sin(PI * i / ROPE_POINT_COUNT))
		previous_rope_points[i] = old_position


func _find_bends_from_loose_rope() -> void:
	bend_points = []
	var fixed_end := rope_points[ROPE_POINT_COUNT]
	for i in range(ROPE_POINT_COUNT - 1, -1, -1):
		var target := player.global_position if i == 0 else rope_points[i]
		for _attempt in 4:
			var hit := _raycast(fixed_end, target)
			if hit.is_empty():
				break
			var corner = _find_corner(fixed_end, rope_points[i + 1], target, hit)
			if corner == null or _is_known_bend(corner) or bend_points.size() >= 16:
				break
			bend_points.append({"position": corner, "side": 1})
			fixed_end = corner
	_update_bend_sides()


func _simulate_loose_rope(delta: float, old_hand_position: Vector2) -> void:
	var player_position := player.global_position
	rope_points[0] = player_position
	previous_rope_points[0] = player_position
	if not is_holding:
		_sweep_collision(ROPE_POINT_COUNT, old_hand_position, 5.0)
	for i in range(1, ROPE_POINT_COUNT):
		var velocity := (rope_points[i] - previous_rope_points[i]) * 0.995
		var start_position := rope_points[i]
		previous_rope_points[i] = rope_points[i]
		rope_points[i] += velocity + Vector2(0.0, rope_gravity * delta * delta)
		_sweep_collision(i, start_position, 3.0)
	var link_length := rope_length / ROPE_POINT_COUNT
	var checked_positions := rope_points.duplicate()
	for iteration in 8:
		for i in ROPE_POINT_COUNT:
			var first_weight := 0.0 if i == 0 else 1.0
			var second_weight := hand_drag_weight if i + 1 == ROPE_POINT_COUNT else 1.0
			var link := rope_points[i + 1] - rope_points[i]
			var length := link.length()
			if length <= link_length or length == 0.0:
				continue
			var correction := (length - link_length) / length / (first_weight + second_weight)
			rope_points[i] += link * correction * first_weight
			rope_points[i + 1] -= link * correction * second_weight
		if iteration % 4 == 3:
			for i in range(1, ROPE_POINT_COUNT + 1):
				var radius := 5.0 if i == ROPE_POINT_COUNT else 3.0
				_sweep_collision(i, checked_positions[i], radius)
				_push_point_out(i, radius)
				checked_positions[i] = rope_points[i]
			_push_links_off_corners()


func _sweep_collision(i: int, from: Vector2, radius: float) -> void:
	if rope_points[i].distance_squared_to(from) < 0.01:
		return
	var hit := _raycast(from, rope_points[i])
	if hit.is_empty():
		return
	var surface_normal: Vector2 = hit.normal
	var velocity := rope_points[i] - previous_rope_points[i]
	var into_surface := velocity.dot(surface_normal)
	rope_points[i] = (hit.position as Vector2) + surface_normal * radius
	previous_rope_points[i] = rope_points[i] - (velocity - minf(0.0, into_surface) * surface_normal)


func _push_point_out(i: int, radius: float) -> Dictionary:
	probe_circle.radius = radius
	shape_query.transform = Transform2D(0.0, rope_points[i])
	shape_query.exclude = [player.get_rid()]
	var contact := get_world_2d().direct_space_state.get_rest_info(shape_query)
	if contact.is_empty():
		return {}
	var contact_point: Vector2 = contact.point
	var surface_normal: Vector2 = contact.normal
	var velocity := rope_points[i] - previous_rope_points[i]
	var overlap := radius - (rope_points[i] - contact_point).dot(surface_normal)
	if overlap > 0.0:
		rope_points[i] += surface_normal * overlap
	var into_surface := velocity.dot(surface_normal)
	var along_surface := velocity - into_surface * surface_normal
	previous_rope_points[i] = rope_points[i] - (along_surface * (1.0 - rope_friction) + maxf(0.0, into_surface) * surface_normal)
	return {"point": contact_point, "normal": surface_normal}


func _push_links_off_corners() -> void:
	for i in ROPE_POINT_COUNT:
		var hit := _raycast(rope_points[i], rope_points[i + 1])
		if hit.is_empty():
			continue
		var surface_normal: Vector2 = hit.normal
		if i > 0:
			rope_points[i] += surface_normal * 2.0
		rope_points[i + 1] += surface_normal * 2.0


func _draw_rope() -> void:
	if not is_shooting and not is_retracting:
		line.clear_points()
		if hand_sprite:
			hand_sprite.visible = false
		return
	var player_position := player.global_position
	var arm_start := arm_origin.global_position if arm_origin else player_position
	var hand_position := rope_points[ROPE_POINT_COUNT]
	var look_back_point := rope_points[ROPE_POINT_COUNT - 2] if rope_points[ROPE_POINT_COUNT - 2].distance_to(hand_position) > 1.0 else player_position
	var arm_direction := (hand_position - look_back_point).normalized() if look_back_point.distance_to(hand_position) > 0.001 else Vector2.UP
	var wrist_distance := 0.0
	if hand_sprite is Sprite2D and (hand_sprite as Sprite2D).texture:
		var hand := hand_sprite as Sprite2D
		var hand_texture := hand_closed_texture if is_holding else hand_open_texture
		if hand_texture:
			hand.texture = hand_texture
		wrist_distance = hand.texture.get_height() * absf(hand.global_scale.y) * 0.5 * wrist_position
	var wrist := hand_position - arm_direction * wrist_distance
	var player_to_hand := hand_position - player_position
	var player_to_hand_length := maxf(player_to_hand.length(), 0.001)
	var sideways := Vector2(-player_to_hand.y, player_to_hand.x) / player_to_hand_length
	var drawn_points := PackedVector2Array()
	for sample in DRAW_SAMPLE_COUNT + 1:
		var along := float(sample) / DRAW_SAMPLE_COUNT
		var point_position := along * ROPE_POINT_COUNT
		var i := mini(ROPE_POINT_COUNT - 1, int(floor(point_position)))
		var progress := point_position - i
		var from_point := player_position if i == 0 else rope_points[i]
		var wave_offset := wave_strength * sin(along * PI * wave_count - time_since_shot * 28.0) * sin(along * PI)
		var drawn_point := from_point.lerp(rope_points[i + 1], progress) + sideways * wave_offset
		if sample > 0 and drawn_point.distance_to(hand_position) < wrist_distance:
			break
		drawn_points.append(line.to_local(arm_start if sample == 0 else drawn_point))
	drawn_points.append(line.to_local(wrist))
	line.points = drawn_points
	if hand_sprite:
		hand_sprite.visible = true
		hand_sprite.global_position = hand_position
		if rotate_hand:
			hand_sprite.rotation = arm_direction.angle() + deg_to_rad(hand_rotation_offset)
