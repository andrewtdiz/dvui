local M = {}

function M.unpack_scroll(payload)
  local x, y, viewport_w, viewport_h, content_w, content_h = string.unpack("<ffffff", payload)
  return {
    x = x,
    y = y,
    viewportW = viewport_w,
    viewportH = viewport_h,
    contentW = content_w,
    contentH = content_h,
  }
end

function M.unpack_pointer(payload)
  local x, y, button, modifiers = string.unpack("<ffBBH", payload)
  return {
    x = x,
    y = y,
    button = button,
    modifiers = modifiers,
  }
end

return M
