# lr-auto-offset — Auto Tone + Exposure Offset plugin for Lightroom Classic

**Date:** 2026-07-12
**Status:** Approved design, pre-implementation

## Problem

The primary user (Naoya's wife) processes batches of RAW photos in Lightroom
Classic with a two-step manual routine: apply Lightroom's **Auto** settings,
then add a fixed relative exposure bump (typically **+0.5 stop**) on top of
whatever Auto chose. Because Auto produces a different exposure value per
photo, the final exposure is variable — the constant is the *offset*, not the
absolute value. Lightroom's native Quick Develop panel can almost do this
(Auto Tone + relative exposure arrows) but only in ⅓- or 1-stop increments,
and it takes several clicks per batch.

## Solution

A Lightroom Classic plugin (Lua, Lightroom SDK) that performs both steps in
one click on the current photo selection.

## User flow

1. User selects any number of photos in the Library grid.
2. Clicks `Library > Plug-in Extras > Auto Tone + Exposure Offset…`.
3. A small dialog shows one numeric field, **"Exposure offset (stops)"**,
   pre-filled with the last-used value (first run defaults to **+0.5**).
   OK / Cancel.
4. A progress bar runs while each photo is processed. Large batches stay
   responsive and the operation is cancelable.
5. A brief summary is shown, e.g. `42 photos processed` (with a skipped count
   when applicable).

All adjustments are normal non-destructive develop edits — each photo keeps
its develop history and can be undone or reset individually afterward.

## Behavior decisions (settled with user)

- **Offset is adjustable per run** via the dialog; the last-used value
  persists across sessions (plugin preferences store).
- **Already-edited photos are re-processed without warning**: Auto overwrites
  the tone sliders, then the offset is applied. The tool always yields
  "Auto + offset" regardless of prior state. Develop history protects
  against loss.
- **Non-adjustable items** (videos, files that can't accept develop
  settings) are skipped and counted in the summary.

## How it works internally

Per photo, inside a catalog write transaction (`catalog:withWriteAccessDo`):

1. **Auto Tone** — applied via a develop preset carrying the `AutoTone`
   flag, created with `LrApplication.addDevelopPresetForPlugin` and applied
   with `photo:applyDevelopPreset`. This is the SDK-sanctioned way to
   batch-apply Auto from the Library module; it uses the same algorithm as
   the Develop module's Auto button.
2. **Relative offset** — `photo:quickDevelopAdjustImage("Exposure", offset)`,
   which adjusts exposure *relative* to the photo's current value (i.e., on
   top of what Auto chose) — exactly mirroring the manual workflow.

Progress is reported via `LrProgressScope` with cancellation support. The
last-used offset is stored via `LrPrefs.prefsForPlugin()`.

## Structure

Repo `lr-auto-offset` containing:

```
lr-auto-offset/
├── README.md                      # what it does + install steps (Plug-in Manager)
├── docs/superpowers/specs/        # this design doc
└── auto-offset.lrplugin/
    ├── Info.lua                   # plugin manifest (menu item registration)
    ├── AutoOffsetMenuItem.lua     # entry point: selection check → dialog → run
    ├── Dialog.lua                 # offset-input dialog + validation
    └── DevelopLogic.lua           # per-photo Auto Tone + offset application
```

File boundaries: `Dialog.lua` and the pure helpers (validation, summary
counting) contain no per-photo SDK calls, keeping the testable logic
separated from SDK-bound code.

## Error handling

- **No photos selected** → friendly message asking to select photos first;
  nothing else happens.
- **Offset validation** → must parse as a number within **−5.0 to +5.0**;
  the dialog rejects invalid input with an inline error.
- **Unsupported items** (videos etc.) → skipped, counted, reported in the
  summary (`40 processed, 2 skipped`).
- **Cancel mid-batch** → photos already processed keep their new settings
  (each is independently undoable); remaining photos are untouched.

## Testing

SDK code only runs inside Lightroom, so verification is manual against a
checklist:

- Batch of RAWs: each photo's final exposure equals its Auto value + offset
  (verify via the Develop panel on a few samples).
- Mixed selection (RAW + JPEG + video): JPEGs processed, video skipped and
  reported.
- Zero selection: friendly message, no error.
- Negative offset works.
- Invalid input (text, out-of-range) rejected by the dialog.
- Last-used offset persists across a Lightroom restart.

Pure-Lua helpers (input validation, summary counting) are written as plain
functions so they can be eyeballed or unit-tested outside Lightroom if ever
needed.

## Out of scope (YAGNI)

- Other relative adjustments (contrast, highlights, etc.)
- Presets/multiple saved offsets
- Export or file-output features — everything stays in the catalog
- Lightroom (cloud) support — no plugin API exists
