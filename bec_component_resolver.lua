local component = require("component")

local M = {}

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

-- Resolve one component address from a complete address or a unique prefix.
-- The caller controls whether an empty prefix is allowed so that automatic
-- discovery and explicitly configured addresses share the same implementation.
function M.resolve(componentType, prefix, options)
  options = options or {}
  prefix = trim(prefix)

  if prefix == "" and not options.allowEmpty then
    return nil, {
      kind = "empty",
      prefix = prefix,
    }
  end

  local available = {}
  local matches = {}
  for address in component.list(componentType, true) do
    available[#available + 1] = address
    if prefix == "" or address:sub(1, #prefix) == prefix then
      matches[#matches + 1] = address
    end
  end

  table.sort(available)
  table.sort(matches)

  if #matches == 0 then
    return nil, {
      kind = "not_found",
      prefix = prefix,
      available = available,
    }
  end
  if #matches > 1 then
    return nil, {
      kind = "ambiguous",
      prefix = prefix,
      matches = matches,
    }
  end

  return matches[1]
end

-- Format resolution failures consistently while allowing callers to choose
-- how much discovery detail belongs in their user-facing error.
function M.describe(problem, label, componentType, options)
  options = options or {}
  if problem.kind == "ambiguous" then
    return label .. " address is ambiguous: " .. table.concat(problem.matches or {}, ",")
  end
  if options.includeAvailable then
    return string.format(
      "%s (%s) not found; prefix=%s; available=%s",
      label,
      componentType,
      problem.prefix ~= "" and problem.prefix or "<auto>",
      #problem.available > 0 and table.concat(problem.available, ",") or "none"
    )
  end
  return label .. " not found: " .. tostring(problem.prefix)
end

return M
