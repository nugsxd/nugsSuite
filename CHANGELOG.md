# Changelog

Bump `## Version:` in `nugsSuite.toc` with every change so the in-game header
reflects the loaded build.

## 0.2.7

- **Fixed: the roster pushed the minimap checkbox out of the bottom of the window.**
  The list was as tall as the catalog and the footer hung off its bottom edge, so
  every addon added to the catalog shoved the checkbox and the hint further down -
  and the seventh shoved them clean outside. The footer is pinned to the window now
  and the roster scrolls in what is left, with a bar you can grab, so the catalog can
  keep growing without the window having to.
- The window is a little taller, since the roster is what it is for.
- **nugsCombatText joins the roster**, marked coming soon: floating combat text with
  ability icons, per-school colours and crit styling, built against what the 12.0
  client will actually hand an addon.
- **Coming soon now means coming soon even if you have a copy.** The flag used to be
  suppressed once an addon was installed, so the author and testers - the people best
  placed to notice a stale one - were the only ones who never saw it. An unreleased
  addon is also out of the installed count now, since a pre-release build sitting on
  one machine should not claim a total nobody else can reach.
- **The hub closes when a fight starts**, and does not come back on its own. There is
  no anchor here and nothing on screen to get wrong - it closes for consistency with
  the other four, since a hub that stayed open while everything it launches closed
  would be the odd one out.
- The roster and the right-click menu follow the renamed commands: nugsRaidReady is
  `/nrr`, nugsCastBars is `/ncast`, and nugsComboBar has taken `/ncb`.

## 0.2.6 — 2026-07-31

- **`/nugs cpu`.** Prints memory and, when Blizzard's script profiler is running, CPU
  time for every installed nugs addon, plus a total for all addons so each number can
  be read as a share rather than a raw figure that grows with session length. Added
  because "is this heavy?" deserves a measurement rather than an assurance.

## 0.2.5 — 2026-07-30

- **nugsDeathNote joins the roster.** A raid death log: it records who died on every
  pull and lets the officers write down why, then hands the night to a desktop app
  so a player's history builds up over a tier. Marked coming soon until it ships.

## 0.2.4 — 2026-07-30

- **Disable, next to Open.** Enabling an addon from the roster without being able to
  switch one off was half a control.
- A disabled addon keeps running until you reload, which is exactly why the card now
  reads **off after reload** and the button flips to Enable. Without that, pressing
  Disable looked like it had done nothing at all - the client still reports the addon
  as loaded for the rest of the session, because it is.
- So the click is undoable on the spot: press Enable again before reloading and
  nothing happened.
- Nothing here can switch off nugsSuite itself. The suite is not in its own catalog,
  so it never gets a card, and there is no way to disable the window you are
  standing in.

## 0.2.3 — 2026-07-30

- The Addons roster is **ordered** now instead of following the order the catalog
  happens to be written in. Installed and running first, then installed but switched
  off, then not installed, with coming-soon last - and alphabetical inside each of
  those bands.
- Coming soon sits below merely-not-installed on purpose: "not installed" is
  something you can act on right now, "coming soon" is not, so it belongs furthest
  from the things you can actually click.
- The minimap right-click menu picks the same order up for free, since the sort
  happens where the roster is built rather than in the window.

## 0.2.2 — 2026-07-30

- CurseForge project id (**1630098**) recorded in the .toc, so addon managers can
  tie an installed copy back to the project and offer updates.
- Dropped the placeholder note that stood in for it.

## 0.2.1 — 2026-07-28

- The About page now carries nugs' own words rather than a placeholder: 22 years
  in the game, why addons have always mattered, and what these are trying to get
  right that others miss.
- Contact details added - CurseForge **nugsxD**, Discord **nug.s**.
- The Commands block was folded into a single "/nugs help" pointer. The page is the
  front of the suite; a command reference in the middle of it undercut that.
- The contact line is anchored to the bottom of the panel rather than a fixed
  offset, so a longer bio can never push text into it.

## 0.2.0 — 2026-07-28

- **An About page with the nugs logo on it.** The mark sits beside the text rather
  than above it - it is square, and stacking would have spent a third of the panel
  before a word was read.
- About is now the first tab, but it is only the landing tab **once**. The first
  time you open the hub you get the front page; every open after that lands on
  Addons. A launcher that opens on its own about page every time costs a click on
  the thing you opened it for.
- The page now says who builds these, why each one exists, and how they are built -
  no external libraries, no dependency on each other, each window doing one job.
- The logo ships as `logo.blp`, generated from the source PNG by
  `nugsSuite-art/logo.js`. WoW will not load a PNG from an addon folder; the source
  is also 1254x1254, which is not a power of two and cannot produce a mipmap chain.
  It is resampled to 256 with the flat black backdrop keyed out, so the mark's glow
  fades into the panel instead of sitting on a black square.
- This adds about 350KB to the addon, which is the price of an uncompressed BLP at
  256 square. 512 was tried and dropped: four times the size for something drawn at
  156 pixels.

## 0.1.5 — 2026-07-28

- nugsAuras is listed as **coming soon** rather than "not installed". It is in the
  roster because the roster is what tells you what the suite is, but it has not
  been released - and showing it the same way as an addon you simply have not
  installed would send people looking for a download that does not exist.
- Anyone who already has a build of it sees a normal entry, so the flag never gets
  in the way of testing.
- An unreleased addon no longer counts towards the minimap tooltip's total, so
  somebody who owns every published nugs addon is not told they are missing one.

## 0.1.4 — 2026-07-28

Found in game: the import was the half of the profile feature that did not work.

- **Importing a profile left you with a blend of both setups instead of the
  sender's.** A profile is a diff against defaults, so a setting the sender never
  touched is absent from the string; the import merged what was there and left
  your own value standing for every key they had left alone. The more you had
  customised, the less the import appeared to do. The addon is now reset to its
  defaults first and the profile laid on top, so the result is exactly the
  sender's state and is the same no matter what you had before.
- This is the same flaw that was fixed for Undo in 0.1.1, on the other side of the
  same function. Undo was given a full snapshot and replace semantics; import was
  left merging. The fix should have been applied to both at once.
- Keys a profile never carries - measured caches, your minimap angle, one-shot
  migration flags - are lifted out and put back around the reset, so an import can
  never clear local data on the strength of somebody else's settings. Restoring a
  backup deliberately does not do this: a backup is your own full snapshot and
  already holds the true value of every key.
- The confirmation now says plainly that your settings are replaced rather than
  merged, since that is a bigger promise than the old wording implied.

## 0.1.3 — 2026-07-28

- The roster lists RaidReady as **nugsRaidReady**, matching the addon's own title.
- The minimap button no longer shows a sliver of the world between the icon and the
  tracking border. The border's hole is slightly wider than the icon was, leaving a
  thin see-through ring; there is now a dark disc behind the icon, and the icon
  itself went from 19 to 21 pixels.

## 0.1.2 — 2026-07-28

- The roster asks whether an addon is loaded by index rather than by folder name.
  Querying a folder that is not installed was the exact thing the whole-list scan
  was written to avoid, and the old line did it anyway.
- Corrected the tooltip on an unregistered addon. It claimed those settings could
  not be exported; they can, via the saved-variable names in the catalog - just
  whole rather than as a diff.

## 0.1.1 — 2026-07-28

Fixes found by review before this ever loaded in game.

- **Importing a profile silently applied nothing** and wrote a junk `__r` key into
  the saved variables, for any addon whose defaults were absent or empty. Export
  wraps a whole table in a replace marker in those cases, and the merge only ever
  looked for that marker one level down, so a marker sitting at the top of a block
  was treated as an ordinary key. This was live, not theoretical: nugsComboBar's
  per-character defaults are an empty table. Now unwrapped on the way in.
- **"Undo last import" could not actually undo.** The backup was a diff against
  defaults, so any setting that had been at its default before the import and was
  changed by it was, by definition, not recorded - and survived the undo. Backups
  are now full snapshots and are restored by replacement rather than merge.
- The export box was only read-only against typing. Backspace, delete and cut raise
  no character event, so they could quietly truncate a string on its way to the
  clipboard, to fail a checksum at the other end. Guarded on text change instead.
- Neither text box scrolled - no wheel handler, and a fixed-height scroll child - so
  only the first few lines of a profile string were ever reachable. Both now scroll,
  and the child is sized from the text it holds.
- Importing no longer takes the per-character setting from the *export* checkbox.
  What arrives in somebody else's string was already their decision.
- Icon: the family **N** with four small pips at the corners, in the same
  storm-blue-on-dark palette as the rest of the set. The N was left off the first
  cut on the theory that the container should not wear the family letter; alongside
  the other four icons it simply read as not belonging, so it went back on.
- The pips are small and cornered because the minimap button masks the icon to a
  circle: anything past a radius of about 0.42 from the centre loses its corners.
  The first composition measured 0.55 and would have had every tile clipped in the
  one place the icon is seen most.

## 0.1.0 — 2026-07-28

First release.

- **The hub.** One minimap button for the whole family. Left click opens a roster
  of every nugs addon with its version and an Open button; right click skips the
  window and drops a menu straight to any of them.
- Addons you do not have installed stay in the roster, greyed, with a line on what
  they do. Anyone handed one of these can see the rest exists.
- Addons that are installed but switched off show an **Enable** button rather than
  being treated as missing.
- **One minimap button.** A single checkbox hides every other nugs minimap button
  and leaves this one. Unticking it puts them back. An addon new enough to register
  is hidden live; an older one has its saved flag set and takes hold on the next
  load, which is prompted for rather than done silently.
- **Profile strings.** Export every nugs setting you have as one string and paste
  it to a guildmate or into another character's client.
  - Exported as a **diff against each addon's defaults**, so the string stays short
    and an import only moves the settings the sender actually chose.
  - Collections whose default is empty - spell lists, priority orders - are carried
    whole and replace rather than merge, because the union of two spell lists is
    not what anybody means by importing one.
  - Machine-written caches, minimap angles and first-launch prompt answers are
    never exported.
  - The current settings are backed up automatically before every import, and one
    button puts them back.
- The import reader is a **hand-written parser rather than `loadstring`**. Import
  strings come from other players, and running one as Lua would hand whoever wrote
  it arbitrary code execution inside the client. The parser accepts only `nil`,
  booleans, numbers, quoted strings and tables of those, so a hostile string can at
  worst fail to load. A checksum catches a half-copied paste before it is merged
  rather than after.
- Addons connect through one plain global table, so registration is free of load
  order and neither side has to exist for the other to work. An addon that has not
  been taught to register is still listed and still opens, via its slash command.
- Icon: four tiles in a two-by-two grid, in the family's storm-blue-on-dark palette.
  Replaced in 0.1.1 - see above.
