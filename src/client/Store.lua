-- Client-side copy of the player's state and the shop stock.

local Store = {
	Data = nil, -- latest snapshot from DataService.Snapshot
	Shop = nil, -- latest snapshot from ShopService.Snapshot
}

local changed = Instance.new("BindableEvent")
Store.Changed = changed.Event -- fires with "Data" or "Shop"

-- Difference between the server's clock and workspace:GetServerTimeNow().
-- Network delay only ever makes a sample too small, so keep the largest.
local clockOffset
local function sampleClock(serverNow)
	if type(serverNow) ~= "number" then
		return
	end
	local sample = serverNow - workspace:GetServerTimeNow()
	if not clockOffset or sample > clockOffset then
		clockOffset = sample
	end
end

function Store.Now()
	return workspace:GetServerTimeNow() + (clockOffset or 0)
end

function Store.SetData(data)
	if type(data) ~= "table" then
		return
	end
	sampleClock(data.ServerNow)
	Store.Data = data
	changed:Fire("Data")
end

function Store.SetShop(shop)
	if type(shop) ~= "table" then
		return
	end
	sampleClock(shop.ServerNow)
	Store.Shop = shop
	changed:Fire("Shop")
end

-- Optimistically change the selected seed before the server confirms.
function Store.SelectSeed(seedId)
	if Store.Data then
		Store.Data.SelectedSeed = seedId
		changed:Fire("Data")
	end
end

return Store
