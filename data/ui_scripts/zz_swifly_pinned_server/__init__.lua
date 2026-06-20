if Engine.GetCurrentMap() ~= "core_frontend" then
  return
end

-- Keeps Lukas's Swifly server pinned at the top by preventing the native
-- ping-sort button from reordering the browser under it.
--
-- Why this exists:
-- The server list starts in the order returned by client.swifly.net, where
-- mp1.swifly.net:1154 is first. The Ping header calls the native engine sort,
-- which reorders the whole browser and moves Swifly away from row 1. This patch
-- blocks only the ping sort action so the pinned order survives.

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

local function isPingSort(sortType)
  local st = Enum and Enum.SteamServerSortType
  if not st then
    return false
  end

  return sortType == st.STEAM_SERVER_SORT_TYPE_PING_ASCENDING
    or sortType == st.STEAM_SERVER_SORT_TYPE_PING_DESCENDING
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

local function hasPinnedServerLoaded()
  if not game or not game.getrawservercount or not game.getrawserverinfo then
    return false
  end

  local rawCount = game.getrawservercount()
  for i = 0, rawCount - 1 do
    local info = game.getrawserverinfo(i)
    if isPinnedServerInfo(info) then
      return true
    end
  end

  return false
end

local function patchSort()
  if not Engine or not Engine.SteamServerBrowser_Sort then
    return false
  end

  if Engine.__swiflyPinnedSortPatch then
    return true
  end

  local originalSort = Engine.SteamServerBrowser_Sort
  Engine.__swiflyPinnedSortPatch = true

  Engine.SteamServerBrowser_Sort = function(sortType)
    -- Ping sort is the one that keeps pushing mp1.swifly.net:1154 down.
    -- If Swifly is loaded, ignore ping sort and leave the current order alone.
    if isPingSort(sortType) and hasPinnedServerLoaded() then
      return
    end

    return originalSort(sortType)
  end

  return true
end

local function patchLobbyCreate()
  if not LUI or not LUI.createMenu or not LUI.createMenu.LobbyServerBrowserOnline then
    return false
  end

  if LUI.createMenu.__swiflyPinnedCreatePatch then
    return true
  end

  local originalCreate = LUI.createMenu.LobbyServerBrowserOnline
  LUI.createMenu.__swiflyPinnedCreatePatch = true

  LUI.createMenu.LobbyServerBrowserOnline = function(...)
    local menu = originalCreate(...)
    patchSort()
    return menu
  end

  return true
end

local patchedSort = patchSort()
local patchedCreate = patchLobbyCreate()
local oldIsServerBrowserEnabled = IsServerBrowserEnabled

function IsServerBrowserEnabled()
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
