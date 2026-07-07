-- ButterCut QA Dump
-- Imports a ButterCut-exported timeline (FCPXML or FCP7 XML) into a scratch
-- project and dumps what Resolve actually built as JSON, for the ButterCut
-- editor round-trip QA harness (qa/editor-roundtrip.md in the ButterCut repo).
--
-- Runs INSIDE Resolve (Workspace > Scripts > ButterCut QA Dump) so it works on
-- both the free edition and Studio, regardless of the external-scripting pref.
--
-- Contract:
--   reads  /tmp/buttercut_qa_resolve_job.lua   -- written by the harness:
--            return { xml_path = "/abs/path.xml", report_path = "/abs/report.json" }
--   writes report_path (JSON) -- always, even on failure (ok=false + error)
--
-- Scratch projects are named buttercut-qa-<epoch>; previous buttercut-qa-*
-- projects are deleted on each run. No other projects are ever touched.

local JOB_PATH = "/tmp/buttercut_qa_resolve_job.lua"
local FALLBACK_REPORT = "/tmp/buttercut_qa_resolve_report.json"

-- ---------- tiny JSON emitter ----------
local function json_escape(s)
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
  s = s:gsub("%c", function(c) return string.format("\\u%04x", c:byte()) end)
  return s
end

local function to_json(v, indent)
  indent = indent or ""
  local t = type(v)
  if v == nil then return "null" end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v == math.floor(v) and math.abs(v) < 2^52 then return string.format("%d", v) end
    return string.format("%.6f", v)
  end
  if t == "boolean" then return tostring(v) end
  if t == "string" then return '"' .. json_escape(v) .. '"' end
  if t == "table" then
    local next_indent = indent .. "  "
    if #v > 0 or next(v) == nil then -- array (or empty)
      local parts = {}
      for _, item in ipairs(v) do parts[#parts + 1] = next_indent .. to_json(item, next_indent) end
      if #parts == 0 then return "[]" end
      return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = next_indent .. '"' .. json_escape(tostring(k)) .. '": ' .. to_json(v[k], next_indent)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  end
  return '"' .. json_escape(tostring(v)) .. '"'
end

-- Written to a temp file then renamed, so the harness's existence poll never
-- reads a half-written report.
local function write_report(path, report)
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then return false end
  f:write(to_json(report), "\n")
  f:close()
  return os.rename(tmp, path) == true
end

-- ---------- safe getters ----------
local function safe(fn)
  local ok, result = pcall(fn)
  if ok then return result end
  return nil
end

-- ---------- main ----------
local report = { ok = false, script = "ButterCut QA Dump", ran_at = os.date("%Y-%m-%dT%H:%M:%S") }
local report_path = FALLBACK_REPORT

local function fail(msg)
  report.ok = false
  report.error = msg
  write_report(report_path, report)
  print("ButterCut QA Dump FAILED: " .. msg)
end

local job_chunk = loadfile(JOB_PATH)
if not job_chunk then return fail("no job file at " .. JOB_PATH) end
local job = job_chunk()
if type(job) ~= "table" or not job.xml_path then return fail("job file malformed (need xml_path)") end
report_path = job.report_path or FALLBACK_REPORT
report.job = { xml_path = job.xml_path, report_path = report_path }

local rv = resolve or (bmd and bmd.scriptapp("Resolve"))
if not rv then return fail("no resolve object (run from Workspace > Scripts inside DaVinci Resolve)") end

report.product = safe(function() return rv:GetProductName() end)
report.resolve_version = safe(function() return rv:GetVersionString() end)

local pm = rv:GetProjectManager()
if not pm then return fail("GetProjectManager returned nil") end

-- clean up previous QA scratch projects (only ours: buttercut-qa-*)
local deleted = {}
local existing = safe(function() return pm:GetProjectListInCurrentFolder() end) or {}
for _, name in ipairs(existing) do
  if type(name) == "string" and name:find("^buttercut%-qa%-") then
    if safe(function() return pm:DeleteProject(name) end) then deleted[#deleted + 1] = name end
  end
end
report.deleted_previous_qa_projects = deleted

local project_name = "buttercut-qa-" .. tostring(os.time())
local project = pm:CreateProject(project_name)
if not project then return fail("CreateProject failed for " .. project_name) end
report.project = project_name

local mp = project:GetMediaPool()
if not mp then return fail("GetMediaPool returned nil") end

local timeline = mp:ImportTimelineFromFile(job.xml_path, {
  timelineName = job.timeline_name or "buttercut-qa-timeline",
  importSourceClips = true,
})
if not timeline then return fail("ImportTimelineFromFile returned nil for " .. job.xml_path) end

report.timeline = {
  name = safe(function() return timeline:GetName() end),
  start_frame = safe(function() return timeline:GetStartFrame() end),
  end_frame = safe(function() return timeline:GetEndFrame() end),
  start_timecode = safe(function() return timeline:GetStartTimecode() end),
  frame_rate = safe(function() return timeline:GetSetting("timelineFrameRate") end),
  width = safe(function() return timeline:GetSetting("timelineResolutionWidth") end),
  height = safe(function() return timeline:GetSetting("timelineResolutionHeight") end),
}

local function dump_track_items(track_type)
  local tracks = {}
  local count = safe(function() return timeline:GetTrackCount(track_type) end) or 0
  for ti = 1, count do
    local items = safe(function() return timeline:GetItemListInTrack(track_type, ti) end) or {}
    local dumped = {}
    for _, item in ipairs(items) do
      local entry = {
        name = safe(function() return item:GetName() end),
        start = safe(function() return item:GetStart() end),
        ["end"] = safe(function() return item:GetEnd() end),
        duration = safe(function() return item:GetDuration() end),
        source_start_frame = safe(function() return item:GetSourceStartFrame() end),
        source_end_frame = safe(function() return item:GetSourceEndFrame() end),
        left_offset = safe(function() return item:GetLeftOffset() end),
      }
      local mpi = safe(function() return item:GetMediaPoolItem() end)
      if mpi then
        entry.media_path = safe(function() return mpi:GetClipProperty("File Path") end)
        entry.media_fps = safe(function() return mpi:GetClipProperty("FPS") end)
        entry.media_type = safe(function() return mpi:GetClipProperty("Type") end)
        entry.media_duration = safe(function() return mpi:GetClipProperty("Duration") end)
      end
      dumped[#dumped + 1] = entry
    end
    tracks[#tracks + 1] = { index = ti, name = safe(function() return timeline:GetTrackName(track_type, ti) end), items = dumped }
  end
  return tracks
end

report.video_tracks = dump_track_items("video")
report.audio_tracks = dump_track_items("audio")
report.subtitle_tracks = dump_track_items("subtitle")

report.ok = true
if not write_report(report_path, report) then
  print("ButterCut QA Dump: could not write report to " .. report_path)
else
  print("ButterCut QA Dump: OK -> " .. report_path)
end
