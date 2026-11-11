extends RefCounted
class_name Utils

class Rnd:
	static var _rnd: RandomNumberGenerator

	static var rnd: RandomNumberGenerator:
		get:
			if _rnd == null:
				_rnd = RandomNumberGenerator.new()
			return _rnd
	
	static func randf() -> float:
		return rnd.randf()
	
	static func range_f(from: float, to: float) -> float:
		return rnd.randf_range(from, to)
	
	static func range_i(from: int, to: int) -> int:
		return rnd.randi_range(from, to)
	
	static func vector2D(magnitude: float) -> Vector2:
		return Vector2(range_f(-magnitude, magnitude), range_f(-magnitude, magnitude))

class UI:
	static var _ui: CanvasLayer
	static var _content: VBoxContainer
	static var _panel: PanelContainer
	static var _updater: UIUpdater

	static var ui: CanvasLayer:
		get:
			if _ui == null:
				_ui = CanvasLayer.new()
			return _ui
	
	static var panel: PanelContainer:
		get:
			if _panel == null:
				_panel = PanelContainer.new()
			return _panel

	static var content: VBoxContainer:
		get:
			if _content == null:
				_content = VBoxContainer.new()
			return _content
	
	static var updater: UIUpdater:
		get:
			if _updater == null:
				_updater = UIUpdater.new()
				ui.add_child(_updater)
			return _updater

	static func setup(node: Node):
		node.add_child(ui)
		ui.add_child(panel)
		panel.add_child(content)
		
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.02, 0.02, 0.02, 0.9)
		bg.corner_radius_top_left = 6
		bg.corner_radius_top_right = 6
		bg.corner_radius_bottom_left = 6
		bg.corner_radius_bottom_right = 6
		bg.content_margin_left = 10
		bg.content_margin_right = 10
		bg.content_margin_top = 8
		bg.content_margin_bottom = 8
		
		panel.position = Vector2(10, 10)
		panel.add_theme_stylebox_override("panel", bg)
	
	static func label(text: String) -> Label:
		var lbl = Label.new()
		lbl.text = text
		content.add_child(lbl)
		
		return lbl

	static func dynamic_label(callback: Callable) -> Label:
		var lbl := Label.new()
		content.add_child(lbl)

		updater.callbacks.append(func():
			lbl.text = str(callback.call())
		)

		return lbl
	
	static func slider(from: float, to: float, step: float, value: float) -> HSlider:
		var sldr = HSlider.new()
		sldr.min_value = from
		sldr.max_value = to
		sldr.value = value
		sldr.step = step
		content.add_child(sldr)
		return sldr
	
	static func labeled_slider(text: String, from: float, to: float, step: float, value: float) -> HSlider:
		var lbl := Label.new()
		lbl.text = text + str(value)

		var sldr := HSlider.new()
		sldr.min_value = from
		sldr.max_value = to
		sldr.step = step
		sldr.value = value

		sldr.value_changed.connect(
			func(new_value: float):
				lbl.text = text + str(new_value)
		)

		content.add_child(lbl)
		content.add_child(sldr)

		return sldr

class Tweens:
	static func create(node: Node) -> Tween:
		return node.create_tween()
		
	static func natural(tween: Tween, callback: Callable, from: float, to: float, duration: float, easing: Tween.EaseType = Tween.EASE_IN_OUT):
		return tween \
			.tween_method(callback, from, to, duration) \
			.set_trans(Tween.TRANS_SINE) \
			.set_ease(easing)
		
	static func natural_short(tween: Tween, callback: Callable, duration: float, easing: Tween.EaseType = Tween.EASE_IN_OUT):
		return natural(tween, callback, 0.0, 1.0, duration, easing)
		
	static func natural_parallel(tween: Tween, callback: Callable, from: float, to: float, duration: float, easing: Tween.EaseType = Tween.EASE_IN_OUT):
		return natural(
			tween.parallel(),
			callback,
			from,
			to,
			duration,
			easing
		)
		
	static func natural_short_parallel(tween: Tween, callback: Callable, duration: float, easing: Tween.EaseType = Tween.EASE_IN_OUT):
		return natural_parallel(
			tween,
			callback,
			0.0,
			1.0,
			duration,
			easing
		)

class Grid2D:
	var cell_size: float
	var cells: Dictionary[Vector2i, int] = {}
	var next: PackedInt32Array
	
	var checked_particles := 0
	var found_particles := 0
	
	func _init(
		p_cell_size: float,
		item_count: int
	) -> void:
		cell_size = p_cell_size
		next.resize(item_count)
	
	func clear() -> void:
		cells.clear()
	
	func rebuild(positions: PackedVector2Array) -> void:
		clear()
		
		for i in positions.size():
			var cell := world_to_cell(positions[i])
			
			var previous: int = cells.get(cell, -1)

			next[i] = previous
			cells[cell] = i
	
	func world_to_cell(position: Vector2) -> Vector2i:
		return Vector2i(
			floori(position.x / cell_size),
			floori(position.y / cell_size)
		)
	
	func circle_query(
		center: Vector2,
		radius: float,
		positions: PackedVector2Array,
		callback: Callable
	) -> Vector2i:
		checked_particles = 0
		found_particles = 0
		
		var min_cell := world_to_cell(center - Vector2.ONE * radius)
		var max_cell := world_to_cell(center + Vector2.ONE * radius)
		
		var radius_squared := radius * radius
		
		for y in range(min_cell.y, max_cell.y + 1):
			for x in range(min_cell.x, max_cell.x + 1):
				var cell := Vector2i(x, y)
				
				if not cells.has(cell):
					continue
				
				var particle := cells[cell]
				
				while particle != -1:
					var offset := positions[particle] - center
					
					checked_particles += 1
					
					if offset.length_squared() <= radius_squared:
						found_particles += 1
						callback.call(particle, offset)
					
					particle = next[particle]
		
		return Vector2i(checked_particles, found_particles)
		
	func calculate_force(
		center: Vector2,
		radius: float,
		repulsion_distance: float,
		positions: PackedVector2Array,
		particle_types: PackedInt32Array,
		input_type: int,
		rules: PackedFloat32Array,
		type_count: int,
		max_speed: float,
		vector_radius: Vector2
	) -> Vector2:
		var force := Vector2.ZERO

		var min_cell := world_to_cell(center - vector_radius)
		var max_cell := world_to_cell(center + vector_radius)

		var radius_squared := radius * radius
		var repulsion_squared := repulsion_distance * repulsion_distance
		var half := radius / 2.0
		var rule_base := input_type * type_count

		for y in range(min_cell.y, max_cell.y + 1):
			for x in range(min_cell.x, max_cell.x + 1):
				var cell := Vector2i(x, y)

				var particle: int = cells.get(cell, -1)

				if particle == -1:
					continue

				while particle != -1:
					var diff := positions[particle] - center
					var distance_squared := diff.length_squared()

					if distance_squared <= radius_squared:
						var distance := sqrt(distance_squared)
						
						if distance_squared == 0.0:
							particle = next[particle]
							continue

						if distance_squared <= repulsion_squared:
							force -= diff / distance * remap(
								distance,
								repulsion_distance,
								0.0,
								0.0,
								max_speed
							)
						else:
							var t: float = 1.0 - (abs(distance - half) / half)

							var rule_index := rule_base + particle_types[particle]

							force += diff / distance \
								* lerpf(0.0, max_speed, t) \
								* rules[rule_index]

					particle = next[particle]

		return force

class Storage:
	static var names := []
	
	static func save(name: String, data: Dictionary) -> void:
		var file := FileAccess.open("user://" + name + ".json", FileAccess.WRITE)

		file.store_string(JSON.stringify(data))
		
		if not names.has(name):
			names.append(name)
		
	static func load(name: String) -> Dictionary:
		if not names.has(name):
			return {}
		
		var file := FileAccess.open("user://" + name + ".json", FileAccess.READ)
		
		if file == null:
			return {}
		
		var data = JSON.parse_string(file.get_as_text())
		
		if data == null:
			return {}
		
		return data

# tool classes
class UIUpdater:
	extends Node

	var callbacks: Array[Callable] = []

	func _process(_delta: float) -> void:
		for callback in callbacks:
			callback.call()
