@tool
extends EditorScript

const SOURCE_DIR := "res://assets/fg/imgs/"     # folder with your PNGs
const OUTPUT_DIR := "res://assets/fg/scenes/"  # where scenes are saved
const EPSILON := 2.0                       # higher = fewer polygon points

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var dir := DirAccess.open(SOURCE_DIR)
	for file in dir.get_files():
		if file.get_extension().to_lower() == "png":
			_make_scene(SOURCE_DIR + file)
	EditorInterface.get_resource_filesystem().scan()
	print("Done")

func _make_scene(path: String) -> void:
	var tex: Texture2D = load(path)
	var image := tex.get_image()
	if image.is_compressed():
		image.decompress()

	# Trace opaque pixels into polygons
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image)
	var polys := bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), EPSILON)

	var base_name := path.get_file().get_basename()
	var root := StaticBody2D.new()   # change to Area2D / RigidBody2D if needed
	root.name = base_name.to_pascal_case()

	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = tex
	root.add_child(sprite)
	sprite.owner = root

	# Sprite2D is centered, polygon points start at top-left -> shift them
	var offset := -Vector2(image.get_size()) / 2.0
	for i in polys.size():
		var cp := CollisionPolygon2D.new()
		cp.name = "CollisionPolygon2D" if i == 0 else "CollisionPolygon2D%d" % (i + 1)
		var pts := PackedVector2Array()
		for p in polys[i]:
			pts.append(p + offset)
		cp.polygon = pts
		root.add_child(cp)
		cp.owner = root   # needed so the node is saved into the scene
		cp.visible = false
		
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, OUTPUT_DIR + base_name + ".tscn")
	root.free()
