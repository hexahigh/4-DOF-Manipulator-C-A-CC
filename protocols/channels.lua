return {
	-- Per-arm bearing channels. Each arm gets 5 consecutive channels
	-- at BEARING_BASE + arm_id * 5 + offset.
	-- Offsets: 0=ring, 1=limb1, 2=limb2, 3=dock, 4=ack
	BEARING_BASE = 20000,
	BEARING_RING_OFFSET = 0,
	BEARING_LIMB1_OFFSET = 1,
	BEARING_LIMB2_OFFSET = 2,
	BEARING_DOCK_OFFSET = 3,
	BEARING_ACK_OFFSET = 4,

	-- All arms broadcast their status and position on this channel
	-- so ships can find the closest reachable arm. Bearing computers
	-- also use it to auto-discover their arm controller.
	ARM_HEARTBEAT = 65535,
	-- Each arm listens on ARM_BASE + its configured ARM_ID
	ARM_BASE = 5000,
	-- Each ship listens on SHIP_BASE + os.getComputerID()
	SHIP_BASE = 10000,
}
