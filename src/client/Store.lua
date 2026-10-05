-- Client-side copy of the player's state and the shop stock.

local Store = {
	Data = nil, -- latest snapshot from DataService.Snapshot
	Shop = nil, -- latest snapshot from ShopService.Snapshot
	Trade = nil, -- latest trade state from TradeService (Active = false when not trading)
	TradeRequests = {}, -- incoming requests: { FromUserId, FromName, ExpiresAt }
}

local changed = Instance.new("BindableEvent")
Store.Changed = changed.Event -- fires with "Data", "Shop", "Trade" or "TradeRequests"

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

function Store.SetTrade(trade)
	if type(trade) ~= "table" then
		return
	end
	sampleClock(trade.ServerNow)
	Store.Trade = trade
	if trade.Active then
		-- a trade started, so any request from that player is used up
		Store.RemoveTradeRequest(trade.PartnerUserId)
	end
	changed:Fire("Trade")
end

function Store.AddTradeRequest(request)
	if type(request) ~= "table" or type(request.FromUserId) ~= "number" then
		return
	end
	sampleClock(request.ServerNow)
	Store.RemoveTradeRequest(request.FromUserId, true)
	table.insert(Store.TradeRequests, request)
	changed:Fire("TradeRequests")
end

function Store.RemoveTradeRequest(userId, silent)
	for i = #Store.TradeRequests, 1, -1 do
		if Store.TradeRequests[i].FromUserId == userId then
			table.remove(Store.TradeRequests, i)
		end
	end
	if not silent then
		changed:Fire("TradeRequests")
	end
end

-- Optimistically change the selected seed before the server confirms.
function Store.SelectSeed(seedId)
	if Store.Data then
		Store.Data.SelectedSeed = seedId
		changed:Fire("Data")
	end
end

return Store
