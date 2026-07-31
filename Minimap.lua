--------------------------------------------------------------------------------
-- nugsSuite
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsSuite  -  Minimap.lua
-- The one button the suite exists to leave behind. Same self-contained button as
-- the other nugs addons - no external libraries, draggable around the minimap
-- edge, angle saved between sessions.
--
-- Left click opens the hub. Right click skips it entirely and drops a menu of
-- whatever is installed, because opening a launcher to press one more button is a
-- worse deal than the four minimap icons this replaces.
--------------------------------------------------------------------------------
local ADDON_NAME, NSU = ...

-- Place the button on the minimap edge, adapting to the minimap's CURRENT size and
-- shape, so it works with resized/reshaped minimaps and not just the default.
local function PositionButton(btn, angle)
    local a = math.rad(angle)
    local cos, sin = math.cos(a), math.sin(a)
    local w = (Minimap:GetWidth()  / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    local shape = (type(GetMinimapShape) == "function") and GetMinimapShape() or "ROUND"
    local x, y
    if shape == "ROUND" then
        x, y = cos * w, sin * h
    else
        -- square / mixed-shape minimaps: clamp the point to the minimap box
        local diag = 1.41421356
        x = math.max(-w, math.min(cos * w * diag, w))
        y = math.max(-h, math.min(sin * h * diag, h))
    end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging, follow the cursor around the minimap edge.
local function OnDragUpdate(btn)
    local mx, my = Minimap:GetCenter()
    if not mx then return end
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    local angle = math.deg(math.atan2(py - my, px - mx))
    NSU.db.minimapAngle = angle
    PositionButton(btn, angle)
end

-- The right click menu. MenuUtil is the current API; if a future client renames it
-- the button quietly falls back to opening the hub rather than erroring under the
-- player's cursor.
local function ShowMenu(btn)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        NSU.ToggleHub()
        return
    end
    MenuUtil.CreateContextMenu(btn, function(_, root)
        root:CreateTitle("nugs")
        local any = false
        for _, row in ipairs(NSU.Scan()) do
            if row.installed and row.loaded then
                any = true
                root:CreateButton(row.title, function() NSU.OpenAddon(row.folder) end)
            end
        end
        if not any then
            root:CreateButton("No nugs addons loaded", function() end)
        end
        root:CreateDivider()
        root:CreateButton("Suite hub", function() NSU.ToggleHub() end)
        root:CreateButton("Profiles", function() NSU.ToggleHub("profiles") end)
    end)
end

function NSU.InitMinimap()
    if NSU.minimapButton or not NSU.db then return end
    NSU.db.minimapAngle = NSU.db.minimapAngle or 200

    local btn = CreateFrame("Button", "nugsSuiteMinimapButton", Minimap)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetSize(31, 31)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    -- A dark disc behind the icon. The tracking border's hole is slightly wider
    -- than the icon, and without this the gap between the two is see-through - the
    -- world scrolls past in a thin ring around the button. Deliberately sized past
    -- the hole, because the border art draws over the excess.
    local backing = btn:CreateTexture(nil, "BACKGROUND")
    backing:SetSize(23, 23)
    backing:SetPoint("CENTER", 0, 1)
    backing:SetTexture("Interface\\Buttons\\WHITE8X8")
    backing:SetVertexColor(0.05, 0.06, 0.08, 1)
    backing:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\AddOns\\nugsSuite\\icon")
    -- Circular alpha mask so the square art cannot poke past the round border.
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    btn:SetScript("OnDragStop",  function(self) self:SetScript("OnUpdate", nil) end)

    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ShowMenu(self)
        else
            NSU.ToggleHub()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("nugsSuite")
        GameTooltip:AddLine("Left click to open the hub", 1, 1, 1)
        GameTooltip:AddLine("Right click for a menu of your addons", 1, 1, 1)
        GameTooltip:AddLine("Drag to move this button", 0.6, 0.6, 0.6)
        local installed, available = NSU.CountInstalled()
        GameTooltip:AddLine(installed .. " of " .. available .. " nugs addons installed", 0.55, 0.78, 1.0)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    NSU.minimapButton = btn
    PositionButton(btn, NSU.db.minimapAngle)
    NSU.SetMinimapShown(not NSU.db.minimapHidden)
end

function NSU.SetMinimapShown(shown)
    if not NSU.minimapButton then return end
    NSU.minimapButton:SetShown(shown and true or false)
end
