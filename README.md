# nugsSuite

One minimap button for every nugs addon.

The suite adds nothing to your gameplay. It exists because five addons had grown
into five minimap buttons, five slash commands and five sets of settings that had
to be rebuilt by hand on every character.

## What it does

**Launches everything.** One button. Left click opens the hub, a roster of every
nugs addon with its version and an Open button. Right click skips the window and
drops a menu straight to any of them.

**Shows the whole family.** Addons you do not have installed stay in the list,
greyed, with a line on what they do. If somebody handed you one of these, the rest
are not a secret.

**Folds up the clutter.** One checkbox hides every other nugs minimap button and
leaves this one. Unticking it puts them all back.

**Moves your settings.** Export every nugs setting you have as a single string,
paste it to a guildmate or into another character's client, and get the same setup
back. A copy of what you had is saved first, and one button undoes the import.

## Commands

| Command | |
|---|---|
| `/nugs` | open the hub |
| `/nugs list` | print every nugs addon and its version |
| `/nugs profile` | open the hub on the profile tab |
| `/nugs castbars` | open an addon by name - partial names work |
| `/nugs minimap` | show or hide the minimap button |

## Profile strings

A profile is a **diff against each addon's defaults**, not a copy of its saved
variables, so the string stays short - most people change a handful of the hundreds
of values an addon stores.

**Importing replaces, it does not blend.** The addon is reset to its defaults and
the profile's choices are laid on top, so you end up in exactly the sender's state.
This matters precisely because a profile is a diff: a setting the sender never
touched is absent from the string entirely, so merging it over your settings would
leave *your* value standing for every key they left alone. The result would match
neither person, and the more you had customised, the less the import would appear
to do.

The practical consequence: importing somebody's profile discards your own settings
for the addons it covers. That is what the automatic backup and the Undo button are
for.

Collections whose default is empty - a cooldown spell list, a priority order - are
carried whole and **replace** rather than merge. Importing a friend's spell list
should give you their list, not the union of theirs and yours.

Some things are stored as settings but are not settings anybody would want to
receive, and are never exported: measured cast-length and cooldown caches, the
angle your minimap button happens to sit at, and RaidReady's first-launch
gold-tracking answer.

Applying a profile ends in a reload. Every nugs addon reads its saved variables
once, at load, so a reload is the one path guaranteed correct for all of them -
including a version that predates the suite entirely.

### On safety

Import strings arrive from other players, so the reader is a **hand-written parser,
not `loadstring`**. It accepts exactly what the writer emits - `nil`, booleans,
numbers, quoted strings, and tables of those - and rejects everything else. A
hostile string can at worst fail to load. Running an import through `loadstring`
would hand whoever wrote it arbitrary code execution inside your client.

The string also carries a checksum, so a half-copied paste is caught before it is
merged into your settings rather than after.

## How addons connect to it

Each addon writes one entry into a plain global table:

```lua
_G.nugsSuiteRegistry = _G.nugsSuiteRegistry or {}
_G.nugsSuiteRegistry[ADDON_NAME] = {
    title      = "nugsCastBars",
    version    = NCB.version,
    icon       = "Interface\\AddOns\\nugsCastBars\\icon",
    slash      = "/ncast",
    Open       = function() NCB.ToggleOptions() end,
    SetMinimap = function(shown) ... end,          -- optional
    GetDB      = function() return theDB, theDefaults end,
    GetCharDB  = function() return theCharDB, theCharDefaults end,
    exclude     = { minimapAngle = true },         -- optional, never exported
    excludeChar = { learned = true },              -- optional, never exported
}
```

A global rather than a call into nugsSuite, because a global is free of load order:
whichever side loads first, the table is already there, and neither addon has to
exist for the other to work.

**Registration is optional.** An addon that has not been taught to register is
still listed and still opens, through its slash command. Registering only buys the
extras - settings export, and folding its minimap button in.

## Requirements

Retail World of Warcraft. No libraries, no dependencies, no other nugs addon
required - the suite is perfectly happy on its own, it just has less to list.

## Checks

Every push runs static analysis over the Lua in this repo, and the same checks run
locally before a release. To run them yourself:

```
npm install
npm test
```

Each check exists because of a bug that got as far as a build, and each script says
which one at the top of the file:

| | |
|---|---|
| `check.js` | every file parses |
| `fwdref.js` | a name used above the `local` that declares it - which silently reads a nil global |
| `selfref.js` | `local x = f(function() ... x ... end)`, where the closure captures nil rather than `x` |
| `wowcheck.js` | taint, secret values, and the other WoW-specific ways Lua that looks fine still breaks |
| `globalwrite.js` | assignments that never declared a local - advisory, since SavedVariables have to be globals |

Two more run before release but are not in this repo, because they need a copy of
Ketho's WoW API annotations: a check that no call has been moved or removed in the
current patch, and a full `lua-language-server` pass.

---

Developed by nugs. (c) 2026 nugs. All Rights Reserved.
