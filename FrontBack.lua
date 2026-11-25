FrontBackData = { name = "FrontBack", version = "1.1.0" }

local Defaults = {
    Enabled = true,
    ShowText = false,
    HudX = 0,
    HudY = -170,
}

local Config
local HUD
local UpdateHUD
local PLAYER_BEHIND_CONFIRM_SECS = 0.12
local PlayerBehindState = { name = nil, since = nil }

local function Print(message, r, g, b)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff55ccffFrontBack:|r " .. message, r or 1, g or 1, b or 1)
    end
end

local function UnitXPBehind()
    if type(UnitXP) ~= "function" then
        return nil
    end
    local ok, behind = pcall(UnitXP, "behind", "player", "target")
    if ok and (behind == true or behind == false) then
        return behind
    end
    return nil
end

local function MeleeDistance()
    if type(UnitXP) == "function" then
        local ok, distance = pcall(UnitXP, "distanceBetween", "player", "target", "meleeAutoAttack")
        if ok and type(distance) == "number" then
            return distance
        end
    end
    return nil
end

local function TargetInMeleeRange()
    local distance = MeleeDistance()
    if distance then
        return distance <= 0.01
    end
    return CheckInteractDistance and CheckInteractDistance("target", 3)
end

local function PositionSnapshot()
    if type(UnitPosition) ~= "function" or type(UnitFacing) ~= "function" then
        return nil
    end
    local playerOK, px, py = pcall(UnitPosition, "player")
    local targetOK, tx, ty = pcall(UnitPosition, "target")
    local facingOK, facing = pcall(UnitFacing, "target")
    if not playerOK or not targetOK or not facingOK
        or type(px) ~= "number" or type(py) ~= "number"
        or type(tx) ~= "number" or type(ty) ~= "number"
        or type(facing) ~= "number" then
        return nil
    end
    return px, py, tx, ty, facing
end

local function SuperWoWBehindTarget()
    local px, py, tx, ty, facing = PositionSnapshot()
    if not px then
        return nil
    end
    local dx, dy = px - tx, py - ty
    if dx == 0 and dy == 0 then
        return nil
    end
    return dx * math.cos(facing) + dy * math.sin(facing) < 0
end

local function StablePlayerBehindTarget(name)
    local behind = SuperWoWBehindTarget()
    if behind == nil then
        PlayerBehindState.name = nil
        PlayerBehindState.since = nil
        return nil
    elseif not behind then
        PlayerBehindState.name = nil
        PlayerBehindState.since = nil
        return false
    end
    if PlayerBehindState.name ~= name or not PlayerBehindState.since then
        PlayerBehindState.name = name
        PlayerBehindState.since = GetTime()
        return false
    end
    return GetTime() - PlayerBehindState.since >= PLAYER_BEHIND_CONFIRM_SECS
end

local function BehindTarget(name)
    local behind
    if UnitIsPlayer("target") then
        behind = StablePlayerBehindTarget(name)
    else
        behind = UnitXPBehind()
    end
    if behind == nil then
        behind = SuperWoWBehindTarget()
    end
    return behind
end

local function DirectionDelta()
    local px, py, tx, ty, facing = PositionSnapshot()
    if not px then
        return nil
    end
    local dx, dy = px - tx, py - ty
    if dx == 0 and dy == 0 then
        return nil
    end
    local toPlayer = math.atan2(dy, dx)
    local desired = facing + math.pi
    local delta = toPlayer - desired
    while delta > math.pi do
        delta = delta - math.pi * 2
    end
    while delta < -math.pi do
        delta = delta + math.pi * 2
    end
    return delta
end

local function DirectionSide(delta)
    if delta == nil then
        delta = DirectionDelta()
    end
    if delta == nil then
        return nil
    end
    local pointsRight = delta > 0
    if UnitIsPlayer("target") then
        pointsRight = not pointsRight
    end
    return pointsRight and "right" or "left"
end

local function DirectionHint()
    local delta = DirectionDelta()
    if delta == nil then
        return ""
    end
    local degrees = math.floor(math.abs(delta) * 180 / math.pi + 0.5)
    if degrees < 5 then
        return ""
    end
    if DirectionSide(delta) == "right" then
        return degrees .. "deg >"
    end
    return "< " .. degrees .. "deg"
end

FrontBackAPI = {}

function FrontBackAPI:GetPosition()
    if not UnitExists("target") then
        return nil, false, ""
    end
    local behind = BehindTarget(UnitName("target") or "target")
    return behind, behind == true or behind == false, DirectionHint()
end

function FrontBackAPI:IsEnabled()
    return Config and Config.Enabled == true
end

function FrontBackAPI:SetEnabled(enabled)
    if not Config then
        return false
    end
    Config.Enabled = (enabled == true)
    UpdateHUD()
    return true
end

local function ValidTarget()
    return UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDeadOrGhost("target")
        and TargetInMeleeRange()
end

UpdateHUD = function()
    if not Config or not HUD or not Config.Enabled then
        if HUD then
            HUD:Hide()
        end
        return
    end

    HUD:Show()
    if not ValidTarget() then
        HUD:SetAlpha(0)
        HUD:EnableMouse(false)
        return
    end
    HUD:SetAlpha(1)

    local targetName = UnitName("target") or "target"
    local behind = BehindTarget(targetName)
    if behind ~= true and behind ~= false then
        HUD:SetAlpha(0)
        HUD:EnableMouse(false)
        return
    end

    HUD:EnableMouse(true)
    HUD.arrow:SetTexture(behind
        and "Interface\\AddOns\\FrontBack\\ArrowDown"
        or "Interface\\AddOns\\FrontBack\\ArrowUp")
    if behind == true then
        HUD.arrow:SetVertexColor(0.25, 1, 0.36, 1)
        HUD.status:SetText("BACK")
        HUD.status:SetTextColor(0.25, 1, 0.36)
    else
        HUD.arrow:SetVertexColor(1, 0.22, 0.18, 1)
        HUD.status:SetText("FRONT")
        HUD.status:SetTextColor(1, 0.22, 0.18)
    end
    if Config.ShowText then
        HUD.status:Show()
    else
        HUD.status:Hide()
    end
end

local function SaveHUDPosition()
    if not Config or not HUD then
        return
    end
    local x, y = HUD:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    Config.HudX = math.floor(x - parentX + 0.5)
    Config.HudY = math.floor(y - parentY + 0.5)
end

local function RestoreHUDPosition()
    HUD:ClearAllPoints()
    HUD:SetPoint("CENTER", UIParent, "CENTER", Config.HudX, Config.HudY)
end

local function CreateHUD()
    if HUD then
        return
    end
    HUD = CreateFrame("Frame", "FrontBackHUD", UIParent)
    HUD:SetWidth(64)
    HUD:SetHeight(82)
    HUD:SetFrameStrata("HIGH")
    HUD:EnableMouse(true)
    HUD:SetMovable(true)
    HUD:RegisterForDrag("LeftButton")
    HUD:SetScript("OnDragStart", function() this:StartMoving() end)
    HUD:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        SaveHUDPosition()
    end)
    if HUD.SetClampedToScreen then
        HUD:SetClampedToScreen(true)
    end
    HUD.arrow = HUD:CreateTexture(nil, "ARTWORK")
    HUD.arrow:SetWidth(64)
    HUD.arrow:SetHeight(64)
    HUD.arrow:SetPoint("TOP", HUD, "TOP", 0, 0)
    HUD.status = HUD:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    HUD.status:SetPoint("TOP", HUD.arrow, "BOTTOM", 0, -2)
    HUD.status:Hide()
    HUD.elapsed = 0
    HUD:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        if this.elapsed >= 0.1 then
            this.elapsed = 0
            UpdateHUD()
        end
    end)
    RestoreHUDPosition()
    HUD:Hide()
end

local function OnOff(enabled)
    return enabled and "|cff80ff80on|r" or "|cffff8080off|r"
end

local function PrintHelp()
    Print(FrontBackData.name .. " " .. FrontBackData.version)
    Print("  /frontback - toggle the positioning HUD")
    Print("  /frontback on|off - explicitly enable or disable it")
    Print("  /frontback text - toggle FRONT/BACK text below the arrow")
    Print("  /frontback reset - restore the default HUD position and enable it")
    Print("  /frontback status - show the current state")
end

function FrontBack_Command(message)
    local _, _, command = string.find(string.lower(message or ""), "^%s*(%w*)")
    if command == "help" or command == "status" then
        if command == "help" then
            PrintHelp()
        else
            Print("HUD is " .. OnOff(Config.Enabled))
        end
    elseif command == "on" or command == "enable" or command == "show" then
        Config.Enabled = true
        UpdateHUD()
        Print("HUD is " .. OnOff(Config.Enabled))
    elseif command == "off" or command == "disable" or command == "hide" then
        Config.Enabled = false
        UpdateHUD()
        Print("HUD is " .. OnOff(Config.Enabled))
    elseif command == "text" or command == "label" or command == "labels" then
        Config.ShowText = not Config.ShowText
        UpdateHUD()
        Print("status text is " .. OnOff(Config.ShowText))
    elseif command == "reset" then
        Config.Enabled = true
        Config.HudX = Defaults.HudX
        Config.HudY = Defaults.HudY
        RestoreHUDPosition()
        UpdateHUD()
        Print("HUD position reset")
    elseif command == "" then
        Config.Enabled = not Config.Enabled
        UpdateHUD()
        Print("HUD is " .. OnOff(Config.Enabled))
    else
        Print("unknown command; use /frontback help")
    end
end

local function Initialise()
    if type(FrontBackVariables) ~= "table" then
        FrontBackVariables = {}
    end
    Config = FrontBackVariables
    if Config.Enabled == nil then
        Config.Enabled = Defaults.Enabled
    end
    Config.Enabled = (Config.Enabled == true)
    Config.ShowText = (Config.ShowText == true)
    for _, key in ipairs({ "HudX", "HudY" }) do
        local value = tonumber(Config[key])
        if not value or value ~= value then
            value = Defaults[key]
        end
        Config[key] = math.max(-2000, math.min(2000, math.floor(value)))
    end
    SlashCmdList["FRONTBACK"] = FrontBack_Command
    SLASH_FRONTBACK1 = "/frontback"
    SLASH_FRONTBACK2 = "/fb"
    CreateHUD()
    UpdateHUD()
    Print("loaded. Drag the indicator to move it; /frontback toggles it.")
end

local EventFrame = CreateFrame("Frame", "FrontBackEventFrame")
EventFrame:RegisterEvent("VARIABLES_LOADED")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
EventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        Initialise()
    elseif Config and event == "PLAYER_TARGET_CHANGED" then
        PlayerBehindState.name = nil
        PlayerBehindState.since = nil
        UpdateHUD()
    elseif Config then
        UpdateHUD()
    end
end)
