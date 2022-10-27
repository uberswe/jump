JUMP = {}

JUMP.name = "Jump"
JUMP.savedData = {}
JUMP.player = {}
JUMP.player.isJumping = false
JUMP.player.overallJumpCount = 0
JUMP.player.timeSinceLastJump = 0
JUMP.player.jumps = 0
JUMP.player.elevations = {}
JUMP.player.jumpStart = 0
JUMP.player.jumpPeak = 0
JUMP.player.unitTag = "player"
JUMP.delay = 50
JUMP.isInGroup = false
JUMP.groupSize = 0
JUMP.group = {}
JUMP.savedData.debug = false
JUMP.inMenu = false

-- A regular jump is an increase of 160 in 500ms.
-- but this could vary a lot since we only poll at certain intervals, may need to poll more often to be more accurate
JUMP.jumpBuffer = 25
-- We assume if the last 3 elevations are within this value that we have landed
JUMP.landedBuffer = 5

-- Functions that trigger the beginning of a possible jump
function JUMP.RegularJump(obj)
    -- Are we jumping by pressing space?
    if obj.timeSinceLastJump < 1000 then
        return false
    end
    if not obj.elevations[2] or not obj.elevations[1] or obj.isJumping then
        return false
    end
    if obj.elevations[2] > 0 and obj.elevations[2] + JUMP.jumpBuffer < obj.elevations[1] then
        return true
    end
    return false
end

--function JUMP.RunOffCliff(obj)
--    -- What about running off a cliff?
--    if obj.timeSinceLastJump < 1000 then
--        return false
--    end
--    if not obj.elevations[2] or not obj.elevations[1] or obj.isJumping then
--        return false
--    end
--    if obj.elevations[2] > 0 and obj.elevations[1] + JUMP.jumpBuffer < obj.elevations[2] then
--        return true
--    end
--    return false
--end

JUMP.possibleJumpIndicators = {
    --runOffCliff = JUMP.RunOffCliff,
    regularJump = JUMP.RegularJump
}

-- Functions that find the end of a jump

function JUMP.UpwardsJump(obj)
    -- If jump start is lower than the peak we jumped upwards, but the current elevation is lower than our peak and our elevation is greater than our current elevation we must have landed since we changed elevation direction
    if not obj.elevations[1] or not obj.elevations[2] then
        return false
    end

    if obj.jumpStart < obj.jumpPeak and obj.elevations[1] < obj.jumpPeak and obj.elevations[2] > obj.elevations[1] then
        return true
    end
    return false
end

--function JUMP.FallJump(obj)
--    -- If our last 5 elevations are all within landedBuffer we have landed
--    local check = 5
--    for i=1,check,1 do
--        if not obj.elevations[i] then
--            return false
--        end
--    end
--    for i=1,check,1 do
--        for x=1,check,1 do
--            if math.abs(obj.elevations[i] - obj.elevations[x]) > JUMP.landedBuffer then
--                return false
--            end
--        end
--    end
--    return true
--end

JUMP.jumpIndicators = {
    upwardsJump = JUMP.UpwardsJump,
    --fallJump = JUMP.FallJump
}

-- Functions that find the end of a false jump

function JUMP.Expire(obj)
    return obj.timeSinceLastJump > 10000
end

function JUMP.StairCheck(obj)
    -- If we go up stairs we expect a fairly consistent climb but in a jump our speed differs throughout the jump
    if obj.timeSinceLastJump < 500 then
        return false
    end

    -- Works ok going up stairs but conflicts with falls and going down stairs
    if obj.jumpPeak == obj.jumpStart then
        return false
    end

    local check = 10
    for i=1,check,1 do
        if not obj.elevations[i] then
            return false
        end
    end
    if (math.abs(obj.elevations[1] - obj.elevations[2]) > JUMP.jumpBuffer) then
        return false
    end
    local lastCheck = math.abs(obj.elevations[2] - obj.elevations[3])
    if lastCheck < JUMP.jumpBuffer then
        return false
    end
    for i=2,check,1 do
        for x=2,check,1 do
            if JUMP.savedData.debug then
                CHAT_ROUTER:AddSystemMessage(string.format("StairCheck %s: %d - not (%d < %d and %d > %d)", obj.unitTag, lastCheck, math.abs(obj.elevations[i] - obj.elevations[x]), JUMP.landedBuffer + lastCheck, math.abs(obj.elevations[i] - obj.elevations[x]), lastCheck - JUMP.landedBuffer))
            end
            if not i == x then
                if not (math.abs(obj.elevations[i] - obj.elevations[x]) < JUMP.landedBuffer + lastCheck and math.abs(obj.elevations[i] - obj.elevations[x]) > lastCheck - JUMP.landedBuffer) then
                    return false
                end
                lastCheck = math.abs(obj.elevations[i] - obj.elevations[x])
            end
        end
    end
    return true
end


JUMP.falseJumps = {
    expire = JUMP.Expire,
    stairCheck = JUMP.StairCheck
}

function JUMP:Initialize()
    -- Do some init stuff
    JUMP.savedData = ZO_SavedVars:NewAccountWide('JumpSavedVariables', 1, nil, systemDefault, nil, JUMP.name)

    if not JUMP.savedData then
        JUMP.savedData = {}
        JUMP.savedData.hidden = false
    end

    if JUMP.savedData.overallJumpCount then
        JUMP.player.overallJumpCount = JUMP.savedData.overallJumpCount
    end

    if JUMP.savedData.group then
        JUMP.group = JUMP.savedData.group
    end

    if IsUnitGrouped("player") then
        JUMP.isInGroup = true
    else
        JUMP.isInGroup = false
    end

    JUMP.player.elevations[1] = JUMP:GetCurrentElevation("player")

    JUMPUI:SetHidden(JUMP.savedData.hidden)
    JUMP.OnGroupChange()
    JUMP:UpdateUI()
end

function JUMP:UpdateUI()
    JUMP_OVERALL_LABEL:SetText(string.format("Lifetime jumps: %d", JUMP.player.overallJumpCount))
    if JUMP.isInGroup then
        if not JUMP.group then
            JUMP.group = {}
            if JUMP.savedData.debug then
                CHAT_ROUTER:AddSystemMessage(string.format("no rows, created group"))
            end
        end
        table.sort(JUMP.group, function(aa, bb)
            if not aa.jumps or not bb.jumps then
                return true
            end
            return aa.jumps > bb.jumps
        end)
        if JUMP.group then
            if not JUMP.rows then
                JUMP.rows = {}
                local lastRow
                local count = 0
                for index, data in ipairs(JUMP.group) do
                    if data.unitTag and IsUnitOnline(data.unitTag) then
                        local row = WINDOW_MANAGER:GetControlByName("GROUP_MEMBER_LABEL" .. tostring(index), tostring(index))
                        if not row then
                            row = CreateControlFromVirtual("GROUP_MEMBER_LABEL" .. tostring(index), JUMPUI, "GROUP_MEMBER_LABEL", tostring(index))
                        end
                        if not lastRow then
                            row:SetAnchor(BOTTOMLEFT, JUMP_OVERALL_LABEL, BOTTOMLEFT, 0, 50)
                        else
                            row:SetAnchor(BOTTOMLEFT, lastRow, BOTTOMLEFT, 0, 50)
                        end
                        row:SetText(string.format("%s: %s", data.accname, data.jumps))
                        row:SetHidden(false)
                        JUMP.rows[index] = row
                        lastRow = row
                        count = count + 1
                        if JUMP.savedData.debug then
                            CHAT_ROUTER:AddSystemMessage(string.format("Added row: %s", tostring(index)))
                        end
                    end
                end
            else
                -- No need to make new controls, just set the text of the row here
                for index, data in ipairs(JUMP.group) do
                    if data.unitTag and IsUnitOnline(data.unitTag) then
                        if JUMP.rows[index] then
                            JUMP.rows[index]:SetText(string.format("%s: %s", data.accname, data.jumps))
                            JUMP.rows[index]:SetHidden(false)
                        else
                            if JUMP.savedData.debug then
                                CHAT_ROUTER:AddSystemMessage(string.format("no row found: %s", tostring(data.unitTag)))
                            end
                        end
                    end
                end
            end
        else
            if JUMP.savedData.debug then
                CHAT_ROUTER:AddSystemMessage(string.format("no rows"))
            end
        end

    end
    JUMPUI:SetHidden(JUMP.inMenu)
    JUMP_CONTAINER:SetDimensions(200, 25 * (2 + JUMP.groupSize))
end

function JUMP.Update()
    local updatedCount = false
    if JUMP.isInGroup then
        for tag in pairs(JUMP.group) do
            if JUMP:CountJumpsForUnit(JUMP.group[tag]) then
                updatedCount = true
            end
        end
    else
        if JUMP:CountJumpsForUnit(JUMP.player) then
            updatedCount = true
        end
    end
    JUMP.savedData.group = JUMP.group
    JUMP.savedData.overallJumpCount = JUMP.player.overallJumpCount
    if updatedCount then
        JUMP:UpdateUI()
    end
end

function JUMP:GetCurrentElevation(unitTag)
    local zone, x, y, z = GetUnitRawWorldPosition(unitTag)
    return y
end

function JUMP:SaveLastElevations(pastElevations, currentElevation, count)
    local newElevations = {}
    if pastElevations then
        for key, val in pairs(pastElevations) do
            newElevations[key+1] = val
            if key == count then
                break
            end
        end
        newElevations[1] = currentElevation
    end
    newElevations[1] = currentElevation
    return newElevations
end

function JUMP:CountJumpsForUnit(obj)
    local updated = false
    if not obj.unitTag or not IsUnitOnline(obj.unitTag) then
        return false
    end

    obj.elevations = JUMP:SaveLastElevations(obj.elevations, JUMP:GetCurrentElevation(obj.unitTag), 10)

    if JUMP.savedData.debug then
        if obj.elevations[1] and obj.elevations[2] and obj.elevations[2] ~= obj.elevations[1] then
            if obj.isJumping then
                CHAT_ROUTER:AddSystemMessage(string.format("Jumping elevation for %s: %d", obj.unitTag, obj.elevations[1]))
            end
        end
    end

    -- Are we still jumping?
    if obj.isJumping then
        for key, func in pairs(JUMP.jumpIndicators) do
            if func(obj) then
                obj.isJumping = false
                obj.jumps = obj.jumps + 1
                if GetUnitDisplayName(obj.unitTag) == GetUnitDisplayName("player") then
                    JUMP.player.overallJumpCount = JUMP.player.overallJumpCount + 1
                end
                obj.timeSinceLastJump = obj.timeSinceLastJump + JUMP.delay
                if JUMP.savedData.debug then
                    CHAT_ROUTER:AddSystemMessage(string.format("Jump finished after %d ms: %s", obj.timeSinceLastJump, key))
                end
                updated = true
            end
        end

        for key, func in pairs(JUMP.falseJumps) do
            if func(obj) then
                obj.isJumping = false
                obj.timeSinceLastJump = 0
                if JUMP.savedData.debug then
                    CHAT_ROUTER:AddSystemMessage(string.format("Invalid jump: %s", key))
                end
            end
        end

        if obj.elevations[1] and obj.elevations[1] > obj.jumpPeak then
            obj.jumpPeak = obj.elevations[1]
        end
    end

    for key, func in pairs(JUMP.possibleJumpIndicators) do
        if func(obj) then
            if obj.elevations[2] then
                obj.jumpStart = obj.elevations[2]
                obj.jumpPeak = obj.elevations[2]
            else
                obj.jumpStart = obj.elevations[1]
                obj.jumpPeak = obj.elevations[1]
            end
            obj.isJumping = true
            obj.timeSinceLastJump = 0
            if JUMP.savedData.debug then
                CHAT_ROUTER:AddSystemMessage(string.format("Possible jump: %s", key))
            end
        end
    end

    obj.timeSinceLastJump = obj.timeSinceLastJump + JUMP.delay
    return updated
end

function JUMP.OnGroupChange()
    if IsUnitGrouped("player") then
        JUMP.isInGroup = true
        JUMP.groupSize = 0
        local list = {}
        for i = 1, GetGroupSize() do
            local unitTag = GetGroupUnitTagByIndex(i)
            if unitTag and IsUnitOnline(unitTag) and string.sub(unitTag, 0, 5) == "group" then
                local accname = GetUnitDisplayName(unitTag)
                local name = string.gsub(GetUnitName(unitTag), "%^%w+", "")
                if name then
                    if not list[i] then
                        list[i] = {}
                    end
                    foundName = false
                    for _, v in pairs(JUMP.group) do
                        if v.accname == accname then
                            list[i].jumps = v.jumps
                            foundName = true
                        end
                    end
                    if not foundName then
                        list[i].jumps = 0
                    end
                    list[i].name = name
                    list[i].accname = accname
                    list[i].unitTag = unitTag
                    list[i].timeSinceLastJump = 0
                    list[i].elevations = {}
                    list[i].elevations[1] = JUMP:GetCurrentElevation(unitTag)
                    list[i].jumpStart = 0
                    list[i].jumpPeak = 0
                    list[i].isJumping = false
                    if JUMP.savedData.debug then
                        CHAT_ROUTER:AddSystemMessage(string.format("added %s - %s", name, unitTag))
                    end
                    JUMP.groupSize = JUMP.groupSize + 1
                end
            end
        end
        JUMP.group = list
    else
        JUMP.isInGroup = false
        JUMP.group = {}
        JUMP.groupSize = 0
    end

    if JUMP.rows then
        for index in ipairs(JUMP.rows) do
            JUMP.rows[index]:SetHidden(true)
        end
    end
    if JUMP.savedData.debug then
        CHAT_ROUTER:AddSystemMessage(string.format("Group size: %d", JUMP.groupSize))
    end
    JUMP.rows = nil
    JUMP:UpdateUI()
end

function JUMP.OnAddOnLoaded(event, addonName)
    if addonName == JUMP.name then
        JUMP:Initialize()

        EVENT_MANAGER:UnregisterForEvent(JUMP.name, EVENT_ADD_ON_LOADED)

        EVENT_MANAGER:RegisterForEvent(JUMP.name, EVENT_GROUP_UPDATE, JUMP.OnGroupChange)
        EVENT_MANAGER:RegisterForEvent(JUMP.name, EVENT_GROUP_MEMBER_LEFT, JUMP.OnGroupChange)
        EVENT_MANAGER:RegisterForEvent(JUMP.name, EVENT_GROUP_MEMBER_JOINED, JUMP.OnGroupChange)
        EVENT_MANAGER:RegisterForUpdate("JumpAddon", JUMP.delay, JUMP.Update)

        SCENE_MANAGER:RegisterCallback("SceneStateChanged", JUMP.SceneStateChanged)

        JUMPUI:ClearAnchors()
        JUMPUI:SetAnchor(JUMP.savedData.point, parent, JUMP.savedData.relativePoint, JUMP.savedData.OffsetX, JUMP.savedData.OffsetY)
    end
end

function JUMP.SceneStateChanged(scene, oldState, newState)
    local sceneName = scene:GetName()
    if sceneName == "hudui" and (newState == "showing" or newState == "shown") then
        JUMP.inMenu = false
    elseif sceneName == "hud" and (newState == "showing" or newState == "shown") then
        JUMP.inMenu = false
    elseif (newState == "showing" or newState == "shown") then
        JUMP.inMenu = true
    end
    JUMP:UpdateUI()
end

function JUMP.Help(options)
    CHAT_ROUTER:AddSystemMessage("Jump counts jumps for you and groups")
    CHAT_ROUTER:AddSystemMessage("")
    CHAT_ROUTER:AddSystemMessage("/jump - shows this help screen")
    CHAT_ROUTER:AddSystemMessage("/jumpreset - reset group Jumps")
    CHAT_ROUTER:AddSystemMessage("/jumpstats - display stats")
    CHAT_ROUTER:AddSystemMessage("/jumpshare or /js - write stats to chat")
    CHAT_ROUTER:AddSystemMessage("/jumptoggle - show/hide ui")
end

function JUMP.Reset(options)
    CHAT_ROUTER:AddSystemMessage("Group jump count has been reset")
    for tag in pairs(JUMP.group) do
        JUMP.group[tag].jumps = 0
    end
end

function JUMP.Stats(options)
    CHAT_ROUTER:AddSystemMessage(string.format("Lifetime jumps: %d", JUMP.player.overallJumpCount))
    for tag in pairs(JUMP.group) do
        CHAT_ROUTER:AddSystemMessage(string.format("%s: %d", JUMP.group[tag].name, JUMP.group[tag].jumps))
    end
end

function JUMP.ShareGroup(options)
    local shareString = "Most jumps -"
    for tag in pairs(JUMP.group) do
        shareString = string.format("%s %s:%d", shareString, JUMP.group[tag].accname, JUMP.group[tag].jumps)
    end
    if IsUnitGrouped("player") then
        StartChatInput(shareString, CHAT_CHANNEL_PARTY)
    else
        StartChatInput(shareString)
    end
end

function JUMP.ShareOverall(options)
    if IsUnitGrouped("player") then
        StartChatInput(string.format("Lifetime jumps: %d", JUMP.player.overallJumpCount), CHAT_CHANNEL_PARTY)
    else
        StartChatInput(string.format("Lifetime jumps: %d", JUMP.player.overallJumpCount))
    end
end

function JUMP.ToggleUI(options)
    JUMPUI:SetHidden(not JUMP.savedData.hidden)
    JUMP.savedData.hidden = not JUMP.savedData.hidden
    if JUMP.savedData.hidden then
        CHAT_ROUTER:AddSystemMessage("Jump UI hidden")
    else
        CHAT_ROUTER:AddSystemMessage("Jump UI shown")
    end
    JUMP:UpdateUI()
end

function JUMP.ToggleDebug(options)
    JUMP.savedData.debug = not JUMP.savedData.debug
    if JUMP.savedData.debug then
        CHAT_ROUTER:AddSystemMessage("Jump debug on")
    else
        CHAT_ROUTER:AddSystemMessage("Jump debug off")
    end
end

function JUMP_SaveUIPosition()
    local isValidAnchor, point, relativeTo, relativePoint, offsetX, offsetY = JUMPUI:GetAnchor()
    JUMP.savedData.OffsetX = offsetX
    JUMP.savedData.OffsetY = offsetY
    JUMP.savedData.point = point
    JUMP.savedData.relativePoint = relativePoint
end

SLASH_COMMANDS["/jump"] = JUMP.Help
SLASH_COMMANDS["/jumpreset"] = JUMP.Reset
SLASH_COMMANDS["/jumpstats"] = JUMP.Stats
SLASH_COMMANDS["/jumpshare"] = JUMP.ShareGroup
SLASH_COMMANDS["/js"] = JUMP.ShareGroup
SLASH_COMMANDS["/jumptoggle"] = JUMP.ToggleUI
SLASH_COMMANDS["/jumptoggledebug"] = JUMP.ToggleDebug

EVENT_MANAGER:RegisterForEvent(JUMP.name, EVENT_ADD_ON_LOADED, JUMP.OnAddOnLoaded)