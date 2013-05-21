-- load libraries
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0");
local AceGUI = LibStub("AceGUI-3.0");

-- declare strings
local ADDON_NAME = "FARaidTools_Assigns";
local ADDON_VERSION_FULL = "v1.0";
local ADDON_VERSION = string.gsub(ADDON_VERSION_FULL, "[^%d]", "");
local ADDON_DOWNLOAD_URL = "https://github.com/aggixx/FARaidTools_Assigns";

local ADDON_COLOR = "FFF9CC30";
local ADDON_CHAT_HEADER  = "|c" .. ADDON_COLOR .. "FA Assigns:|r ";
local ADDON_MSG_PREFIX = "RT_Assigns";

local ASSIGN_BLOCK_NEW = "\n\-\-NEW BLOCK\-\-\n";

local ROLE_STRINGS = {
  -- {"role", "<role%d>"},
  {"tank", "<tank%d>"}, -- TANK
  {"rheal", "<rheal%d>"}, -- NON-MONK HEALERS
  {"mheal", "<mheal%d>"}, -- MONK HEALERS
  {"heal", "<heal%d>"}, -- HEALER
  {"rdps", "<rdps%d>"}, -- RANGED DPS
  {"mdps", "<mdps%d>"}, -- MELEE DPS
  {"dps", "<dps%d>"}, -- DPS
};

-- declare locals for variables declared in ADDON_LOADED
-- (eg: SavedVariables)
local debugOn;
local inspectInterval;
local inspectTimeout;
local renewTime;
local purgeTime;
local purgeTimeXr;
local table_specializations;
local table_encounters;
local table_dropdown;

-- declare variables
local _;
local playerName;
local timeSinceLastCheck = 0; -- onUpdate accumulator
local inspectInProgress = false;
local inspectStart;
local groupType;
local updateMsg = false;
local inspectFailed = {};
local dropdownValue;

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
  elseif groupType == "party" and i == GetNumGroupMembers() then
    return "player";
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

local function GetEncounterSlug(msg)
  -- set encounter name to lower case
  msg = string.lower(msg);

  -- remove any difficulty suffix
  local difficulty = string.match(msg, "%d%d?[hnlc]$") or "";
  if difficulty then
    msg = string.gsub(msg, "%d%d?[hnlc]$", "");
  end
  
  -- remove all non-alphabetical letters from the encounter name
  msg = string.gsub(msg, "[^%l]", "");
  
  -- reattach difficulty suffix
  return msg..difficulty;
end

local function GetDropdownTable()
  local t = {};
  for i, v in pairs(table_encounters) do
    table.insert(t, v["displayName"]);
  end
  return t
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
    local candidates
    if debugOn > 0 and groupType == "player" then
      candidates = {};
      for j, v in pairs(table_specializations) do
        table.insert(candidates, j);
      end
    else
      candidates = candidatesCopy; -- grab a copy of the list of candidates for this block
    end
    --debug(candidates, 1);

    -- parse groups
    local x = 0;
    while string.match(blocks[i], "%d+{%d+%l+%s?.-}") and x < 100 do
      x = x + 1;
      local group = string.match(blocks[i], "%d+{%d+%l+%s?.-}");
      local unitCap = tonumber(string.match(blocks[i], "(%d+){%d+%l+%s?.-}"));
      debug("group unitCap = "..unitCap, 1);
      local s = "";
      
      local y = 0;
      while string.match(group, "%d+%l+") and y < 25 do
	y = y + 1;
        local roleCap, role = string.match(group, "(%d+)(%l+)");
	roleCap = tonumber(roleCap);
	debug("role = "..role..", roleCap = "..roleCap, 1);
	
	local limit = #candidates;
        for j=0,limit-1 do -- loop through all remaining candidates in this block
          -- check if this candidate matches the role criteria
          if table_specializations[candidates[limit-j]] then
            local id = table_specializations[candidates[limit-j]][2]
            if RTA_specData[id] and RTA_specData[id][role] then
	      debug("Adding "..candidates[limit-j].." to s2.", 1);
	      
	      -- append the player's name to s2
	      if s ~= "" then
	        s = s .. " ";
	      end
	      s = s .. string.match(candidates[limit-j], "^%a+");
	      
	      -- remove the player from the candidate list
	      table.remove(candidates, limit-j);
	      
	      -- this candidate matches
	      -- decrement the param count
	      roleCap = roleCap - 1
	      if roleCap > 0 then
	        debug("Decremented "..role.." to "..roleCap..".", 1);
	        group = string.gsub(group, string.match(group, "%d+%l+"), roleCap..role, 1);
	      else
	        debug("Role limit reached, removed "..role.." param.", 1);
	        group = string.gsub(group, string.match(group, "%d+%l+%s*"), "", 1);
		break;
	      end
	      
	      if select(2, string.gsub(s, "[%a-]+", "")) >= unitCap then
		break;
	      else
	        debug("players in group = "..select(2, string.gsub(s, "[%a-]+", ""))..", unitCap = "..unitCap, 1);
	      end
	    end
	  end
	  
	  if j == limit-1 then
	    debug("Candidate limit reached.", 1);
	    group = string.gsub(group, string.match(group, "%d+%l+%s*"), "", 1);
	  end
	end
	
	if select(2, string.gsub(s, "[%a-]+", "")) >= unitCap then
	  debug("Group limit reached ("..select(2, string.gsub(s, "[%a-]+", ""))..").", 1);
	  break;
	end
      end
      
      blocks[i] = string.gsub(blocks[i], "%d+{%d+%l+%s?.-}", s, 1);
    end
    
    -- parse individual
    for j=1,#ROLE_STRINGS do
      local k = 1;
      while string.match(blocks[i], string.format(ROLE_STRINGS[j][2], k)) do -- while there is spots left of this role to fill
        local success;
	local limit = #candidates;
        for l=0,limit-1 do -- loop through all remaining candidates in this block
          -- check if this candidate matches our criteria
          if table_specializations[candidates[limit-l]] then
            local id = table_specializations[candidates[limit-l]][2]
            if RTA_specData[id] and RTA_specData[id][ROLE_STRINGS[j][1]] then
              -- this candidate matches
              blocks[i] = string.gsub(blocks[i], string.format(ROLE_STRINGS[j][2], k), string.match(candidates[limit-l], "^%a+")); -- replace template text with candidate's name
              table.remove(candidates, limit-l); -- each player can only be assigned once per block
              -- so remove them from the candidate list for this block
              success = true; -- set success variable so loop knows to continue
              break; -- since we likely still have candidates left for this role
            end
          end
        end
        if success then
          k = k + 1; -- successfully found a match, so keep going
        else -- we're out of candidates for this role so break loop early
          blocks[i] = string.gsub(blocks[i], "%s*<"..ROLE_STRINGS[j][1].."%d+>", ""); -- Remove any remaining matches
          break;
        end
      end
    end
  end
  
  local s = "";
  for i=1,#blocks do
    if i > 1 then
      s = s .. "\n";
    end
    s = s .. blocks[i];
  end
  return s;
end

local function onUpdate(self, elapsed)
  local currentTime = time();
  timeSinceLastCheck = timeSinceLastCheck + elapsed;
  if not inspectInProgress and timeSinceLastCheck >= inspectInterval and (not InspectFrame or not InspectFrame:IsShown()) and not InCombatLockdown() then
    debug("Scanning "..GetNumGroupMembers().." group members for inspect candidates...", 3);
    timeSinceLastCheck = 0;
    
    for i=1,GetNumGroupMembers() do
      local unitId = GetUnitId(i);
      local name = UnitNameRealm(unitId);
      if name == playerName then
	debug("Inspect NOT triggered for "..name.." (Reason: is player).", 4);
      elseif name == "Unknown" then
	debug("Inspect NOT triggered for "..name.." (Reason: is Unknown).", 4);
      else
        local lastCheck = GetSpecializationInfoByName(name);
        if (not lastCheck or currentTime - lastCheck >= renewTime) and not inspectFailed[name] then
          if CanInspect(unitId) and UnitIsConnected(unitId) then
            debug("Triggered inspect for "..name..".", 1);
            NotifyInspect(unitId);
            inspectInProgress, inspectStart = unitId, currentTime;
            break;
	  elseif debugOn >= 4 then
	   local reason;
	    if not CanInspect(unitId) then
	      reason = "CanInspect";
	    else
	      reason = "UnitIsConnected";
	    end
	    debug("Inspect NOT triggered for "..name.." (Reason: "..reason..").", 4);
          end
        elseif debugOn >= 4 then
	  local reason;
	  if not (not lastCheck or currentTime - lastCheck >= renewTime) then
	    reason = "lastCheck";
	  else
	    reason = "inspectFailed";
	  end
	  debug("Inspect NOT triggered for "..name.." (Reason: "..reason..").", 4);
        end
      end
      
      if i == GetNumGroupMembers() then -- if we've made it to the end of the loop
        inspectFailed = {}; -- then clear the failed list so we can try those people again
      end
    end
  elseif inspectInProgress then
    if currentTime - inspectStart >= inspectTimeout then
      local name = UnitNameRealm(inspectInProgress);
      if name then
        debug("Inspect for "..name.." timed out!", 2);
        inspectFailed[name] = true;
      end
      ClearInspectPlayer();
      inspectInProgress = false;
      inspectStart = nil;
      
      timeSinceLastCheck = inspectInterval; -- cause an immediate check for another player to inspect
    end
  end
end

local onUpdateFrame = CreateFrame("frame")
onUpdateFrame:SetScript("OnUpdate", onUpdate)

-- #############
-- GUI START
-- #############

-- Create a container frame
local frame = AceGUI:Create("Frame");
frame:SetCallback("OnClose", function(this)
  this:Hide();
end);
frame:SetTitle("FARaidTools_Assigns");
--frame:SetStatusText("Status Bar");
frame:SetWidth(300);
frame:SetHeight(389);
frame:EnableResize(false);
frame:SetLayout("Flow");

-- Create the output box
local editboxOutput = AceGUI:Create("MultiLineEditBox");
editboxOutput:SetLabel("Output");
editboxOutput:SetWidth(300);
editboxOutput:SetNumLines(6);

-- Create the template box
local editboxInput = AceGUI:Create("MultiLineEditBox");
editboxInput:SetLabel("Template");
editboxInput:SetWidth(300);
editboxInput:SetNumLines(6);

-- Create the encounter selection dropdown
local dropdown = AceGUI:Create("Dropdown");
dropdown:SetLabel("Encounter");
dropdown:SetWidth(206);

-- Create the new encounter button
local button2 = AceGUI:Create("Button");
button2:SetWidth(60);
button2:SetHeight(25);
button2:SetText("New");

-- Create the announce button
local button = AceGUI:Create("Button");
button:SetWidth(150);
button:SetHeight(17);
button:SetText("Announce to Group");

-- add widgets to frame as children
frame:AddChild(dropdown);
frame:AddChild(button2);
frame:AddChild(editboxInput);
frame:AddChild(editboxOutput);
frame:AddChild(button);

-- Hide GUI
if debugOn == 0 then
  frame:Hide();
end

-- set scripts
local function editboxInput_OnEnterPressed(this, event, template)
  for i, v in pairs(table_encounters) do
    if table_dropdown[dropdownValue] == v["displayName"] then
      table_encounters[i]["template"] = template;
      break;
    end
  end
  editboxOutput:SetText(generateAssigns(template));
end

local function dropdown_OnValueChanged(this, event, item)
  dropdownValue = item;
  local encounter = GetEncounterSlug(table_dropdown[item]);
  if table_encounters[encounter] then
    editboxInput:SetText(table_encounters[encounter]["template"]);
    editboxInput_OnEnterPressed(nil, nil, table_encounters[encounter]["template"]);
  else
    debug("Encounter not found!");
  end
end

dropdown:SetCallback("OnValueChanged", dropdown_OnValueChanged);
editboxInput:SetCallback("OnEnterPressed", editboxInput_OnEnterPressed);

StaticPopupDialogs["RTA_NEW_ENCOUNTER"] = {
  text = "Name of encounter (eg: Nalak or Ji'kun 25H):",
  button1 = ACCEPT,
  button2 = CANCEL,
  hasEditBox = true,
  OnAccept = function(self)
    local text = self.editBox:GetText();
    local slug = GetEncounterSlug(text);
    table_encounters[slug] = {
      ["displayName"] = text,
      ["template"] = "",
    };
    table_dropdown = GetDropdownTable();
    dropdown:SetList(table_dropdown);
    for i=1,#table_dropdown do
      if table_dropdown[i] == text then
        dropdown:SetValue(i);
        dropdown_OnValueChanged(nil, nil, i);
        break;
      end
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,  -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
}

button2:SetCallback("OnClick", function(this, event)
  StaticPopup_Show("RTA_NEW_ENCOUNTER")
end);

button:SetCallback("OnClick", function(this, event)
  local text, lines = editboxOutput:GetText(), {};
  while 1 do
    local line = string.match(text, "^(.-)\n");
    if line then
      table.insert(lines, line);
      text = string.gsub(text, "^.-\n", "");
    else
      table.insert(lines, text); -- insert the last line into the table
      break;
    end
  end
    
  local channel;
  if groupType == "raid" then
    if UnitIsGroupLeader("player") or UnitIsRaidOfficer("player") then
      channel = "RAID_WARNING";
    else
      channel = "RAID";
    end
  elseif groupType == "party" then
    channel = "PARTY";
  end
    
  for i=1,#lines do
    SendChatMessage(lines[i], channel);
  end
end);

-- #############
-- GUI END
-- #############

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
  
  if not string.match(msg, "%s*%d%d?[hnlcHNLC]$") then
    local diff = select(3, GetInstanceInfo());
    if diff > 0 then
      if diff == 1 then
        msg = msg .. " 5N";
      elseif diff == 2 then
        msg = msg .. " 5H";
      elseif diff == 3 then
        msg = msg .. " 10N";
      elseif diff == 4 then
        msg = msg .. " 25N";
      elseif diff == 5 then
        msg = msg .. " 10H";
      elseif diff == 6 then
        msg = msg .. " 25H";
      elseif diff == 7 then
        msg = msg .. " 25L";
      elseif diff == 8 then
        msg = msg .. " 5C";
      elseif diff == 9 then
        msg = msg .. " 40N";
      elseif diff == 10 then
        msg = msg .. " 3N";
      elseif diff == 11 then
        msg = msg .. " 3H";
      end
    end
  end
  
  msg = GetEncounterSlug(msg);
  
  if not table_encounters[msg] then
    msg = string.gsub(msg, "%s*%d%d?[hnlc]$", "");
  end
  
  if table_encounters[msg] then
    debug('Loading template for encounter "'..msg..'".', 1);
    frame:Show()
    for i=1,#table_dropdown do
      if table_encounters[msg]["displayName"] == table_dropdown[i] then
        dropdown:SetValue(i);
        dropdown_OnValueChanged(nil, nil, i);
        break;
      end
    end
  else
    debug('Template for encounter "'..msg..'" was not found!');
  end
end
SlashCmdList["ASSIGNS"] = slashParse;

local frame, events = CreateFrame("Frame"), {}
function events:ADDON_LOADED(addon)
  if addon == ADDON_NAME then
    RTA_options           = RTA_options or {};
    table_specializations = RTA_options["table_specializations"] or {};
    table_encounters      = RTA_options["table_encounters"] or {
		["darkanimus25n"] = {
			["template"] = "Starting from {x} flare:\nGolem #1: <rdps1>\nGolem #2: <rdps1>\nGolem #3: <dps1>\nGolem #4: <dps2>\nGolem #5: <rdps2>\nGolem #6: <rdps2>\nGolem #7: <dps3>\nGolem #8: <dps4>\nGolem #9: <dps5>\nGolem #10: <tank1>\nGolem #11: <tank1>\nGolem #12: <dps6>\nGolem #13: <dps7>\nGolem #14: <dps8>\nGolem #15: <tank2>\nGolem #16: <tank2>\nGolem #17: <dps9>\nGolem #18: <dps10>\nGolem #19: <rdps3>\nGolem #20: <rdps3>\nGolem #21: <dps11>\nGolem #22: <dps12>\nGolem #23: <rdps4>\nGolem #24: <rdps4>\nGolem #25: <dps13>",
			["displayName"] = "Dark Animus 25N",
		},
		["leishen25n"] = {
			["template"] = "{star}: 6{1heal 1tank 3dps 1heal 3dps}\n{square}: 6{1heal 4dps 1heal 2dps}\n{diamond} 6{1heal 1tank 3dps 1heal 3dps}\n{x}: 7{1heal 5dps 1heal 2dps}",
			["displayName"] = "Lei Shen 25N",
		},
		["councilofelders25n"] = {
			["template"] = "Sul: 3{3mdps 3dps}",
			["displayName"] = "Council of Elders 25N",
		},
		["darkanimus10n"] = {
			["template"] = "Starting from {x} flare:\nGolem #1: <rdps1>\nGolem #2: <rdps1>'s pet\nGolem #3: <rdps2>\nGolem #4: <rdps2>'s pet\nGolem #5: <tank1>\nGolem #6: <tank1>\nGolem #7: <tank2>\nGolem #8: <tank2>\nGolem #9: <dps1>\nGolem #10: <dps2>\nGolem #11: <rdps3>\nGolem #12: <rdps3>'s pet",
			["displayName"] = "Dark Animus 10N",
		},
		["durumutheforgotten10n"] = {
			["template"] = "Red: 3{3rdps 3dps}\nYellow: 4{2tank 4dps}\nBlue: 3{3heal 3dps}",
			["displayName"] = "Durumu the Forgotten 10N",
		},
    };
    debugOn = RTA_options["debugOn"] or 0;
    -- inspect scan interval (eg: how often it is checked if anyone needs a renew)
    inspectInterval = RTA_options["inspectInterval"] or 15;
    -- amount of time before an inspect request is abandoned
    inspectTimeout = RTA_options["inspectTimeout"] or 10;
    -- the minimum amount of time before a reinspect is triggered on a specific character (barring specific triggers)
    renewTime = RTA_options["renewTime"] or 60 * 60;
    -- amount of time before purging old character data entries
    purgeTime = RTA_options["purgeTime"] or 17 * 24 * 60 * 60;
    -- same as above, but for people offrealm
    purgeTimeXr = RTA_options["purgeTimeXr"] or 3 * 24 * 60 * 60;
    
    RegisterAddonMessagePrefix("RT_Assigns");
    table_dropdown = GetDropdownTable();
    dropdown:SetList(table_dropdown);
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
      inspectFailed[name] = true;
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
	    debug("Your current version is not up to date! Please go to "..ADDON_DOWNLOAD_URL.." to update.");
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
	      debug("Your current version is not up to date! Please go to "..ADDON_DOWNLOAD_URL.." to update.");
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