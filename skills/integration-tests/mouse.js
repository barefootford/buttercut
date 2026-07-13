#!/usr/bin/env osascript -l JavaScript
// Real CGEvent mouse clicks at global screen coordinates (points, origin at
// the top-left of the main display), for the Tier-2 visual pass
// (skills/integration-tests/SKILL.md).
//
// System Events' `click at` only sends an AXPress, which FCP's browser rows
// (and some other views) ignore for double-clicks — a real double-click needs
// kCGMouseEventClickState set on the event, which is what this does.
//
// Usage:
//   osascript -l JavaScript skills/integration-tests/mouse.js <x> <y> [clicks]
//     clicks: 1 (default) or 2 for a double-click

ObjC.import('CoreGraphics');

function run(argv) {
  const x = parseFloat(argv[0]);
  const y = parseFloat(argv[1]);
  const clicks = argv.length > 2 ? parseInt(argv[2], 10) : 1;
  if (!isFinite(x) || !isFinite(y) || !(clicks >= 1)) {
    return 'Usage: mouse.js <x> <y> [clicks]';
  }
  const pt = { x: x, y: y };

  function post(type, clickState) {
    const ev = $.CGEventCreateMouseEvent($(), type, pt, $.kCGMouseButtonLeft);
    if (clickState > 0) $.CGEventSetIntegerValueField(ev, $.kCGMouseEventClickState, clickState);
    $.CGEventPost($.kCGHIDEventTap, ev);
  }

  post($.kCGEventMouseMoved, 0);
  delay(0.1);
  for (let c = 1; c <= clicks; c++) {
    post($.kCGEventLeftMouseDown, c);
    post($.kCGEventLeftMouseUp, c);
    delay(0.08);
  }
  return `clicked (${x}, ${y}) x${clicks}`;
}
