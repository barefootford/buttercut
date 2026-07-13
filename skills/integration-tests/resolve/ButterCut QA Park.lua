-- ButterCut QA Park
-- Parks the playhead of the current Resolve timeline at a requested timeline
-- frame, for the Tier-2 visual pass of the editor round-trip QA harness
-- (qa/editor-roundtrip.md). Runs INSIDE Resolve (Workspace > Scripts >
-- ButterCut QA Park) so it works on the free edition.
--
-- Contract:
--   reads  /tmp/buttercut_qa_park_job.lua -- written by resolve_park.rb:
--            return { frame = 315, report_path = "/abs/report.json",
--                     timeline_name = "optional -- switch to it first" }
--   writes report_path (JSON) -- always, even on failure (ok=false + error)
--
-- Timecode math is NDF at the nominal integer rate (30 for 29.97, 24 for
-- 23.976). That's exact for the QA timelines because they start at
-- 00:00:00:00 and run well under a minute — no drop-frame labels can occur
-- before the first minute boundary. Don't reuse this on long DF timelines.

local JOB_PATH = "/tmp/buttercut_qa_park_job.lua"
local FALLBACK_REPORT = "/tmp/buttercut_qa_park_report.json"

local function json_escape(s)
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
  return (s:gsub("%c", function(c) return string.format("\\u%04x", c:byte()) end))
end

local function to_json(v)
  local t = type(v)
  if v == nil then return "null" end
  if t == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.6f", v)
  end
  if t == "boolean" then return tostring(v) end
  if t == "string" then return '"' .. json_escape(v) .. '"' end
  if t == "table" then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = '"' .. json_escape(tostring(k)) .. '": ' .. to_json(v[k])
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return '"' .. json_escape(tostring(v)) .. '"'
end

-- temp file + rename so the driver's existence poll never reads a half write
local function write_report(path, report)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return false end
  f:write(to_json(report), "\n")
  f:close()
  return os.rename(tmp, path) == true
end

local function safe(fn)
  local ok, result = pcall(fn)
  if ok then return result end
  return nil
end

local report = { ok = false, script = "ButterCut QA Park" }
local report_path = FALLBACK_REPORT

local function fail(msg)
  report.error = msg
  write_report(report_path, report)
  print("ButterCut QA Park FAILED: " .. msg)
end

local job_chunk = loadfile(JOB_PATH)
if not job_chunk then return fail("no job file at " .. JOB_PATH) end
local job = job_chunk()
if type(job) ~= "table" or type(job.frame) ~= "number" then
  return fail("job file malformed (need frame = <number>)")
end
report_path = job.report_path or FALLBACK_REPORT
report.requested_frame = job.frame

local rv = resolve or (bmd and bmd.scriptapp("Resolve"))
if not rv then return fail("no resolve object (run from Workspace > Scripts inside DaVinci Resolve)") end

local project = rv:GetProjectManager():GetCurrentProject()
if not project then return fail("no current project") end

if job.timeline_name then
  local found = false
  for i = 1, (safe(function() return project:GetTimelineCount() end) or 0) do
    local tl = project:GetTimelineByIndex(i)
    if tl and safe(function() return tl:GetName() end) == job.timeline_name then
      project:SetCurrentTimeline(tl)
      found = true
      break
    end
  end
  if not found then return fail("no timeline named " .. job.timeline_name) end
end

local timeline = project:GetCurrentTimeline()
if not timeline then return fail("no current timeline") end
report.timeline = safe(function() return timeline:GetName() end)

local fps = tonumber(safe(function() return timeline:GetSetting("timelineFrameRate") end)) or 0
if fps <= 0 then return fail("could not read timelineFrameRate") end
local nominal = math.floor(fps + 0.5)
local start_frame = safe(function() return timeline:GetStartFrame() end) or 0

local abs = start_frame + job.frame
local ff = abs % nominal
local total_s = math.floor(abs / nominal)
local tc = string.format("%02d:%02d:%02d:%02d",
  math.floor(total_s / 3600), math.floor(total_s / 60) % 60, total_s % 60, ff)

if not safe(function() return timeline:SetCurrentTimecode(tc) end) then
  return fail("SetCurrentTimecode(" .. tc .. ") failed")
end

report.ok = true
report.fps = fps
report.nominal_fps = nominal
report.start_frame = start_frame
report.tc_set = tc
report.tc_readback = safe(function() return timeline:GetCurrentTimecode() end)
write_report(report_path, report)
print("ButterCut QA Park: frame " .. job.frame .. " -> " .. tc)
