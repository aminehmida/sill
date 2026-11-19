# Keyboard on text focus (fork: aminehmida/sill)

A device's keyboard comes up by itself when the Mac's focus goes into a text field, and goes away when
it leaves one, if the keyboard came up that way.

- Kind 64, `TextFocus` (Sources/StreamProtocol/TextFocus.swift), host → device: `{"editable":Bool,
  "secure":true?}`, nothing of the field itself. Only to a device whose hello says `textFocus` 1
  (`Hello.textFocus`); older devices never get it, older hosts never send it.
- The rule (`TextFocus.judge`, pure, `Tests/checks/text-focus`): AXTextField, AXTextArea, AXComboBox,
  AXSearchField, subrole AXSearchField or AXSecureTextField (`secure`), else a settable value with a
  selected text range.
- `TextFocusReader` (SillHostCore): the Accessibility reads on its own thread `sill.textfocus` (a run
  loop, for the observer), 0.2 s per element; asks Electron apps for their tree once
  (`AXManualAccessibility`). It observes the app it read last (AXObserver: focused element or focused
  window changed), so a field the Mac focuses by itself (an app opening on its search box, a sheet) is
  told at once; the coordinator sends what it reads only while that app is still the target.
- The coordinator reads the focus of the menus' target app, only while it is frontmost (none while
  locked or for Sill itself, and then nothing is observed): 0.15 s and 0.45 s after a device's click
  (left up) or key down, at each app activation under the AppKit loop, and every 2 s as a safety net
  for apps that post no focus notification (some Electron and web views). StreamServer sends each
  device only a change, but a device's click is answered to that device whatever its last kind 64
  said, so clicking a field again brings back a keyboard the person put away; a key never forces (a
  hardware keyboard).
- DisplayWake: kind 64 is no person at the device (`Tests/checks/display-wake`'s count is 35).
- Not done: the iOS client (built with Xcode 27, not on this Mac). The Android client
  (aminehmida/sill-android) reads it, with Settings' "Show Keyboard in Text Fields", on by default.
- Where it falls short: apps that expose no Accessibility focus (games, canvases, some GPU-drawn
  terminals), and Chrome, which builds its tree only for assistive technology.
