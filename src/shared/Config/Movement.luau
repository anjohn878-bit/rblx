--!strict
-- Every movement number the game and the map checker read. Change here, nowhere else.
return {
	WalkSpeed = 16, -- studs/s (Humanoid.WalkSpeed)
	JumpHeight = 7.2, -- studs (Humanoid.JumpHeight, UseJumpPower = false)
	Gravity = 196.2, -- studs/s^2 (Workspace.Gravity)
	CharacterHeight = 5, -- studs, R15 default standing height
	CharacterRadius = 1, -- studs, horizontal clearance needed to stand
	MaxSlopeAngle = 89, -- degrees (Humanoid.MaxSlopeAngle)
	RagdollRecoverTime = 1.5, -- seconds a ragdoll needs to get back up
	SafeFallHeight = 40, -- studs; falls above this count as "long"
}
