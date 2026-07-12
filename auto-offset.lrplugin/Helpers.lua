-- Pure Lua helpers — no Lightroom SDK imports. Loaded by both the plugin
-- (inside Lightroom) and the CLI test runner (tests/test_helpers.lua).
local Helpers = {}

Helpers.MIN_OFFSET = -5.0
Helpers.MAX_OFFSET = 5.0

-- Parses user input into an exposure offset in stops.
-- Returns the number on success, or nil plus an error message.
function Helpers.parseOffset(text)
    local n = tonumber(text)
    if n == nil or n ~= n then -- n ~= n catches NaN (Lua 5.1 tonumber("nan"))
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
