-- Omarchy's default keybinds as data. Loads upstream's bind modules
-- (default/hypr/bindings/*.lua) against a stub `hl` that records every
-- hl.bind instead of configuring Hyprland, once without and once with the
-- preinstalled app binds, and prints JSON:
--   [{ keys, description, layer = "core"|"apps"|"webapps",
--      action = { exec | omarchy | launch | webapp | tui | dispatcher, focus? },
--      locked?, repeating? }, …]
--
--   lua keybinds.lua <OMARCHY_PATH>
local root = assert(arg[1], "usage: keybinds.lua <OMARCHY_PATH>")

-- Lua value → Lua-ish source text, for dispatchers.
local function repr(v)
  if type(v) == "string" then
    return string.format("%q", v)
  elseif type(v) == "table" then
    if v.__dispatch then return v.__dispatch end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = (type(k) == "string" and k .. " = " or "") .. repr(v[k])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
  end
  return tostring(v)
end

local recorded, pending

-- hl: every field is a callable proxy that returns a description of the call.
local function proxy(name)
  return setmetatable({}, {
    __index = function(_, k) return proxy(name .. "." .. k) end,
    __call = function(_, ...)
      local args = table.pack(...)
      local parts = {}
      for i = 1, args.n do parts[i] = repr(args[i]) end
      return { __dispatch = name .. "(" .. table.concat(parts, ", ") .. ")", __name = name, __args = args }
    end,
  })
end

local function record(keys, dispatcher, opts)
  opts = opts or {}
  local action
  if pending and type(pending) == "table" and not pending.__dispatch then
    action = {}
    for _, k in ipairs({ "omarchy", "launch", "webapp", "tui", "focus" }) do action[k] = pending[k] end
  elseif pending and type(pending) == "string" then
    action = { exec = pending }
  elseif type(dispatcher) == "table" and dispatcher.__name == "hl.dsp.exec_cmd" then
    action = { exec = dispatcher.__args[1] }
  elseif type(dispatcher) == "function" then
    action = { dispatcher = "function" }
  else
    action = { dispatcher = repr(dispatcher) }
  end
  pending = nil
  recorded[keys] = {
    keys = keys,
    description = opts.description or "",
    action = action,
    locked = opts.locked or nil,
    repeating = opts.repeating or nil,
  }
end

local function load(preinstalled)
  recorded = {}
  hl = proxy("hl")
  hl.bind = record
  hl.unbind = function(keys) recorded[keys] = nil end
  hl.on = function() end
  hl.get_config = function() return nil end
  _G.omarchy_preinstalled_bindings = preinstalled
  o = nil
  for name in pairs(package.loaded) do
    if name:find("^default%.hypr") then package.loaded[name] = nil end
  end
  package.path = root .. "/?.lua;" .. package.path
  require("default.hypr.helpers")
  -- Keep o.bind's own action (launch/webapp/tui/…) next to what it compiles to.
  local bind = o.bind
  o.bind = function(keys, description, dispatcher, options)
    pending = dispatcher
    return bind(keys, description, dispatcher, options)
  end
  for _, m in ipairs({ "media", "clipboard", "tiling", "utilities", "voxtype", "applications" }) do
    require("default.hypr.bindings." .. m)
  end
  return recorded
end

local core = load(false)
local all = load(true)

-- JSON.
local function json(v)
  local t = type(v)
  if t == "nil" then return "null"
  elseif t == "boolean" or t == "number" then return tostring(v)
  elseif t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      return ({ ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\t'] = '\\t' })[c]
        or string.format("\\u%04x", c:byte())
    end) .. '"'
  elseif v[1] ~= nil or next(v) == nil then
    local parts = {}
    for i, x in ipairs(v) do parts[i] = json(x) end
    return "[" .. table.concat(parts, ",") .. "]"
  else
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = json(k) .. ":" .. json(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
end

local out = {}
for keys, b in pairs(all) do
  if core[keys] then
    b.layer = "core"
  elseif b.action.webapp then
    b.layer = "webapps"
  else
    b.layer = "apps"
  end
  out[#out + 1] = b
end
table.sort(out, function(a, b) return a.keys < b.keys end)
print(json(out))
