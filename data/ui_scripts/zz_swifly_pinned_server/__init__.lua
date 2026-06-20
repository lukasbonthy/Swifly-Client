if Engine.GetCurrentMap() ~= "core_frontend" then
  return
end

-- Keeps Lukas's Swifly server visually pinned at row 1 in the server browser,
-- even after ping/name/player sorting and normal filter refreshes.

local PINNED_SERVER_ADDR = "mp1.swifly.net:1154"
local PINNED_SERVER_PORT = ":1154"
local PINNED_SERVER_NAME = "swifly"

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

local function isPinnedServerInfo(info)
  if not info then
    return false
  end

  local addr = lower(info.connectAddr or "")
  local name = lower(info.name or "")

  if addr == PINNED_SERVER_ADDR then
    return true
  end

  -- BO3 may resolve mp1.swifly.net to an IP internally, so also match the
  -- unique Swifly connect port.
  if stringEndsWith(addr, PINNED_SERVER_PORT) then
    return true
  end

  if string.find(name, PINNED_SERVER_NAME, 1, true) then
    return true
  end

  return false
end

local function findPinnedRawIndex()
  if not game or not game.getrawservercount or not game.getrawserverinfo then
    return nil
  end

  local rawCount = game.getrawservercount()
  for i = 0, rawCount - 1 do
    local info = game.getrawserverinfo(i)
    if isPinnedServerInfo(info) then
      return i
    end
  end

  return nil
end

local function modelIsPinned(model)
  if not model then
    return false
  end

  local connectModel = Engine.GetModel(model, "connectAddr")
  if connectModel then
    local addr = lower(Engine.GetModelValue(connectModel) or "")
    if addr == PINNED_SERVER_ADDR or stringEndsWith(addr, PINNED_SERVER_PORT) then
      return true
    end
  end

  local nameModel = Engine.GetModel(model, "name")
  if nameModel then
    local name = lower(Engine.GetModelValue(nameModel) or "")
    if string.find(name, PINNED_SERVER_NAME, 1, true) then
      return true
    end
  end

  return false
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

local function getPinnedVisualModel(controller, list)
  local pinnedIndex = findPinnedRawIndex()
  if not pinnedIndex then
    return nil
  end

  local info = game.getrawserverinfo(pinnedIndex)
  if not isPinnedServerInfo(info) then
    return nil
  end

  list.__swiflyPinnedRawIndex = pinnedIndex
  return writeServerInfoToVisualRow(controller, list, info, pinnedIndex, 0)
end

local function patchLobbyServerDataSource()
  if not DataSources or not DataSources.LobbyServer then
    return false
  end

  if DataSources.LobbyServer.__swiflyPinnedPatchV2 then
    return true
  end

  local originalPrepare = DataSources.LobbyServer.prepare
  local originalGetItem = DataSources.LobbyServer.getItem

  if not originalPrepare or not originalGetItem then
    return false
  end

  DataSources.LobbyServer.__swiflyPinnedPatchV2 = true

  DataSources.LobbyServer.prepare = function(controller, list, filter)
    local result = originalPrepare(controller, list, filter)
    if list then
      list.__swiflyPinnedRawIndex = findPinnedRawIndex()
    end
    return result
  end

  DataSources.LobbyServer.getItem = function(controller, list, index)
    if not list then
      return originalGetItem(controller, list, index)
    end

    -- Row 1 is always written from game.getrawserverinfo(), not from the engine
    -- sorted row. This is what keeps it pinned after Ping sort.
    if index == 1 then
      local pinnedModel = getPinnedVisualModel(controller, list)
      if pinnedModel then
        return pinnedModel
      end
      return originalGetItem(controller, list, index)
    end

    -- Avoid showing the pinned server twice if the normal sorted list would also
    -- place it in a later row.
    local searchIndex = index
    for _ = 1, 8 do
      local model = originalGetItem(controller, list, searchIndex)
      if not modelIsPinned(model) then
        return model
      end
      searchIndex = searchIndex + 1
    end

    return nil
  end

  return true
end

local patched = patchLobbyServerDataSource()
local oldIsServerBrowserEnabled = IsServerBrowserEnabled

function IsServerBrowserEnabled()
  if not patched then
    patched = patchLobbyServerDataSource()
  end

  if oldIsServerBrowserEnabled then
    return oldIsServerBrowserEnabled()
  end

  return true
end
