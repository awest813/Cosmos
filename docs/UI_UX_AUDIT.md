# UI/UX audit and polish

Reviewed the native SwiftUI shell, shared design components, library toolbar, and search interactions on September 7, 2026.

## Findings addressed

| Priority | Finding | Change |
| --- | --- | --- |
| High | The fixed deep-indigo accent is also used for text and icons on dark surfaces. | Added a light lavender accent in dark appearance; retained deep indigo for gradients with white labels. |
| Medium | Library search, view switching, filtering, imports, pending status, and sync share one crowded row. | Added a two-row fallback with a full-width search field and a fixed-width view picker. |
| Medium | Running a command disables library search and display filters even though these do not modify game files. | Kept search, store filtering, and view switching available; command actions retain their existing busy-state guards. |
| Medium | The custom search field has no explicit focus outline and its clear control is small. | Added a focus outline, a larger clear target, stable field height, Escape handling, and focus retention after clearing. |
| Medium | Notification and empty-state containers combine interactive children into one accessibility element. | Changed these containers to preserve child controls for assistive navigation; enlarged notification dismissal targets. |
| Low | Dashboard selection animates regardless of Reduce Motion, while hover feedback disappears when it is enabled. | Honor Reduce Motion for tab transitions and retain immediate hover feedback. |

## Verification

Source review and whitespace checks completed. The release app compiled and linked successfully. Automated tests could not compile because the installed developer tools do not provide XCTest. The debug build is also blocked by the unavailable PreviewsMacros plugin. The following interactive checks remain required before release; source inspection is not a substitute for testing the running app.

- Compare Launch, Games, Tools, and Bottles in light and dark appearance, including selected chips and white button labels.
- At the minimum window size, inspect the Games toolbar with both Steam and GOG pending items; verify search and action labels fit.
- Tab into search, type, clear with the pointer, and press Escape. Confirm the outline and stable height, and that typing continues after clearing.
- During a background command, confirm search, source filtering, and grid/list changes work while mutation controls remain disabled.
- With VoiceOver, navigate to notice dismissal and each empty-state action separately.
- With Reduce Motion enabled, verify immediate tab changes and visible hover feedback.


## Mission-focused follow-up: priorities 1–5

Cosmos helps people play Windows games on Mac through guided setup, sensible compatibility settings, easy launching, and clear recovery steps.

Implemented:

1. First-game guidance now leads with opening Steam to install a game, followed by finding installed games. The latter uses the existing detect-and-install flow to add games and create Dock shortcuts. The Games empty state follows the same sequence.
2. Launch now groups Steam and graphics settings in a collapsed disclosure. Existing settings menu shortcuts expand it before scrolling to the requested panel.
3. Recommended Game Settings and Game Preset labels explain the purpose of compatibility profiles. YAML and winetricks details remain available in an explanatory disclosure and the preset editor.
4. Library and maintenance actions distinguish previewing detected games, adding games to Cosmos, and creating Dock shortcuts. Menu shortcuts and underlying commands are preserved.
5. Setup progress counts Rosetta only when required. Regression tests cover skipped Rosetta on Intel and required Rosetta on Apple Silicon.

Validation: release build and focused progress verification are reported in the task response. Full XCTest execution remains unavailable with the installed developer tools. Live layout, settings-menu navigation, and first-game smoke checks remain pending.


## Remaining follow-up: priorities 6–8

- Grid/list mode and the user's advanced-tab preference now persist across launches using app preferences. A first launch still defaults to Grid with advanced tabs hidden.
- The navigation toggle reads Advanced / Hide Advanced, with matching guidance and an expanded/collapsed accessibility value.
- The advanced-tab toggle respects Reduce Motion. Pending-game notices expose their explanatory text and action separately to VoiceOver, with store-specific action labels and decorative icons hidden.

Release compilation is checked in the task response. Reopening the app to verify saved preferences and live VoiceOver / Reduce Motion checks remain part of the manual verification checklist.


## Game-loading audit

Fixed direct executable launches that unnecessarily required a Profiles directory, and imported `drive_c/...` paths that failed to resolve inside the active Wine prefix. Legacy relative profile paths retain their existing behavior. A hermetic regression script verifies absolute paths, paths containing spaces, prefix selection, legacy paths, missing files, and argument preservation without launching Wine.

Dashboard launches now reject repeated requests while another command or Terminal job is active. Library double-clicks honor the same availability checks as context-menu launch actions, and unavailable games show an explanatory hint. Quick Launch now says Play Selected Game.

The new launch-path test is included in the local shell suite. Actual game startup and UI interaction still require live verification; these checks do not establish compatibility for individual games.

## Downloads and installation polish — September 19, 2026

- Renamed “Install Cosmos” inside the running app to “Set Up Game Launchers.”
  This step configures game shortcuts; it does not install the desktop app or Wine.
  Sidebar and checklist descriptions now match that behavior.
- Downloads keeps its text label in the toolbar, distinguishing it from the nearby
  setup icon. The recommended pack is separated from individual components.
- Download buttons now say Download, Check Again, or Building/Downloading for the
  active component. Success offers Back to Setup; failures offer Try Again and
  reveal activity details, with a Copy Details action.
- Choosing an existing Spock build or Apple toolkit now waits for the Downloads
  sheet to close before opening the file chooser.
- The Downloads window retains its last result and activity while it is closed.
  Component availability detected during a download is session-based; Wine status
  is also read from the installed runtime. Check Again reuses existing files.

Validation: release compilation, download routing/failure/reuse checks, Spock
validation checks, and installed-app smoke checks are performed for this change.
Game compatibility remains subject to testing with real games.

The installed-app Wine recheck exposed a stuck busy state after a process exited.
Embedded commands now run on a worker that drains output before collecting the
exit code and delivering completion on the main queue. A standalone Swift smoke
test covers output larger than the pipe buffer, stderr, a nonzero exit, callback
ordering, and a missing executable.

Lifecycle tracing confirmed that the subprocess and completion callback succeeded
while SwiftUI reported AttributeGraph update cycles. Console expansion now derives
its default directly from the current sections, retaining only user overrides.
Automatic log scrolling runs after layout and is suspended while Downloads is open,
avoiding synchronous scroll changes during the output render.

## Follow-up after the ScrollViewProxy crash

The prior yield-before-autoscroll approach still produced a fatal
"ScrollViewProxy may not be accessed during view updates" error in the installed
app. Automatic log scrolling is now removed. A user-operated Latest button jumps
to the end, and the log has a bounded height so output does not resize the page.
Section navigation scrolls before clearing its pending state.

Setup and Downloads now show actual free space when the Cosmos data volume has
less than 10 GiB available. This is a headroom warning, not a per-game minimum;
Recheck and app activation refresh it. No storage is deleted automatically.

Manual verification confirmed that Latest scrolls the bounded log without a crash.
Menu availability publications are deferred out of SwiftUI's change callbacks;
download activity no longer expands the hidden main-window log. Graphics settings
also reveal the pre-Steam advanced section when opened from Downloads.

The remaining update cycles were resolved by moving menu-state observation into
a dedicated Commands view, so command availability changes no longer invalidate
the app's scene declaration. In the final installed release smoke check, Wine's
Check Again completed, the success message and Back to Setup appeared, and the
controls became available again. The fresh diagnostic log contained normal command
completion with no AttributeGraph warnings or fatal errors. This verifies the
tested UI flow, not game compatibility or every download provider.
