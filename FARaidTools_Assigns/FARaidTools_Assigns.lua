-- declare strings
local ADDON_NAME = "FARaidTools_Assigns";
local ADDON_VERSION_FULL = "v1.0";
local ADDON_VERSION = string.gsub(ADDON_VERSION_FULL, "[^%d]", "");

local ADDON_COLOR = "00FF0000"
local ADDON_CHAT_HEADER  = "|c" .. ADDON_COLOR .. "FA Assigns:|r ";

local ASSIGN_BLOCK_NEW = "\n\-\-NEW BLOCK\-\-\n";

local ROLE_STRINGS = {
  -- {formatPattern, matchPattern},
  ["tank"]  = "<tank%d>", -- TANK
  ["rheal"] = "<rheal%d>", -- NON-MONK HEALERS
  ["mheal"] = "<mheal%d>", -- MONK HEALERS
  ["heal"]  = "<heal%d>", -- HEALER
  ["rdps"]  = "<rdps%d>", -- RANGED DPS
  ["mdps"]  = "<mdps%d>", -- MELEE DPS
  ["dps"]   = "<dps%d>", -- DPS
};

-- declare locals for variables declared in ADDON_LOAD
-- (eg: SavedVariables)
local debugOn;
local inspectInterval;
local renewTime;
local purgeTime;
local purgeTimeXr;
local table_specializations;
local table_encounters;

-- declare variables
local _;
local playerName;
local timeSinceLastCheck = 0; -- onUpdate accumulator
local inspectInProgress = false;
local groupType;

--helper functions
local function debug(msg, verbosity)
  if (not verbosity or debugOn >= verbosity) then
    if type(msg) == "string" or type(msg) == "number" then
      print(ADDON_CHAT_HEADER..msg);
    elseif type(msg) == "table" then
      if not DevTools_Dump then
        LoadAddOn("Blizzard UI Debug Tools");
      end
      DevTools_Dump(msg);
    end
  end
end

local GetNumGroupMembersOld = GetNumGroupMembers;
local function GetNumGroupMembers()
  if groupType == "player" then
    return 1;
  else
    return GetNumGroupMembersOld();
  end
end

local function UnitNameRealm(unit)
  if unit and unit ~= "" then
    local name, realm = UnitName(unit);
    if realm and realm ~= "" then
      name = name.."-"..realml;
    end
    return name;
  else
    debug("UnitNameRealm was called without a unit!", 1);
  end
end

local function GetUnitId(i)
  if groupType == "player" then
    return groupType;
  else
    return groupType..i;
  end
end

-- main code
local function GetSpecializationInfoByName(name)
  if table_specializations[name] then
    -- time, id
    return table_specializations[name][1], table_specializations[name][2];
  end
end

local function SetSpecializationInfo(name, id, resetTime)
  if name and id then
    table_specializations[name] = {time(), id};
    return true
  elseif name and resetTime and table_specializations[name] then
    table_specializations[name] = {0, table_specializations[name][2]};
  else
    return false
  end
end

local function generateAssigns(templateString)
  local blocks = {};
  while 1 do
    local block = string.match(templateString, "(.-)"..ASSIGN_BLOCK_NEW..".+");
    if block then
      table.insert(blocks, block);
      string.gsub(templateString, block, "");
    else
      table.insert(blocks, templateString); -- insert the last block into the table
      break;
    end
  end
  
  -- assemble a list of candidates, we'll make a copy of this list once per block
  local candidatesCopy = {};
  for i=1,GetNumGroupMembers() do
    table.insert(candidatesCopy, UnitNameRealm(GetUnitId(i)));
  end

  for i=1,#blocks do
    local candidates = candidatesCopy; -- grab a copy of the list of candidates for this block

    for j, v in pairs(ROLE_STRINGS) do
      local k = 1;
      while string.match(blocks[i], string.format(v, k)) do -- while there is spots left of this role to fill
        local success;
        for l, w in ipairs(candidates) do -- loop through all remaining candidates in this block
          -- check if this candidate matches our criteria
          if table_specializations[w] then
            local id = table_specializations[w][2]
            if RTA_specData[id] and RTA_specData[id][v] then
              -- this candidate matches
              blocks[i] = string.gsub(blocks[i], string.format(v, k), w); -- replace template text with candidate's name
              table.remove(candidates, l); -- each player can only be assigned once per block
              -- so remove them from the candidate list for this block
              success = true; -- set success variable so loop knows to continue
              break; -- since we likely still have candidates left for this role
            end
          end
        end
        if success then
          k = k + 1; -- successfully found a match, so keep going
        else -- we're out of candidates for this role so break loop early
          break; -- TODO: Replace any remaining matches with some PH text, or remove.
        end
      end
    end
  end
end

SLASH_ASSIGNS1 = "/assigns";
local function slashParse(msg, editbox)
  msg = string.lower(msg);
  if msg == "" then
    if UnitExists("target") then
      msg = UnitName("target");
    end
  elseif string.match(msg, "^dump ") then
    msg = string.gsub(msg, "^dump ", "");
    if msg == "specs" then
      DevTools_Dump(table_specializations)
    end
    return
  end

  -- remove all non-alphabetical letters from the encounter name
  msg = string.gsub(msg, "!%a", ""); -- FIXME: Pattern is wrong.

  for i=1,#table_encounters do
    for j=1,#table_encounters[i]["names"] do
      if msg == table_encounters[i]["names"][j] then
        RTAssigns:Show()
        -- TODO: set the display window to the corresponding encounter entry
        return
      end
    end
  end
end
SlashCmdList["ASSIGNS"] = slashParse;

local function onUpdate(self, elapsed)
  timeSinceLastCheck = timeSinceLastCheck + elapsed;
  if not InCombatLockdown() and not inspectInProgress and timeSinceLastCheck >= 5 then -- TODO: Add "not InspectFrame:IsShown()" conditional
    debug("Checking for inspect candidates...", 3);
    timeSinceLastCheck = 0;

    for i=1,GetNumGroupMembers() do
      local unitId = GetUnitId(i);
      local name = UnitNameRealm(unitId);
      if name == playerName then
        return
      end
      local lastCheck = GetSpecializationInfoByName(name);
      if not lastCheck or time() - lastCheck >= renewTime then
        if CanInspect(unitId) then
          debug("Triggered inspect for "..name..".", 1);
          NotifyInspect(unitId);
          inspectInProgress = unitId;
          break;
        end
      end
    end
  end
end

local onUpdateFrame = CreateFrame("frame")
onUpdateFrame:SetScript("OnUpdate", onUpdate)
	
local frame, events = CreateFrame("Frame"), {}
function events:ADDON_LOADED(addon)
  if addon == ADDON_NAME then
    RTA_options           = RTA_options or {};
    table_specializations = RTA_options["table_specializations"] or {};
    table_encounters      = RTA_options["table_encounters"] or {};
    debugOn = RTA_options["debugOn"] or 2;
    -- inspect scan interval (eg: how often it is checked if anyone needs a renew)
    inspectInterval = RTA_options["inspectInterval"] or 5;
    -- the minimum amount of time before a reinspect is triggered on a specific character (barring specific triggers)
    renewTime = RTA_options["renewTime"] or 15 * 60;
    -- amount of time before purging old character data entries
    purgeTime = RTA_options["purgeTime"] or 10 * 24 * 60 * 60;
    -- same as above, but for people offrealm
    purgeTimeXr = RTA_options["purgeTimeXr"] or 3 * 24 * 60 * 60;
  end
end
function events:PLAYER_LOGIN()
  SetSpecializationInfo(UnitNameRealm("player"), GetSpecializationInfo(GetSpecialization()));

  playerName = UnitNameRealm("player");

  local currentTime = time();

  -- loop through specialization data and purge any data older than our thresholds
  for i, v in pairs(table_specializations) do
    if currentTime - v[1] >= purgeTime or (string.match(i, "\-") and currentTime - v[1] >= purgeTimeXr) then
      table_specializations[i] = nil;
    end
  end

  -- determine current group type
  if IsInRaid() then
    groupType = "raid";
  elseif GetNumGroupMembersOld() > 0 then
    groupType = "party";
  else
    groupType = "player";
  end
end
function events:PLAYER_LOGOUT()
  RTA_options = {
    ["table_specializations"] = table_specializations,
    ["table_encounters"]      = table_encounters,
    ["debugOn"]               = debugOn,
    ["inspectInterval"]       = inspectInterval,
    ["renewTime"]             = renewTime,
    ["purgeTime"]             = purgeTime,
    ["purgeTimeXr"]           = purgeTimeXr,
  };
end
function events:INSPECT_READY()
  if inspectInProgress then
    local id, name = GetInspectSpecialization(inspectInProgress), UnitNameRealm(inspectInProgress);
    if id and id > 0 and name then
      SetSpecializationInfo(name, id);
      debug("Retrieved "..name.."'s specialization as #"..id..".", 1);
    else
      debug("Retrieval of specialization info failed!", 1);
    end
    ClearInspectPlayer();
    inspectInProgress = nil;
    timeSinceLastCheck = 5;  -- cause an immediate check for another player to inspect
  end
end
--[[function events:COMBAT_LOG_EVENT_UNFILTERED(timestamp, event, hideCaster, srcGUID, srcName, srcFlags, srcFlags2, dstGUID, dstName, dstFlags, dstFlags2, ...)
  if srcGUID == UnitGUID("player") then
    local spellId, spellName, spellSchool = ...;
    debug({[event] = {spellId, spellName, spellSchool}}, 3)
  end
end--]]
function events:PLAYER_SPECIALIZATION_CHANGED(unitId)
  debug({["PLAYER_SPECIALIZATION_CHANGED"] = {unitId}}, 3);
  if unitId == "player" then
    SetSpecializationInfo(UnitNameRealm("player"), GetSpecializationInfo(GetSpecialization()));
  elseif unitId and unitId ~= "" then
    local name = UnitNameRealm(unitId);
    if name == "Unknown" then
      return;
    end
    debug("Scheduled inspect for "..name.." (specialization changed).", 1);
    SetSpecializationInfo(name, nil, true);
  end
end
function events:ROLE_CHANGED_INFORM(player, changedBy, oldRole, newRole)
  debug({["ROLE_CHANGED_INFORM"]={player, changedBy, oldRole, newRole}}, 2);
  if oldRole ~= "NONE" and oldRole ~= newRole then
    -- "player" variable does NOT include realm suffix so we must confirm
    local unitId, name;
    for i=1,GetNumGroupMembers() do
      local unitId = GetUnitId(i);
      if UnitName(unitId) == player then
        name = UnitNameRealm(unitId);
        break
      end
    end
    if name then
      SetSpecializationInfo(name, nil, true); -- reset time of last inspect for name
      debug("Scheduled inspect for "..name.." (role changed).", 1);
    end
  end
end
events:GROUP_ROSTER_UPDATE()
  -- determine current group type
  if IsInRaid() then
    groupType = "raid";
  elseif GetNumGroupMembersOld() > 0 then
    groupType = "party";
  else
    groupType = "player";
  end
end
event:RAID_ROSTER_UPDATE()
  -- determine current group type
  if IsInRaid() then
    groupType = "raid";
  elseif GetNumGroupMembersOld() > 0 then
    groupType = "party";
  else
    groupType = "player";
  end
end
frame:SetScript("OnEvent", function(self, event, ...)
  events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
  frame:RegisterEvent(k) -- Register all events for which handlers have been defined
end