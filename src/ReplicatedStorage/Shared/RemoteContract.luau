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
--   StorePurchase  RemoteFunction (kind: "Pass" | "Product" | "Offer", key: string) -> (ok, message)
--                  Pass/Product only ask the server to show the Roblox prompt; grants happen
--                  server-side (ownership check / ProcessReceipt). Offer spends Gems.
--   HatchEgg       RemoteFunction (eggId: string) -> (ok, message)
--   ManagePet      RemoteFunction (action: "Equip" | "Unequip" | "Lock" | "Unlock" | "Sell",
--                                  fuseKey: string) -> (ok, message)
--                  Acts on one group of identical pets (species|material|size).
--   BuyUpgrade     RemoteFunction (upgradeId: string) -> (ok, message)   coins only
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
	{ name = "StorePurchase", class = "RemoteFunction", direction = "ClientToServer" },
	{ name = "HatchEgg", class = "RemoteFunction", direction = "ClientToServer" },
	{ name = "ManagePet", class = "RemoteFunction", direction = "ClientToServer" },
	{ name = "BuyUpgrade", class = "RemoteFunction", direction = "ClientToServer" },
	{ name = "StateSync", class = "RemoteEvent", direction = "ServerToClient" },
	{ name = "CatchEffect", class = "RemoteEvent", direction = "ServerToClient" },
	{ name = "WeatherEvent", class = "RemoteEvent", direction = "ServerToClient" },
} :: { RemoteSpec }

RemoteContract.ThrowActions = { Begin = true, Release = true }
RemoteContract.StoreKinds = { Pass = true, Product = true, Offer = true }
RemoteContract.PetActions = { Equip = true, Unequip = true, Lock = true, Unlock = true, Sell = true }

-- Settings a client may change through ToggleSetting, with their value validator.
RemoteContract.Settings = {
	AutoThrow = "boolean",
	AutoSkipRarity = "rarityOrOff",
	KeepMutated = "boolean",
	ShowCutscenes = "boolean",
	ShowGuide = "boolean",
	ReduceMotion = "boolean",
	GoldenTrail = "boolean",
	Sfx = "boolean",
	Music = "boolean",
}

return RemoteContract
