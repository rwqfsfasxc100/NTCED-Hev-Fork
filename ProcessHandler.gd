extends Node2D

export (NodePath) var node
export (bool) var process
export (bool) var physics

func _ready():
	node = get_node(node)
	set_process(process)
	set_physics_process(physics)

func _process(delta):
	node.__process(delta)

func _physics_process(delta):
	node.__physics_process(delta)
