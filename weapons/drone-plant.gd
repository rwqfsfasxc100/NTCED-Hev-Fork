extends Sprite

export  var sanbus = true
export  var repairReplacementPrice = 250000
export  var repairReplacementTime = 1
export  var repairFixPrice = 50000
export  var repairFixTime = 12

export  var currentTargetBias = 5.0
export  var command = ""
export  var powerDraw = 40000.0
export  var scanPowerDraw = 20.0
export  var lauchPowerDraw = 10000.0
export  var power = 12500.0
export  var systemName = "SYSTEM_DND_TS"
export  var dronesPerSecond = 10
export (float, 0.1, 2, 0.1) var scanEvery = 1.0
export  var laserRange = 4000
export  var maxDroneDistance = 4000
export  var minDroneDistance = 0
export  var minEnergyToTarget = 100
export  var minVelocityToTarget = 1.0
export  var droneTugPower = 10.0
export  var hitDeadZone = 10000.0
export  var enabled = true setget _setEnabled
export  var haulVelocity = 100
export  var shoveVelocity = 200
export  var haulDistance = 1500
var haulMinDistance = 400
export  var haulGatherSpot = Vector2(0, - 500)
export  var haulGatherDeadzone = 150.0
export  var haulCrawlVelocity = 50
export  var haulAccurancy = 0.98
export  var haulDeadCone = 0.8
export  var haulDeadConeDistance = 350
export (float) var fixPerDrone = 0.1
export (float) var droneWeightKg = 1.0
export  var launchVector = Vector2(0, 0)
export  var builtInDroneStorage = 100
onready var slotName = name

export  var mineralTargetting = true

export (String, "tug", "repair", "haul") var droneFunction = "tug"

export  var repairLimit = 0.75

onready var target = null
export  var mass = 4000

func _setEnabled(how:bool):
	enabled = how
	DronePickupArea.monitoring = how
	if not how:
		ship.clearSystemTarget(self)

var ship
var firepower = 0
var readpower = 0
onready var drones = $DroneLaunchManager

var mineralConfig = {}

onready var slot = get_parent().slot
func getSlotName(param):
	return "weaponSlot.%s.%s" % [slot, param]
	
var excavator

onready var DronePickupArea = $DronePickupArea
	
func _ready():
	ship = getShip()
	if ship.getConfig(getSlotName("type")) != systemName:
		Tool.remove(self)
	else :
		drones.drones = dronesPerSecond
		ship.addDronesCapacity(builtInDroneStorage)
		haulMinDistance = ship.haulMinDistance
	
	var x = ship.getSystemsFiredBy("x")
	if x.size() > 0:
		excavator = x[0]
	haulGatherSpot = haulGatherSpot.rotated(ship.droneGatheringSpotRotation)
	if mineralTargetting:
		mineralConfig = ship.getConfig(getSlotName("config"), {})
		if mineralConfig.empty():
			var pickup = CurrentGame.traceMinerals.duplicate()
			pickup.append("CARGO_UNKNOWN")
			mineralConfig = {
				"minerals":pickup, 
				"minValue":0
			}
			ship.setConfig(getSlotName("config"), mineralConfig)
		
func setMineralConfig(mineral:String, how:bool):
	if mineralTargetting:
		if how:
			if not mineralConfig.minerals.has(mineral):
				mineralConfig.minerals.append(mineral)
		else :
			mineralConfig.minerals.erase(mineral)

func hasMineralEnabled(mineral)->bool:
	if mineralTargetting:
		return mineralConfig.minerals.has(mineral)
	else :
		return false
		
func setMinValue(value:float):
	if mineralTargetting:
		mineralConfig.minValue = value
		
func getMinValue()->float:
	if mineralTargetting:
		return mineralConfig.get("minValue", 0.0)
	else :
		return 0.0
		
func getStatus():
	return 100

func getPower():
	return readpower
	
func getShip():
	var c = self
	while not c.has_method("getConfig") and c != null:
		c = c.get_parent()
	return c

func fire(p):
	
	
	pass

func getPossibleTargets():
	return targets
	

func getRangeMin():
	return ship.getTunedValue(slotName, "TUNE_RANGE_MIN", minDroneDistance / 10)

func getRangeMax():
	return min(laserRange / 10, ship.getTunedValue(slotName, "TUNE_RANGE_MAX", maxDroneDistance / 10))

func getMinProximity():
	return ship.getTunedValue(slotName, "TUNE_RANGE_KEEP_AWAY", haulMinDistance / 10)

func getProximity():
	return ship.getTunedValue(slotName, "TUNE_SLOW_ZONE", haulDistance / 10)
	
func getTuneables():
	if droneFunction == "repair":
		return {}
	
	var opts = {
		"TUNE_RANGE_MIN":{
			"type":"float", 
			"min":0, 
			"max":400, 
			"step":10, 
			"default":minDroneDistance / 10, 
			"current":getRangeMin(), 
			"unit":"m", 
			"testProtocol":"drone"
		}, 
		"TUNE_RANGE_MAX":{
			"type":"float", 
			"min":0, 
			"max":400, 
			"step":10, 
			"default":maxDroneDistance / 10, 
			"current":getRangeMax(), 
			"unit":"m", 
			"testProtocol":"drone"
		}
	}
	match droneFunction:
		"haul":
			opts.TUNE_RANGE_KEEP_AWAY = {
				"type":"float", 
					"min":0, 
					"max":200, 
					"step":10, 
					"default":haulMinDistance / 10, 
					"current":getMinProximity(), 
					"unit":"m", 
					"testProtocol":"drone"
				}
			opts.TUNE_SLOW_ZONE = {
				"type":"float", 
					"min":10, 
					"max":400, 
					"step":10, 
					"default":haulDistance / 10, 
					"current":getProximity(), 
					"unit":"m", 
					"testProtocol":"drone"
				}
	return opts
	
func isInRange(what):
	var dist = global_position.distance_to(what.global_position)
	var dmin = getRangeMin() * 10
	var dmax = getRangeMax() * 10
	return dist <= dmax and dist >= dmin

var scanProcess = 0
func scanForTarget(delta):
	scanProcess += delta
	if scanProcess > scanEvery:
		var dmin = getRangeMin() * 10
		var dmax = getRangeMax() * 10
		scanProcess = 0
		target = null
		var space = ship.get_parent()
		var priority = false
		var previousTarget = target
		match droneFunction:
			"haul":
				if ship.droneQueue:
					for t in ship.droneQueue:
						if Tool.claim(t):
							if t == ship.autopilotVelocityOffsetTarget:
								Tool.release(t)
								continue
							var dist = global_position.distance_to(t.global_position)
							if dist > laserRange:
								Tool.release(t)
								continue
							var desired = desiredVelicityFor(t)
							var check = t.mass * pow((desired - t.linear_velocity).length(), 2) / dist
							if t == previousTarget:
								check *= currentTargetBias
							if check > minEnergyToTarget:
								target = t
								Tool.release(t)
								priority = true
								break
							Tool.release(t)
								
				if not priority:
					var best = minEnergyToTarget
					for t in getPossibleTargets():
						if Tool.claim(t):
							if t.get_parent() != space:
								Tool.release(t)
								continue
							if "inCargoHold" in t and t.inCargoHold:
								Tool.release(t)
								continue
							if not t is RigidBody2D:
								Tool.release(t)
								continue
							if t == ship.autopilotVelocityOffsetTarget:
								Tool.release(t)
								continue
							var dist = global_position.distance_to(t.global_position)
							if dist > dmax or dist < dmin:
								Tool.release(t)
								continue
							if sanbus and not ship.isValidSystemTarget(self, t):
								Tool.release(t)
								continue
							if mineralTargetting and not ship.isValidMineralTarget(t, mineralConfig):
								Tool.release(t)
								continue
								
							var desired = desiredVelicityFor(t)
							var check = t.mass * pow((desired - t.linear_velocity).length(), 2) / dist
							if t == previousTarget:
								check *= currentTargetBias
							if check > best:
								target = t
								best = check
							Tool.release(t)
			"tug":
				if ship.droneQueue:
					for t in ship.droneQueue:
						if Tool.claim(t):
							var dist = global_position.distance_to(t.global_position)
							if dist > laserRange:
								Tool.release(t)
								continue
							var v = t.linear_velocity.length()
							if v < minVelocityToTarget:
								Tool.release(t)
								continue
							var check = t.mass * pow(v, 2)
							if t == previousTarget:
								check *= currentTargetBias
							if check > minEnergyToTarget:
								target = t
								priority = true
								Tool.release(t)
								break
							Tool.release(t)
				if not priority:
					var best = minEnergyToTarget
					for t in getPossibleTargets():
						if Tool.claim(t):
							if t.get_parent() != space:
								Tool.release(t)
								continue
							if "inCargoHold" in t and t.inCargoHold:
								Tool.release(t)
								continue
							if not t is RigidBody2D:
								Tool.release(t)
								continue
							var dist = global_position.distance_to(t.global_position)
							if dist > dmax or dist < dmin:
								Tool.release(t)
								continue
							var v = t.linear_velocity.length()
							if v < minVelocityToTarget:
								Tool.release(t)
								continue
							if sanbus and not ship.isValidSystemTarget(self, t):
								Tool.release(t)
								continue
							if mineralTargetting and not ship.isValidMineralTarget(t, mineralConfig):
								Tool.release(t)
								continue
							var check = t.mass * pow(v, 2)
							if t == previousTarget:
								check *= currentTargetBias
							if check > best:
								target = t
								best = check
							Tool.release(t)
			"repair":
				var systems = ship.getSystems()
				for k in systems:
					var system = systems[k]
					for d in system.damage:
						if d.current > d.maxRaw * (1 - repairLimit):
							target = ship
							return 
	else :
		if Tool.claim(target):
			var rel = false
			if "inCargoHold" in target and target.inCargoHold:
				rel = true
			Tool.release(target)
			if rel:
				target = null
		
		
		
		
		

onready var playerLaser = $Laser
onready var playerAudioFire = $AudioFire
onready var playing = false

func _physics_process(delta):
	if Tool.claim(ship):
		if ship.drawEnergy(scanPowerDraw * delta) >= scanPowerDraw * delta * 0.9:
			scanForTarget(delta)
		else :
			target = null
		
		drones.sourceVelocity = ship.linear_velocity + launchVector.rotated(global_rotation)
		if drones.laserFiring:
			var energyRequired = delta * powerDraw
			var energy = ship.drawEnergy(energyRequired)
			drones.power = energy / energyRequired > 0.9
			if ship.isPlayerControlled() and drones.power:
				if not playerLaser.playing:
					playerLaser.play()
			else :
				playerLaser.stop()
		else :
			playerLaser.stop()
			drones.power = true
		
		if Tool.objectValid(target):
			firepower = 1

		if firepower > 0 and enabled and not ship.cutscene:
			var energyRequired = delta * lauchPowerDraw
			var energy = ship.drawEnergy(energyRequired)
			if energy / energyRequired > 0.9 and Tool.claim(target):
				if sanbus:
					ship.addSystemTarget(self, target)
				drones.targetNode = target
				var needDrones = dronesPerSecond * delta * droneWeightKg
				var gotDrones = ship.drawDrones(needDrones)
				if gotDrones >= needDrones:
					drones.emitting = true
					readpower = firepower
					if not playing and ship.isPlayerControlled():
						playerAudioFire.play()
						playing = true
				else :
					drones.emitting = false
					playing = false
					
				if ship.isPlayerControlled():
					CurrentGame.logEvent("LOG_EVENT_DIVE", {"LOG_EVENT_DETAILS_DRONE":gotDrones})
				Tool.release(target)
			firepower = 0
		else :
			readpower = 0
			drones.emitting = false
			playing = false
			ship.clearSystemTarget(self)
		Tool.release(ship)

func desiredVelicityFor(target:RigidBody2D)->Vector2:
	match droneFunction:
		"haul":
			if target.global_position != null and excavator:
				
				var toShip = ship.global_position - target.global_position
				var hmd = getMinProximity() * 10
				var hm = getProximity() * 10
				
				var vRelativeStop = ship.linear_velocity
				var vToShip = ship.linear_velocity + toShip.normalized() * haulVelocity
				var vAwayFromShip = ship.linear_velocity - toShip.normalized() * haulCrawlVelocity
				var distance = toShip.length()
				var vOriginal = target.linear_velocity
				var toExcavator = excavator.global_position - target.global_position
				var toGatheringSpot = toExcavator + haulGatherSpot.rotated(excavator.global_rotation)
				var zoneFactor = clamp((toExcavator.length() - hmd) / (hm), - 1, 1)
				var proximityFactor = clamp((distance - hmd) / (hm), - 1, 1)
				var vToGatheringSpot = ship.linear_velocity + toGatheringSpot.normalized() * haulVelocity
				var vCrawlToGathering = ship.linear_velocity + toGatheringSpot.normalized() * haulCrawlVelocity
				var zoneGathered = pow(clamp((toGatheringSpot.length() / haulGatherDeadzone), 0, 1), 2)
				vToGatheringSpot = lerp(vRelativeStop, vToGatheringSpot, zoneGathered)
				vCrawlToGathering = lerp(vRelativeStop, vCrawlToGathering, zoneGathered)
				var vTarget = vToGatheringSpot if zoneFactor >= 1 else vOriginal
				
				var vToExcavator = ship.linear_velocity + toExcavator.normalized() * shoveVelocity
				var inTargetFactorRaw = Vector2(0, 1).rotated(ship.global_rotation + ship.droneGatheringSpotRotation).dot(toExcavator.normalized())
				var inTargetFactor = clamp((inTargetFactorRaw - haulAccurancy) / (1.0 - haulAccurancy), 0, 1)
				var inDeadConeFactor = clamp((1.0 + (inTargetFactorRaw - haulDeadCone) / (1.0 - haulDeadCone)) * clamp(1.0 - toExcavator.length() / haulDeadConeDistance, 0, 1), 0, 1)
				
				var desired = lerp(vCrawlToGathering, vTarget, proximityFactor)
				var shipProximityFactor = clamp(distance / hmd, 0, 1) if hmd > 0 else 1.0
				desired = lerp(vAwayFromShip, desired, shipProximityFactor).normalized() * (desired.length())
				desired = lerp(desired, vOriginal, inDeadConeFactor)
				desired = lerp(desired, vRelativeStop, inTargetFactor * inDeadConeFactor)
				
				if excavator.has_method("getPower") and excavator.getPower() > 0.5:
					if inTargetFactor > 0:
						desired = lerp(desired, vToExcavator, inTargetFactor)
				
				return desired
			else :
				return Vector2(0, 0)
	return Vector2(0, 0)

func _on_DroneLaunchManager_droneHit(pt, delta, drones):
	match droneFunction:
		"haul":
			if Tool.claim(target):
				if target.global_position != null:
					var distance = pt.distance_to(target.global_position)
					if distance < hitDeadZone:
						var desired = desiredVelicityFor(target)
						
						var impulse = (desired - target.linear_velocity).normalized() * delta * drones * droneTugPower
						
						target.apply_impulse(Vector2(0, 0), impulse)
					else :
						Debug.l("Haul drone target out of range: %f" % distance)
				Tool.release(target)
			
		"tug":
			if Tool.claim(target):
				if target.global_position != null:
					var distance = pt.distance_to(target.global_position)
					if distance < hitDeadZone:
						var impulse = - target.linear_velocity.normalized() * delta * drones * droneTugPower
						
						target.apply_impulse(Vector2(0, 0), impulse)
					else :
						Debug.l("Tug drone target out of range: %f" % distance)
				Tool.release(target)
		"repair":
			if Tool.claim(target):
				if target.has_method("getSystems") and target.has_method("changeSystemDamage"):
					var distance = pt.distance_to(target.global_position)
					if distance < hitDeadZone:
						var systems = target.getSystems()
						for k in systems:
							var system = systems[k]
							for d in system.damage:
								if d.current > d.maxRaw * (1 - repairLimit):
									var fixby = clamp(fixPerDrone * delta * drones * float(d.maxRaw) / 100, 0, d.maxRaw * repairLimit)
									target.changeSystemDamage(system.key, d.type, - fixby)
					else :
						Debug.l("Maint drone target out of range: %f" % distance)
				Tool.release(target)


var targets = []
func _on_DronePickupArea_body_entered(body):
	if body.is_in_group("pickable"):
		targets.append(body)

func _on_DronePickupArea_body_exited(body):
	targets.erase(body)
