--!strict
-- Serialises a session's saves and makes the releasing save (player left, server
-- closing) the final write. Without this, an autosave or receipt queued behind the
-- releasing save would re-take the DataStore session lock after the player left, and
-- their next server would wait for the lock to go stale (minutes) and load unsaved.
-- Pure apart from the injected writer / wait / clock, so the test-suite drives it.

export type Gated = {
	canSave: boolean,
	saving: boolean,
	released: boolean,
}

local SaveGate = {}

SaveGate.WaitLimit = 30 -- seconds to wait for an in-flight save before writing anyway

function SaveGate.save(s: Gated, release: boolean?, write: (release: boolean?) -> boolean, wait: (number) -> (), clock: () -> number): boolean
	if not s.canSave or s.released then
		return false
	end
	local deadline = clock() + SaveGate.WaitLimit
	while s.saving and clock() < deadline do
		wait(0.1)
	end
	if s.released then
		return false -- the releasing save ran while we waited: nothing may follow it
	end
	s.saving = true
	if release then
		s.released = true
	end
	local ok, result = pcall(write, release)
	s.saving = false
	return ok and result == true
end

return SaveGate
