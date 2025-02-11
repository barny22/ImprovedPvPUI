local Log = IMP_PVP_UI_Logger('IMP_KCT')

local EVENT_NAMESPACE = 'IMP_KEEP_CAPTURE_TRACKER'
local ICON_SIZE = 16

local LKT = LibKeepTooltip

local siegeBuffer = {}
local campaignId = nil

local GetKeepIcon = IMP_PVP_UI_SHARED.GetKeepIcon
local SecondsToTime = IMP_PVP_UI_SHARED.SecondsToTime

local BEFORE = 1
local AFTER = 2
local LAST_SIEGE_STRING = 3

local ALLIANCE = 1

local function GetLastSiegeStringForKeep(keepId)
    local keepBuffer = siegeBuffer[keepId]

    if not keepBuffer[AFTER] then return end

    local allianceBefore, startTimestamp = unpack(keepBuffer[BEFORE])
    local allianceAfter, endTimestamp = unpack(keepBuffer[AFTER])

    local captured = allianceAfter ~= allianceBefore
    local durationString = startTimestamp and SecondsToTime(endTimestamp - startTimestamp) or '?'

    local iconBefore = GetKeepIcon(keepId, allianceBefore, ICON_SIZE)
    local iconAfter = GetKeepIcon(keepId, allianceAfter, ICON_SIZE)

    local text
    if captured then
        text = string.format('%s->%s (%s) CAP', iconBefore, iconAfter, durationString)
    else
        text = string.format('%s (%s) DEF', iconBefore, durationString)
    end

    return text
end

local function GuessAmountOfEnemies(captureDuration)
	if captureDuration > 61 then return '1' end
	if captureDuration > 42 then return '2' end
	return '3+'
end

local function GetLastSiegeStringForResource(keepId)
    local keepBuffer = siegeBuffer[keepId]

    if not keepBuffer[AFTER] then return end

    local allianceBefore, startTimestamp = unpack(keepBuffer[BEFORE])
    local allianceAfter, endTimestamp = unpack(keepBuffer[AFTER])

    local captured = allianceAfter ~= allianceBefore
    local duration = startTimestamp and endTimestamp - startTimestamp or nil
    local durationString = duration and SecondsToTime(duration) or '?'

    local iconBefore = GetKeepIcon(keepId, allianceBefore, ICON_SIZE)
    local iconAfter = GetKeepIcon(keepId, allianceAfter, ICON_SIZE)

    local text
    if captured then
        local amountOfEnemies = duration and GuessAmountOfEnemies(duration) or '?'
        text = string.format('%s->%s (%s ~ %sp) CAP', iconBefore, iconAfter, durationString, amountOfEnemies)
    else
        text = string.format('%s (%s) DEF', iconBefore, durationString)
    end

    return text
end

local function GetKeepLatestSiege(keepId)
    local keepBuffer = siegeBuffer[keepId]

    if not keepBuffer then return end
    if not keepBuffer[LAST_SIEGE_STRING] then return end

    local endTimestamp = keepBuffer[AFTER][2]
    local agoString = SecondsToTime(GetTimeStamp() - endTimestamp)

    return string.format('%s (%s)', keepBuffer[LAST_SIEGE_STRING], agoString)
end

local function AddKeepLastSiegeLine(self)
    if not IsLocalBattlegroundContext(self.battlegroundContext) then return end

    local keepId = self.keepId
    local text = GetKeepLatestSiege(keepId)

    if text then
        LKT.AddLine(self, text, LKT.KEEP_TOOLTIP_NORMAL_LINE)
        Log('Line was added: %s', text)
    -- else
    --     LKT.AddLine(self, 'Unknown', LKT.KEEP_TOOLTIP_NORMAL_LINE)
    end
end

local function OnKeepUnderAttack(_, keepId, battlegroundContext, underAttack)
    Log('%s under attack', GetKeepName(keepId))
    -- df('keepbuffer: %s', tostring(latestSiegeBuffer[keepId]))  -- delete

	local timestamp = GetTimeStamp()
	-- local keepType = GetKeepType(keepId)
	local ownerAllianceId = GetKeepAlliance(keepId, battlegroundContext)

    -- is seems in rare cases it can return 0 which is not good, so just ignore this event
    if ownerAllianceId == 0 then return end

    local keepBuffer = siegeBuffer[keepId]

    if underAttack then
        keepBuffer[BEFORE] = {ownerAllianceId, timestamp}
    else
        if not keepBuffer then return end
        keepBuffer[AFTER] = {ownerAllianceId, timestamp}
        if GetKeepType(keepId) == KEEPTYPE_RESOURCE then
            keepBuffer[LAST_SIEGE_STRING] = GetLastSiegeStringForResource(keepId)
        else
            keepBuffer[LAST_SIEGE_STRING] = GetLastSiegeStringForKeep(keepId)
        end
    end
end

local function ChangeReceipes()
    local KEEP_LAST_SIEGE = LKT:RegisterIngridient('KEEP_LAST_SIEGE', AddKeepLastSiegeLine)

    local keepTypesToModify = {
        KEEPTYPE_KEEP,
        KEEPTYPE_OUTPOST,
        KEEPTYPE_TOWN,
        KEEPTYPE_RESOURCE,
    }

    for _, keepType in ipairs(keepTypesToModify) do
        local recipe = LKT.GetRecipeByKeepType(keepType)
        LKT.AddIngridientAfter(recipe, KEEP_LAST_SIEGE, LKT.INGRIDIENTS.HEADER)
    end

    Log('Recipes changed')
end

local function OnPlayerActivated(_, initial)
    if not IsInAvAZone() then return end
    local currentCampaignId = GetCurrentCampaignId()

    if initial or campaignId ~= currentCampaignId then
        ZO_ClearTable(siegeBuffer)

        campaignId = currentCampaignId
        local numKeeps = GetNumKeeps()
        for i = 1, numKeeps do
            local keepId, battlegroundContext = GetKeepKeysByIndex(i)

            if IsLocalBattlegroundContext(battlegroundContext) then
                local allianceId = GetKeepAlliance(keepId, battlegroundContext)
                siegeBuffer[keepId] = {}
                siegeBuffer[keepId][ALLIANCE] = {allianceId, nil}
            end
        end
    else
        local numKeeps = GetNumKeeps()
        for i = 1, numKeeps do
            local keepId, battlegroundContext = GetKeepKeysByIndex(i)
            local keepBuffer = siegeBuffer[keepId]
            if IsLocalBattlegroundContext(battlegroundContext) then
                local currentAllianceId = GetKeepAlliance(keepId, battlegroundContext)
                if keepBuffer[AFTER] and keepBuffer[AFTER][ALLIANCE] and keepBuffer[AFTER][ALLIANCE] ~= currentAllianceId then
                    keepBuffer[BEFORE] = {keepBuffer[AFTER][ALLIANCE], nil}
                    keepBuffer[AFTER] = {currentAllianceId, nil}

                    if GetKeepType(keepId) == KEEPTYPE_RESOURCE then
                        keepBuffer[LAST_SIEGE_STRING] = GetLastSiegeStringForResource(keepId)
                    else
                        keepBuffer[LAST_SIEGE_STRING] = GetLastSiegeStringForKeep(keepId)
                    end
                end
            end
        end
    end

    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_KEEP_UNDER_ATTACK_CHANGED, OnKeepUnderAttack)
end

function IMP_KT_EnableTracker()
    ChangeReceipes()
    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
end