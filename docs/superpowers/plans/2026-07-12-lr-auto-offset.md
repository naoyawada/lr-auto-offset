# lr-auto-offset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Lightroom Classic plugin that, in one click, applies Auto Tone to all selected photos and then adds a user-chosen relative exposure offset (default +0.5 stop) on top of each photo's Auto result.

**Architecture:** A `.lrplugin` folder of small Lua modules. Pure logic (input validation, summary text) lives in `Helpers.lua` with no SDK imports so it is unit-testable with plain `lua`. SDK-bound code is split into `Dialog.lua` (offset prompt + preference persistence), `DevelopLogic.lua` (per-photo Auto Tone + relative exposure), and `AutoOffsetMenuItem.lua` (menu entry point orchestrating selection → dialog → progress loop → summary).

**Tech Stack:** Lua 5.x, Adobe Lightroom Classic SDK (LrApplication, LrDialogs, LrView, LrBinding, LrPrefs, LrTasks, LrProgressScope). Plain `lua` CLI for helper tests.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-12-lr-auto-offset-design.md`
- Plugin folder name: `auto-offset.lrplugin` (exact)
- Toolkit identifier: `com.naoyawada.lrautooffset` (exact)
- Plugin display name / dialog titles: `Auto Tone + Exposure Offset`
- Menu item title: `Auto Tone + Exposure Offset…` (with trailing ellipsis character)
- Offset bounds: −5.0 to +5.0 stops inclusive; first-run default +0.5
- `Helpers.lua` must contain NO `import` calls (pure Lua) — it is loaded both by Lightroom and by the CLI test runner
- Lightroom SDK code cannot run outside Lightroom: every task that touches SDK files ends with a manual verification step inside Lightroom Classic
- All catalog changes go through `catalog:withWriteAccessDo` with a per-photo transaction named `Auto Tone + Exposure Offset` (one undo step per photo)
- Commit after every task

---

### Task 1: Repo scaffolding + pure helpers (TDD)

**Files:**
- Create: `auto-offset.lrplugin/Helpers.lua`
- Create: `tests/test_helpers.lua`
- Create: `.gitignore`

**Interfaces:**
- Consumes: nothing (first task)
- Produces:
  - `Helpers.parseOffset(text) -> number | nil, string` — parses user input; returns the numeric offset, or `nil` plus a human-readable error message when invalid or out of bounds
  - `Helpers.formatSummary(processed, skipped) -> string` — e.g. `"42 photos processed"`, `"1 photo processed"`, `"40 photos processed, 2 skipped"`
  - `Helpers.MIN_OFFSET = -5.0`, `Helpers.MAX_OFFSET = 5.0`

- [ ] **Step 1: Install Lua interpreter (not currently installed)**

Run: `brew install lua`
Verify: `lua -v` prints a version string (e.g. `Lua 5.4.x`)

- [ ] **Step 2: Write the failing test**

Create `tests/test_helpers.lua`:

```lua
-- Run from the repo root: lua tests/test_helpers.lua
package.path = "auto-offset.lrplugin/?.lua;" .. package.path
local Helpers = require "Helpers"

local failures = 0
local function check(label, got, expected)
    if got ~= expected then
        failures = failures + 1
        print(string.format("FAIL %s: expected %s, got %s",
            label, tostring(expected), tostring(got)))
    else
        print("ok   " .. label)
    end
end

-- parseOffset: valid input
check("parses positive", Helpers.parseOffset("0.5"), 0.5)
check("parses negative", Helpers.parseOffset("-0.3"), -0.3)
check("parses integer", Helpers.parseOffset("1"), 1)
check("parses with leading plus", Helpers.parseOffset("+0.5"), 0.5)
check("parses bound min", Helpers.parseOffset("-5"), -5)
check("parses bound max", Helpers.parseOffset("5"), 5)
check("parses zero", Helpers.parseOffset("0"), 0)

-- parseOffset: invalid input returns nil + message
local n, err = Helpers.parseOffset("abc")
check("rejects text", n, nil)
check("text has error message", type(err), "string")

local n2, err2 = Helpers.parseOffset("6")
check("rejects above max", n2, nil)
check("above-max has error message", type(err2), "string")

local n3 = Helpers.parseOffset("-5.1")
check("rejects below min", n3, nil)

local n4 = Helpers.parseOffset("")
check("rejects empty string", n4, nil)

local n5 = Helpers.parseOffset(nil)
check("rejects nil", n5, nil)

-- formatSummary
check("plural summary", Helpers.formatSummary(42, 0), "42 photos processed")
check("singular summary", Helpers.formatSummary(1, 0), "1 photo processed")
check("summary with skipped", Helpers.formatSummary(40, 2), "40 photos processed, 2 skipped")
check("zero processed", Helpers.formatSummary(0, 3), "0 photos processed, 3 skipped")

if failures > 0 then
    print(failures .. " test(s) failed")
    os.exit(1)
end
print("All tests passed")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd /Users/naoyawada/Documents/GitHub/lr-auto-offset && lua tests/test_helpers.lua`
Expected: error — `module 'Helpers' not found`

- [ ] **Step 4: Write the implementation**

Create `auto-offset.lrplugin/Helpers.lua`:

```lua
-- Pure Lua helpers — no Lightroom SDK imports. Loaded by both the plugin
-- (inside Lightroom) and the CLI test runner (tests/test_helpers.lua).
local Helpers = {}

Helpers.MIN_OFFSET = -5.0
Helpers.MAX_OFFSET = 5.0

-- Parses user input into an exposure offset in stops.
-- Returns the number on success, or nil plus an error message.
function Helpers.parseOffset(text)
    local n = tonumber(text)
    if n == nil then
        return nil, "Enter a number of stops, e.g. 0.5 or -0.3"
    end
    if n < Helpers.MIN_OFFSET or n > Helpers.MAX_OFFSET then
        return nil, string.format(
            "Offset must be between %.1f and %.1f stops",
            Helpers.MIN_OFFSET, Helpers.MAX_OFFSET)
    end
    return n
end

-- Builds the end-of-run summary line, e.g. "40 photos processed, 2 skipped".
function Helpers.formatSummary(processed, skipped)
    local summary = string.format("%d photo%s processed",
        processed, processed == 1 and "" or "s")
    if skipped > 0 then
        summary = summary .. string.format(", %d skipped", skipped)
    end
    return summary
end

return Helpers
```

Note: `tonumber("+0.5")` returns `0.5` in stock Lua — no special handling needed for a leading plus.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd /Users/naoyawada/Documents/GitHub/lr-auto-offset && lua tests/test_helpers.lua`
Expected: every line starts with `ok`, final line `All tests passed`, exit code 0

- [ ] **Step 6: Add .gitignore**

Create `.gitignore`:

```
.DS_Store
```

- [ ] **Step 7: Commit**

```bash
git add .gitignore auto-offset.lrplugin/Helpers.lua tests/test_helpers.lua
git commit -m "feat: pure helpers for offset parsing and run summary"
```

---

### Task 2: Plugin manifest + smoke-test menu item

**Files:**
- Create: `auto-offset.lrplugin/Info.lua`
- Create: `auto-offset.lrplugin/AutoOffsetMenuItem.lua` (stub — replaced in Task 4)

**Interfaces:**
- Consumes: nothing
- Produces: an installable plugin whose menu item appears at `Library > Plug-in Extras > Auto Tone + Exposure Offset…`. `Info.lua` is final after this task; `AutoOffsetMenuItem.lua` is a temporary stub proving the plugin loads and can read the photo selection.

- [ ] **Step 1: Write the manifest**

Create `auto-offset.lrplugin/Info.lua`:

```lua
return {
    LrSdkVersion = 10.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'com.naoyawada.lrautooffset',
    LrPluginName = 'Auto Tone + Exposure Offset',
    LrLibraryMenuItems = {
        {
            title = 'Auto Tone + Exposure Offset…',
            file = 'AutoOffsetMenuItem.lua',
        },
    },
    VERSION = { major = 0, minor = 1, revision = 0 },
}
```

- [ ] **Step 2: Write the stub menu item**

Create `auto-offset.lrplugin/AutoOffsetMenuItem.lua`:

```lua
-- Temporary smoke-test stub — replaced with the real flow in Task 4.
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()
    LrDialogs.message('Auto Tone + Exposure Offset',
        string.format('Plugin loaded. %d photo(s) selected.', #photos), 'info')
end)
```

- [ ] **Step 3: Manual verification in Lightroom Classic**

1. Open Lightroom Classic → `File > Plug-in Manager… > Add`
2. Select `/Users/naoyawada/Documents/GitHub/lr-auto-offset/auto-offset.lrplugin`
3. Expected: plugin appears in the left list as **Auto Tone + Exposure Offset** with a green/enabled status and no load errors
4. In Library, select 3 photos → `Library > Plug-in Extras > Auto Tone + Exposure Offset…`
5. Expected: dialog saying `Plugin loaded. 3 photo(s) selected.`

If the plugin fails to load, the Plug-in Manager shows the Lua error — fix and click `Reload Plug-in` (no restart needed).

- [ ] **Step 4: Commit**

```bash
git add auto-offset.lrplugin/Info.lua auto-offset.lrplugin/AutoOffsetMenuItem.lua
git commit -m "feat: plugin manifest and smoke-test menu item"
```

---

### Task 3: Offset dialog with preference persistence

**Files:**
- Create: `auto-offset.lrplugin/Dialog.lua`
- Modify: `auto-offset.lrplugin/AutoOffsetMenuItem.lua` (extend stub to exercise the dialog)

**Interfaces:**
- Consumes: `Helpers.parseOffset(text) -> number | nil, string` (Task 1)
- Produces: `Dialog.askForOffset() -> number | nil` — shows a modal dialog with one text field pre-filled from plugin prefs (first run `0.5`); returns the validated offset in stops, or `nil` if the user cancels. On success, persists the value to `LrPrefs.prefsForPlugin().lastOffset`. Re-prompts on invalid input (never returns an invalid number). Must be called from within an async task.

- [ ] **Step 1: Write Dialog.lua**

Create `auto-offset.lrplugin/Dialog.lua`:

```lua
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPrefs = import 'LrPrefs'
local LrView = import 'LrView'

local Helpers = require 'Helpers'

local Dialog = {}

-- Shows the offset dialog. Returns the validated offset in stops,
-- or nil if the user cancels. Persists the last-used value in plugin prefs.
function Dialog.askForOffset()
    local prefs = LrPrefs.prefsForPlugin()
    local currentText = tostring(prefs.lastOffset or 0.5)

    while true do
        local enteredText = nil

        LrFunctionContext.callWithContext('autoOffsetDialog', function(context)
            local f = LrView.osFactory()
            local props = LrBinding.makePropertyTable(context)
            props.offsetText = currentText

            local contents = f:row {
                spacing = f:label_spacing(),
                bind_to_object = props,
                f:static_text { title = 'Exposure offset (stops):' },
                f:edit_field {
                    value = LrView.bind 'offsetText',
                    width_in_chars = 6,
                    immediate = true,
                },
            }

            local result = LrDialogs.presentModalDialog {
                title = 'Auto Tone + Exposure Offset',
                contents = contents,
                actionVerb = 'Apply',
            }

            if result == 'ok' then
                enteredText = props.offsetText
            end
        end)

        if enteredText == nil then
            return nil -- user canceled
        end

        local offset, err = Helpers.parseOffset(enteredText)
        if offset then
            prefs.lastOffset = offset
            return offset
        end

        currentText = enteredText -- keep their input so they can correct it
        LrDialogs.message('Invalid offset', err, 'warning')
    end
end

return Dialog
```

- [ ] **Step 2: Wire the dialog into the stub menu item**

Replace the body of `auto-offset.lrplugin/AutoOffsetMenuItem.lua` with:

```lua
-- Temporary smoke-test stub — replaced with the real flow in Task 4.
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'

local Dialog = require 'Dialog'

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()

    local offset = Dialog.askForOffset()
    if offset == nil then
        return
    end

    LrDialogs.message('Auto Tone + Exposure Offset',
        string.format('Would apply Auto Tone %+.2f stops to %d photo(s).',
            offset, #photos), 'info')
end)
```

- [ ] **Step 3: Manual verification in Lightroom Classic**

1. Plug-in Manager → select the plugin → `Reload Plug-in`
2. Run the menu item. Expected: dialog titled `Auto Tone + Exposure Offset`, field pre-filled `0.5`, buttons `Apply` / `Cancel`
3. Enter `abc` → Apply. Expected: warning `Enter a number of stops, e.g. 0.5 or -0.3`, then the dialog reappears with `abc` still in the field
4. Enter `7` → Apply. Expected: warning `Offset must be between -5.0 and 5.0 stops`, dialog reappears
5. Enter `0.75` → Apply. Expected: message `Would apply Auto Tone +0.75 stops to N photo(s).`
6. Run the menu item again. Expected: field pre-filled `0.75` (persistence)
7. Cancel. Expected: nothing happens, no message
8. Quit and reopen Lightroom, run again. Expected: field still pre-filled `0.75`

- [ ] **Step 4: Commit**

```bash
git add auto-offset.lrplugin/Dialog.lua auto-offset.lrplugin/AutoOffsetMenuItem.lua
git commit -m "feat: offset dialog with validation and pref persistence"
```

---

### Task 4: Develop logic + full pipeline

**Files:**
- Create: `auto-offset.lrplugin/DevelopLogic.lua`
- Modify: `auto-offset.lrplugin/AutoOffsetMenuItem.lua` (replace stub with the real flow)

**Interfaces:**
- Consumes:
  - `Dialog.askForOffset() -> number | nil` (Task 3)
  - `Helpers.formatSummary(processed, skipped) -> string` (Task 1)
- Produces: `DevelopLogic.processPhoto(catalog, photo, offset) -> boolean` — applies Auto Tone then a relative exposure offset to one photo inside its own write transaction; returns `true` if processed, `false` if skipped (video/unsupported). Must be called from within an async task.

- [ ] **Step 1: Write DevelopLogic.lua**

Create `auto-offset.lrplugin/DevelopLogic.lua`:

```lua
local LrApplication = import 'LrApplication'

local DevelopLogic = {}

-- The AutoTone flag in a develop preset triggers Lightroom's Auto algorithm
-- (same as the Develop module's Auto button) when the preset is applied.
local autoTonePreset

local function getAutoTonePreset()
    if autoTonePreset == nil then
        autoTonePreset = LrApplication.addDevelopPresetForPlugin(
            _PLUGIN, 'Auto Tone (lr-auto-offset)', { AutoTone = true })
    end
    return autoTonePreset
end

-- Applies Auto Tone then a relative exposure offset (in stops) to one photo.
-- Each photo gets its own named write transaction = one undo step per photo,
-- so a canceled batch leaves already-processed photos individually undoable.
-- Returns true if processed, false if skipped (videos can't take develop settings).
function DevelopLogic.processPhoto(catalog, photo, offset)
    if photo:getRawMetadata('fileFormat') == 'VIDEO' then
        return false
    end

    local status = catalog:withWriteAccessDo('Auto Tone + Exposure Offset', function()
        photo:applyDevelopPreset(getAutoTonePreset(), _PLUGIN)
        if offset ~= 0 then
            photo:quickDevelopAdjustImage('Exposure', offset)
        end
    end, { timeout = 15 })

    return status == 'executed'
end

return DevelopLogic
```

- [ ] **Step 2: Replace the menu item stub with the real flow**

Replace the entire contents of `auto-offset.lrplugin/AutoOffsetMenuItem.lua` with:

```lua
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'

local Dialog = require 'Dialog'
local DevelopLogic = require 'DevelopLogic'
local Helpers = require 'Helpers'

LrFunctionContext.postAsyncTaskWithContext('autoOffset', function(context)
    local catalog = LrApplication.activeCatalog()
    -- getTargetPhotos() falls back to the whole filmstrip when nothing is
    -- selected; getTargetPhoto() is nil in that case, so it is the sentinel.
    local photos = catalog:getTargetPhoto() and catalog:getTargetPhotos() or {}

    if #photos == 0 then
        LrDialogs.message('No photos selected',
            'Select one or more photos in the Library grid, then run this again.',
            'info')
        return
    end

    local offset = Dialog.askForOffset()
    if offset == nil then
        return
    end

    local progress = LrProgressScope {
        title = string.format('Auto Tone %+.2f stops (%d photos)', offset, #photos),
        functionContext = context,
    }
    progress:setCancelable(true)

    local processed, skipped = 0, 0
    for i, photo in ipairs(photos) do
        if progress:isCanceled() then
            break
        end
        local ok, result = LrTasks.pcall(DevelopLogic.processPhoto, catalog, photo, offset)
        if ok and result then
            processed = processed + 1
        else
            skipped = skipped + 1
        end
        progress:setPortionComplete(i, #photos)
        LrTasks.yield()
    end
    progress:done()

    LrDialogs.message('Auto Tone + Exposure Offset',
        Helpers.formatSummary(processed, skipped), 'info')
end)
```

- [ ] **Step 3: Manual verification in Lightroom Classic (core behavior)**

1. Plug-in Manager → `Reload Plug-in`
2. **The key test — offset is relative to Auto:** pick one RAW photo. In Develop, press Reset, then the `Auto` button, and note the Exposure value (call it A). Press Reset again. Back in Library, select that photo, run the plugin with `0.5`. Expected: Develop panel shows Exposure ≈ A + 0.50 and other tone sliders (Contrast, Highlights, Shadows…) have non-zero Auto values
3. Batch: select ~10 RAWs, run with `0.5`. Expected: progress bar in the upper-left activity area; summary `10 photos processed`; spot-check 2 photos as in step 2
4. Deselect everything (Edit > Select None), run. Expected: `No photos selected` message
5. Negative offset: run with `-0.3` on one photo. Expected: exposure = its Auto value − 0.30

- [ ] **Step 4: Manual verification (edge cases)**

1. Mixed selection: select RAWs + a JPEG + a video, run with `0.5`. Expected: summary like `5 photos processed, 1 skipped` (JPEG processed, video skipped); no errors
2. Re-run on already-processed photos with `1.0`. Expected: fresh Auto is applied then +1.0 — final exposure ≈ A + 1.00 (not A + 0.5 + 1.0)
3. Undo granularity: after a batch, select one photo → Edit > Undo (or check History panel). Expected: a history step named `Auto Tone + Exposure Offset` per photo, individually revertible
4. Cancel mid-batch: select 100+ photos, run, click the X on the progress bar. Expected: loop stops; summary reports fewer photos than selected; processed photos keep their settings, the rest are untouched

- [ ] **Step 5: Commit**

```bash
git add auto-offset.lrplugin/DevelopLogic.lua auto-offset.lrplugin/AutoOffsetMenuItem.lua
git commit -m "feat: auto tone + relative exposure pipeline with progress and skip handling"
```

---

### Task 5: README + final checklist run

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: the finished plugin (Tasks 1–4)
- Produces: install/usage documentation for the end user (Naoya's wife)

- [ ] **Step 1: Write README.md**

Create `README.md`:

```markdown
# Auto Tone + Exposure Offset — Lightroom Classic plugin

One-click batch processing: applies Lightroom's **Auto** settings to every
selected photo, then adds a fixed exposure offset (e.g. **+0.5 stop**) on
top of whatever Auto chose for each photo. The offset is relative, so every
photo ends up at *its own* Auto exposure plus your offset — exactly like
pressing Auto and nudging the exposure slider by hand, but for the whole
selection at once.

Everything is a normal non-destructive develop edit: each photo gets one
history step that can be undone or reset individually.

## Install (one time)

1. Open Lightroom Classic
2. `File > Plug-in Manager… > Add`
3. Select the `auto-offset.lrplugin` folder from this repo
4. Done — no restart needed

## Use

1. In the **Library** grid, select the photos to process
2. `Library > Plug-in Extras > Auto Tone + Exposure Offset…`
3. Enter the offset in stops (`0.5`, `-0.3`, …) — it remembers your last value
4. Click **Apply** and watch the progress bar (cancelable)

Videos in the selection are skipped automatically. Photos that already have
edits are re-processed: Auto overwrites the tone sliders, then the offset is
applied — undo/History has your back if that wasn't what you wanted.

## Development

Pure-Lua helpers are unit tested outside Lightroom:

    lua tests/test_helpers.lua

Everything else is Lightroom SDK code, verified manually — see
`docs/superpowers/plans/2026-07-12-lr-auto-offset.md` for the checklist.
```

- [ ] **Step 2: Run the full manual test checklist once more, end to end**

With the final code (no stubs), verify the complete list from the spec:

1. Batch of RAWs: each photo's exposure = its Auto value + offset (spot-check via Develop panel)
2. Mixed selection: JPEG processed, video skipped and counted in summary
3. Zero selection: friendly message
4. Negative offset works
5. Invalid input (`abc`, `7`) rejected with re-prompt
6. Last-used offset persists across a Lightroom restart

Run: `cd /Users/naoyawada/Documents/GitHub/lr-auto-offset && lua tests/test_helpers.lua`
Expected: `All tests passed`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README with install and usage instructions"
```
