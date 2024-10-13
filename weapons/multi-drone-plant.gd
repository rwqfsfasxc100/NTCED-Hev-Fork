extends "res://NTCED Parts Pack/weapons/drone-plant.patch.gd"

# How many independant drone streams the drone plant will handle
export (int, 1, 1000) var drone_amount = 1
# Patches in the functionality of the `currentTargetBias` setting.
# This is present but non-functional on vanilla launchers
export (bool) var patchCurrentTargetBias = false

var droneTargets := []
#onready var target = null

var droneLaunchers := []
#onready var drones = $DroneLaunchManager

var playerLasers := []
#onready var playerLaser = $Laser

# Generate a new laser AudioStreamPlayer
func newLaser():
	var laser := AudioStreamPlayer.new()
	laser.set_script(playerLaser.get_script())
	laser.stream = playerLaser.stream
	laser.volume_db = playerLaser.volume_db
	laser.bus = playerLaser.bus
	playerLasers.append(laser)
	add_child(laser)

# Generate a new DroneLaunchManager
func newLauncher(idx):
	var launcher = drones.duplicate()
	launcher.disconnect("droneHit", self, "_on_DroneLaunchManager_droneHit")
	launcher.connect("droneHit", self, "_on_DroneLaunchManager_droneHit", [idx])
	launcher.drones = dronesPerSecond
	droneLaunchers.append(launcher)
	add_child(launcher)

func _ready():
# Disable physics so we can 'override' it with our own
	set_physics_process(false)
	droneLaunchers.append(drones)
	playerLasers.append(playerLaser)
	droneTargets.append(null)

# Spawn extra nodes for the extra drones
	for i in drone_amount-1:
		newLauncher(i+1)
		newLaser()
		droneTargets.append(null)

func _setEnabled(how:bool):
	enabled = how
# Disable the monitoring area if we're repair drones
	if droneFunction == "repair":
		DronePickupArea.monitoring = false
	else: DronePickupArea.monitoring = how
# Clear SANBUS when module is disabled
	if not how:
		for launcher in droneLaunchers:
			ship.clearSystemTarget(launcher)

# Sort the targets based on how desireable they are
func sortTargets(a, b):
	if a[1] > b[1]:
		return true
	return false

# Check if the target was targeted last check, and assign it to the same launcher if it was
func wasTargetedLast(target, pastTargets: Array) -> bool:
	var lastPos = pastTargets.find(target)
# If the target was targeted last check
	if lastPos != -1:
	# If something else is already in that slot
		if droneTargets[lastPos]:
		# Shuffle the targets so the drones target their previous target
			var nullPos = droneTargets.find_last(null)
			droneTargets[nullPos] = droneTargets[lastPos]
			droneTargets[lastPos] = target
			return true
	# If the previous slot is empty, have it target the same one
		else:
			droneTargets[lastPos] = target
			return true
# Continue if it wasn't targeted
	else: return false

func scanForTargets(delta):
	scanProcess += delta
	if scanProcess > scanEvery:
		scanProcess = 0

	# If this is a repair drone, just check the status of the ship
		if droneFunction == "repair":
			var systems = ship.getSystems()
			for k in systems:
				var system = systems[k]
				for d in system.damage:
					if d.current > d.maxRaw * (1 - repairLimit):
						# If it needs repairs, target with all launchers
							droneTargets.fill(ship)
							return
		# If it does not need repairs, target nothing
			droneTargets.fill(null)
			return

		else:
			var dmin = getRangeMin() * 10
			var dmax = getRangeMax() * 10
			var space = ship.get_parent()

			var shipQueue : Array = ship.droneQueue
			var possibleTargets : Array = targets.duplicate()
			var pastTargets : Array = droneTargets.duplicate()
			droneTargets.fill(null)

			var viableTargets := []
			var priorityTargets := []

		# Add the priority queue targets to the list
			if shipQueue:
				for t in shipQueue:
					# Make sure we don't double up on them
					if not possibleTargets.has(t):
						possibleTargets.append(t)

			for t in possibleTargets:
				if Tool.claim(t):
					# Check if it's a valid target
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
					if mineralTargetting and not ship.isValidMineralTarget(t, mineralConfig):
						Tool.release(t)
						continue

					# Check if the target needs work done on it
					var check
					match droneFunction:
						"haul":
							var desired := desiredVelicityFor(t)
							check = t.mass * pow((desired - t.linear_velocity).length(), 2) / dist
						"tug":
							var v = t.linear_velocity.length()
							check = t.mass * pow(v, 2)

					if patchCurrentTargetBias and t in pastTargets:
						check *= currentTargetBias
					# If the target passes the check, add it to the list it belongs to
					if check > minEnergyToTarget:
						if t in shipQueue:
							priorityTargets.append(t)
						else:
							viableTargets.append([t, check])
					Tool.release(t)

			for t in priorityTargets:
			# Check if there's an empty slot
				if droneTargets.has(null):
				# If the target was not previously targeted, set the target
					if !wasTargetedLast(t, pastTargets):
						droneTargets[droneTargets.find_last(null)] = t
			# If there is no empty slot, we're done sorting
				else: return

		# Sort our targets by how much work they need done to them
			viableTargets.sort_custom(self, "sortTargets")
			for key in viableTargets:
			# Check if there's an empty slot
				if droneTargets.has(null):
					var t = key[0]
				# If the target was not previously targeted, set the target
					if !wasTargetedLast(t, pastTargets):
						droneTargets[droneTargets.find(null)] = t
			# If there is no empty slot, we're done sorting
				else: return
	else :
	# Clear any targets that entered the cargo hold this frame
		for idx in droneTargets.size():
			target = droneTargets[idx]
			if Tool.claim(target):
				if "inCargoHold" in target and target.inCargoHold:
					droneTargets[idx] = null
				Tool.release(target)

func __physics_process(delta):
	if Tool.claim(ship):
		readpower = 0
		if enabled and ship.drawEnergy(scanPowerDraw * delta) >= scanPowerDraw * delta * 0.9:
			scanForTargets(delta)

		for idx in droneLaunchers.size():
			target = droneTargets[idx]
			var drones = droneLaunchers[idx]
			var laser = playerLasers[idx]

			drones.sourceVelocity = ship.linear_velocity + launchVector.rotated(global_rotation)
			if drones.laserFiring:
				var energyRequired = delta * powerDraw
				var energy = ship.drawEnergy(energyRequired)
				drones.power = energy / energyRequired > 0.9
				if ship.isPlayerControlled() and drones.power:
					if not laser.playing:
						laser.play()
				else :
					laser.stop()
			else :
				laser.stop()
				drones.power = true
		
			if Tool.objectValid(target):
				firepower = 1

			if firepower > 0 and enabled and not ship.cutscene:
				var energyRequired = delta * lauchPowerDraw
				var energy = ship.drawEnergy(energyRequired)
				if energy / energyRequired > 0.9 and Tool.claim(target):
					if sanbus:
						ship.addSystemTarget(drones, target)
					drones.targetNode = target
					var needDrones = dronesPerSecond * delta * droneWeightKg
					var gotDrones = ship.drawDrones(needDrones)
					if gotDrones >= needDrones:
						drones.emitting = true
						readpower += firepower
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
				drones.emitting = false
				playing = false
				ship.clearSystemTarget(drones)
			idx += 1
		Tool.release(ship)

# Hacky way to use the existing code with multiple targets
func _on_DroneLaunchManager_droneHit(pt, delta, drones, idx=0):
	target = droneTargets[idx]
	._on_DroneLaunchManager_droneHit(pt, delta, drones)
