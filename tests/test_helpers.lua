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

local n6, err6 = Helpers.parseOffset("nan")
check("rejects nan", n6, nil)
check("nan has error message", type(err6), "string")

local n7, err7 = Helpers.parseOffset("NaN")
check("rejects NaN", n7, nil)
check("NaN has error message", type(err7), "string")

-- Lightroom embeds Lua 5.1, where tonumber("nan") yields a real NaN
-- (Lua 5.3+ rejects the string, so exercise the guard with a NaN value).
local n8, err8 = Helpers.parseOffset(0 / 0)
check("rejects NaN value", n8, nil)
check("NaN value has error message", type(err8), "string")

-- isResolvedExposure: true only for real, resolved exposure values
check("resolved zero", Helpers.isResolvedExposure(0), true)
check("resolved negative", Helpers.isResolvedExposure(-0.17), true)
check("resolved positive", Helpers.isResolvedExposure(0.33), true)
check("rejects auto-pending sentinel", Helpers.isResolvedExposure(-999999), false)
check("rejects positive sentinel-scale value", Helpers.isResolvedExposure(999999), false)
check("rejects nil exposure", Helpers.isResolvedExposure(nil), false)
check("rejects NaN exposure", Helpers.isResolvedExposure(0 / 0), false)
check("rejects non-number exposure", Helpers.isResolvedExposure("0.5"), false)

-- formatAutoOnlyNote: appended when photos got Auto Tone but no offset
check("no note when zero", Helpers.formatAutoOnlyNote(0), "")
check("no note when negative", Helpers.formatAutoOnlyNote(-1), "")
check("note for one", Helpers.formatAutoOnlyNote(1), ", 1 left with Auto Tone only")
check("note for several", Helpers.formatAutoOnlyNote(3), ", 3 left with Auto Tone only")

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
