JUMP = {}

JUMP.name = "Jump"
JUMP.savedData = {}
JUMP.player = {}
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
JUMP.savedData.hideBackground = true
JUMP.inMenu = false
JUMP.elevationBuffer = math.floor(700 / JUMP.delay)
JUMP.minLookBack = math.floor((500 - JUMP.delay) / JUMP.delay)
JUMP.maxLookBack = math.floor(500 / JUMP.delay)

-- A regular jump is an increase of 160 in 500ms.
-- but this could vary a lot since we only poll at certain intervals, may need to poll more often to be more accurate
JUMP.jumpBuffer = math.floor(JUMP.delay / 4)

-- Functions that trigger a jump
function JUMP.RegularJump(obj)
    if obj.timeSinceLastJump < 1000 then
        return false
    end
    local peakElevation = 0
    local lowestElevation = 0
    for key, val in ipairs(obj.elevations) do
        -- We are going backwards in time here, we want the current value to be higher than the next value since we want to find a peak in our jump and then check if the next n values seem to indicate a jump
        if obj.elevations[key + 1] and val > obj.elevations[key + 1] and val > peakElevation then
            peakElevation = val
        end
        -- After we found our jump peak we keep looping to find the beginning of our jump which is any value lower than our peak that came before we reached our peak, the loop is backwards in time
        if peakElevation > 0 and (lowestElevation == 0 or val + JUMP.jumpBuffer < lowestElevation) then
            lowestElevation = val
        end
    end
    if lowestElevation == 0 or peakElevation == 0 then
        return false
    end
    -- We expect a jump to be around 160
    if peakElevation - lowestElevation > 165 then
        if JUMP.savedData.debug then
            CHAT_ROUTER:AddSystemMessage(string.format("Invalid jump, too high: %d", peakElevation - lowestElevation))
        end
        return false
    end
    if peakElevation - lowestElevation < 145 then
        if JUMP.savedData.debug and peakElevation - lowestElevation > 10 then
            CHAT_ROUTER:AddSystemMessage(string.format("Invalid jump, too low: %d", peakElevation - lowestElevation))
        end
        return false
    end
    local lastVal = 0
    local lastValKey = 0
    for key, val in ipairs(obj.elevations) do
        -- this is the middle of the jump going backwards
        if peakElevation == val and key > 1 then
            lastVal = val
            lastValKey = key
        end
        if lastVal ~= 0 then
            -- we found the jump going backwards with 4 to 5 consecutive increments at 100ms, a jump should only take about 500ms but we do have lag here
            if key - lastValKey >= JUMP.minLookBack and key - lastValKey <= JUMP.maxLookBack then
                if JUMP.savedData.debug then
                    local debugElevationString = ""
                    for key2, val2 in ipairs(obj.elevations) do
                        debugElevationString = string.format("%d:%d %s", key2, val2, debugElevationString)
                    end
                    CHAT_ROUTER:AddSystemMessage(string.format("Elevations: %s", debugElevationString))
                end
                return true
            end
            if lastVal < val then
                return false
            end
        end
    end

    return false
end

JUMP.JumpIndicators = {
    regularJump = JUMP.RegularJump
}

function JUMP:RegisterMenu()
    if LibAddonMenu2 then
        local LAM = LibAddonMenu2
        local panelName = "JUMPSettingsPanel"
        local panelData = {
            type = "panel",
            name = "Jump",
            author = "@uberswe",
        }
        local panel = LAM:RegisterAddonPanel(panelName, panelData)
        local optionsData = {
            {
                type = "description",
                title = nil, --(optional)
                text = "The Jump addon estimates jumps based on players x,y,z coordinates, it's not perfect but I have worked hard to make it as accurate as possible. Please report any issues you find on ESOUI or send me a mail on PC EU to @uberswe. Enjoy the addon? Feel free to send some gold instead :)",
                width = "full", --or "half" (optional)
            },
            {
                type = "checkbox",
                name = "Show background",
                getFunc = function()
                    return not JUMP.savedData.hideBackground
                end,
                setFunc = function(value)
                    JUMP.savedData.hideBackground = not value
                end
            },
            {
                type = "checkbox",
                name = "Hide UI",
                getFunc = function()
                    return JUMP.savedData.hidden
                end,
                setFunc = function(value)
                    JUMP.savedData.hidden = value
                end
            },
            {
                type = "checkbox",
                name = "Debug Mode",
                getFunc = function()
                    return JUMP.savedData.debug
                end,
                setFunc = function(value)
                    JUMP.savedData.debug = value
                end
            }
        }

        LAM:RegisterOptionControls(panelName, optionsData)
    end
end

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

    if JUMP.savedData.debug then

        zo_callLater(function()
            CHAT_ROUTER:AddSystemMessage(string.format("jumpBuffer: %d", JUMP.jumpBuffer))
            CHAT_ROUTER:AddSystemMessage(string.format("elevationBuffer: %d", JUMP.elevationBuffer))
            CHAT_ROUTER:AddSystemMessage(string.format("polling every %dms", JUMP.delay))
            CHAT_ROUTER:AddSystemMessage(string.format("minLookBack: %d", JUMP.minLookBack))
            CHAT_ROUTER:AddSystemMessage(string.format("maxLookBack: %d", JUMP.maxLookBack))
        end, 1000)
    end

    JUMPUI:SetHidden(JUMP.savedData.hidden)
    JUMP.OnGroupChange()
    JUMP:UpdateUI()
    JUMP:RegisterMenu()
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
            if not aa or not bb or not aa.jumps or not bb.jumps then
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
                        if row then
                            if not lastRow then
                                row:SetAnchor(BOTTOMLEFT, JUMP_OVERALL_LABEL, BOTTOMLEFT, 0, 50)
                            else
                                row:SetAnchor(BOTTOMLEFT, lastRow, BOTTOMLEFT, 0, 50)
                            end
                            if data.accname and data.jumps then
                                row:SetText(string.format("%s: %s", data.accname, data.jumps))
                            end
                            row:SetHidden(false)
                            JUMP.rows[index] = row
                            lastRow = row
                            count = count + 1
                            if JUMP.savedData.debug then
                                CHAT_ROUTER:AddSystemMessage(string.format("Added row: %s", tostring(index)))
                            end
                        end
                    end
                end
            else
                -- No need to make new controls, just set the text of the row here
                for index, data in ipairs(JUMP.group) do
                    if data.unitTag then
                        if JUMP.rows and JUMP.rows[index] and data.accname and data.jumps then
                            JUMP.rows[index]:SetText(string.format("%s: %s", data.accname, data.jumps))
                            JUMP.rows[index]:SetHidden(false)
                        else
                            if JUMP.savedData.debug and data.unitTag then
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
    JUMPUI:SetHidden(JUMP.inMenu or JUMP.savedData.hidden)
    JUMP_CONTAINER:SetHidden(JUMP.savedData.hideBackground)
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
            newElevations[key + 1] = val
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

    obj.elevations = JUMP:SaveLastElevations(obj.elevations, JUMP:GetCurrentElevation(obj.unitTag), JUMP.elevationBuffer)

    for key, func in pairs(JUMP.JumpIndicators) do
        if func(obj) then
            obj.jumps = obj.jumps + 1
            if GetUnitDisplayName(obj.unitTag) == GetUnitDisplayName("player") then
                JUMP.player.overallJumpCount = JUMP.player.overallJumpCount + 1
            end
            obj.elevations = {}
            obj.timeSinceLastJump = 0
            updated = true
            if JUMP.savedData.debug then
                CHAT_ROUTER:AddSystemMessage(string.format("Jump: %s", key))
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