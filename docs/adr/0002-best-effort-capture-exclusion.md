# ADR 0002 — best-effort window capture exclusion

Status: accepted owner request, 2026-11-03.

## Decision

Set the floating chat panel's `NSWindow.sharingType` to `.none` before it is
shown. Husky stays visible and usable locally. This is a compatibility request
to capture software that honors the legacy flag, not a guarantee of invisibility.
No recording permission, capture service, or automatic sharing detection is added.

## Limits and verification

Apple calls `.none` a legacy constant and advises against using it to hide
captured content. ScreenCaptureKit may include Husky despite this setting.
Zoom's Advanced capture with window filtering is the requested test mode;
Zoom documents filtering of its own windows, not a promise to exclude Husky.

Qualification requires a receiving participant's view or local Zoom recording
of a full-desktop share, with Husky visible on the sharing Mac. Exercise incoming
text, typing, dragging, hide/show and any auxiliary windows. Record macOS and
Zoom versions and the selected mode. Repeat on Sequoia 15.6.1 before claiming
compatibility there. A flag readback alone does not pass capture acceptance.

Sources:
- https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none
- https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0063824
