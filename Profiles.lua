--------------------------------------------------------------------------------
-- nugsSuite
-- Copyright (c) 2026 nugs. All Rights Reserved.
-- Unauthorized copying, distribution, or modification is prohibited. See LICENSE.
--------------------------------------------------------------------------------
-- nugsSuite  -  Profiles.lua
-- One string that carries every nugs setting you have, to another character or to
-- another player.
--
-- Two decisions shape this file.
--
-- First, a profile is a DIFF against each addon's defaults, not a copy of its
-- saved variables. Most players change a handful of things out of the hundred an
-- addon stores, so the diff is a fraction of the size, and - more usefully - it
-- means importing somebody's profile only moves the settings they actually chose.
-- Anything they left alone stays at the default on your side rather than being
-- stamped over with their copy of the same value.
--
-- Second, a collection whose default is an empty table - a spell list, a priority
-- order - is exported whole and marked to replace rather than merge. Merging a
-- list is meaningless: importing a friend's cooldown spell list should give you
-- their list, not the union of theirs and yours.
--
-- Applying a profile ends in a reload rather than a live refresh. The addons all
-- read their saved variables once, at load, and a reload is the one path that is
-- guaranteed correct for every one of them - including the ones that know nothing
-- about the suite. ReloadUI writes saved variables on the way out, so mutating the
-- tables in memory and reloading persists cleanly.
--------------------------------------------------------------------------------
local ADDON_NAME, NSU = ...

local P = {}
NSU.Profiles = P

local REPLACE_KEY = "__r"

--------------------------------------------------------------------------------
-- Table plumbing
--------------------------------------------------------------------------------
local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, sub in pairs(v) do out[k] = DeepCopy(sub) end
    return out
end

local function IsEmpty(t)
    return next(t) == nil
end

-- Returns what in `cur` differs from `def`, or nil when they match. A table whose
-- default is empty comes back wrapped in a replace marker (see the header).
local function Diff(cur, def)
    if type(cur) ~= "table" then
        if cur == def then return nil end
        return cur, true
    end

    if type(def) ~= "table" then
        return { [REPLACE_KEY] = DeepCopy(cur) }, true
    end

    if IsEmpty(def) then
        if IsEmpty(cur) then return nil end
        return { [REPLACE_KEY] = DeepCopy(cur) }, true
    end

    local out, any = {}, false
    for k, v in pairs(cur) do
        local sub, present = Diff(v, def[k])
        if present then
            out[k] = sub
            any = true
        end
    end
    if not any then return nil end
    return out, true
end

P.Diff = Diff

-- The mirror of Diff. Replace markers overwrite, everything else merges key by key.
local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if v[REPLACE_KEY] ~= nil then
                dst[k] = DeepCopy(v[REPLACE_KEY])
            else
                if type(dst[k]) ~= "table" then dst[k] = {} end
                Merge(dst[k], v)
            end
        else
            dst[k] = v
        end
    end
end
P.Merge = Merge

--------------------------------------------------------------------------------
-- Reaching an addon's settings
--------------------------------------------------------------------------------
-- A registered addon hands over its own tables and its own defaults. One that has
-- not registered falls back to the saved variable names in the catalog, with no
-- defaults - which is handled correctly rather than skipped: with nothing to diff
-- against, the whole table is exported as a replacement.
local function GetTables(folder)
    local reg   = (_G.nugsSuiteRegistry or {})[folder]
    local entry = NSU.byFolder[folder]
    local db, defaults, cdb, cdefaults

    if reg and type(reg.GetDB) == "function" then
        local ok, a, b = pcall(reg.GetDB)
        if ok then db, defaults = a, b end
    end
    if reg and type(reg.GetCharDB) == "function" then
        local ok, a, b = pcall(reg.GetCharDB)
        if ok then cdb, cdefaults = a, b end
    end

    if type(db) ~= "table" and entry and entry.dbName then
        db = _G[entry.dbName]
    end
    if type(cdb) ~= "table" and entry and entry.charDbName then
        cdb = _G[entry.charDbName]
    end

    return db, defaults, cdb, cdefaults
end

-- Some things are stored as settings but are not settings anybody would want to
-- receive: measured cooldown caches, first-launch prompt answers, where a minimap
-- button happens to sit. An addon names those in its registration and they are
-- dropped here, before the diff, so they can never reach a profile string.
local function WithoutExcluded(tbl, exclude)
    if type(exclude) ~= "table" or type(tbl) ~= "table" then return tbl end
    local out = {}
    for k, v in pairs(tbl) do
        if not exclude[k] then out[k] = v end
    end
    return out
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------
-- `folders` is a set of folder names to include; `includeChar` carries the
-- per-character tables (spell lists, priorities) as well as the account-wide ones.
--
-- `full` makes this a snapshot rather than a diff: every table is carried whole and
-- nothing is excluded. Only the automatic pre-import backup uses it, because a
-- backup has to be able to put back a setting that was at its default before the
-- import and is not afterwards - which a diff, by definition, does not record. It
-- never leaves the player's own machine, so the exclusions do not apply either.
-- Returns the string, plus a per-addon summary the window can show.
function P.Export(folders, includeChar, full)
    local payload = { v = 1, addons = {} }

    local who = UnitName("player")
    local realm = GetRealmName and GetRealmName() or nil
    if who then payload.by = who .. (realm and ("-" .. realm) or "") end

    local summary, count = {}, 0
    for _, row in ipairs(NSU.Scan()) do
        if row.installed and folders[row.folder] then
            local db, defaults, cdb, cdefaults = GetTables(row.folder)
            local reg = row.reg
            local block = { ver = row.version }
            local touched = false

            if type(db) == "table" then
                -- Passing no defaults makes Diff wrap the whole table as a
                -- replacement, which is exactly what a snapshot is.
                local diff = full and Diff(db, nil)
                              or Diff(WithoutExcluded(db, reg and reg.exclude), defaults)
                if diff ~= nil then
                    block.db = diff
                    touched = true
                end
            end
            if includeChar and type(cdb) == "table" then
                local diff = full and Diff(cdb, nil)
                              or Diff(WithoutExcluded(cdb, reg and reg.excludeChar), cdefaults)
                if diff ~= nil then
                    block.cdb = diff
                    touched = true
                end
            end

            if touched then
                payload.addons[row.folder] = block
                count = count + 1
                summary[#summary + 1] = { title = row.title, registered = row.reg ~= nil }
            else
                summary[#summary + 1] = { title = row.title, unchanged = true }
            end
        end
    end

    if count == 0 then
        return nil, "None of the selected addons have any settings that differ from their defaults."
    end

    local text, err = NSU.Serialize.Encode(payload)
    if not text then return nil, err end
    return text, nil, summary
end

--------------------------------------------------------------------------------
-- Import
--------------------------------------------------------------------------------
-- Decodes and describes without changing anything, so the window can show what a
-- string contains before the player commits to it. Nothing in here writes.
function P.Inspect(text)
    local payload, err = NSU.Serialize.Decode(text)
    if not payload then return nil, err end
    if type(payload.addons) ~= "table" then
        return nil, "that profile string does not contain any settings"
    end

    local info = { by = type(payload.by) == "string" and payload.by or nil, rows = {}, applicable = 0 }
    local installedRows = {}
    for _, row in ipairs(NSU.Scan()) do installedRows[row.folder] = row end

    for folder, block in pairs(payload.addons) do
        local entry = NSU.byFolder[folder]
        if entry and type(block) == "table" then
            local row = installedRows[folder]
            local item = {
                folder    = folder,
                title     = entry.title,
                fromVer   = type(block.ver) == "string" and block.ver or "?",
                installed = row and row.installed or false,
                yourVer   = row and row.version or nil,
                hasChar   = block.cdb ~= nil,
            }
            if item.installed then info.applicable = info.applicable + 1 end
            info.rows[#info.rows + 1] = item
        end
    end

    table.sort(info.rows, function(a, b)
        local ea, eb = NSU.byFolder[a.folder], NSU.byFolder[b.folder]
        return (ea and ea.order or 99) < (eb and eb.order or 99)
    end)

    if #info.rows == 0 then
        return nil, "that profile is for addons that are not part of the nugs suite"
    end
    info.payload = payload
    return info
end

-- Applies one addon's block, leaving the receiver in the SENDER's state rather than
-- a blend of the two.
--
-- The reset is the whole point. A profile is a diff against defaults, so a setting
-- the sender never touched is simply absent from it. Merging such a profile leaves
-- the receiver's own value standing for every key the sender left alone, which
-- produces a UI matching neither person - and the more the receiver had customised,
-- the less the import appears to do. So the table is cleared, the defaults are laid
-- back down, and the sender's choices go on top.
--
-- `exclude` names the keys a profile never carries in the first place: measured
-- caches, this player's minimap angle, one-shot migration flags. They are lifted out
-- and put back, because clearing them would be destroying local data on the strength
-- of somebody else's settings. Restoring a backup passes no exclude list, since a
-- backup is a full snapshot and already holds the true value of every key.
--
-- The block may itself BE a replace marker rather than merely contain them: Diff
-- wraps the whole table when there are no defaults to compare against, or when the
-- defaults are empty. Merge only looks for a marker one level down, so unwrapping
-- has to happen here - without it nothing is applied and a literal __r key is
-- written into the saved variables.
local function ApplyBlock(dst, src, defaults, exclude)
    if type(dst) ~= "table" or type(src) ~= "table" then return false end

    local keep = {}
    if type(exclude) == "table" then
        for k in pairs(exclude) do keep[k] = dst[k] end
    end

    for k in pairs(dst) do dst[k] = nil end

    local whole = src[REPLACE_KEY]
    if whole ~= nil then
        -- A whole table: either a backup snapshot or an addon with no defaults to
        -- have been diffed against. Either way it stands on its own.
        Merge(dst, whole)
    else
        if type(defaults) == "table" then
            for k, v in pairs(defaults) do dst[k] = DeepCopy(v) end
        end
        Merge(dst, src)
    end

    for k, v in pairs(keep) do dst[k] = v end
    return true
end

-- Writes the profile into the live saved-variable tables. Only ever called after
-- Inspect has succeeded and the player has confirmed. Returns how many addons were
-- touched; the caller is responsible for the reload.
-- `preserveExcluded` is true for a real import and false when restoring a backup.
-- See ApplyBlock for why the two differ.
function P.Apply(payload, folders, includeChar, preserveExcluded)
    local applied = 0
    local registry = _G.nugsSuiteRegistry or {}
    for folder, block in pairs(payload.addons) do
        if folders[folder] and type(block) == "table" then
            local db, defaults, cdb, cdefaults = GetTables(folder)
            local reg = registry[folder]
            local exclude     = preserveExcluded and reg and reg.exclude or nil
            local excludeChar = preserveExcluded and reg and reg.excludeChar or nil
            local touched = false
            if type(block.db) == "table"
               and ApplyBlock(db, block.db, defaults, exclude) then
                touched = true
            end
            if includeChar and type(block.cdb) == "table"
               and ApplyBlock(cdb, block.cdb, cdefaults, excludeChar) then
                touched = true
            end
            if touched then applied = applied + 1 end
        end
    end
    return applied
end

-- Taken automatically just before any import, so a profile that turns out to be
-- somebody else's taste is one button to undo rather than a rebuild from memory.
-- A full snapshot rather than a diff, for the reason spelled out on P.Export.
function P.TakeBackup()
    local all = {}
    for _, row in ipairs(NSU.Scan()) do
        if row.installed then all[row.folder] = true end
    end
    local text = P.Export(all, true, true)
    if text then
        NSU.db.backup = text
    end
    return text
end
