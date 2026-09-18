# Agent instructions

Lightroom Classic plugin (Lua, LR SDK): applies Lightroom's Auto to every selected photo,
then adds a fixed exposure offset on top of each photo's own Auto result. Built for a real
RAW workflow — the user's wife uses it.

Install and usage: `README.md`. Plugin source lives in `auto-offset.lrplugin/`.

**Status: SHIPPED 2026-07-12** (PR #1, merged). Verified against real Lightroom Classic
v13: single photo auto +0.62 + offset 1.0 → +1.62 exactly; batch of 5 correct.

## Testing

Pure-Lua helpers run outside Lightroom:

```bash
lua tests/test_helpers.lua
```

Everything touching the SDK is verified manually in Lightroom — there is no way to unit
test it. The checklist is in `docs/superpowers/plans/2026-07-12-lr-auto-offset.md`.
Don't claim SDK behavior works without an in-app run.

## LR SDK gotchas

All verified empirically in-app, several of them contradicting the SDK docs:

- **Auto Tone is asynchronous.** Applying a preset with `{ AutoTone = true }` writes
  `Exposure2012 = -999999` as a pending placeholder; the real value lands ~1s later.
  Anything that reads or adjusts exposure in the same write transaction operates on the
  placeholder and gets overwritten.
- **`photo:quickDevelopAdjustImage('Exposure', n)` is BROKEN** — it applies roughly `n/50`
  (measured: +0.5 requested → +0.01 actual), contrary to the docs. Never use it. Write
  absolute values with `photo:applyDevelopSettings({ Exposure2012 = value })`.
- **The working pattern is two passes.** Pass 1 queues autos on all photos so they compute
  concurrently. Pass 2 polls `getDevelopSettings()` per photo until `Exposure2012` is sane
  (`|v| < 100`), then absolute-writes auto + offset. If idle polling stalls,
  `photo:requestJpegThumbnail()` forces the develop engine to compute pending autos.
- **`catalog:getTargetPhotos()` returns the ENTIRE filmstrip when the selection is empty.**
  Guard with `catalog:getTargetPhoto() and catalog:getTargetPhotos() or {}` — otherwise a
  stray click reprocesses the whole catalog.
- `catalog:withWriteAccessDo` with a `{ timeout }` table **returns a status string**
  (`'executed'`) instead of throwing on lock timeout. Check the return value.
- Use `LrFunctionContext.postAsyncTaskWithContext` and pass `functionContext` to
  `LrProgressScope`, or progress bars orphan. Use `LrTasks.pcall`, not plain `pcall`,
  around anything that yields.
- **Lightroom embeds Lua 5.1**, where `tonumber("nan")` returns NaN (5.3+ returns nil).
  Guard with `n ~= n`.
- **Plug-in Manager "Reload Plug-in" does not pick up newly added files.** Adding a new
  `.lua` file needs a full Lightroom restart; edits to existing files reload fine.

## Notes for Claude

- Every change is a non-destructive develop edit producing one undoable history step per
  photo. Keep it that way.
- Videos in a selection must be skipped, not errored on.
- This runs on someone's real photo library. Data safety over cleverness.
