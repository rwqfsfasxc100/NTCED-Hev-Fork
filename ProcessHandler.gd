extends Node2D

export (NodePath) var node
export (bool) var newProcess = false
export (bool) var newPhysics = false
export (bool) var oldProcess = false
export (bool) var oldPhysics = false

func _ready():
	node = get_node(node)
	set_process(newProcess)
	set_physics_process(newPhysics)

	yield(node, "ready")
	node.set_process(oldProcess)
	node.set_physics_process(oldPhysics)

func _process(delta):
	node.__process(delta)

func _physics_process(delta):
	node.__physics_process(delta)
