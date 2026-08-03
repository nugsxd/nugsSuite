--------------------------------------------------------------------------------
-- nugsSuite
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsSuite  -  Core.lua
-- The hub for the nugs addons: one minimap button that opens any of them, one
-- place to see what is installed and at what version, and one string that carries
-- every nugs setting you have to another character or another player.
--
-- The suite deliberately owns no gameplay behaviour at all. Everything in here is
-- either discovery (what is installed) or routing (open that addon's config).
-- That is what makes it safe to add or remove at any point: nothing else in the
-- suite depends on this addon, and nothing in here breaks when an addon is absent.
--
-- Integration runs through one plain global table, _G.nugsSuiteRegistry, that each
-- addon writes a single entry into. A global rather than a call into this addon,
-- because a global is free of load order - whichever side loads first, the table
-- is already there, and neither addon has to exist for the other to work.
--
-- An addon that has NOT been taught to register is still listed and still opens,
-- through the slash command in the catalog below. Registering only buys the
-- extras: settings export, and folding its minimap button into this one.
--------------------------------------------------------------------------------
local ADDON_NAME, NSU = ...

NSU.name    = ADDON_NAME
NSU.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "0.1.0"

local PREFIX = "|cff6fc2ffnugsSuite|r: "
function NSU.Print(msg) print(PREFIX .. tostring(msg)) end

-- The registry is created here as well as in each addon, so that the suite can be
-- read from safely whether it loaded first, last, or entirely alone.
_G.nugsSuiteRegistry = _G.nugsSuiteRegistry or {}

-- The one public handle, and the only reliable way for another addon to ask "is the
-- suite actually here?". Set at file scope, so it exists the moment this addon
-- loads. Checking the registry instead would not work: every addon creates that
-- table itself, so it is present whether or not the suite is.
--
-- Absent also covers "installed but disabled", which is the honest answer - a
-- disabled suite is no more use to the player than a missing one.
_G.nugsSuite = NSU

--------------------------------------------------------------------------------
-- Catalog
--------------------------------------------------------------------------------
-- Every nugs addon, installed or not. Uninstalled ones stay in the list greyed
-- out: the roster is the point, and a player who only has one of these should be
-- able to see what else exists without going hunting for it.
--
-- `slashKey` is the SlashCmdList key, not the typed command - firing the handler
-- directly is the only way into an addon that predates the registry, since none
-- of them export their namespace. `settings` is the Settings category id, used as
-- a last resort. RaidReady has no Settings category, so it has no entry here.
--
-- `dbName` and `charDbName` exist because two of these addons store their settings
-- under a name that is not their folder name: RaidReady predates the nugs prefix,
-- and nugsCooldownPulse deliberately kept its old unprefixed variable so that the
-- rename would not throw away everybody's saved profile. They are only a fallback
-- for an addon that has not registered - a registered addon hands over its own.
NSU.catalog = {
    {
        folder     = "nugsRaidReady",
        title      = "nugsRaidReady",
        notes      = "Raid addon, consumable and character readiness checks.",
        slash      = "/nrr",
        slashKey   = "RAIDREADY",
        dbName     = "RaidReadyDB",
    },
    {
        folder     = "nugsCastBars",
        title      = "nugsCastBars",
        notes      = "Cast bars for you, your target, focus, pet and bosses.",
        slash      = "/ncast",
        slashKey   = "NUGSCASTBARS",
        settings   = "nugsCastBars",
        dbName     = "nugsCastBarsDB",
        charDbName = "nugsCastBarsCharDB",
    },
    {
        folder     = "nugsComboBar",
        title      = "nugsComboBar",
        notes      = "Your class resource drawn as configurable pips.",
        slash      = "/ncb",
        slashKey   = "NUGSCOMBOBAR",
        settings   = "nugsComboBar",
        dbName     = "nugsComboBarDB",
        charDbName = "nugsComboBarCharDB",
    },
    {
        folder     = "nugsCooldownPulse",
        title      = "nugsCooldownPulse",
        notes      = "Pulses an icon the moment a cooldown comes back up.",
        slash      = "/ncp",
        slashKey   = "NUGSCOOLDOWNPULSE",
        settings   = "nugsCooldownPulse",
        dbName     = "CooldownPulseDB",
        charDbName = "CooldownPulseCharDB",
    },
    {
        folder     = "nugsAuras",
        title      = "nugsAuras",
        -- Not released yet. Listed anyway, because the roster exists to show what
        -- the suite is, and showing it as merely "not installed" would send people
        -- looking for a download that is not there. Drop this line on release.
        comingSoon = true,
        notes      = "Free-floating buff and debuff groups you place yourself.",
        slash      = "/na",
        slashKey   = "NUGSAURAS",
        settings   = "nugsAuras",
        dbName     = "nugsAurasDB",
        charDbName = "nugsAurasCharDB",
    },
    {
        folder     = "nugsCombatText",
        title      = "nugsCombatText",
        -- Not released yet; same reasoning as nugsAuras above. Drop this line on
        -- release.
        comingSoon = true,
        notes      = "Floating combat text, with ability icons and crit styling.",
        slash      = "/nct",
        slashKey   = "NUGSCOMBATTEXT",
        dbName     = "nugsCombatTextDB",
    },
    {
        folder     = "nugsDeathNote",
        title      = "nugsDeathNote",
        -- Not released yet; same reasoning as nugsAuras above. Drop this line on
        -- release.
        comingSoon = true,
        notes      = "Logs who died on every pull, and lets officers write down why.",
        slash      = "/ndn",
        slashKey   = "NUGSDEATHNOTE",
        settings   = "nugsDeathNote",
        dbName     = "nugsDeathNoteDB",
    },
}

NSU.byFolder = {}
for i, entry in ipairs(NSU.catalog) do
    entry.order = i
    entry.icon  = "Interface\\AddOns\\" .. entry.folder .. "\\icon"
    NSU.byFolder[entry.folder] = entry
end

--------------------------------------------------------------------------------
-- Saved variables
--------------------------------------------------------------------------------
NSU.defaults = {
    minimapHidden = false,
    minimapAngle  = 200,
    consolidate   = false,  -- hide the other addons' minimap buttons
    includeChar   = true,   -- carry per-character settings in profile strings
    backup        = false,  -- last pre-import profile string, for undo
    seenAbout     = false,  -- the hub lands on About once, then on Addons
}

-- Recursive merge of missing keys only, so a new release can add a default without
-- touching anything the player has already changed. Duplicated from the other nugs
-- addons rather than shared, because a shared copy would be a load-order dependency.
local function CopyDefaults(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end
NSU.CopyDefaults = CopyDefaults

local function InitDB()
    nugsSuiteDB = CopyDefaults(nugsSuiteDB or {}, NSU.defaults)
    NSU.db = nugsSuiteDB
end

--------------------------------------------------------------------------------
-- Discovery
--------------------------------------------------------------------------------
-- One pass over the whole addon list rather than a GetAddOnInfo per folder: asking
-- about a folder that is not installed is not reliably safe across clients, and
-- walking the list once cannot be wrong.
local function BuildInstalledMap()
    local map = {}
    if not (C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetAddOnInfo) then return map end
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name then
            map[name:lower()] = {
                index   = i,
                name    = name,
                version = C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(i, "Version") or nil,
            }
        end
    end
    return map
end

-- Which band of the roster a row belongs in. Lower sorts higher.
--
-- Coming soon sits below merely-not-installed on purpose: "not installed" is
-- something you can act on right now, "coming soon" is not, so it belongs furthest
-- from the things you can actually click.
local function SortRank(row)
    if row.comingSoon then return 3 end
    if not row.installed then return 2 end
    if not row.loaded then return 1 end   -- installed but switched off
    return 0                              -- installed and running
end

-- Returns the catalog decorated with what is true right now: installed, loaded,
-- the version actually on disk, and the registry entry if the addon supplied one.
-- Rebuilt on every call - it is four entries, and a stale list here would show the
-- wrong version after an addon updates.
function NSU.Scan()
    local installed = BuildInstalledMap()
    local registry  = _G.nugsSuiteRegistry or {}
    local list = {}
    for _, entry in ipairs(NSU.catalog) do
        local found = installed[entry.folder:lower()]
        local row = {
            folder    = entry.folder,
            title     = entry.title,
            notes     = entry.notes,
            slash     = entry.slash,
            icon      = entry.icon,
            installed = found ~= nil,
            -- Asked by index, not by name: the map above already proved the addon
            -- exists, and querying a folder that is not installed is the thing the
            -- whole-list scan was written to avoid.
            loaded    = (found and C_AddOns and C_AddOns.IsAddOnLoaded
                         and C_AddOns.IsAddOnLoaded(found.index)) or false,
            version   = found and found.version or nil,
            reg       = registry[entry.folder],
            -- An authoring flag: it means "not published", which stays true whether
            -- or not this machine happens to have a copy.
            --
            -- It used to be suppressed once the addon was installed, on the grounds
            -- that the author and testers should see a normal entry. That was wrong
            -- in both directions: it hid the one fact that matters about a
            -- pre-release build, and it meant the person best placed to notice a
            -- stale flag was the only one who never saw it.
            comingSoon = entry.comingSoon or false,
        }
        list[#list + 1] = row
    end

    -- Ordered so the list reads top-down as "what you have, then what you could
    -- have, then what you cannot have yet" - and alphabetically inside each of those,
    -- so a name stays where you last saw it instead of moving because the catalog was
    -- edited. Sorting here rather than in the window means the minimap's right-click
    -- menu gets the same order without knowing anything about it.
    table.sort(list, function(a, b)
        local ra, rb = SortRank(a), SortRank(b)
        if ra ~= rb then return ra < rb end
        return a.title:lower() < b.title:lower()
    end)

    return list
end

-- How many are installed, and how many there are to install. An addon that has not
-- been released does not count towards the total - otherwise somebody who owns
-- every published nugs addon would still be told they were missing one.
function NSU.CountInstalled()
    local installed, available = 0, 0
    for _, row in ipairs(NSU.Scan()) do
        -- An unreleased addon is out of both numbers, installed or not. A
        -- pre-release copy on the author's machine counting as "1 of 6" would be
        -- claiming a total nobody else can reach.
        if row.comingSoon then                      -- luacheck: ignore
        elseif row.installed then
            installed = installed + 1
            available = available + 1
        else
            available = available + 1
        end
    end
    return installed, available
end

--------------------------------------------------------------------------------
-- Routing
--------------------------------------------------------------------------------
-- Three ways in, tried best first. The registry's Open is the only one that can be
-- trusted to hit the addon's real window; the slash handler is what every addon
-- has whether or not it knows about the suite; the Settings category is the last
-- resort for an addon whose slash command was renamed out from under this list.
function NSU.OpenAddon(folder)
    local entry = NSU.byFolder[folder]
    if not entry then return false end

    local reg = (_G.nugsSuiteRegistry or {})[folder]
    if reg and type(reg.Open) == "function" then
        local ok, err = pcall(reg.Open)
        if ok then return true end
        NSU.Print(entry.title .. " could not open its options: " .. tostring(err))
    end

    if entry.slashKey and SlashCmdList and SlashCmdList[entry.slashKey] then
        SlashCmdList[entry.slashKey]("")
        return true
    end

    if entry.settings and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(entry.settings)
        return true
    end

    NSU.Print("No way to open " .. entry.title .. ". Try " .. (entry.slash or "its slash command") .. " directly.")
    return false
end

-- Enabling takes effect on the next load, so this only makes sense paired with a
-- reload prompt - which the caller in Options.lua owns, because a silent ReloadUI
-- from a list row would be a nasty surprise.
function NSU.EnableAddon(folder)
    if not (C_AddOns and C_AddOns.EnableAddOn) then return false end
    local ok = pcall(C_AddOns.EnableAddOn, folder)
    return ok
end

-- The other half of the same control. Nothing here can switch off nugsSuite itself:
-- the suite is not in its own catalog, so it never gets a card and there is no way to
-- disable the window you are standing in.
function NSU.DisableAddon(folder)
    if not (C_AddOns and C_AddOns.DisableAddOn) then return false end
    local ok = pcall(C_AddOns.DisableAddOn, folder)
    return ok
end

--------------------------------------------------------------------------------
-- Minimap consolidation
--------------------------------------------------------------------------------
-- The whole reason the suite exists is to stop four buttons crowding the minimap.
-- An addon that registered a SetMinimap can be hidden live; one that did not gets
-- its saved flag set directly, which takes hold on the next load. Either way the
-- suite never leaves a player with no button at all - its own is always the one
-- that stays.
function NSU.ApplyConsolidation()
    if not NSU.db then return end
    local hide = NSU.db.consolidate and true or false
    local pending = false
    for _, row in ipairs(NSU.Scan()) do
        if row.installed then
            local reg = row.reg
            if reg and type(reg.SetMinimap) == "function" then
                pcall(reg.SetMinimap, not hide)
            elseif row.loaded then
                -- No registration: set the flag in the addon's own saved variables.
                -- Via the catalog's dbName rather than the folder name, because two
                -- of these store their settings under a different name entirely.
                local entry = NSU.byFolder[row.folder]
                local db = entry and entry.dbName and _G[entry.dbName]
                if type(db) == "table" and db.minimapHidden ~= nil then
                    db.minimapHidden = hide
                    pending = true
                end
            end
        end
    end
    return pending
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitDB()
        if NSU.InitOptions then NSU.InitOptions() end
    elseif event == "PLAYER_LOGIN" then
        if NSU.InitMinimap then NSU.InitMinimap() end
        -- Consolidation is re-applied at login because the addons it hides only
        -- build their buttons at their own PLAYER_LOGIN, which may run after this.
        if NSU.db and NSU.db.consolidate then
            C_Timer.After(1, function() NSU.ApplyConsolidation() end)
        end
    end
end)

--------------------------------------------------------------------------------
-- Slash command
--------------------------------------------------------------------------------
local function Usage()
    NSU.Print("v" .. NSU.version .. " commands:")
    print("  |cffffff00/nugs|r - open the suite hub")
    print("  |cffffff00/nugs list|r - print every nugs addon and its version")
    print("  |cffffff00/nugs <name>|r - open that addon (castbars, combobar, cooldownpulse, raidready)")
    print("  |cffffff00/nugs profile|r - open the hub on the profile tab")
    print("  |cffffff00/nugs cpu|r - memory and CPU used by each nugs addon")
    print("  |cffffff00/nugs minimap|r - show or hide this button")
end

-- Loose matching on purpose: the folder names are long and the point of a launcher
-- is that you do not have to remember exactly what anything is called.
local function MatchFolder(term)
    term = term:gsub("^nugs", "")
    for _, entry in ipairs(NSU.catalog) do
        local short = entry.folder:gsub("^nugs", ""):lower()
        if short == term or entry.folder:lower() == term then return entry.folder end
    end
    for _, entry in ipairs(NSU.catalog) do
        local short = entry.folder:gsub("^nugs", ""):lower()
        if short:find(term, 1, true) then return entry.folder end
    end
    return nil
end

SLASH_NUGSSUITE1 = "/nugs"
SLASH_NUGSSUITE2 = "/nugssuite"
SlashCmdList["NUGSSUITE"] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "hub" or cmd == "config" or cmd == "options" then
        NSU.ToggleHub()
    elseif cmd == "list" then
        NSU.Print("v" .. NSU.version .. " - installed nugs addons:")
        for _, row in ipairs(NSU.Scan()) do
            if row.installed then
                print(string.format("  |cff8cd2ff%s|r v%s%s", row.title, row.version or "?",
                    row.loaded and "" or " |cffff6060(disabled)|r"))
            else
                print(string.format("  |cff777777%s - not installed|r", row.title))
            end
        end
    elseif cmd == "profile" or cmd == "profiles" then
        NSU.ToggleHub("profiles")
    elseif cmd == "cpu" or cmd == "perf" then
        -- Answers "how heavy is this actually" with a number instead of an opinion.
        --
        -- CPU figures only exist while the scriptProfile CVar is on, and they are
        -- cumulative since it was switched on rather than a rate - so the useful
        -- reading is each addon's SHARE of all addon CPU, which is comparable and
        -- does not depend on how long you have been logged in.
        local upMem  = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
        local getMem = (C_AddOns and C_AddOns.GetAddOnMemoryUsage)    or GetAddOnMemoryUsage
        local upCPU  = (C_AddOns and C_AddOns.UpdateAddOnCPUUsage)    or UpdateAddOnCPUUsage
        local getCPU = (C_AddOns and C_AddOns.GetAddOnCPUUsage)       or GetAddOnCPUUsage
        local numAddons = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
        local addonInfo = (C_AddOns and C_AddOns.GetAddOnInfo)  or GetAddOnInfo

        if upMem then pcall(upMem) end
        if upCPU then pcall(upCPU) end

        -- Totals across EVERY addon, so a nugs number can be quoted as a share.
        local totalMem, totalCPU = 0, 0
        if numAddons and addonInfo then
            for i = 1, numAddons() do
                if getMem then local ok, v = pcall(getMem, i); if ok and v then totalMem = totalMem + v end end
                if getCPU then local ok, v = pcall(getCPU, i); if ok and v then totalCPU = totalCPU + v end end
            end
        end

        local profiling = (totalCPU or 0) > 0
        NSU.Print("v" .. NSU.version .. " footprint" ..
                  (profiling and "" or "  |cffd8a13f(CPU needs /console scriptProfile 1 then a reload)|r"))

        local sumMem, sumCPU = 0, 0
        for _, row in ipairs(NSU.Scan()) do
            if row.installed and row.loaded then
                local mem = getMem and select(2, pcall(getMem, row.folder)) or 0
                local cpu = getCPU and select(2, pcall(getCPU, row.folder)) or 0
                mem, cpu = tonumber(mem) or 0, tonumber(cpu) or 0
                sumMem, sumCPU = sumMem + mem, sumCPU + cpu
                local line = string.format("  |cff8cd2ff%-20s|r %7.1f KB", row.title, mem)
                if profiling then
                    line = line .. string.format("   %8.1f ms  (%.2f%% of addon CPU)",
                                                 cpu, totalCPU > 0 and (cpu / totalCPU * 100) or 0)
                end
                print(line)
            end
        end

        print(string.format("  |cffffd479%-20s|r %7.1f KB%s", "all nugs addons", sumMem,
              profiling and string.format("   %8.1f ms  (%.2f%% of addon CPU)",
                                          sumCPU, totalCPU > 0 and (sumCPU / totalCPU * 100) or 0) or ""))
        print(string.format("  |cff777777%-20s %7.1f KB%s|r", "every addon you run", totalMem,
              profiling and string.format("   %8.1f ms", totalCPU) or ""))

    elseif cmd == "minimap" then
        NSU.db.minimapHidden = not NSU.db.minimapHidden
        if NSU.SetMinimapShown then NSU.SetMinimapShown(not NSU.db.minimapHidden) end
        NSU.Print("minimap button " .. (NSU.db.minimapHidden and "hidden" or "shown"))
    elseif cmd == "help" then
        Usage()
    else
        local folder = MatchFolder(cmd)
        if folder then
            NSU.OpenAddon(folder)
        else
            Usage()
        end
    end
    if NSU.RefreshHub then NSU.RefreshHub() end
end
