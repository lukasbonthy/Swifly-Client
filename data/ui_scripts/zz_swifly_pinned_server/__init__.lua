if Engine.GetCurrentMap() ~= "core_frontend" then
  return
end

-- Allows players to sort by ping, but always keeps Lukas's Swifly server
-- visually pinned as row 1. The rest of the list still sorts normally.

local PINNED_SERVER_ADDR = "mp1.swifly.net:1154"
local PINNED_SERVER_PORT = ":1154"
local PINNED_SERVER_NAME = "swifly"

local activePingSortType = nil
local activeList = nil

local function lower(value)
  return string.lower(value or "")
end

local function stringEndsWith(value, ending)
  value = value or ""
  ending = ending or ""
  if #ending == 0 then
    return true
  end
  return string.sub(value, -#ending) == ending
end

local function isPingSort(sortType)
  local st = Enum and Enum.SteamServerSortType
  if not st then
    return false
  end

  return sortType == st.STEAM_SERVER_SORT_TYPE_PING_ASCENDING
    or sortType == st.STEAM_SERVER_SORT_TYPE_PING_DESCENDING
end

local function isPingAscending(sortType)
  local st = Enum and Enum.SteamServerSortType
  return st and sortType == st.STEAM_SERVER_SORT_TYPE_PING_ASCENDING
end

local function isPinnedServerInfo(info)
  if not info then
    return false
  end

  local addr = lower(info.connectAddr or "")
  local name = lower(info.name or "")

  if addr == PINNED_SERVER_ADDR then
    return true
  end

  if stringEndsWith(addr, PINNED_SERVER_PORT) then
    return true
  end

  if string.find(name, PINNED_SERVER_NAME, 1, true) then
    return true
  end

  return false
end

local function isUsableServerInfo(info)
  return info and info.name and info.name ~= "" and info.gametype and info.gametype ~= ""
end

local function getRawInfo(index)
  if not game or not game.getrawserverinfo then
    return nil
  end
  local ok, info = pcall(game.getrawserverinfo, index)
  if ok then
    return info
  end
  return nil
end

local function rawCount()
  if not game or not game.getrawservercount then
    return 0
  end
  local ok, count = pcall(game.getrawservercount)
  if ok then
    return count or 0
  end
  return 0
end

local function buildPinnedPingOrder(sortType)
  local count = rawCount()
  local pinned = nil
  local rest = {}

  for i = 0, count - 1 do
    local info = getRawInfo(i)
    if isUsableServerInfo(info) then
      if isPinnedServerInfo(info) then
        pinned = i
      else
        table.insert(rest, {
          index = i,
          ping = tonumber(info.ping) or 999999,
          name = lower(info.name or ""),
        })
      end
    end
  end

  local asc = isPingAscending(sortType)
  table.sort(rest, function(a, b)
    if a.ping == b.ping then
      return a.name < b.name
    end
    if asc then
      return a.ping < b.ping
    end
    return a.ping > b.ping
  end)

  local order = {}
  if pinned then
    table.insert(order, pinned)
  end

  for _, item in ipairs(rest) do
    table.insert(order, item.index)
  end

  return order
end

local function setModelValue(parent, key, value)
  local model = Engine.CreateModel(parent, key)
  if model then
    Engine.SetModelValue(model, value)
  end
end

local function writeServerInfoToVisualRow(controller, list, serverInfo, rawIndex, displayOffset)
  if not list or not list.servers or not list.numElementsInList or not serverInfo then
    return nil
  end

  local elementIndex = (displayOffset or 0) % list.numElementsInList + 1
  if not list.servers[elementIndex] or not list.servers[elementIndex].model then
    return nil
  end

  local serverModel = list.servers[elementIndex].model
  setModelValue(serverModel, "serverIndex", serverInfo.serverIndex or rawIndex or 0)
  setModelValue(serverModel, "connectAddr", serverInfo.connectAddr or "")
  setModelValue(serverModel, "ping", serverInfo.ping or 0)
  setModelValue(serverModel, "modName", serverInfo.modName or "")
  setModelValue(serverModel, "mapName", serverInfo.map or "")
  setModelValue(serverModel, "desc", serverInfo.desc or "")

  local clientCount = (serverInfo.playerCount or 0) - (serverInfo.botCount or 0)
  setModelValue(serverModel, "clientCount", clientCount)
  setModelValue(serverModel, "maxClients", serverInfo.maxPlayers or 0)
  setModelValue(serverModel, "passwordProtected", serverInfo.password or false)
  setModelValue(serverModel, "secure", serverInfo.secure or false)
  setModelValue(serverModel, "name", serverInfo.name or "")
  setModelValue(serverModel, "gameType", serverInfo.gametype or "")
  setModelValue(serverModel, "dedicated", serverInfo.dedicated or false)
  setModelValue(serverModel, "ranked", serverInfo.ranked or false)
  setModelValue(serverModel, "hardcore", serverInfo.hardcore or false)
  setModelValue(serverModel, "zombies", serverInfo.zombies or false)
  setModelValue(serverModel, "campaign", serverInfo.campaign or 0)
  setModelValue(serverModel, "botCount", serverInfo.botCount or 0)
  setModelValue(serverModel, "rounds", serverInfo.rounds or 0)

  return serverModel
end

local function patchLobbyServerDataSource()
  if not DataSources or not DataSources.LobbyServer then
    return false
  end

  if DataSources.LobbyServer.__swiflyPinnedPingPatch then
    return true
  end

  local originalPrepare = DataSources.LobbyServer.prepare
  local originalGetItem = DataSources.LobbyServer.getItem

  if not originalPrepare or not originalGetItem then
    return false
  end

  DataSources.LobbyServer.__swiflyPinnedPingPatch = true

  DataSources.LobbyServer.prepare = function(controller, list, filter)
    local result = originalPrepare(controller, list, filter)
    activeList = list
    return result
  end

  DataSources.LobbyServer.getItem = function(controller, list, index)
    if activePingSortType then
      local order = buildPinnedPingOrder(activePingSortType)
      local rawIndex = order[index]
      if rawIndex == nil then
        return nil
      end

      local info = getRawInfo(rawIndex)
      if info then
        return writeServerInfoToVisualRow(controller, list, info, rawIndex, index - 1)
      end
    end

    return originalGetItem(controller, list, index)
  end

  return true
end

local function patchSort()
  if not Engine or not Engine.SteamServerBrowser_Sort then
    return false
  end

  if Engine.__swiflyPinnedPingSortPatch then
    return true
  end

  local originalSort = Engine.SteamServerBrowser_Sort
  Engine.__swiflyPinnedPingSortPatch = true

  Engine.SteamServerBrowser_Sort = function(sortType)
    if isPingSort(sortType) then
      activePingSortType = sortType
      -- Still call the original so the header/UI state updates normally.
      local result = originalSort(sortType)
      if activeList then
        pcall(function()
          activeList:updateDataSource(false, false)
        end)
      end
      return result
    end

    activePingSortType = nil
    return originalSort(sortType)
  end

  return true
end

local function patchLobbyCreate()
  if not LUI or not LUI.createMenu or not LUI.createMenu.LobbyServerBrowserOnline then
    return false
  end

  if LUI.createMenu.__swiflyPinnedPingCreatePatch then
    return true
  end

  local originalCreate = LUI.createMenu.LobbyServerBrowserOnline
  LUI.createMenu.__swiflyPinnedPingCreatePatch = true

  LUI.createMenu.LobbyServerBrowserOnline = function(...)
    local menu = originalCreate(...)
    patchLobbyServerDataSource()
    patchSort()
    return menu
  end

  return true
end

local patchedDataSource = patchLobbyServerDataSource()
local patchedSort = patchSort()
local patchedCreate = patchLobbyCreate()
local oldIsServerBrowserEnabled = IsServerBrowserEnabled

function IsServerBrowserEnabled()
  if not patchedDataSource then
    patchedDataSource = patchLobbyServerDataSource()
  end

  if not patchedSort then
    patchedSort = patchSort()
  end

  if not patchedCreate then
    patchedCreate = patchLobbyCreate()
  end

  if oldIsServerBrowserEnabled then
    return oldIsServerBrowserEnabled()
  end

  return true
end
