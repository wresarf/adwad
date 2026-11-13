--!strict
-- Single source of truth for the network surface. The Lune test-suite checks that the
-- built place, the server and the client all agree with this table.
--
-- Client -> Server
--   ThrowFood      RemoteEvent    (action: "Begin" | "Release")
--   TrainStrength  RemoteEvent    ()
--   BuyFood        RemoteFunction (foodId: string) -> (ok: boolean, message: string)
--   EquipBest      RemoteFunction () -> (ok, message)
--   FusePets       RemoteFunction (fuseKey: string | "ALL") -> (ok, message)
--   AutoSell       RemoteFunction (threshold: rarity | "Off", sellNow: boolean?) -> (ok, message)
--   ToggleSetting  RemoteFunction (setting: string, value: any) -> (ok, message)
-- Server -> Client
--   StateSync      RemoteEvent    (state: table)   full player snapshot
--   CatchEffect    RemoteEvent    (catch: table)   result of a throw (thrower only)
--   WeatherEvent   RemoteEvent    (weather: table) broadcast on start/end and on join

export type RemoteSpec = { name: string, class: string, direction: "ClientToServer" | "ServerToClient" }

local RemoteContract = {}

RemoteContract.Remotes = {
	{ name = "ThrowFood", class = "RemoteEvent", direction = "ClientToServer" },
	{ name = "TrainStrength", class = "RemoteEvent", direction = "ClientToServer" },
	{ name = "BuyFood", class = "RemoteFunction", direction = "ClientToServer" },
	{ name = "EquipBest", class = "RemoteFunction", direction = "ClientToServer" },
	{ name = "FusePets", class = "RemoteFunction", direction = "ClientToServer" },
	{ name = "AutoSell", class = "RemoteFunction", direction = "ClientToServer" },
	{ name = "ToggleSetting", class = "RemoteFunction", direction = "ClientToServer" },
	{ name = "StateSync", class = "RemoteEvent", direction = "ServerToClient" },
	{ name = "CatchEffect", class = "RemoteEvent", direction = "ServerToClient" },
	{ name = "WeatherEvent", class = "RemoteEvent", direction = "ServerToClient" },
} :: { RemoteSpec }

RemoteContract.ThrowActions = { Begin = true, Release = true }

-- Settings a client may change through ToggleSetting, with their value validator.
RemoteContract.Settings = {
	AutoThrow = "boolean",
	AutoSkipRarity = "rarityOrOff",
	KeepMutated = "boolean",
	ShowCutscenes = "boolean",
	ShowGuide = "boolean",
}

return RemoteContract
