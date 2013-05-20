-- load libraries
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0");

-- declare strings
local ADDON_NAME = "FARaidTools_Assigns";
local ADDON_VERSION_FULL = "v1.0";
local ADDON_VERSION = string.gsub(ADDON_VERSION_FULL, "[^%d]", "");
local ADDON_DOWNLOAD_URL = "https://github.com/aggixx/FARaidTools_Assigns";

local ADDON_COLOR = "FFF9CC30";
local ADDON_CHAT_HEADER  = "|c" .. ADDON_COLOR .. "FA Assigns:|r ";
local ADDON_MSG_PREFIX = "RT_Assigns";

local ASSIGN_BLOCK_NEW = "\n\-\-NEW BLOCK\-\-\n";

local ROLE_STRINGS = { -- FIXME: Change this so it is not keyed! pairs() does not respect its order.
  -- ["name"] = "format",
  ["tank"]  = "<tank%d>", -- TANK
  ["rheal"] = "<rheal%d>", -- NON-MONK HEALERS
  ["mheal"] = "<mheal%d>", -- MONK HEALERS
  ["heal"]  = "<heal%d>", -- HEALER
  ["rdps"]  = "<rdps%d>", -- RANGED DPS
  ["mdps"]  = "<mdps%d>", -- MELEE DPS
  ["dps"]   = "<dps%d>", -- DPS
};

-- declare locals for variables declared in ADDON_LOADED
-- (eg: SavedVariables)
local debugOn;
local inspectInterval;
local inspectTimeout;
local inspectRecovery;
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
local inspectStart;
local groupType;
local updateMsg = false;
local inspectFailed = {};

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

local SendAddonMessageOld = SendAddonMessage;
local function SendAddonMessage(prefix, message, type, target)
  message = libSerialize:Serialize(message);
  if not message then
    return false;
  end
  return SendAddonMessageOld(prefix, message, type, target);
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
      name = name.."-"..realm;
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

local function GetDataCompletionRate()
  local count, total, missing = 0, GetNumGroupMembers(), {};
  for i=1,total do
    local name = UnitNameRealm(GetUnitId(i));
    if table_specializations[name] then
      count = count + 1;
    else
      table.insert(missing, name);
    end
  end
  return count, total, missing
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
  debug({["blocks"] = blocks}, 2);
  
  -- assemble a list of candidates, we'll make a copy of this list once per block
  local candidatesCopy = {};
  for i=1,GetNumGroupMembers() do
    table.insert(candidatesCopy, UnitNameRealm(GetUnitId(i)));
  end
  debug({["candidatesCopy"] = candidatesCopy}, 2);

  for i=1,#blocks do
    local candidates = candidatesCopy; -- grab a copy of the list of candidates for this block

    for j, v in pairs(ROLE_STRINGS) do
      debug(j, 2);
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
  
  local s = "";
  for i, v in ipairs(blocks) do
    local s = s .. v;
  end
  return s;
end

SLASH_ASSIGNS1 = "/assigns";
local function slashParse(msg, editbox)
  if msg == "" then
    if UnitExists("target") and not UnitIsPlayer("target") then
      msg = UnitName("target");
    else
      debug("You must specify (or target) a non-player unit.")
      return;
    end
  elseif string.match(msg, "^dump ") then
    msg = string.gsub(msg, "^dump ", "");
    if msg == "specs" then
      DevTools_Dump(table_specializations);
    elseif msg == "encounters" then
      DevTools_Dump(table_encounters);
    elseif msg == "inspectFailed" then
      DevTools_Dump(inspectFailed);
    elseif msg == "completion" then
      local count, total, missing = GetDataCompletionRate();
      if #missing > 0 then
        local missingS = "";
	for i=1,#missing do
	  if i > 1 then
	    missingS = missingS .. ", ";
	  end
	  missingS = missingS .. missing[i]
	end
        debug(string.format("Data completion rate is %d/%d (%d%%). Missing data for: %s", count, total, count/total*100, missingS));
      else
        debug(string.format("Data completion rate is %d/%d (%d%%).", count, total, count/total*100));
      end
    end
    return;
  elseif string.match(msg, "^debug %d") then
    debugOn = tonumber(string.match(msg, "^debug (%d)"));
    if debugOn then
      debug("Debug is now ON ("..debugOn..").");
    else
      debug("Debug is now OFF.");
    end
    return;
  end
  
  -- set encounter name to lower case
  msg = string.lower(msg);

  -- remove all non-alphabetical letters from the encounter name
  msg = string.gsub(msg, "[^%l]", "");
  
  if table_encounters[msg] then
    --RTAssigns:Show()
    -- TODO: set the display window to the corresponding encounter entry
    debug('Loading template for encounter "'..msg..'".', 1);
    print(generateAssigns(table_encounters[msg]));
  else
    debug('Template for encounter "'..msg..'" was not found!');
  end
end
SlashCmdList["ASSIGNS"] = slashParse;

local function onUpdate(self, elapsed)
  local currentTime = time();
  timeSinceLastCheck = timeSinceLastCheck + elapsed;
  if not inspectInProgress and timeSinceLastCheck >= inspectInterval and (not InspectFrame or not InspectFrame:IsShown()) and (not InCombatLockdown() or debugOn >= 3) then
    debug("Checking for inspect candidates...", 3);
    timeSinceLastCheck = 0;
    
    debug(GetNumGroupMembers(), 3);
    for i=1,GetNumGroupMembers() do
      local unitId = GetUnitId(i);
      local name = UnitNameRealm(unitId);
      if name == playerName then
	debug("Inspect NOT triggered for "..name.." (Reason: is player).", 3);
        return;
      elseif name == "Unknown" then
	debug("Inspect NOT triggered for "..name.." (Reason: is Unknown).", 3);
        return;
      end
      local lastCheck = GetSpecializationInfoByName(name);
      if (not lastCheck or currentTime - lastCheck >= renewTime) and not inspectFailed[name] then
        if CanInspect(unitId) and UnitIsConnected(unitId) then
          debug("Triggered inspect for "..name..".", 1);
          NotifyInspect(unitId);
          inspectInProgress, inspectStart = unitId, currentTime;
          break;
	elseif debugOn >= 3 then
	  local reason;
	  if not CanInspect(unitId) then
	    reason = "CanInspect";
	  else
	    reason = "UnitIsConnected";
	  end
	  debug("Inspect NOT triggered for "..name.." (Reason: "..reason..").", 3);
        end
      elseif debugOn >= 3 then
	local reason;
	if not (not lastCheck or currentTime - lastCheck >= renewTime) then
	  reason = "lastCheck";
	else
	  reason = "inspectFailed";
	end
	debug("Inspect NOT triggered for "..name.." (Reason: "..reason..").", 3);
      end
    end
  elseif inspectInProgress then
    if currentTime - inspectStart >= inspectTimeout then
      local name = UnitNameRealm(inspectInProgress);
      debug("Inspect for "..name.." timed out!", 2)
      ClearInspectPlayer();
      inspectFailed[name] = currentTime;
      inspectInProgress = false;
      inspectStart = nil;
      
      timeSinceLastCheck = inspectInterval; -- cause an immediate check for another player to inspect
    end
  end
  
  for i, v in pairs(inspectFailed) do
    if currentTime - v >= inspectRecovery then
      inspectFailed[i] = nil;
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
    inspectInterval = RTA_options["inspectInterval"] or 15;
    -- amount of time before an inspect request is abandoned
    inspectTimeout = RTA_options["inspectTimeout"] or 10;
    -- amount of time before trying a player than timed out an inspect again
    inspectRecovery = RTA_options["inspectRecovery"] or 60;
    -- the minimum amount of time before a reinspect is triggered on a specific character (barring specific triggers)
    renewTime = RTA_options["renewTime"] or 60 * 60;
    -- amount of time before purging old character data entries
    purgeTime = RTA_options["purgeTime"] or 10 * 24 * 60 * 60;
    -- same as above, but for people offrealm
    purgeTimeXr = RTA_options["purgeTimeXr"] or 3 * 24 * 60 * 60;
    
    RegisterAddonMessagePrefix("RT_Assigns");
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
    ["inspectTimeout"]        = inspectTimeout,
    ["inspectRecovery"]       = inspectRecovery,
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
      ClearInspectPlayer();
      inspectFailed[name] = time();
      inspectInProgress = false;
      inspectStart = nil;
    end
    ClearInspectPlayer();
    inspectInProgress = nil;
    timeSinceLastCheck = inspectInterval;  -- cause an immediate check for another player to inspect
  end
end
function events:PLAYER_SPECIALIZATION_CHANGED(unitId)
  debug({["PLAYER_SPECIALIZATION_CHANGED"] = {unitId}}, 3);
  if unitId and (unitId == "player" or UnitIsUnit(unitId, "player")) then
    SetSpecializationInfo(UnitNameRealm("player"), GetSpecializationInfo(GetSpecialization()));
  elseif unitId and unitId ~= "" then
    local name = UnitNameRealm(unitId);
    if name == "Unknown" then
      return;
    end
    debug("Scheduled inspect for "..name.." (specialization changed).", 1);
    SetSpecializationInfo(name, nil, true);
    timeSinceLastCheck = inspectInterval;
  end
end
function events:GROUP_ROSTER_UPDATE()
  -- determine current group type
  if IsInRaid() then
    groupType = "raid";
  elseif GetNumGroupMembersOld() > 0 then
    groupType = "party";
  else
    groupType = "player";
  end
end
function events:RAID_ROSTER_UPDATE()
  -- determine current group type
  if IsInRaid() then
    groupType = "raid";
  elseif GetNumGroupMembersOld() > 0 then
    groupType = "party";
  else
    groupType = "player";
  end
end
function events:GROUP_JOINED()
  if IsInRaid() then
    SendAddonMessage(ADDON_MSG_PREFIX, {["versionCheck"] = ADDON_VERSION_FULL,}, "RAID")
  end
end
function events:CHAT_MSG_ADDON(prefix, message, channel, sender)
  if prefix == ADDON_MSG_PREFIX then
    local message = libSerialize:Deserialize(message)
    if not (message and type(message) == "table") then
      return;
    end
    for i, v in pairs(message) do
      if i == "versionCheck" then
        if channel == "WHISPER" then
	  if not updateMsg then
	    print("Your current version of "..ADDON_NAME.." is not up to date! Please go to "..ADDON_DOWNLOAD_URL.." to update.");
	    updateMsg = true;
	  end
	elseif channel == "RAID" or channel == "GUILD" then
	  if not v then
            return;
	  end
	  if v < ADDON_VERSION_FULL then
	    SendAddonMessage(ADDON_MSG_PREFIX, {["versionCheck"] = "",}, "WHISPER", sender)
	  elseif not updateMsg then
	    if ADDON_VERSION_FULL < v then
	      print("Your current version of "..ADDON_NAME.." is not up to date! Please go to "..ADDON_DOWNLOAD_URL.." to update.");
	      updateMsg = true;
	    end
	  end
	end
      end
    end
  end
end
frame:SetScript("OnEvent", function(self, event, ...)
  events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
  frame:RegisterEvent(k) -- Register all events for which handlers have been defined
end