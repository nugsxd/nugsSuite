--------------------------------------------------------------------------------
-- nugsSuite
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsSuite  -  Options.lua
-- The hub window: a roster of every nugs addon on one tab, profile export and
-- import on another.
--
-- Same flat dark skin and the same 30px header as RaidReady, nugsCastBars,
-- nugsComboBar and nugsCooldownPulse, for the obvious reason - a launcher that did
-- not look like the things it launches would be the one window in the set that
-- felt bolted on.
--
-- Addons that are not installed stay in the list, greyed. The roster is the point:
-- somebody who was handed one of these should be able to see the rest without
-- being told they exist.
--
-- Widgets are hand-rolled rather than built on Blizzard templates, which get
-- renamed between expansions.
--------------------------------------------------------------------------------
local ADDON_NAME, NSU = ...

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------
local C = {
    bg     = { 0.07, 0.07, 0.07, 0.96 },
    header = { 0.10, 0.10, 0.10, 1.00 },
    panel  = { 0.10, 0.10, 0.10, 0.90 },
    input  = { 0.14, 0.14, 0.14, 1.00 },
    btn    = { 0.16, 0.16, 0.16, 1.00 },
    btnHi  = { 0.24, 0.24, 0.24, 1.00 },
    accent = { 0.35, 0.72, 1.00, 1.00 },
    rowB   = { 1, 1, 1, 0.055 },
    text   = { 0.82, 0.82, 0.82 },
    faint  = { 0.50, 0.50, 0.50 },
    gold   = { 1.00, 0.84, 0.42 },
}

local ADDON_ICON = "Interface\\AddOns\\nugsSuite\\icon"

local WIDTH, HEIGHT = 640, 566
local CONTENT_W = WIDTH - 24
local CARD_H    = 74

local window, tabStrip, panels, exportBox, importBox, importStatus, applyButton, undoButton
local cardPool, exportChecks = {}, {}

-- Addons switched off from the roster this session. C_AddOns keeps reporting them as
-- loaded until the reload - which is true, they are still running - so without
-- remembering the click the card would look completely unchanged and Disable would
-- read as a dead button. Session-only on purpose: after a reload the addon really is
-- off and IsAddOnLoaded says so on its own.
local pendingDisable = {}
-- Where the hub returns to once the About page has been seen once.
local currentTab = "addons"
local pendingImport = nil          -- the last string that passed Inspect

--------------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------------
local function Backdrop(frame, color, borderAlpha)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(color))
    frame.bgTex = bg
    if borderAlpha then
        for _, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetHeight(1)
            t:SetColorTexture(0, 0, 0, borderAlpha)
        end
        for _, p in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetPoint(p[1]); t:SetPoint(p[2]); t:SetWidth(1)
            t:SetColorTexture(0, 0, 0, borderAlpha)
        end
    end
    return bg
end

local function Panel(parent, color)
    local f = CreateFrame("Frame", nil, parent)
    Backdrop(f, color or C.panel, 1)
    return f
end

local function Label(parent, text, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(color or C.text))
    return fs
end

local function SectionHeader(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(C.accent))
    return fs
end

local function Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    Backdrop(b, C.btn, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b.text:SetTextColor(unpack(C.text))
    b:SetScript("OnEnter", function(self)
        if self:IsEnabled() then self.bgTex:SetColorTexture(unpack(C.btnHi)) end
    end)
    b:SetScript("OnLeave", function(self) self.bgTex:SetColorTexture(unpack(C.btn)) end)
    b:SetScript("OnClick", onClick)
    b.SetLabel = function(self, t) self.text:SetText(t) end
    -- Disabled buttons keep their frame but drop to the faint text colour, so the
    -- window never grows or shrinks as things become available.
    b.SetGrey = function(self, grey)
        self.text:SetTextColor(unpack(grey and C.faint or C.text))
        if grey then self:Disable() else self:Enable() end
    end
    return b
end

-- Deliberately built to match RaidReady's header so the suite reads as one thing:
-- a 30px bar with a storm-blue underline, the addon icon on the left, a gold title
-- with a blue tail, and a small flat close button.
local function HeaderBar(f, titleText, tailText)
    local header = CreateFrame("Frame", nil, f)
    Backdrop(header, C.header, 1)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(30)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local accent = header:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", 0, 0)
    accent:SetHeight(3)
    accent:SetColorTexture(unpack(C.accent))

    local icon = header:CreateTexture(nil, "OVERLAY")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture(ADDON_ICON)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(titleText .. (tailText and (" |cff8cd2ff" .. tailText .. "|r") or ""))
    title:SetTextColor(unpack(C.gold))
    header.titleText = title

    local close = Button(header, "x", 22, 18, function() f:Hide() end)
    close:SetPoint("RIGHT", -6, 0)

    return header
end

-- Checkbox: a small square that fills with the accent colour when on.
local function Check(parent, text, getter, setter, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)

    local box = CreateFrame("Frame", nil, b)
    box:SetSize(14, 14)
    box:SetPoint("LEFT", 0, 0)
    Backdrop(box, C.input, 1)

    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(unpack(C.accent))

    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
    fs:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetTextColor(unpack(C.text))

    b:SetScript("OnClick", function()
        setter(not getter())
        if NSU.RefreshHub then NSU.RefreshHub() end
    end)
    b:SetScript("OnEnter", function(self)
        fs:SetTextColor(1, 1, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        fs:SetTextColor(unpack(C.text))
        GameTooltip:Hide()
    end)

    b.Refresh = function(self) fill:SetShown(getter() and true or false) end
    b.SetLabel = function(self, t) fs:SetText(t) end
    b.SetGrey = function(self, grey)
        fs:SetTextColor(unpack(grey and C.faint or C.text))
        self:SetEnabled(not grey)
    end
    b:Refresh()
    return b
end

-- A scrolling multi-line text box. Used for both halves of the profile tab: one to
-- hand a string out, one to take one in.
local function TextArea(parent, w, h, readOnlyish)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(w, h)
    Backdrop(holder, C.input, 1)

    local scroll = CreateFrame("ScrollFrame", nil, holder)
    scroll:SetPoint("TOPLEFT", 5, -5)
    scroll:SetPoint("BOTTOMRIGHT", -5, 5)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetTextColor(unpack(C.text))
    edit:SetWidth(w - 14)
    edit:SetHeight(h - 10)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- A profile string is far taller than this box once it wraps, so the scroll
    -- child has to be resized to what the text actually needs - a fixed tall child
    -- either cuts off a long string or scrolls into empty space on a short one.
    -- EditBox exposes no height-of-its-text call, so an offscreen FontString with
    -- the same font and width does the measuring.
    local measure = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    measure:SetWidth(w - 14)
    measure:Hide()

    local function Resize(text)
        measure:SetText(text or "")
        edit:SetHeight(math.max(h - 10, (measure:GetStringHeight() or 0) + 10))
    end

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local viewH = self:GetHeight() or 1
        local maxScroll = math.max(0, (edit:GetHeight() or 1) - viewH)
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 24)))
    end)
    -- Keep the caret in view while typing or arrowing through a pasted string.
    edit:SetScript("OnCursorChanged", function(_, _, cy, _, ch)
        local viewH = scroll:GetHeight() or 1
        local top, bottom = -cy, -cy + ch
        local offset = scroll:GetVerticalScroll()
        if top < offset then scroll:SetVerticalScroll(top)
        elseif bottom > offset + viewH then scroll:SetVerticalScroll(bottom - viewH) end
    end)

    if readOnlyish then
        -- Not truly read only - the player has to be able to select the text in
        -- order to copy it - but any edit is put straight back. OnTextChanged
        -- rather than OnChar, because backspace, delete and cut never raise a
        -- character event and would otherwise hand out a truncated string.
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput and self:GetText() ~= (self.lockedText or "") then
                self:SetText(self.lockedText or "")
                self:HighlightText()
            end
        end)
        edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    else
        -- The pasted-into box grows as the player pastes.
        edit:SetScript("OnTextChanged", function(self) Resize(self:GetText()) end)
    end
    scroll:SetScrollChild(edit)

    holder.edit = edit
    holder.SetContent = function(self, text)
        edit.lockedText = text
        edit:SetText(text or "")
        edit:SetCursorPosition(0)
        scroll:SetVerticalScroll(0)
        Resize(text)
    end
    holder.GetContent = function(self) return edit:GetText() end
    return holder
end

--------------------------------------------------------------------------------
-- Confirmation popups
--------------------------------------------------------------------------------
-- Importing overwrites settings and enabling an addon needs a reload, so both go
-- through a popup rather than happening under the player's hands.
StaticPopupDialogs["NUGSSUITE_IMPORT"] = {
    text = "Import these nugs settings?\n\n|cffff9f40Your settings for the addons listed are REPLACED with the ones in this profile - anything you changed yourself goes back to default unless the profile sets it. Your interface then reloads.|r\n\nA copy of your current settings is saved first, and the Undo button on the profile tab puts them back.",
    button1 = "Import and reload",
    button2 = CANCEL,
    OnAccept = function()
        if not pendingImport then return end
        NSU.Profiles.TakeBackup()
        local folders = {}
        for _, row in ipairs(pendingImport.rows) do
            if row.installed then folders[row.folder] = true end
        end
        -- includeChar is always true here, not NSU.db.includeChar: that checkbox
        -- governs what YOU put into a string you hand out. What arrives in somebody
        -- else's string was already their choice, and the preview listed it.
        --
        -- preserveExcluded is true because this is somebody else's profile: it must
        -- not be allowed to clear this player's measured caches or minimap angle.
        local n = NSU.Profiles.Apply(pendingImport.payload, folders, true, true)
        NSU.Print("imported settings for " .. n .. " addon" .. (n == 1 and "" or "s") .. ". Reloading.")
        ReloadUI()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["NUGSSUITE_UNDO"] = {
    text = "Put back the settings you had before your last import?\n\nYour interface will reload.",
    button1 = "Restore and reload",
    button2 = CANCEL,
    OnAccept = function()
        local info, err = NSU.Profiles.Inspect(NSU.db.backup)
        if not info then
            NSU.Print("the saved backup could not be read: " .. tostring(err))
            return
        end
        local folders = {}
        for _, row in ipairs(info.rows) do
            if row.installed then folders[row.folder] = true end
        end
        -- preserveExcluded = false: the backup is a full snapshot taken from this
        -- player's own settings, so it already holds the true value of every key,
        -- including the ones a shared profile would never carry. Holding any of
        -- them back would leave the post-import value standing.
        NSU.Profiles.Apply(info.payload, folders, true, false)
        NSU.db.backup = false
        ReloadUI()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["NUGSSUITE_RELOAD"] = {
    text = "%s\n\nReload your interface now?",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

--------------------------------------------------------------------------------
-- Addons tab
--------------------------------------------------------------------------------
-- One card per catalog entry, built once and refreshed in place. Cards are not
-- rebuilt on refresh because the version and enabled state are the only things
-- that ever change, and rebuilding would drop the tooltip out from under the mouse.
local function BuildCard(parent, index)
    local card = Panel(parent, C.panel)
    -- Anchored to both edges of the list rather than given a fixed width, so the
    -- card cannot end up wider than the column it sits in.
    card:SetHeight(CARD_H - 6)
    card:SetPoint("TOPLEFT", 0, -((index - 1) * CARD_H))
    card:SetPoint("TOPRIGHT", 0, -((index - 1) * CARD_H))

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("LEFT", 10, 0)
    card.icon = icon

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)
    title:SetJustifyH("LEFT")
    card.title = title

    local notes = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notes:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    notes:SetJustifyH("LEFT")
    notes:SetTextColor(unpack(C.text))
    card.notes = notes

    local slash = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slash:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -3)
    slash:SetJustifyH("LEFT")
    slash:SetTextColor(unpack(C.faint))
    card.slash = slash

    local action = Button(card, "Open", 74, 22, nil)
    action:SetPoint("RIGHT", -12, 0)
    card.action = action

    -- Sits left of Open, and only appears for an addon that is actually running.
    local toggle = Button(card, "Disable", 74, 22, nil)
    toggle:SetPoint("RIGHT", action, "LEFT", -6, 0)
    card.toggle = toggle

    -- Bound against a fixed inset that leaves room for BOTH buttons rather than
    -- against whichever happens to be showing. Rebinding per refresh would make the
    -- text jump around as cards change state, and every row lining up in the same
    -- place reads as tidier than each one using every pixel it could.
    local TEXT_INSET = -(12 + 74 + 6 + 74 + 10)
    title:SetPoint("RIGHT", card, "RIGHT", TEXT_INSET, 0)
    notes:SetPoint("RIGHT", card, "RIGHT", TEXT_INSET, 0)
    slash:SetPoint("RIGHT", card, "RIGHT", TEXT_INSET, 0)

    card:EnableMouse(true)
    return card
end

local function RefreshCards()
    local rows = NSU.Scan()
    for i, row in ipairs(rows) do
        local card = cardPool[i]
        if not card then
            card = BuildCard(panels.addons.list, i)
            cardPool[i] = card
        end
        card:Show()

        card.icon:SetTexture(row.icon)
        card.notes:SetText(row.notes)
        card.slash:SetText(row.slash)

        local tail
        if row.comingSoon then
            tail = "|cffd8a13fcoming soon|r"
        elseif not row.installed then
            tail = "|cff777777not installed|r"
        elseif not row.loaded then
            tail = "|cffff6060disabled|r"
        elseif pendingDisable[row.folder] then
            -- Switched off but still running until the reload. Saying so is the whole
            -- point: without it, pressing Disable appears to do nothing at all,
            -- because IsAddOnLoaded stays true for the rest of the session.
            tail = "|cffff6060off after reload|r"
        else
            tail = "|cff8cd2ffv" .. (row.version or "?") .. "|r"
        end
        card.title:SetText(row.title .. "  " .. tail)

        -- Greying is done with the text colour and the icon's desaturation rather
        -- than frame alpha, so the card keeps its shape in the list.
        local dim = not (row.installed and row.loaded)
        card.title:SetTextColor(unpack(dim and C.faint or C.gold))
        card.notes:SetTextColor(unpack(dim and C.faint or C.text))
        card.icon:SetDesaturated(not row.installed)
        card.icon:SetAlpha(row.installed and 1 or 0.35)

        local action, toggle = card.action, card.toggle
        if not row.installed then
            action:Hide()
            toggle:Hide()
        elseif not row.loaded then
            -- Installed but switched off: the only useful thing is to turn it back on.
            toggle:Hide()
            action:Show()
            action:SetLabel("Enable")
            action:SetGrey(false)
            action:SetScript("OnClick", function()
                if NSU.EnableAddon(row.folder) then
                    StaticPopup_Show("NUGSSUITE_RELOAD", row.title .. " will load on your next reload.")
                else
                    NSU.Print("could not enable " .. row.title .. ". Enable it from the character select addon list.")
                end
            end)
        else
            action:Show()
            action:SetLabel("Open")
            action:SetGrey(false)
            action:SetScript("OnClick", function() NSU.OpenAddon(row.folder) end)

            toggle:Show()
            toggle:SetGrey(false)
            if pendingDisable[row.folder] then
                -- Undo, without needing the reload first.
                toggle:SetLabel("Enable")
                toggle:SetScript("OnClick", function()
                    if NSU.EnableAddon(row.folder) then
                        pendingDisable[row.folder] = nil
                        NSU.RefreshHub()
                    end
                end)
            else
                toggle:SetLabel("Disable")
                toggle:SetScript("OnClick", function()
                    if NSU.DisableAddon(row.folder) then
                        pendingDisable[row.folder] = true
                        NSU.RefreshHub()
                        -- Named in the prompt on purpose. Until the reload the addon
                        -- is still running, so without saying which one this is the
                        -- sort of misclick you would not notice until next login.
                        StaticPopup_Show("NUGSSUITE_RELOAD",
                            row.title .. " is switched off and will stop loading after a reload."
                            .. "\n\nIt keeps running until then, and Enable puts it back.")
                    else
                        NSU.Print("could not disable " .. row.title .. ". Turn it off from the character select addon list.")
                    end
                end)
            end
        end

        card:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(row.title)
            if row.installed and row.loaded then
                GameTooltip:AddLine("Type " .. row.slash .. " to open it directly.", 1, 1, 1)
                if not row.reg then
                    GameTooltip:AddLine("This version predates the suite. Its settings still export, but whole rather than as a diff, and its minimap button cannot be folded in. Update it to the current release.", 1, 0.6, 0.3, true)
                end
            elseif row.installed then
                GameTooltip:AddLine("Installed but switched off in your addon list.", 1, 1, 1)
            elseif row.comingSoon then
                GameTooltip:AddLine("Not released yet.", 1, 1, 1)
                GameTooltip:AddLine(row.notes, 0.6, 0.6, 0.6, true)
            else
                GameTooltip:AddLine("Not installed.", 1, 1, 1)
                GameTooltip:AddLine(row.notes, 0.6, 0.6, 0.6, true)
            end
            GameTooltip:Show()
        end)
        card:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    for i = #rows + 1, #cardPool do cardPool[i]:Hide() end
end

local function BuildAddonsTab(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()

    local list = CreateFrame("Frame", nil, tab)
    list:SetPoint("TOPLEFT", 12, -8)
    list:SetPoint("TOPRIGHT", -12, -8)
    list:SetHeight(#NSU.catalog * CARD_H)
    tab.list = list

    local consolidate = Check(tab, "Use one minimap button (hide the others)",
        function() return NSU.db.consolidate end,
        function(v)
            NSU.db.consolidate = v
            local pending = NSU.ApplyConsolidation()
            if pending then
                StaticPopup_Show("NUGSSUITE_RELOAD",
                    "One of your addons is an older version that can only hide its button on load.")
            end
        end,
        "Hides the minimap button belonging to every other nugs addon, leaving this one. Their buttons come straight back if you switch this off.")
    consolidate:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -10)
    consolidate:SetPoint("RIGHT", list, "RIGHT", -2, 0)
    tab.consolidate = consolidate

    local hint = Label(tab, "Left click the minimap button for this window. Right click it for a menu straight to any addon.", "GameFontNormalSmall", C.faint)
    hint:SetPoint("TOPLEFT", consolidate, "BOTTOMLEFT", 0, -8)
    hint:SetWidth(CONTENT_W - 30)
    hint:SetJustifyH("LEFT")

    return tab
end

--------------------------------------------------------------------------------
-- Profiles tab
--------------------------------------------------------------------------------
local function SelectedExportFolders()
    local folders = {}
    for folder, check in pairs(exportChecks) do
        if check.selected then folders[folder] = true end
    end
    return folders
end

local function BuildProfilesTab(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()

    local y = -10

    local exportHeader = SectionHeader(tab, "Export")
    exportHeader:SetPoint("TOPLEFT", 12, y)
    y = y - 20

    local exportHint = Label(tab, "Everything you have changed from the defaults, as one string you can paste to somebody else.", "GameFontNormalSmall", C.faint)
    exportHint:SetPoint("TOPLEFT", 12, y)
    exportHint:SetWidth(CONTENT_W - 12)
    exportHint:SetJustifyH("LEFT")
    y = y - 24

    -- Two columns of addon checkboxes, so four entries take two rows rather than
    -- pushing the import half off the bottom of the window.
    local colW = math.floor((CONTENT_W - 24) / 2)
    local startY = y
    for i, entry in ipairs(NSU.catalog) do
        local col = (i - 1) % 2
        local rowIndex = math.floor((i - 1) / 2)
        local folder = entry.folder
        local check = Check(tab, entry.title,
            function() return exportChecks[folder] and exportChecks[folder].selected end,
            function(v) if exportChecks[folder] then exportChecks[folder].selected = v end end)
        check:SetPoint("TOPLEFT", 14 + col * colW, startY - rowIndex * 22)
        check:SetWidth(colW - 10)
        check.selected = true
        exportChecks[folder] = check
        y = math.min(y, startY - rowIndex * 22 - 22)
    end

    local charCheck = Check(tab, "Include per-character settings",
        function() return NSU.db.includeChar end,
        function(v) NSU.db.includeChar = v end,
        "Carries the things stored per character rather than per account: your cooldown spell list and its priority order. Leave this on if you are sharing a setup with somebody, turn it off if you only want the look and layout.")
    charCheck:SetPoint("TOPLEFT", 14, y - 4)
    charCheck:SetWidth(CONTENT_W - 24)
    tab.charCheck = charCheck
    y = y - 30

    exportBox = TextArea(tab, CONTENT_W - 12, 88, true)
    exportBox:SetPoint("TOPLEFT", 12, y - 28)

    local genButton = Button(tab, "Generate string", 118, 22, function()
        local folders = SelectedExportFolders()
        local text, err = NSU.Profiles.Export(folders, NSU.db.includeChar)
        if not text then
            exportBox:SetContent("")
            NSU.Print(err or "nothing to export")
            return
        end
        exportBox:SetContent(text)
        exportBox.edit:SetFocus()
        exportBox.edit:HighlightText()
    end)
    genButton:SetPoint("TOPLEFT", 12, y)

    local copyHint = Label(tab, "Click the box, then Ctrl-C.", "GameFontNormalSmall", C.faint)
    copyHint:SetPoint("LEFT", genButton, "RIGHT", 10, 0)
    y = y - 28 - 88 - 14

    local importHeader = SectionHeader(tab, "Import")
    importHeader:SetPoint("TOPLEFT", 12, y)
    y = y - 20

    local importHint = Label(tab, "Paste a string below and check it before you apply it.", "GameFontNormalSmall", C.faint)
    importHint:SetPoint("TOPLEFT", 12, y)
    y = y - 18

    importBox = TextArea(tab, CONTENT_W - 12, 62, false)
    importBox:SetPoint("TOPLEFT", 12, y)
    y = y - 62 - 10

    local checkButton = Button(tab, "Check string", 118, 22, function()
        pendingImport = nil
        applyButton:SetGrey(true)
        local info, err = NSU.Profiles.Inspect(importBox:GetContent())
        if not info then
            importStatus:SetText("|cffff6060" .. tostring(err) .. "|r")
            return
        end
        if info.applicable == 0 then
            importStatus:SetText("|cffff6060That profile is for addons you do not have installed.|r")
            return
        end
        local names = {}
        for _, row in ipairs(info.rows) do
            names[#names + 1] = row.installed
                and ("|cff8cd2ff" .. row.title .. "|r")
                or  ("|cff777777" .. row.title .. " (skipped)|r")
        end
        pendingImport = info
        applyButton:SetGrey(false)
        importStatus:SetText((info.by and ("From " .. info.by .. ". ") or "") .. "Will change: " .. table.concat(names, ", "))
    end)
    checkButton:SetPoint("TOPLEFT", 12, y)

    applyButton = Button(tab, "Apply and reload", 128, 22, function()
        if pendingImport then StaticPopup_Show("NUGSSUITE_IMPORT") end
    end)
    applyButton:SetPoint("LEFT", checkButton, "RIGHT", 8, 0)
    applyButton:SetGrey(true)

    undoButton = Button(tab, "Undo last import", 128, 22, function()
        if NSU.db.backup then StaticPopup_Show("NUGSSUITE_UNDO") end
    end)
    undoButton:SetPoint("LEFT", applyButton, "RIGHT", 8, 0)
    y = y - 26

    importStatus = Label(tab, "", "GameFontNormalSmall", C.faint)
    importStatus:SetPoint("TOPLEFT", 12, y)
    importStatus:SetWidth(CONTENT_W - 12)
    importStatus:SetJustifyH("LEFT")

    return tab
end

--------------------------------------------------------------------------------
-- About tab
--------------------------------------------------------------------------------
-- The logo is a BLP because WoW will not load a PNG from an addon folder. It is
-- generated from nugsSuite-art/nugs.png by that folder's logo.js, resampled to 256
-- (a power of two, which the source is not) with the flat black backdrop keyed out
-- so the mark's glow fades into the panel instead of sitting on a black square.
local LOGO = "Interface\\AddOns\\nugsSuite\\logo"
local LOGO_SIZE = 156

local function BuildAboutTab(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()

    local logo = tab:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SIZE, LOGO_SIZE)
    logo:SetPoint("TOPLEFT", 10, -6)
    logo:SetTexture(LOGO)

    -- Text column beside the logo rather than under it: the mark is square, so
    -- stacking would spend a third of the panel's height before a word is read.
    local COL_X = 10 + LOGO_SIZE + 16
    local COL_W = CONTENT_W - COL_X - 12

    local header = SectionHeader(tab, "nugsSuite")
    header:SetPoint("TOPLEFT", COL_X, -16)

    local tagline = Label(tab, "Addons. Elevated.", "GameFontNormalSmall", C.gold)
    tagline:SetPoint("TOPLEFT", COL_X, -38)

    local blurb = Label(tab,
        "One button for every nugs addon. It opens any of them, shows what you have " ..
        "installed, and carries all of their settings between characters as a single " ..
        "string you can paste to somebody else.\n\n" ..
        "Every addon stands on its own. The suite only ties them together - by itself " ..
        "it does nothing at all.",
        "GameFontNormalSmall", C.text)
    blurb:SetPoint("TOPLEFT", COL_X, -60)
    blurb:SetWidth(COL_W)
    blurb:SetJustifyH("LEFT")

    local aboutHeader = SectionHeader(tab, "About nugs")
    aboutHeader:SetPoint("TOPLEFT", 12, -178)

    local about = Label(tab,
        "I am a 22 year WoW veteran, retail almost exclusively, with a real love and " ..
        "passion for the game. I have been a fan of addons since the early days and " ..
        "have watched great ones come and go - some because the developer stopped, " ..
        "others because Blizzard's design closed the door on them. Either way, they " ..
        "have always felt like a core necessity to the game.\n\n" ..
        "Some of them still miss something, though. A finesse. A quality finish. The " ..
        "sense that you understand every decision you are making while you use it. " ..
        "These are built the way I would want them built: limited to no dependencies, " ..
        "a consistent look, and each window doing its job.\n\n" ..
        "It is not that similar addons do not exist. Maybe they just were not for me. " ..
        "I hope you enjoy the suite, and whichever of the addons you have chosen to use.",
        "GameFontNormalSmall", C.text)
    about:SetPoint("TOPLEFT", 12, -200)
    about:SetWidth(CONTENT_W - 24)
    about:SetJustifyH("LEFT")

    local contact = Label(tab,
        "Find me on CurseForge as |cff8cd2ffnugsxD|r, or on Discord at |cff8cd2ffnug.s|r.  " ..
        "Type |cffffff00/nugs help|r for the full command list.",
        "GameFontNormalSmall", C.faint)
    -- Anchored to the bottom rather than a fixed offset from the top: the bio above
    -- it wraps to however many lines the font gives, and a top-anchored line here
    -- would collide with it the moment that estimate is wrong.
    contact:SetPoint("BOTTOMLEFT", 12, 54)
    contact:SetWidth(CONTENT_W - 24)
    contact:SetJustifyH("LEFT")

    local ver = Label(tab, "nugsSuite  |cff9fd7ffv" .. NSU.version .. "|r", "GameFontNormalSmall", C.text)
    ver:SetPoint("BOTTOMLEFT", 12, 34)

    local dev = Label(tab, "Developed by nugs", "GameFontNormalSmall", C.faint)
    dev:SetPoint("BOTTOMLEFT", 12, 20)

    local cr = Label(tab, "|cff777777(c) 2026 nugs. All Rights Reserved.|r", "GameFontNormalSmall", C.faint)
    cr:SetPoint("BOTTOMLEFT", 12, 6)

    return tab
end

--------------------------------------------------------------------------------
-- Tabs
--------------------------------------------------------------------------------
-- About sits first because it is the front page of the suite, but it is only ever
-- the LANDING tab once - see ToggleHub. A launcher that opens on its own about page
-- every time costs a click on the thing people opened it for.
local TABS = {
    { key = "about",    label = "About" },
    { key = "addons",   label = "Addons" },
    { key = "profiles", label = "Profiles" },
}

local function SelectTab(key)
    currentTab = key
    for _, def in ipairs(TABS) do
        local button = tabStrip.buttons[def.key]
        local active = (def.key == key)
        button.underline:SetShown(active)
        button.text:SetTextColor(unpack(active and C.gold or C.faint))
        panels[def.key]:SetShown(active)
    end
    if NSU.RefreshHub then NSU.RefreshHub() end
end

local function BuildTabStrip(f)
    local strip = CreateFrame("Frame", nil, f)
    strip:SetPoint("TOPLEFT", 1, -31)
    strip:SetPoint("TOPRIGHT", -1, -31)
    strip:SetHeight(26)
    strip.buttons = {}

    local x = 10
    for _, def in ipairs(TABS) do
        local b = CreateFrame("Button", nil, strip)
        b:SetSize(80, 26)
        b:SetPoint("LEFT", x, 0)

        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.text:SetPoint("CENTER")
        b.text:SetText(def.label)

        b.underline = b:CreateTexture(nil, "OVERLAY")
        b.underline:SetPoint("BOTTOMLEFT", 6, 2)
        b.underline:SetPoint("BOTTOMRIGHT", -6, 2)
        b.underline:SetHeight(2)
        b.underline:SetColorTexture(unpack(C.accent))
        b.underline:Hide()

        b:SetScript("OnClick", function() SelectTab(def.key) end)
        b:SetScript("OnEnter", function(self)
            if currentTab ~= def.key then self.text:SetTextColor(1, 1, 1) end
        end)
        b:SetScript("OnLeave", function(self)
            self.text:SetTextColor(unpack(currentTab == def.key and C.gold or C.faint))
        end)

        strip.buttons[def.key] = b
        x = x + 82
    end
    return strip
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function BuildWindow()
    local f = CreateFrame("Frame", "nugsSuiteHub", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    Backdrop(f, C.bg, 1)

    HeaderBar(f, "nugsSuite", "v" .. NSU.version)
    tabStrip = BuildTabStrip(f)

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 12, -62)
    body:SetPoint("BOTTOMRIGHT", -12, 12)

    panels = {}
    panels.addons   = BuildAddonsTab(body)
    panels.profiles = BuildProfilesTab(body)
    panels.about    = BuildAboutTab(body)

    tinsert(UISpecialFrames, "nugsSuiteHub")
    window = f
    SelectTab("addons")

    -- CreateFrame hands back a *shown* frame, so the window would flash up on
    -- login without this.
    f:Hide()
    return f
end

function NSU.RefreshHub()
    if not window or not window:IsShown() then return end
    RefreshCards()
    if panels.addons.consolidate then panels.addons.consolidate:Refresh() end
    if panels.profiles.charCheck then panels.profiles.charCheck:Refresh() end
    for folder, check in pairs(exportChecks) do
        check:Refresh()
        local entry = NSU.byFolder[folder]
        local loaded = entry and C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(entry.folder)
        check:SetGrey(not loaded)
    end
    if undoButton then undoButton:SetGrey(not NSU.db.backup) end
end

function NSU.ToggleHub(tab)
    if not window then BuildWindow() end
    if tab and window:IsShown() and currentTab ~= tab then
        SelectTab(tab)
        return
    end
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        if tab then
            SelectTab(tab)
        elseif not NSU.db.seenAbout then
            -- One introduction, then never again. The first time somebody opens the
            -- hub they get the front page; every open after that lands where the
            -- work is.
            NSU.db.seenAbout = true
            SelectTab("about")
        else
            SelectTab(currentTab)
        end
        NSU.RefreshHub()
    end
end

--------------------------------------------------------------------------------
-- Blizzard settings entry
--------------------------------------------------------------------------------
-- A stub only, so the addon is findable where players look for addon settings. The
-- real window is the one above; this just points at it.
function NSU.InitOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end

    local panel = CreateFrame("Frame")
    panel.name = "nugsSuite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("nugsSuite")

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetText("One button for every nugs addon. Type |cffffff00/nugs|r or use the button below.")

    local open = Button(panel, "Open nugsSuite", 150, 24, function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        NSU.ToggleHub()
    end)
    open:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "nugsSuite")
    category.ID = "nugsSuite"
    Settings.RegisterAddOnCategory(category)
end
