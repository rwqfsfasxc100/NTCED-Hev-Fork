extends "res://weapons/drone-plant.gd"

onready var pickupAreaShape = $DronePickupArea/Shape

func _ready():
	ship.connect("setup", self, "updateTargeting")
	ship.connect("tuningChanged", self, "updateTargeting")

func updateTargeting():
	pickupAreaShape.shape.radius = getRangeMax() * 10

func getTuneables():
	var options = .getTuneables()
	for option in options:
		var data = options[option]
		match option:
			"TUNE_RANGE_KEEP_AWAY":
				data.min = minDroneDistance / 10
				data.max = maxDroneDistance / 20
			"TUNE_SLOW_ZONE":
				data.min = max(minDroneDistance / 10, data.min)
				data.max = maxDroneDistance / 10
			_:
				data.min = minDroneDistance / 10
				data.max = maxDroneDistance / 10
	return options
