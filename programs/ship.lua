package.path = package.path .. ";/?.lua"
-- Gets position of the dock and sends it to the closest reachable arm
local channels = require("protocols.channels")
local network = require("protocols.network")
local geometry = require("protocols.geometry")
local calculate = require("protocols.calculate")

local ship_id = os.getComputerID()
if ship_id > 9000 then
	error("Computer ID " .. ship_id .. " is too large for the channel scheme (max 9000)", 0)
end
local ship_channel = channels.SHIP_BASE + ship_id

local modem = peripheral.find("modem") or error("No modem", 0)
-- Responses from arms arrive on this ship's own channel
modem.open(ship_channel)
-- Arm status broadcasts
modem.open(channels.ARM_HEARTBEAT)

for _, name in ipairs(peripheral.getNames()) do
	print(string.format("Found peripheral %s to the %s..", peripheral.getType(name), name))
end

-- For checking if in docking mode
local gimbal, north, speaker =
	peripheral.find("gimbal_sensor"),
	peripheral.find("navigation_table"),
	peripheral.find("speaker")

local function play(num)
	-- Success
	if num == 1 then
		speaker.playNote("chime", 2, 8)
		sleep(0.3)
		speaker.playNote("chime", 2, 12)
		sleep(0.3)
		speaker.playNote("chime", 2, 15)
	-- Fail
	elseif num == 2 then
		speaker.playNote("didgeridoo", 2, 18)
		sleep(0.3)
		speaker.playNote("didgeridoo", 2, 12)
		sleep(0.3)
		speaker.playNote("didgeridoo", 2, 6)
	-- Undock
	elseif num == 3 then
		speaker.playNote("chime", 2, 16)
		sleep(0.3)
		speaker.playNote("chime", 2, 15)
		sleep(0.3)
		speaker.playNote("chime", 2, 13)
		sleep(0.3)
		speaker.playNote("chime", 2, 11)
	end
end

-- Listens for arm heartbeats and returns the closest idle arm
-- that can safely reach this ship's dock position.
-- Computes `calculate.process()` once for the ship's own data,
-- then evaluates `calculate.angles()` locally for every arm
-- using each arm's position/radius/initial_angle from its
-- heartbeat — so the ship knows exactly which arms can dock
-- without any network round-trips.
-- Returns a sorted table of {arm, dist}; caller pops the first
-- entry and retries with the next on a busy rejection.
local function findReachableArms(x, y, z, rawData)
	-- Compute the ship's global dock vector and pivot angle once
	local processed = calculate.process(rawData)

	local messages = network.scan(channels.ARM_HEARTBEAT, 3)
	-- Keep only the latest heartbeat of each arm
	local arms = {}
	for _, msg in ipairs(messages) do
		if type(msg) == "table" and type(msg.id) == "number" then
			arms[msg.id] = msg
		end
	end

	local candidates = {}
	for _, arm in pairs(arms) do
		if arm.status == "idle" and type(arm.pos) == "table" and arm.radius and arm.initial_angle then
			local arm_config = {
				pos = arm.pos,
				radius = arm.radius,
				initial_angle = arm.initial_angle,
			}
			local data = calculate.angles(processed, arm_config)
			if data.possible then
				local dist = math.sqrt((arm.pos.x - x) ^ 2 + (arm.pos.y - y) ^ 2 + (arm.pos.z - z) ^ 2)
				table.insert(candidates, { arm = arm, dist = dist })
				print(string.format("Arm %d can safely dock (%.1f blocks away)", arm.id, dist))
			else
				local dist = math.sqrt((arm.pos.x - x) ^ 2 + (arm.pos.y - y) ^ 2 + (arm.pos.z - z) ^ 2)
				print(string.format("Arm %d cannot safely dock (%.1f blocks away)", arm.id, dist))
			end
		end
	end

	-- Sort by distance: closest reachable arm first
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)

	if #candidates > 0 then
		print(string.format("Closest reachable arm: %d (%.1f blocks away)", candidates[1].arm.id, candidates[1].dist))
	end
	return candidates
end

while true do
	-- Check if wanna dock (button)
	if redstone.getInput("left") then
		local x, y, z = gps.locate(1, false)
		local raw = {
			north = (north.getRelativeAngle() + geometry.ORIENTATION) % 360,
			gimbal = gimbal.getAngles(),
			x = x,
			y = y,
			z = z,
			dock_x = geometry.SHIP_DOCK_OFFSET.x,
			dock_y = geometry.SHIP_DOCK_OFFSET.y,
			dock_z = geometry.SHIP_DOCK_OFFSET.z,
			dock_dir = geometry.DOCK_DIR,
		}

		-- Find the closest idle arm that can safely reach this ship
		local candidates = findReachableArms(x, y, z, raw)

		if #candidates == 0 then
			print("No reachable arms found..")
			play(2)
			sleep(1)
		else
			local docked = false
			for _, entry in ipairs(candidates) do
				local arm = entry.arm
				-- Build the full request including ship channel info
				raw.arm = arm.id
				raw.channel = ship_channel
				raw.id = ship_id

				-- Transmit to the chosen arm
				print(string.format("Requesting dock with arm %d (%.1f blocks away)..", arm.id, entry.dist))
				modem.transmit(arm.channel, ship_channel, raw)
				-- Poll for 3 seconds for arm response
				local success = network.poll_for(ship_channel, 3)
				if success == true then
					play(1)
					docked = true
					-- Wait until the arm tells us the ship has undocked
					local undocked
					repeat
						undocked = network.poll_for(ship_channel, 1)
					until undocked
					play(3)
					break
				else
					print("Arm busy, trying next reachable arm..")
				end
			end
			if not docked then
				play(2)
			end
			sleep(1)
		end
	else
		print("Press button to initiate docking..")
		sleep(1)
	end
end
