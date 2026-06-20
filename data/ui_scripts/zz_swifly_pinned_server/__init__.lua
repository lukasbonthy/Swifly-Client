if Engine.GetCurrentMap() ~= "core_frontend" then
  return
end

-- Keeps Lukas's Swifly server at the top of the server browser.
-- This is a small wrapper around the existing server-browser datasource so it
-- does not have to rewrite the whole browser script.

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

  -- BO3 may display the resolved IP instead of mp1.swifly.net, so also match
  -- the unique Swifly game port.
  if stringEndsWith(addr, PINNED_SERVER_PORT) then
    return true
  end

  -- Fallback if the server name contains Swifly.
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

local function patchLobbyServerDataSource()
  if not DataSources or not DataSources.LobbyServer then
    return false
  end

  if DataSources.LobbyServer.__swiflyPinnedPatch then
    return true
  end

  local originalPrepare = DataSources.LobbyServer.prepare
  local originalGetItem = DataSources.LobbyServer.getItem

  if not originalPrepare or not originalGetItem then
    return false
  end

  DataSources.LobbyServer.__swiflyPinnedPatch = true

  DataSources.LobbyServer.prepare = function(controller, list, filter)
    local result = originalPrepare(controller, list, filter)
    list.__swiflyPinnedRawIndex = findPinnedRawIndex()
    return result
  end

  DataSources.LobbyServer.getItem = function(controller, list, index)
    if not list then
      return originalGetItem(controller, list, index)
    end

    local pinnedIndex = list.__swiflyPinnedRawIndex or findPinnedRawIndex()
    list.__swiflyPinnedRawIndex = pinnedIndex

    -- Always render the pinned server in visual row 1 when it exists.
    if index == 1 and pinnedIndex and list.updateModels then
      local ok, model = pcall(function()
        return list.updateModels(controller, list, pinnedIndex, 0)
      end)
      if ok and model then
        return model
      end
    end

    -- If the normal row would duplicate the pinned server, skip one row ahead.
    local model = originalGetItem(controller, list, index)
    if index > 1 and modelIsPinned(model) then
      local ok, replacement = pcall(function()
        return originalGetItem(controller, list, index + 1)
      end)
      if ok and replacement then
        return replacement
      end
    end

    return model
  end

  return true
end

-- Most of the time server_browser loads before this because this folder starts
-- with zz. If load order ever flips, retry when the menu asks if the browser is
-- enabled.
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
