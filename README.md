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
