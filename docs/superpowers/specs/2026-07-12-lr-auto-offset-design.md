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

*(Revised 2026-07-12 after in-Lightroom debugging — see "Field findings"
below for why the original single-transaction relative-adjust design was
unworkable.)*

Two passes over the selection, each SDK call in its own write transaction:

1. **Pass 1 — queue Auto Tone on every photo** via a develop preset carrying
   the `AutoTone` flag (`LrApplication.addDevelopPresetForPlugin` +
   `photo:applyDevelopPreset`). Lightroom writes a `-999999` placeholder
   into `Exposure2012` and computes the real auto values asynchronously in
   the background — queuing all photos first lets those computations run
   concurrently.
2. **Pass 2 — per photo: wait for the placeholder to resolve** into a real
   exposure (polling `photo:getDevelopSettings()`, requesting a thumbnail
   render halfway through the wait to force computation; 10 s timeout →
   photo reported as "left with Auto Tone only"), **then write the exposure
   absolutely**: `photo:applyDevelopSettings({ Exposure2012 = resolvedAuto +
   offset })`. A zero offset skips pass 2's wait-and-write entirely.

The summary reports three outcome buckets: **processed** (Auto + offset
fully applied), **skipped** (strictly untouched — videos, write-gate
failures), and **left with Auto Tone only** (Auto applied but the offset
never written: canceled mid-run, resolution timeout, or write failure).

Because each photo gets two write transactions ("Auto Tone" then "Exposure
Offset"), each photo has **two** develop-history steps rather than the one
originally specified — a deliberate trade forced by the async Auto
computation; both steps are individually undoable.

Progress is reported via `LrProgressScope` (spanning both passes) with
cancellation support. The last-used offset is stored via
`LrPrefs.prefsForPlugin()`.

## Field findings (2026-07-12, Lightroom Classic v13)

Discovered via step-by-step diagnostics on a real catalog; these invalidated
the original mechanism and are worth remembering for any LR plugin work:

- **Auto Tone is asynchronous.** Applying a preset with `AutoTone = true`
  stores `Exposure2012 = -999999` as a "pending" sentinel; the real value
  appears ~1 s later (or when the photo is next rendered). Anything that
  reads or adjusts exposure in the same transaction operates on the
  placeholder and is overwritten when Auto resolves.
- **`quickDevelopAdjustImage("Exposure", n)` does not apply `n` stops.**
  Measured: `+0.5` moved exposure by `+0.01` (≈ n/50), on a clean photo with
  no auto involved — contrary to the SDK documentation. The API was dropped
  entirely in favor of absolute `applyDevelopSettings` writes.
- `photo:requestJpegThumbnail(...)` reliably forces the develop engine to
  compute pending auto settings when idle waiting doesn't.

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
