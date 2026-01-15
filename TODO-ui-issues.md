# UI Issues Tracker (Screenshots 2026-01-12)

## Focus + Keyboard
- [x] Adjust heading font override to respect explicit text classes (should remove ghost/overlap)
- [x] Render input placeholder when the value is empty
- [x] Fix event payload decoding to avoid [object Object] in status
- [ ] Verify focus trap region layout matches spec (pill, Primary/Outline buttons, spacing)
- [ ] Recheck header rendering after renderer changes

## Inputs + Toggles
- [x] Remove fallback button caption rendering that caused stray "Bu" text
- [x] Remove fallback caption overlap on switch/toggle (should eliminate stray "on")
- [ ] Verify label alignment/clipping for checkbox/radio text after renderer change
- [ ] Validate spacing between radio group, toggle, and "Auto-save / Off" row

## Notes
- [ ] Capture the intended UI reference or spec for these two sections
