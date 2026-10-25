# Contributing

Bug reports and ideas are welcome in [Issues](https://github.com/dev-pikapik/pikapik/issues). This page covers building, the code layout and how releases are made.

## Building from source

You need Xcode 26 or newer, the Command Line Tools alone are not enough. There is no Xcode project: `build.sh` calls `swiftc` directly. If `xcode-select -p` points to the Command Line Tools, run the scripts with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```bash
git clone https://github.com/dev-pikapik/pikapik.git
cd pikapik
./scripts/build.sh      # build/pikapik.app
./scripts/package.sh    # build/pikapik.dmg and build/pikapik.zip
```

`install.sh` can also build from source: add `-- --source` after the install command from the README.

The direct build also bundles the official 7-Zip command line tool for archives. `build.sh` downloads it once into `Vendor/` (`scripts/fetch-7zip.sh` checks the download and the copy in `Vendor/` against pinned SHA-256 values and fetches it again when they differ), so the first build needs a network connection. The App Store build leaves it out. In the same way it builds LGPL FFmpeg and dav1d from source for the video player (`scripts/fetch-ffmpeg.sh`, needs `brew install meson ninja nasm pkg-config`).

Local builds are signed ad-hoc, which is fine for your own Mac. macOS treats every ad-hoc build as a new app, so after a rebuild you may need to remove pikapik from Accessibility and Input Monitoring with the − button and add it again.

To sign with a Developer ID and notarize:

```bash
xcrun notarytool store-credentials pika-notary --apple-id you@example.com --team-id TEAMID
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=pika-notary ./scripts/package.sh
```

## Layout

```
Sources/pikapik/
  main.swift, App.swift, MenuView.swift
  Core/                              constants, symbols, strings, event tags, shortcuts, focus, updater
  UI/                                shared controls, row styles, icons, new marks
  Settings/                          settings window, tabs, search, iCloud sync
  Permissions/                       permissions checks, UI, leftover permissions
  Tools/Tool.swift                   Tool protocol and ToolRegistry
  Tools/<Feature>/                   one folder per feature (Games, Mouse, Finder, Pet, …)
Helper/                              privileged fan helper and sandboxed media player
Extensions/                          Finder Sync, Quick Look, Action and Share extensions
Resources/Localizable.xcstrings      String Catalog (23 languages)
Resources/AppIcon.icon               app icon, AppIcon.icns is the fallback
scripts/                             build, package, release, icon, tests
```

Each test below is one line to paste into Terminal. `./scripts/run-tests.sh` runs all of them the way CI does: it keeps going after a failure, stops a test that takes longer than 10 minutes to build or to run (that needs `brew install coreutils`) and lists every problem at the end. `./scripts/run-tests.sh --changed` runs only the tests that build, name or read a file changed since `origin/main`, committed or not, and `--list` prints which tests it would run without running them; CI still runs every test. The lines that build most of the app get those files from `./scripts/test-core.sh`, which builds them once into `build/test-core` and again only when one of them changes. A test file without its line here fails CI. On CI a test that prints that it skipped something fails the run too, unless [`scripts/ci-skips.txt`](scripts/ci-skips.txt) lists that skip with the reason CI can't run it and where it runs instead. CI also starts both builds of the app and checks that each keeps running and quits cleanly when asked (`swiftc -O scripts/smoke-test.swift -o build/smoke-test && build/smoke-test build/pikapik.app`), and fails when a signing key, certificate, profile or token gets into the code (`./scripts/check-secrets.sh`).

Game Mode reads the complete symbolic shortcut catalogue on the current Mac, including Command combinations and user assignments. Automatic pauses actions that would interrupt the game. A short deliberate input-source shortcut selects the language directly without the system menu, while held game keys have priority. Per-action choices and previews are in More game settings. Keyboard events retain their keys and modifier flags. The separate Ctrl-click rule removes Control only from left mouse events so macOS does not turn them into context menu clicks. The catalogue, coverage limits and validation are described in [Game input and shortcut catalogue](docs/game-input-catalog.md).

Which apps count as games, which keys and clicks reach the game, and how the pointer is kept on the game's screen live in `GameRules`, which you can test without the app:

```bash
swiftc -swift-version 5 -parse-as-library $(./scripts/test-core.sh $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift) scripts/test-game-mode.swift -o build/test-game-mode && build/test-game-mode
```

Which macOS shortcuts, gestures and hot corners Game Mode pauses for each rule is decided in `SystemShortcutCatalog` and `PointerShortcuts`:

```bash
swiftc -swift-version 5 -parse-as-library $(./scripts/test-core.sh $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift) scripts/test-system-shortcuts.swift -o build/test-system-shortcuts && build/test-system-shortcuts
```

The ⌘Q and ⌘W guard is a `CGEventTap` on `keyDown`/`keyUp`. A bare ⌘Q or ⌘W, with Cmd and without Ctrl, Option or Shift, is dropped. The quit and close shortcuts, ⇧⌘Q and ⇧⌘W unless you record your own, are swallowed and replaced with a fresh ⌘Q or ⌘W, so the app sees a normal quit or close. During Game Mode, shortcuts with Control or without Command pass through as game input, even if they were assigned to quitting or closing elsewhere. A key-up is dropped only when its key-down was (`Core/SwallowedKeys.swift`, which Game Mode uses the same way): a key you hold when ⌘ goes down, such as W to walk in a game, still comes up in the app, and the key-up of a dropped ⌘Q is dropped even when ⌘ comes up first. The key-up test below checks both.

Every event pikapik posts (the keys it sends for you, the mouse clicks, the swipes, the replayed Dock clicks) goes through `CGEvent.postPikapik` in `Core/EventTag.swift`: it marks the event as pikapik's own and hands it to a sender that a test can replace. Keyboard events are built only by `CGEvent.pikapikKey` in the same file. A key-down carries the modifiers the replacement needs, and a key-up carries the modifiers the user really holds (`CGEvent.pikapikHeld`, by default `CGEventSource.flagsState(.hidSystemState)`). A key-up with the key-down's flags leaves ⌘ held in every other app until the next real keyboard or mouse event. The test replaces the sender (`CGEvent.pikapikSend`) with a recorder and the held modifiers with a fixed value, so the result doesn't depend on the keys held on the Mac that runs it. It then runs the real code of each place and compares the keys it would send, their order, their flags, their text, and the tag on every event itself: the Home and End key-down and key-up, the release in `stop()` of Home and End, the ⌘ keys, the Finder keys and the App Store layout-fix key, the Finder ⌘X after a copy (on a pasteboard of its own, never the general one), the layout-fix retype in the website build, and Back and Forward. It also reads the sources and fails if any file but `EventTag.swift` builds a keyboard event or posts an event. It posts nothing and needs no Accessibility. Run it for the website build and for the App Store build, which has its own layout-fix key and must let typed words through untouched:

```bash
swiftc -swift-version 5 -parse-as-library $(./scripts/test-core.sh $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift) scripts/test-key-up-flags.swift -o build/test-key-up-flags && build/test-key-up-flags
```

```bash
swiftc -swift-version 5 -parse-as-library -D APPSTORE $(./scripts/test-core.sh -D APPSTORE $(./scripts/appstore-sources.sh --tests)) scripts/test-key-up-flags.swift -o build/test-key-up-flags-appstore && build/test-key-up-flags-appstore
```

Shortcuts in Settings are read live. macOS shortcuts come from `AppleSymbolicHotKeys` in `com.apple.symbolichotkeys`, and a missing entry means the macOS default, which SkyLight reports. Finder's Cut comes from `NSUserKeyEquivalents` for Finder and then for all apps, matched by the menu title in Finder's language. They are read again when pikapik becomes active or a window comes forward. The recorder catches keys with a session event tap and pauses the Mac's own shortcuts while you type, the same way Game Mode does, so it can tell you what already uses them. Parsing and the conflict check live in `Shortcuts`, which you can test without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Shortcuts.swift scripts/test-shortcuts.swift -o build/test-shortcuts && build/test-shortcuts
```

The FPS counter over a game (Settings > Games > Show FPS) is `Games/FrameRate.swift`, which has no AppKit, and `Games/FrameRateMeter.swift`, the overlay and the two counters. The direct build on macOS 27 and later asks `/usr/bin/metalperftrace listen --json --pid` for the presented frames per second of the largest layer that presented anything. The tool buffers its output unless it is a terminal, so it gets a pty, and a small shell reading from a pipe that pikapik holds open stops it when pikapik quits or crashes. Games it can't see (OpenGL, older macOS, the App Store build) are counted from a small ScreenCaptureKit stream of the display, which needs Screen Recording: a frame counts only when the changed area covers at least 30% of the game window, so the number can't go above the screen's refresh rate. The stream starts only after three seconds without a number from `metalperftrace`, only if the permission is already granted, and never for a game it has already measured. On macOS 27 a game that needs the stream while the permission is missing makes pikapik remember it (`game-mode-fps-recording`, never reset or exported), and only then does Settings show the Screen Recording row; older macOS and the App Store build show it whenever Show FPS is on. The row belongs to the Permissions page like every other permission: Settings > Games shows only a line under the switch ("To count frames, allow “Screen Recording”. No picture is kept or sent." with Allow), which opens that page on the row, and the switch itself never asks. The pill has room for two digits and grows to three, anchored in its corner, once a value of 100 or more arrives in a game. You can test the logic without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Games/FrameRate.swift scripts/test-frame-rate.swift -o build/test-frame-rate && build/test-frame-rate
```

The Mac App Store copy can't switch hot corners off, so the cursor fence of Game Mode (`GameRules.fenceCorners`) keeps the pointer 16 points from every corner instead, except corners you allow. There the screen lock is also tracked from the `com.apple.screenIsLocked` and `screenIsUnlocked` notifications (`GameModeTool.received`), and the game is left at once. The test compiles the same files as the App Store build: `scripts/appstore-sources.sh` lists them for both.

```bash
swiftc -swift-version 5 -parse-as-library -D APPSTORE $(./scripts/test-core.sh -D APPSTORE $(./scripts/appstore-sources.sh --tests)) scripts/test-game-appstore.swift -o build/test-game-appstore && build/test-game-appstore
```

Quit on last window uses an `AXObserver` per regular app: it tracks standard windows and, half a second after one is destroyed, quits the app if it has no windows left, including minimized ones and ones on other desktops (checked with `CGWindowListCopyWindowInfo`). Finder, pikapik and the apps in the exceptions list are skipped. A busy app can take seconds to answer an Accessibility question, and every pikapik tap runs on the main thread, so none of these questions is asked there: the observers live on a thread with its own run loop (`Core/RunLoopThread.swift`), and a click is looked at on a queue, only when it lands in a title bar corner of a normal window (`TitleBarCorner`), by asking that one app, never the whole system, for at most 0.25 s. An app too busy to say whether it has a window in the Dock is not quit. The test checks the corners and the thread:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/RunLoopThread.swift Sources/pikapik/Tools/Windows/TitleBarCorner.swift scripts/test-quit-on-close.swift -o build/test-quit-on-close && build/test-quit-on-close
```

Hide with a Dock click is a `CGEventTap` on the left mouse button. On a plain click it asks the Dock for the element under the pointer with `AXUIElementCopyElementAtPosition`. If that is the icon of the frontmost app and the app has a visible window, the click is dropped and the app hides. Otherwise the click goes to the Dock as usual.

Keep the Dock on one display sets the Dock’s own `allow-display-switching` key in `com.apple.dock` to false, so the Dock stops following the pointer to another display. A missing key counts as true. The Dock reads the key only when it starts, so pikapik restarts the Dock, and only when the value really changes. pikapik remembers what the key was, so turning the switch off and `--uninstall` put back exactly that, or delete the key if there was none, and at launch the key is brought in line with the switch. The Mac App Store version can’t change the Dock’s settings and doesn’t have this switch. Main display moves every display with `CGConfigureDisplayOrigin`, and macOS keeps the result for the set of displays connected, so pikapik saves the first arrangement of each set of displays before it moves anything. Turning the switch off, `--uninstall` and a launch with the switch off put back the arrangement of the displays connected then. One saved for other displays waits until they are connected again; quitting, logging out and updating keep the pick, and a display someone made the main one since is left alone. What to write and whether to restart is decided in `DockDisplaySwitch`, and what to put back for Main display in `MainDisplay`; you can test both without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Dock/DockDisplaySwitch.swift scripts/test-dock-display.swift -o build/test-dock-display && build/test-dock-display
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Dock/DockHideMigration.swift scripts/test-dock-hide-migration.swift -o build/test-dock-hide-migration && build/test-dock-hide-migration
```

Only one copy of pikapik acts on the Mac. Copies of the same family (the website and App Store builds) pick the one that started last as the main copy (every copy reads each launch date, its own included, from the kernel process start time, `MainCopyChoice.started`, so all of them see the same moment; a copy that cannot read its own start counts as the oldest, so any other copy leads): it is the only one that runs event taps and writes settings, and any other copy stays passive and shows a single screen with a button to take over. When the main copy quits or loses the lead, it puts back what it changed, and the previous copy takes over. Features that change a system switch keep the original in an `OriginalValue` entry that is written once and is put back only while the switch still holds our value. Animations keep their journal (`animations-own`, `animations-ours`, the Dock autohide entry) in one defaults domain per family. The logic lives in `AnimationsEngine` (`AnimationSetting.swift`), which reaches the Mac only through `AnimationsHost`, so the test below runs the real engine on a simulated Mac. When the main copy quits or loses the lead while another Animations-capable copy of the family runs, it hands over: it puts nothing back, the journal stays, the next main copy writes its own choices, and the Dock restarts at most once, and not at all when the choices are the same. The animations are put back instead when no other copy is left, when the copy that comes next is the App Store one (it has no Animations), or when the quit comes from logout, restart or shutdown (`Background.isLoggingOut`). On logout, restart or shutdown every copy puts its values back first thing, in `applicationShouldTerminate`: the game's Dock values, hot corners, animations and Dock autohide, the Dock on one display, key repeat and desktop icons, all before anything asks Launch Services about running apps, which stops answering soon after the quit, and the Dock restarts at most once. Before that it posts `org.pikapik.main-copy.logging-out`, and every other copy waits 3 seconds before it may become main, so a passive copy does not take over and write its values again while its own quit is on the way; if the logout is cancelled, it takes over when the wait ends. When a signal stops pikapik (`sudo shutdown`, launchd at shutdown, `kill`), the main copy does the same before it quits, and `scripts/test-dock-layers.swift` checks that `applicationShouldTerminate` and the signal handler call it first. Autohide goes back to how it was, a missing key stays missing, and Restore Defaults puts it back too. A copy that is not the main one and quits last puts back what the journal still holds. Before it quits, each copy calls `willQuit()`, which sets its own journal key `animations-leaving-<pid>` to the copy's launch date (one key per copy, so two copies never overwrite each other's mark); a copy that leaves, or that hands over, counts a peer as leaving only when that key holds the peer's launch date (within a second), so a key left by an earlier process with the same pid never counts, even before the new copy has started, and each copy also clears its own key at start. So when two copies get the quit at the same moment each sees the other as leaving and the last one puts everything back, once. The put-back removes all these keys. A Dock restart is decided, and its flag `animations-dock-pending` is set, before the first write that needs it; the flag stays until the Dock has restarted, so the next copy finishes the restart if this one stops.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift Sources/pikapik/Core/MainCopy.swift Sources/pikapik/Tools/Animations/AnimationSetting.swift scripts/test-main-copy.swift -o build/test-main-copy && build/test-main-copy
```

What a copy does when it starts, hands over to another copy, quits, when the Mac shuts down or the user logs out, and on `--uninstall` is one table, `Lifecycle.rows` in `Core/Lifecycle.swift`. Each row belongs to one owner, and a row whose owner changes something on the Mac says for every moment what happens to that change: a step that runs, the tools putting it back themselves, a call made elsewhere (`applicationWillTerminate` or `--uninstall` in `main.swift`), or why nothing is needed. `Lifecycle.run` goes through the rows top to bottom, logs each step it runs (for example `quit HotCorners`), and restarts the Dock at most once, at the Dock row, when a step above it asked. The test runs the runner on made-up rows, checks the real table's order for every moment, compares the table with `--uninstall` and `applicationWillTerminate`, and scans the sources for calls that change the Mac, so a new one cannot land without a row, and checks when a launch registers the Services entry, the Player and the Finder extension again (`Lifecycle.isDue`):

```bash
swiftc -swift-version 5 -parse-as-library $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift scripts/test-lifecycle.swift -o build/test-lifecycle && build/test-lifecycle
```

Every copy brings its own Finder extensions, and Finder asks every running one for its menu, so without a choice each copy adds its own New File, Make a Smaller Copy, Convert and Archive item. Before it adds an item, an extension asks `MainCopyChoice.showsMenu`: among the running extensions of the same kind (pikapik ids only), the item belongs to the one whose app is running, then to the website or App Store copy over dev and test copies, then to the app that started last (the main copy), so exactly one extension adds it, whatever copies are installed or running. When the main copy quits or is deleted, the item moves to a copy that is left. An extension that does not find itself in the list adds its item, so the item never disappears. The website copy, while it is the main one, also switches off the same extension of dev and test copies, which helps with copies built before this choice; it never switches off the App Store one, which only the user can turn back on.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift scripts/test-finder-menu.swift -o build/test-finder-menu && build/test-finder-menu
```

Both lists come from pure functions: `MainCopyChoice.sameMenu` picks the running extensions of pikapik copies with the same menu item, and `MainCopyChoice.ignored` reads the `pluginkit -m` list and picks the switched-on ones of dev and test copies that the website copy switches off, never its own and never the App Store one. The test runs both on a made-up list.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift scripts/test-finder-menu-cleanup.swift -o build/test-finder-menu-cleanup && build/test-finder-menu-cleanup
```

In the website build, Retype words you typed in the wrong language and Home/End switch on `AXManualAccessibility` (or `AXEnhancedUserInterface`) in Chromium and Electron apps so their text fields become visible. They do it only in an app that needs it, at the first key that needs it: `TextFocus(pid)` checks once whether the app is built on Chromium (other apps are remembered until they quit), switches it on off the main thread, trying again every second for up to 10 tries, and reads the focused element again for up to 0.4 seconds, so the first key can already find the text field. If all 10 tries fail, the app is put back and forgotten, and the next key tries again. `TextFocus.Awake` decides when an app is put back: once it has been in the background for a minute. An app that quits is forgotten and dropped from the journal. `TextFocus` writes each switched app (bundle id, pid, attribute, original value) to a journal before the switch, and an app leaves the journal only once it has been put back, has quit or has refused the switch, so a switch-on that does not answer in time stays in the journal. An app that does not answer whether the mode is already on is not switched and not written to the journal on that try, and the next try asks again. An app that quits or is put back while its switch-on is still being tried ends switched off and out of the journal, and the tries left for it do not switch it on again. After a crash the main copy reads the journal at start and, off the main thread, puts back every app that still runs with the same pid and bundle id, trying again every second for up to 10 tries while the app still runs and does not answer. Switching off works the same way, off the main thread, and on quit the main copy waits up to 2 seconds for it. New switches wait until putting back is done. It does not read the attribute before putting an app back: Electron answers `false` even while the switch is on. The test keeps the journal in a temporary folder.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/TextFocus.swift scripts/test-chromium-ax-journal.swift -o build/test-chromium-ax-journal && build/test-chromium-ax-journal
```

Stopping leaves no Chromium app switched on. A switch-on that lands after pikapik has already put the app back is switched off again, a switch-on tried again after pikapik stopped watching does nothing, and an app stays on while Retype or Home/End still needs it, until the last of them is turned off or pikapik quits. An app that does not answer when pikapik quits stays in the journal while it is tried again every second, at most 10 times. The test keeps the journal in a temporary folder.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/TextFocus.swift scripts/test-chromium-ax-quit.swift -o build/test-chromium-ax-quit && build/test-chromium-ax-quit
```

Changing a hot corner from the Games page remembers the first action and puts it back on request, and a change to the same action writes nothing, so the Dock restarts only on a real change.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Tools/Games/DockEdges.swift Sources/pikapik/Tools/Games/HotCorners.swift scripts/test-hot-corners.swift -o build/test-hot-corners && build/test-hot-corners
```

While a game runs, Game Mode puts its own values on the hot corners it calms (no action) and on the Dock delay (so a hidden Dock does not pop up) and keeps the user's values underneath in its journal (`game-mode-dock`). The Games and Animations pages reach these keys only through `DockEdges.read` and `DockEdges.write`: while the game's value is still on a key they read and change the value underneath, otherwise the live one. So the original of a hot corner or of the Dock delay is never taken from the game, the game and the pages put back in any order, and the game puts back only keys that still hold its value, so a corner changed by hand during the game stays. The game clears its journal only after the values are written back.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift Sources/pikapik/Tools/Animations/AnimationSetting.swift Sources/pikapik/Tools/Games/DockEdges.swift Sources/pikapik/Tools/Games/HotCorners.swift scripts/test-dock-layers.swift -o build/test-dock-layers && build/test-dock-layers
```

In the website build, Hide desktop icons shows as on whenever the desktop is hidden: by the System Settings switch (`StandardHideDesktopIcons`, or `HideDesktop` with Stage Manager) or because Finder has no desktop window, as after `defaults write com.apple.finder CreateDesktop -bool false`, which also takes away the selection rectangle. Switching it off always brings the desktop back: it shows the icons, forgets the journal and, when Finder has no desktop window, removes `CreateDesktop` and restarts Finder once it has finished copying. Switching it on hides the icons only on a visible desktop and notes that pikapik hid them. Putting back, on quit and whenever a copy becomes the main one, only ever shows the icons, and only while the note says pikapik hid them and they are still hidden, so icons hidden in System Settings stay hidden and a journal from an older version never hides them again. The note also keeps which of the two keys pikapik wrote, and putting back reads and writes only that key, so turning Stage Manager on or off while the icons are hidden leaves its own setting alone. When that key had no value before, putting back takes it away again instead of setting it to false, so System Settings is left as it was. The logic lives in `DesktopIcons`, which reaches the Mac only through `DesktopIconsHost`, so the test runs it on a simulated Mac. The test keeps its journals in a temporary folder.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift Sources/pikapik/Tools/Finder/DesktopIcons.swift scripts/test-desktop-icons.swift -o build/test-desktop-icons && build/test-desktop-icons
```

In the App Store build the curtain over the desktop icons shows the wallpaper frame for the macOS look, read from `AppleInterfaceStyle` when pikapik's own Appearance is Light or Dark. A wallpaper with light and dark versions names their frames in `apple_desktop:apr`, and one that follows the sun or the time of day names them in the `ap` entry of `apple_desktop:solar` or `apple_desktop:h24`; any other picture, unreadable metadata or a frame that isn't there gives the first frame. The test checks that choice in `WallpaperFrame` on two-frame pictures made in memory, then builds the curtain itself for made-up screens and pictures in a temporary folder: `DesktopCurtain.screens` hands it the screens and their wallpapers, and `DesktopCurtain.show` only notes each window, so nothing appears on screen. It covers one curtain per screen at the screen's frame, one level above the icons, with clicks passing through; a redraw only when a screen, Space, wallpaper or look really changes; the plain wallpaper color for a moving or unreadable picture; a 6000×4000 picture decoded at 2880×1920 for a 1440×900 Retina screen; the four scaling choices; and no curtain or poll left after turning it off or quitting.

```bash
swiftc -swift-version 5 -parse-as-library -D APPSTORE Sources/pikapik/Tools/Finder/DesktopCurtain.swift scripts/test-desktop-curtain.swift -o build/test-desktop-curtain && build/test-desktop-curtain
```

Hide desktop icons writes its note before it hides the icons, so a copy that is force quit at that moment has already saved it, and its next launch brings the icons back and forgets the note. The test hides the icons in a second process that stops dead while hiding, with the journal in a temporary folder.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift Sources/pikapik/Tools/Finder/DesktopIcons.swift scripts/test-desktop-icons-force-quit.swift -o build/test-desktop-icons-force-quit && build/test-desktop-icons-force-quit
```

Hide desktop icons and Show hidden files restart Finder only when it is not copying or moving files. They look at Finder twice, half a second apart, and while it does more than 5 ms of work or reads or writes the disk in between, they wait and say “Waiting for Finder to finish copying”. Finding Finder, measuring it, the restart and the half-second wait go through `FinderHost`, so the test drives a made-up Finder that copies, finishes or goes away and never touches the real one. It also measures its own process to check that the work is read in seconds.

```bash
swiftc -swift-version 5 -parse-as-library $(./scripts/test-core.sh $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift) scripts/test-finder-restart.swift -o build/test-finder-restart && build/test-finder-restart
```

A `Toggle` inside a `Menu` needs `.toggleStyle(.automatic)`: the switch style that Settings pages apply makes each item draw three rows that do nothing when chosen. The test reads every Swift file in `Sources` and fails on a `Toggle` in a `Menu` without it.

```bash
swiftc -swift-version 5 -parse-as-library scripts/test-menu-items.swift -o build/test-menu-items && build/test-menu-items
```

Creating an event tap makes macOS ask for Accessibility or Input Monitoring at once, so every tool checks the permission it `needs` before it creates one (`AXIsProcessTrusted()`, `CGPreflightListenEventAccess()` or `Permissions.shared`) and leaves the request to the Permissions tab. The test reads every Swift file in `Sources` and fails on a `CGEvent.tapCreate` whose function, or each function that calls it, doesn't check first.

```bash
swiftc -swift-version 5 -parse-as-library scripts/test-tap-guards.swift -o build/test-tap-guards && build/test-tap-guards
```

The language switch uses a listen-only `CGEventTap`, so it never changes or delays events. It watches `flagsChanged` for Option and Shift, and any `keyDown` or mouse click in between cancels the gesture, as does Cmd, Ctrl or Fn. When both keys are released, the order they were pressed in picks the next or previous input source, which is then selected with `TISSelectInputSource`. Only keyboard layouts and input methods take part, not the emoji or character palettes. The decision is made in `InputSwitchGesture`, which you can test without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/InputSwitch/InputSwitchGesture.swift scripts/test-input-switch.swift -o build/test-input-switch && build/test-input-switch
```

In a game the language switch needs a short, deliberate Option and Shift: a game key still held, or modifiers held longer than 0.45 seconds, leave the game the keys. `GameInputIntent` decides this:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Games/GameInputIntent.swift scripts/test-game-language.swift -o build/test-game-language && build/test-game-language
```

Middle click on the trackpad uses two `CGEventTap`s. A listen-only one reads the fingers from gesture events with `NSEvent.allTouches()`, leaving out resting thumbs, and `MiddleClickGesture` decides when a quick tap with the chosen number of fingers ends; pikapik then posts a middle button click at the pointer. The other one turns a left or right press made while that many fingers are down into the middle button: down, drag and up. Both read the trackpad settings each time, so a three-finger tap stays with Look up and a three-finger press with three-finger drag. The tap decision can be tested without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Mouse/MiddleClickGesture.swift scripts/test-middle-click.swift -o build/test-middle-click && build/test-middle-click
```

Turn off pointer acceleration sets `HIDUseLinearScalingMouseAcceleration` and the speed on each mouse through the private `IOHIDEventSystemClient`. Before the first write it notes what the mouse had (`linear-pointer-saved`) and what pikapik writes (`linear-pointer-ours`). Quitting and `--uninstall` put back what the mouse had, or what System Settings has now, only where the mouse still has pikapik’s value, so a change made since then stays. `--uninstall` runs in a new copy that knows only these notes. `PointerPutBack` makes the decisions, and the test runs it on pretend mice, starting from the notes as `--uninstall` does:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift Sources/pikapik/Tools/Mouse/PointerPutBack.swift scripts/test-pointer-put-back.swift -o build/test-pointer-put-back && build/test-pointer-put-back
```

`WheelStep` turns each mouse wheel notch into a fixed number of lines or pixels and leaves trackpad scrolling alone, and `ScrollDirection` sets the direction for the mouse and the trackpad separately. The same test checks how `SettingsFile` merges settings from another Mac:

```bash
swiftc -swift-version 5 -parse-as-library $(./scripts/test-core.sh $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift) scripts/test-scroll.swift -o build/test-scroll && build/test-scroll
```

Animations writes hidden macOS preferences with `CFPreferencesSetAppValue`: the Dock keys go to `com.apple.dock`, the Finder key to `com.apple.finder` and the rest to the global domain. pikapik remembers which keys it wrote, so Restore Defaults and `--uninstall` delete exactly those; a value set in Terminal is shown as it is and stays until you move its slider. A change to a Dock key restarts the Dock once, 0.6 seconds after the last change, and Finder restarts only from its button. The slider math and what gets written live in `AnimationSetting`, which you can test without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/MainCopyChoice.swift Sources/pikapik/Tools/Animations/AnimationSetting.swift scripts/test-animation-tweaks.swift -o build/test-animation-tweaks && build/test-animation-tweaks
```

Only Allow on Settings > Permissions asks macOS for a permission. A dimmed switch, a "Needs a permission" row or an Allow bar on another page opens that page on the row (`Permissions.ask`), and the switch itself never asks. macOS sends no notice when a permission changes, so the page checks every 1.5 seconds while it is on screen, and after Allow for two minutes or until macOS grants what was asked (`PermissionPolling`); nothing checks otherwise. The test checks that rule and reads the sources: only `Permissions.swift` may call the macOS functions that show a prompt, and only from Allow:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Permissions/PermissionPolling.swift scripts/test-permission-prompts.swift -o build/test-permission-prompts && build/test-permission-prompts
```

Permissions left by deleted apps are read from the system TCC database (`/Library/Application Support/com.apple.TCC/TCC.db`), which needs Full Disk Access. A client counts as deleted when LaunchServices has no copy of it outside the Trash, no helper, launch agent or system extension with its id is left, and it is not on a disk that is unplugged; Apple apps and system paths are skipped. Remove calls `tccutil reset All <id>`. tccutil only accepts ids that LaunchServices knows, so pikapik registers a tiny placeholder app with that id in its Caches folder for a moment and deletes it right after. Path clients can’t be reset this way, so their row opens the list in System Settings instead. The parsing and the deleted check live in `LeftoverPermissions`, which you can test without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/Symbol.swift Sources/pikapik/Permissions/LeftoverPermissions.swift scripts/test-leftover-permissions.swift -o build/test-leftover-permissions && build/test-leftover-permissions
```

In the App Store version the sandbox and macOS hide who was allowed, so Settings › Permissions reads the usage keys in the `Info.plist` of the apps in `/Applications` (and one folder level below it) and says “can ask”, never “has”: Camera (`NSCameraUsageDescription`), Microphone, Automation (`NSAppleEventsUsageDescription`), Files and Folders (the folder and volume keys) and Bluetooth. Accessibility, Screen Recording, Input Monitoring, Full Disk Access, App Management and Developer Tools have no such key, so those rows only open System Settings. The scan lives in `PrivacyAsks`, which you can test without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Permissions/PrivacyAsks.swift scripts/test-privacy-asks.swift -o build/test-privacy-asks && build/test-privacy-asks
```

The App Store build and its extensions carry the privacy manifest `Resources/PrivacyInfo.xcprivacy`. Apple accepts some APIs only with a reason from its list: the app's own defaults, the time since startup for the pet and the FPS counter, file dates (`stat` and `lstat` on archives and the files you pick) and the free space checked before unpacking. The test reads the manifest, checks that every reason is on Apple's list, and fails when a file in `Sources` or `Extensions` calls one of these APIs while the manifest doesn't declare its category:

```bash
swiftc -swift-version 5 -parse-as-library scripts/test-privacy-manifest.swift -o build/test-privacy-manifest && build/test-privacy-manifest
```

App Volume (macOS 14.2 and later) changes one app’s volume without a driver. For every app whose slider is below 100% or that is muted, pikapik creates a Core Audio process tap (`CATapDescription`) that mutes the app’s own output, read through a private aggregate device that holds only the tap. A HAL output unit with its input off, set to the output the app plays to (the current output if it uses several), takes the sound from a ring buffer, multiplies it by the app’s gain and plays it there, so the microphone is never opened; an app at 100% gets no tap and is never touched. Helper processes, such as a browser’s audio service, are listed under the app that contains or started them; system daemons are left out. The gain follows the slider squared and moves through a 30 ms ramp so nothing clicks. macOS has no call that says whether System Audio Recording is allowed, so pikapik plays a tone too quiet to hear through a tap on itself and takes any sound that comes back as “allowed”; it asks again when a running tap delivers only silence. The gain, the ramp, the mixing, the ring buffer, the grouping, the saved levels (`AppVolumeMemory`, kept under the app’s bundle ID) and the merge of running and remembered apps into the list live in `AppVolumeMath`, which you can test without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Tools/AppVolume/AppVolumeMath.swift scripts/test-app-volume.swift -o build/test-app-volume && build/test-app-volume
```

The path checks run without the app: a Homebrew copy, an app moved to another folder, Finder extensions registered from the right place, and a free name for a new file:

```bash
swiftc -swift-version 5 -parse-as-library $(./scripts/test-core.sh $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift) scripts/test-rename.swift -o build/test-rename && build/test-rename
```

The pet lives in a borderless window one level above the desktop icons, so every normal window and the Dock cover it. The window lets clicks through everywhere except the pet itself: on each frame it checks whether the pointer is over the pet’s hitbox, swept over the last frame so a fast pet can still be caught. While you hold or throw the pet, the window grows to the whole screen and rises above the Dock, and it drops back behind everything once the pet lands. It joins all Spaces, stays out of Mission Control and the app switcher, and hides during full-screen apps, Game Mode, screen sleep, the lock screen and while the Mac runs hot. It draws only while something moves: walking, jumps, kicks, holding and throwing run at 30 frames per second (20 on battery or in Low Power Mode), a pet that sits still wakes only to blink, check its mood or say a phrase, and the dozing breath is baked once into a Core Animation loop of 130 frames over 10.8 s (`FigureView.loop`) that the system plays with no work from the app. The pointer coming near, pressing Space, a mouse press, a display change or a switch to another Space wakes it at once; a pet or ball under a window is not drawn, and once everything is covered and nothing is flying or rolling, only the check every 2 s still runs. Space comes from a listen-only `CGEventTap`, so the key is never changed or delayed; the tap is made only if Input Monitoring is already allowed, and the Pet page does not ask for it. Walking, jumps, bumps, holding and throwing live in `PetPhysics`, which has no AppKit and steps in fixed slices of 1/120 s: the pet and the pointer are rectangles, their relative motion is swept every slice so nothing tunnels through, and the pet always stays inside the screen and on the ground. A throw takes the pointer speed over the last 80 ms, capped, bounces off the sides and never goes above the menu bar, and the pointer can’t knock the pet over for a second after it is let go. The phrases are one list in `PetPhrases`, each with an id, ready for partner lines. You can test the physics without the app:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Pet/PetPhysics.swift Sources/pikapik/Tools/Pet/BallPhysics.swift scripts/test-pet.swift -o build/test-pet && build/test-pet
```

When the pet draws, waits for its next blink or stops is decided in `PetPace`, which has no AppKit; the test checks those rules and counts the frames of a ten-minute simulation of a pet sitting idle, dozing, walking, in Low Power Mode, covered by a window and with Reduce Motion on:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Pet/{PetPace,PetPhysics,BallPhysics,PetMood,PetFigure,PetClothes,PetGeometry,PetWardrobe}.swift scripts/test-pet-pace.swift -o build/test-pet-pace && build/test-pet-pace
```

Awards and wardrobe unlocks live in `PetProgress`. `PetPhysics` reports what the pet does (jumps, leaps over the pointer, climbs, tumbles, hard throws) and `PetStage` adds it up while no demo runs, together with steps, kicks, phrases and the days, nights and weekends you spend together. Everything stays on the Mac in five keys, `pet-counts`, `pet-awards`, `pet-seen`, `pet-fresh` and `pet-outfit`; they are not part of the settings file, so Restore Defaults leaves them alone. The rules run without the app too:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/Symbol.swift Sources/pikapik/Tools/Pet/PetWardrobe.swift Sources/pikapik/Tools/Pet/PetAwards.swift scripts/test-awards.swift -o build/test-awards && build/test-awards
```

The pet’s feelings are a face (eye, brow, mouth, blush, a mark above the head) that `PetMind` fades between. `PetStage` cues a mood from what the pet already knows (being picked up, a kick, an award, a late hour) and the rules are plain numbers: a higher mood interrupts a lower one, the same cue extends a mood instead of restarting it, every mood rests before it can come back, and the pet starts at most one mood of its own every three minutes. The rules run without the app too:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Pet/PetMood.swift scripts/test-mood.swift -o build/test-mood && build/test-mood
```

What the pet feels, when it sits down and when it says a phrase it owes live in `PetCues`, which has no AppKit, and `PetStage` only feeds it the clock and the pet: a pet that wakes from a doze is sleepy and sits, the morning phrase waits for the yawn and is never lost, a phrase owed while the pet cannot sit waits until it can, and bored and sleepy never start while it cannot sit:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/Symbol.swift Sources/pikapik/Tools/Pet/{PetCues,PetMood,PetPhrases,PetPhysics,BallPhysics,PetWardrobe,PetAwards}.swift scripts/test-pet-cues.swift -o build/test-pet-cues && build/test-pet-cues
```

Each mark stays 0.4 units clear of the pet and of every hat and back item, in every pose and both facings, so the crown heights in `PetFigure.mark` can’t drift out of date:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Pet/{PetFigure,PetClothes,PetGeometry,PetWardrobe,PetMood,PetPhysics,BallPhysics}.swift scripts/test-pet-marks.swift -o build/test-pet-marks && build/test-pet-marks
```

Every item and sign stands out at 3:1 or better on a white window and on a #1E1E1E window; a fill that falls below that gets a thin gray rim under it (about 0.8 pt on screen) at full strength. At most 10% of any outline may stay below 3:1 against white and against #1E1E1E (day and night colours on both), in walking, sitting and jumping poses and both facings, and where the rim is gray its first 2 render px (the test draws at scale 6) must keep the 3:1 too and the rim must stick out 2 to 3 render px, so a rim half or twice as wide fails:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Pet/{PetFigure,PetClothes,PetGeometry,PetWardrobe,PetMood,PetPhysics,BallPhysics}.swift scripts/test-pet-contrast.swift -o build/test-pet-contrast && build/test-pet-contrast
```

The outline must stay cheap: drawing any single item with it costs at most 0.3 ms more per frame than without it, and a whole look, which is 3 to 7 items whose outlines add up, at most 0.5 ms, under 2% of a frame at the pet’s 30 frames per second (release build on an idle Mac; add `raster` to also fill the paths). This check is manual: CI does not run it, because timings on shared runners are too noisy to hold such small limits:

```bash
swiftc -O -parse-as-library Sources/pikapik/Tools/Pet/{PetFigure,PetClothes,PetGeometry,PetWardrobe,PetMood,PetPhysics,BallPhysics}.swift scripts/bench-pet.swift -o build/bench-pet && build/bench-pet
```

The app and the pet tell you about an update only when the latest release is newer than the running version, compared number by number, so `1.26.10` is newer than `1.26.9` and `v1.27.0` equals `1.27.0`. The comparison lives in `Version`:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Version.swift scripts/test-updater.swift -o build/test-updater && build/test-updater
```

After an update the app points at what is new: a dot after the tab’s name until the tab is opened, a New tag beside the row until the tab is left, nothing on a fresh install and nothing 21 days after the update. `NewMarks` holds the table of what is new and the version logic, and the test checks fresh installs, upgrades from 1.49.x, seen items that stay seen after a relaunch, a downgrade or a second running copy, expiry and that every tab in the table exists:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/Version.swift Sources/pikapik/UI/NewMarks.swift scripts/test-new-marks.swift -o build/test-new-marks && build/test-new-marks
```

Before Homebrew removes the app, it runs `pikapik --uninstall`, which turns off launch at login and puts back the system settings the app changed, such as the Dock and key repeat. Homebrew runs the same step when it upgrades or reinstalls the app, so the app first looks for the `brew` command that started it and does nothing for `upgrade`, `reinstall` and `install`. The check lives in `Brew`:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Brew.swift scripts/test-brew.swift -o build/test-brew && build/test-brew
```

Work with the lid closed turns lid sleep off with `pmset -a disablesleep 1` and leaves a small watcher running as root. The watcher touches its flag file every 2 seconds and turns lid sleep back on when the flag is gone, when the app has been gone for a minute, or when it is stopped. At log out, restart and shut down pikapik removes the flag right away. The watcher starts with `launchctl asuser 0`, outside the login session: a watcher left inside it keeps running after a log out, but its `pmset` then fails without any error, so lid sleep would stay off. pikapik remembers that it turned lid sleep off until `pmset -g` shows it back on. If it is still off, pikapik asks for the password once per launch, and after a cancel shows Let It Sleep in Settings and in the menu. The test runs the real watcher script against a fake `pmset`, so your Mac isn't changed:

```bash
swiftc -swift-version 5 -parse-as-library $(./scripts/test-core.sh $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift) scripts/test-keep-awake-lid.swift -o build/test-keep-awake-lid && build/test-keep-awake-lid
```

The helper that runs as root sets the fan speed and, in the website version, turns background services off and on. You install it once, with the administrator password, from Settings › Permissions (Administrator access). On every connection the app and the helper check each other’s signature: the same developer, and the helper’s name is the app’s name plus `.fans`. The helper carries the app’s build number inside its signature. When pikapik updates, it hands the new helper from its own bundle to the one already installed, and the helper updates itself without a password: it copies the file into its own folder, which only root can write to, and checks that copy’s signature and that its build number isn’t lower than its own. It swaps the files in one step only when it quits, after the last app disconnects, and checks the copy once more first: macOS compares a running program with its file on disk, so a helper swapped while running would fail every signature check until it restarts. If anything fails, the copy is deleted, the old helper stays and the fans keep working. The new code starts the next time the helper is launched. The test signs tiny programs with the local `pikapik Dev` certificate, or the one named in `SIGN_IDENTITY`, and stages and swaps them in a temporary folder:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Fans/FanHelperProtocol.swift scripts/test-fan-helper.swift -o build/test-fan-helper && codesign -f -s "${SIGN_IDENTITY:-pikapik Dev}" build/test-fan-helper && build/test-fan-helper
```

The fan speeds and temperatures come from the SMC. `SMCCodec` turns its bytes into numbers and back and keeps a requested fan speed between the fan's minimum and maximum:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Fans/SMC.swift scripts/test-fans.swift -o build/test-fans && build/test-fans
```

`ThermalSensors` picks which SMC sensors stand for the processor, graphics, memory, storage, battery and Wi-Fi on each chip family, from M1 to M5, and on Intel:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Symbol.swift Sources/pikapik/Tools/Fans/SMC.swift Sources/pikapik/Tools/Temperatures/Temperatures.swift scripts/test-temps.swift -o build/test-temps && build/test-temps
```

The same helper switches launch daemons off and on with `launchctl disable` and `bootout`, or `enable` and `bootstrap`, for `system/<label>`. It takes only a label and finds the file itself, so the app never hands it a path. A label must use letters, digits, dots, hyphens and underscores, must not start with `com.apple.` or be pikapik’s own, and must be the `Label` of a regular file (not a link) directly inside `/Library/LaunchDaemons`. The only exceptions are Remote Login (`com.openssh.sshd`) and Screen Sharing (`com.apple.screensharing`), which have fixed files in `/System/Library/LaunchDaemons`. File Sharing (`com.apple.smbd`) is left out: macOS 27 has no launchd on/off entry for it (the other two have one), so System Settings stays the way to change it.

Only an administrator may switch services: on every call the helper reads the user ID of the connection that sent it and checks membership of the `admin` group with `mbr_check_membership` (root counts as an administrator). Fan control and the self-update stay open to every account. The helper keeps the labels it turned off in `/Library/PrivilegedHelperTools/<label>.turned-off`, a property list owned by root (mode 644) written in one step. Turning a service off adds its label before `launchctl disable`, turning it on removes it. Remote Login and Screen Sharing are shown and turned back on only when that record lists them, so nothing an account writes can make the page offer to turn them on. The first time a new helper answers, an administrator’s app hands over the old `background-turned-off-services` list once: the helper keeps only the sharing services launchd still shows disabled, switches nothing, and the app deletes the setting. Run as root with `--restore`, before it opens the SMC, the helper turns everything in the record back on and clears it. Removing the helper from Settings, `uninstall.sh` and `brew uninstall --zap` run it first, only when the record exists and with a 30-second limit, so an older helper without `--restore` can’t hold the removal, then delete the helper, its `.new` copy, the record and the launchd file. Change the allow-list, the administrator check or the record only together with this test:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Fans/FanHelperProtocol.swift scripts/test-service-guard.swift -o build/test-service-guard && build/test-service-guard
```

iCloud sync keeps `settings.json` in the pikapik folder in iCloud Drive, or pikapik-dev for local builds. Sync reads the file with `SettingsFile.read`, which tells a missing or damaged file, which sync may replace, from one it can't read yet, for example while iCloud downloads it or the Mac is offline, which it never replaces. An upload that no change on this Mac caused, such as the first one after sync is turned on, carries a time from `SettingsFile.unclaimed` in the first day of 1970, which loses to every real file, so a Mac that joins never wipes the settings of the others. A later such upload gets an earlier time, so of two Macs that turn sync on before iCloud has anything, the second takes the settings of the first. Migration Assistant and backups copy the device id to another Mac along with the settings. A Mac never saves a file with a later time than it remembers, so a file with its own id and a later time came from such a copy: `SettingsFile.copiedDevice` then gives this Mac a new id and the file's settings, instead of the two Macs overwriting each other's file forever. Each file lists the keys its version syncs, and applying it removes only keys that version knew but left unset (`SettingsFile.removed`), so a Mac on an older version never deletes settings it doesn't have. Files from 1.56.1 and older carry no list and count as knowing the keys 1.53.1 synced, `SettingsFile.olderKeys`, which stays as it is when keys are added. The test works on temporary folders:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Settings/SettingsFile.swift Sources/pikapik/Tools/Games/GameRules.swift scripts/test-settings-folder.swift -o build/test-settings-folder && build/test-settings-folder
```

The search field in Settings matches words in any order, ignores accents and understands shortcuts typed as words, so Ctrl+Space finds ⌃Space. The rules live in `SettingsSearch`:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Settings/SettingsSearch.swift scripts/test-settings-search.swift -o build/test-settings-search && build/test-settings-search
```

The hints that point to a System Settings pane use the pane's own words, read from the string tables macOS ships in the pane's extension (`GuideTables`). One table file holds every language, so only English and the language shown are kept, and `GuideText` lets go of them when the Settings window closes. The test reads made-up tables and, where the Mac has it, the Accessibility pane, and checks that no third language is kept:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Settings/GuideTables.swift scripts/test-guide-tables.swift -o build/test-guide-tables && build/test-guide-tables
```

The app also reads the file whenever it comes to the front, so a change that arrived while it sat in the background is picked up. This check writes newer settings from "another Mac" into the local build's folder and waits for them to be applied. It needs `./scripts/build.sh` first and switches between apps, so it refuses to run unless the keyboard and mouse have been idle for two minutes:

```bash
./scripts/check-settings-sync.sh
```

Sync hears about every saved setting through `SettingsFile.onSave`, including the ones saved off the main thread, for example the list of Chromium apps that `TextFocus` keeps while it holds its lock. Such a save must not wait for the main thread: on quit the main thread waits for `TextFocus`, so a waiting save would freeze pikapik. A setting saved on the main thread is still heard at once, so sync can tell its own changes apart. The test checks both, with the main thread busy for the second, and fails if anything else in `Sources` listens for saved settings:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Settings/SettingsFile.swift Sources/pikapik/Tools/Games/GameRules.swift scripts/test-settings-sync-thread.swift -o build/test-settings-sync-thread && build/test-settings-sync-thread
```

Removing an app completely starts with `AppFootprint`, which finds everything an app keeps on the Mac and decides which app each file belongs to, without changing anything. The App Store build uses it only to list background tasks. The test builds a made-up home folder in a temporary directory, so nothing real is read or touched:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Settings/SettingsSearch.swift Sources/pikapik/Tools/Uninstaller/{AppIdentity,AppOwnerIndex,AppFootprint}.swift scripts/test-uninstaller.swift -o build/test-uninstaller && build/test-uninstaller
```

`AppRemover` moves what `AppFootprint` found to the Trash, asks for the administrator password once for the files only an administrator can move, and keeps a record so everything can be put back. Quitting apps, `launchctl`, the password prompt and Finder are all passed in as closures, so the test runs the real logic against a made-up home folder with fakes. Only a few tiny `pika-uninstall-test-*` files go through your real Trash, and the test puts them back. The Finder fallback needs the Automation permission, which the direct build declares in `Resources/Direct.entitlements`:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/Log.swift Sources/pikapik/Settings/SettingsSearch.swift Sources/pikapik/Tools/Uninstaller/{AppIdentity,AppOwnerIndex,AppFootprint}.swift Sources/pikapik/Tools/Uninstaller/AppRemover.swift scripts/test-app-remover.swift -o build/test-app-remover && build/test-app-remover
```

`AppShelf` reads apps dragged onto a page from the pasteboard and ignores other files and folders. Game Mode also accepts a bare program and a process row dragged from Activity Monitor:

```bash
swiftc -swift-version 5 -parse-as-library $(./scripts/test-core.sh $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift) scripts/test-app-drop.swift -o build/test-app-drop && build/test-app-drop
```

The Uninstaller page keeps its choices in `UninstallerLogic`: how the app list is sorted, what is ticked and what is not, the total on the **Move to Trash** button, how apps in the Trash and leftovers of removed apps are shown, and the wording of sizes and dates. The test gives it made-up apps and files, so nothing real is read or touched:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Settings/SettingsSearch.swift Sources/pikapik/Tools/Uninstaller/{AppIdentity,AppOwnerIndex,AppFootprint}.swift Sources/pikapik/Tools/Uninstaller/UninstallerLogic.swift Sources/pikapik/Core/Symbol.swift scripts/test-uninstaller-ui.swift -o build/test-uninstaller-ui && build/test-uninstaller-ui
```

`UninstallerModel` does the Uninstaller page's slow work in the background: it lists the apps, measures how much space each one takes and checks every app that goes to the Trash. Closing the sheet or starting a removal stops a long measurement within moments, and many apps moved to the Trash at once, or many reloads in a row, build the list of apps once instead of once each. App icons are drawn in the background too, so an app on a slow disk or a network volume can't freeze the window. The test gives it a made-up Mac in a temporary directory with one app full of empty folders, so nothing real is read or touched, and takes a few seconds:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Core/Log.swift Sources/pikapik/Settings/SettingsSearch.swift Sources/pikapik/Tools/Uninstaller/{AppIdentity,AppOwnerIndex,AppFootprint}.swift Sources/pikapik/Tools/Uninstaller/{AppRemover,UninstallerLogic,UninstallerModel}.swift Sources/pikapik/Core/Symbol.swift scripts/test-uninstaller-model.swift -o build/test-uninstaller-model && build/test-uninstaller-model
```

The **Background Tasks** page shows everything that starts by itself: apps that open at login, launch agents and daemons, helpers inside apps, and tasks left behind by deleted apps. `BackgroundTasks` reads what `launchctl print` reports and uses `AppFootprint` to find the app that added each task, whether it runs now, how it starts and whether its program is gone. Daemons for the whole Mac can be switched only by an administrator; a standard account sees “Needs administrator rights, so turn it off in System Settings” and a button that opens Login Items. Login items and the user’s own agents that pikapik turned off are remembered, and `pikapik --uninstall` puts them back before the app is removed. The test gives it made-up `launchctl` output and a made-up Mac in a temporary directory, so nothing real is read, turned off or touched:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Settings/SettingsSearch.swift Sources/pikapik/Tools/Fans/FanHelperProtocol.swift Sources/pikapik/Tools/Uninstaller/{AppIdentity,AppOwnerIndex,AppFootprint}.swift Sources/pikapik/Tools/Background/BackgroundTasks.swift scripts/test-background.swift -o build/test-background && build/test-background
```

The Mac App Store version keeps `BackgroundTasks.swift`, `AppIdentity.swift` and `AppFootprint.swift` for the **Background Tasks** page. Apple asks apps to give a reason for the calls that can tell when a file was made or changed, such as `stat` and `lstat`, so in the App Store version these three files call none of them and read no file dates: they get what they need from `FileManager` and `access`. The test builds them the way the App Store version is built, for Apple silicon and for Intel, and fails if any of those calls is still there:

```bash
swiftc -swift-version 5 -parse-as-library scripts/test-appstore-no-stat.swift -o build/test-appstore-no-stat && build/test-appstore-no-stat
```

`TrashWatcher` is what makes **Offer to clean up when an app goes to the Trash** work: it watches the Trash, ignores the apps that are already there when it starts, reports only the ones that arrive later, and stays quiet once stopped or when the folder cannot be read. The test watches a folder of its own in the temporary directory, never your real Trash, and takes about eight seconds. The folder stays in the temporary directory, which macOS clears itself:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Uninstaller/TrashWatcher.swift scripts/test-trash-watcher.swift -o build/test-trash-watcher && build/test-trash-watcher
```

The archive engine in `Tools/Archive/` opens and creates ZIP, 7Z, TAR.GZ and TAR.XZ files and opens RAR and many more. It runs the bundled `7zz`, plus `ditto` and `bsdtar` for ZIP names in older encodings, as separate programs, and checks every result before it is shown: nothing lands outside the output folder, links that point out are removed, setuid bits are stripped, the archive's quarantine flag is copied onto everything extracted, and an unpacking that writes far more than the archive announced is stopped. The test makes its own archives, including broken and hostile ones, in a temporary folder, mounts a 16 MB scratch disk image to run out of space on purpose, and takes about ten seconds. Run it from the repository root: it uses `Vendor/7zip/7zz` (`scripts/fetch-7zip.sh` puts it there) or the tool named in `PIKA_7ZZ`. Only RARLAB's `rar` can make RAR files, so for RAR it opens the samples from libarchive's tests in `scripts/rar-corpus/`; to try your own `.rar` files instead, set `PIKA_RAR_SAMPLES` to their folder:

```bash
swiftc -swift-version 5 -parse-as-library scripts/test-archive.swift Sources/pikapik/Core/Constants.swift Sources/pikapik/Tools/Archive/Archive{,Create,Extract,Probe,Run,Sanitize}.swift Extensions/Preview/ZipNames.swift Sources/pikapik/Core/UniqueURL.swift -o build/test-archive && build/test-archive
```

The archive windows are an `ArchivePanel`: the red button, a VoiceOver press and closing twice all answer the question only once:

```bash
swiftc -swift-version 5 -parse-as-library $(./scripts/test-core.sh $(find Sources -name '*.swift' ! -name main.swift ! -name App.swift) Extensions/Shared/*.swift Extensions/Convert/ConvertFormats.swift Extensions/Preview/ZipNames.swift) scripts/test-archive-panel.swift -o build/test-archive-panel && build/test-archive-panel
```

`Battery.swift` turns the readings from IOKit into a `BatteryState` and a `BatteryHealth`, and `BatterySettings.swift` shows them on the read-only Battery page. The battery condition comes from `system_profiler` in the direct version and straight from IOKit in the App Store version, which starts no other program. The test feeds them made-up readings, so it runs on a Mac without a battery; the second line checks the App Store version:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Constants.swift Sources/pikapik/Tools/Battery/Battery.swift scripts/test-battery.swift -o build/test-battery && build/test-battery
swiftc -swift-version 5 -parse-as-library -D APPSTORE Sources/pikapik/Core/Constants.swift Sources/pikapik/Tools/Battery/Battery.swift scripts/test-battery.swift -o build/test-battery-appstore && build/test-battery-appstore
```

The **Ports** page learns which programs listen on which ports from the same kernel list `netstat` reads (`net.inet.tcp.pcblist_n` and `net.inet.udp.pcblist_n`), so it needs no extra tools. macOS 27 gives the whole list only to programs signed without a team, like local builds and this test, so the command signs the test before running it. A signed release sees only its own sockets: it finds the user's programs through libproc, and a port it can't see is checked with a test bind, so the page never calls a taken port free. In the App Store version the sandbox blocks libproc too, so the page is hidden there. The test opens a few sockets of its own on ports the system picks, checks that the list finds each one with the right program, address and protocol and that a plain connection is not counted as listening, that a taken port is never called free, then groups made-up processes the way the page does. It only reads the list and never touches other programs:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Ports/PortScanner.swift scripts/test-ports.swift -o build/test-ports && codesign -s - -f -i com.pikapik.app.direct.test-ports build/test-ports && build/test-ports
```

The **Speed Test** page runs `networkQuality`. `SpeedResult` reads its JSON and the live progress lines and works out how long a big download would take:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/SpeedTest/SpeedResult.swift scripts/test-speed-test.swift -o build/test-speed-test && build/test-speed-test
```

The **Brightness** page changes the brightness of monitors macOS can’t adjust on its own: it asks the monitor itself through its cable or, if the monitor doesn’t listen, dims the picture. `BrightnessMath.swift` holds the parts that need no monitor: the messages that set and read the brightness with their checksums, reading the monitor’s answer even when HDMI repeats a byte or two, the maker, model and serial number from the monitor’s EDID, how dark the picture gets and the steps of the brightness keys. The test feeds it made-up bytes and never talks to a monitor:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Brightness/BrightnessMath.swift scripts/test-brightness.swift -o build/test-brightness && build/test-brightness
```

`KeyboardLayouts` is the engine behind **Fix words typed in the wrong layout**. It turns the keys that were pressed into text for every keyboard layout you have, and fixes a word only when what came out is not a word in any of your languages while another layout gives a common one, so names, slang and typos stay as typed. The test uses Apple's own layouts and the answers of the macOS spell checker recorded in `scripts/test-layout-spell.lzma`, so it gives the same result on every Mac: it checks pairs such as ghbdtn → привет, then runs every word of the app's texts in 18 languages and about 25,000 English dictionary words and names through the engine and fails on a single wrong fix. The file keeps those words of the app's texts too, so new or changed texts need no new recording. Last, it checks that an English word stays as typed when the spell checker leaves one question unanswered. When the engine asks something the file has no answer for, the test stops. The answers are recorded on a clean macOS user account with `build/test-layout record` from the repo root, which keeps the answers already in the file and adds the new ones; on your own account macOS would mix the words it learned from you and the names of your contacts into them.

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/LayoutFix/KeyboardLayouts.swift scripts/test-layout.swift -o build/test-layout && build/test-layout
```

The **Player** page opens videos in `pikapik Player.app`, a small sandboxed app inside `Contents/Helpers/` that reads only the files you open, never reaches out to the internet and listens on the network only while a video is shown on an AirPlay device (see below). It plays every file through one pipeline: the `Demuxer` from `Extensions/MediaReader/` reads the packets with FFmpeg, H.264, HEVC and AV1 go straight to `AVSampleBufferDisplayLayer`, which decodes them in hardware, other video is decoded by FFmpeg, and the sound goes to `AVSampleBufferAudioRenderer`, both kept in step by one `AVSampleBufferRenderSynchronizer`. It is an alternate app for every type until you choose it for a format from the menu on **Open videos in pikapik**, **Open music in pikapik** or **Open pictures in pikapik**: `Core/DefaultApps.swift` (shared with the archives row) assigns the chosen app, the helper or another app that opens the type, with `NSWorkspace.setDefaultApplication`, one type at a time, waiting for each answer (macOS reports “Keep” as a cancel error, which only moves on to the next type; no answer for 60 s stops the run). It keeps no memory of earlier apps, and every copy of an app counts as one app by its identifier. What the rows show is read from `urlForApplication(toOpen:)`, not from our own settings; all four, with the archives one, are the same row, `OpenWithRow` in `UI/RowStyles.swift`. Time, seeking, keys and the format list live in `PlayerLogic.swift`, and the chapter jumps, the chapter marks and the A–B loop in `PlayerMarks.swift`:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/DefaultApps.swift Sources/pikapik/Tools/Player/PlayerLogic.swift Sources/pikapik/Tools/Player/PlayerMarks.swift Sources/pikapik/Tools/Player/PlayerOutput.swift scripts/test-player.swift -o build/test-player && build/test-player
```

The Picture in Picture window (`Helper/Player/PictureInPicture.swift`) has a check too: after it is closed it must not keep the video it showed alive, which AVKit does for as long as its content source holds the delegate. It does nothing on a Mac that cannot show Picture in Picture.

```bash
swiftc -swift-version 5 -parse-as-library Helper/Player/PictureInPicture.swift scripts/test-pip.swift -o build/test-pip && build/test-pip
```

Pictures open in the same app: `Helper/Player/ImageDecoder.swift` reads them with ImageIO (SVG with `NSImage`), `Helper/Player/ImageWindow.swift` is the window, and everything that needs no window (formats, paging, keys, zoom, decoded sizes) lives in `Sources/pikapik/Tools/Player/ImageLogic.swift`. Their test writes small pictures in a dozen formats, cuts them, and checks zoom, folders, keys and damaged files:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Tools/Player/PlayerLogic.swift Sources/pikapik/Tools/Player/ImageLogic.swift Helper/Player/ImageDecoder.swift scripts/test-images.swift -o build/test-images && build/test-images
```

Remembered folders are cleaned by `FolderAccess.prune` (`Helper/Player/FolderAccess.swift`): at launch and on every new save it drops entries whose folder is deleted, in the Trash or no longer opens, and keeps those of an unplugged disk. The test saves bookmarks to temporary folders, deletes and trashes some, and checks that only the live entry is left (it keeps its settings in its temporary folder and removes the trashed folder from the Trash again):

```bash
swiftc -swift-version 5 -parse-as-library Helper/Player/FolderAccess.swift Sources/pikapik/Tools/Player/PlayerLogic.swift scripts/test-folder-access.swift -o build/test-folder-access && build/test-folder-access
```

The player window has no title bar: `WindowChrome` (`Helper/Player/WindowChrome.swift`) makes the content run under a transparent, title-less bar, hides the three window buttons and a dark gradient under them together with the control panel, decides in `overControls` whether the panel may hide (an open sheet or menu of ours keeps it), owns the hide timer that starts again when a menu closes or a sheet ends, and is the one call any other player window makes. Its test opens real windows without showing them, and compiles the player's own `VideoView` (`PlayerWindow.swift`) so that a mouse-down is followed through to the window drag and the strip zoom; it needs the bundled FFmpeg like the thumbnail test below (CI builds it before the tests, and `./scripts/build.sh` builds it on your Mac the first time):

```bash
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 -import-objc-header Helper/Player/Player.h -I Vendor/ffmpeg/include Vendor/ffmpeg/lib/*.dylib Vendor/ffmpeg/lib/libass.a -lc++ -liconv -framework CoreText -Xlinker -rpath -Xlinker "$PWD/Vendor/ffmpeg/lib" Helper/Player/{AirPlay,AirPlayBurn,AirPlayContainer,AirPlayPlaylists,AirPlaySegments,AirPlayServer,AirPlaySession,AirPlaySource,Ass,ControlPanel,Engine,FolderAccess,MusicView,NowPlaying,PictureInPicture,PictureSubtitles,PlayerControls,PlayerWindow,SubtitleScanner,Subtitles,Thumbnails,TimeMarks,TrackMenus,WindowChrome}.swift Extensions/MediaReader/{Demuxer,Formats,Codecs,AudioDecoder}.swift Sources/pikapik/Tools/Player/{PlayerLogic,PlayerMarks,PlayerOutput,SubtitleParser}.swift Sources/pikapik/Core/Symbol.swift Sources/pikapik/UI/SymbolImage.swift scripts/test-player-window.swift -o build/test-player-window && build/test-player-window
```

The chapter marks on the time bar (`Helper/Player/TimeMarks.swift`) are drawn offscreen on dark glass and must stay visible there:

```bash
swiftc -swift-version 5 -parse-as-library Helper/Player/TimeMarks.swift scripts/test-time-marks.swift -o build/test-time-marks && build/test-time-marks
```

The preview over the time bar (`Helper/Player/Thumbnails.swift`) has its own test. It makes short videos with ffmpeg (set `FFMPEG=/path/to/ffmpeg` if it is not in Homebrew’s folder), checks the picture at 50 % for H.264, MPEG-4 and VP9, the background filling, and that closing the window frees everything. For AV1 it checks the picture and playback three ways: as the Mac reads it, forced onto the built-in dav1d decoder (`PikaCodec.nativeAV1 = false`) and with VideoToolbox refusing it (`videoToolboxDecodesAV1 = false`), so both decoding paths are tested on every Mac. A seek in a 23.976 fps AVI whose file stops reading must end the film, not crash it. H.264 in 4:4:4 must play with its picture on a Mac that decodes it and be refused when it opens on one that doesn't, never play its sound over a black picture. It needs the bundled FFmpeg: CI builds it before the tests, and on your Mac `./scripts/build.sh` builds it the first time:

```bash
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 -import-objc-header Extensions/MediaReader/FFmpeg.h -I Vendor/ffmpeg/include Vendor/ffmpeg/lib/*.dylib -Xlinker -rpath -Xlinker "$PWD/Vendor/ffmpeg/lib" Helper/Player/Thumbnails.swift Helper/Player/Engine.swift Extensions/MediaReader/{Demuxer,Formats,Codecs,AudioDecoder}.swift Sources/pikapik/Tools/Player/PlayerLogic.swift scripts/test-thumbnails.swift -o build/test-thumbnails && build/test-thumbnails
```

Songs have a test too (`scripts/test-music.swift`). It makes a short song in MP3, AAC, M4A, ALAC, FLAC, WAV, AIFF, CAF, Ogg, Opus and WMA with ffmpeg, with a title, artist, album and cover, checks that each one plays, that the tags and the cover are read, and that about seventy cut, empty, random and damaged copies are refused or played without a crash. Two Matroska files it writes byte by byte have times that overflow 64-bit numbers (a jump to 10¹³ ticks with a time base of 1000001/10⁹, and a block 2⁶² ms long at 2⁶² ms); they must play or be refused without a crash too. Same ffmpeg and same build as above:

```bash
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 -import-objc-header Extensions/MediaReader/FFmpeg.h -I Vendor/ffmpeg/include Vendor/ffmpeg/lib/*.dylib -Xlinker -rpath -Xlinker "$PWD/Vendor/ffmpeg/lib" Helper/Player/Engine.swift Extensions/MediaReader/{Demuxer,Formats,Codecs,AudioDecoder}.swift Sources/pikapik/Tools/Player/PlayerLogic.swift scripts/test-music.swift -o build/test-music && build/test-music
```

The folder, the next-song logic and Now Playing have one too (`scripts/test-folder.swift`). It opens a folder of three songs in a real player window with the volume at zero, and checks the first song, the automatic move to the next one, Next and Previous, and what macOS would show in Control Center after opening, pausing, moving on and closing. It also checks that the bottom row of buttons, with every button shown and ten-hour times, fits the narrowest window, that a 16:9 video opens in a 16:9 window, and that video and music windows keep a larger size. It needs the same ffmpeg:

```bash
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 -import-objc-header Helper/Player/Player.h -I Vendor/ffmpeg/include Vendor/ffmpeg/lib/*.dylib Vendor/ffmpeg/lib/libass.a -lc++ -liconv -framework CoreText -Xlinker -rpath -Xlinker "$PWD/Vendor/ffmpeg/lib" Helper/Player/{AirPlay,AirPlayBurn,AirPlayContainer,AirPlayPlaylists,AirPlaySegments,AirPlayServer,AirPlaySession,AirPlaySource,Ass,ControlPanel,Engine,FolderAccess,MusicView,NowPlaying,PictureInPicture,PictureSubtitles,PlayerControls,PlayerWindow,SubtitleScanner,Subtitles,Thumbnails,TimeMarks,TrackMenus,WindowChrome}.swift Extensions/MediaReader/{Demuxer,Formats,Codecs,AudioDecoder}.swift Sources/pikapik/Tools/Player/{PlayerLogic,PlayerMarks,PlayerOutput,SubtitleParser}.swift Sources/pikapik/Core/Symbol.swift Sources/pikapik/UI/SymbolImage.swift scripts/test-folder.swift -o build/test-folder && build/test-folder
```

Subtitles have three tests. The reader (`Sources/pikapik/Tools/Player/SubtitleParser.swift`, no FFmpeg needed) is checked on SubRip, WebVTT, mov_text and WebVTT boxes with a byte order mark, CRLF, UTF-16, Windows-1251, overlapping lines, empty lines, broken times, the delay, the line at a given time, how an ASS script is told from other text, and random bytes:

```bash
swiftc -swift-version 5 -O -parse-as-library Sources/pikapik/Tools/Player/SubtitleParser.swift scripts/test-subtitles.swift -o build/test-subtitles && build/test-subtitles
```

ASS scripts are drawn by libass (`Helper/Player/Ass.swift`). `scripts/test-ass.swift` draws a script with `\move` and one with karaoke and compares the frames at fixed times, and a `\clip` frame, with the small reference pictures in `scripts/ass-reference/` (at most 1% of the pixels may differ; `UPDATE=1 build/test-ass` writes the pictures again after a change you meant to make). It also checks the limits on events, fonts and time, and feeds the 12 scripts in `scripts/ass-corpus/` (animation, karaoke, `\move`, `\t`, `\clip`, drawings, bidirectional text, broken tags and headers, a crowd of events) and up to 150 random changes of each (6 seconds per script) to libass in a child process; none may crash or hang:

```bash
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 -import-objc-header Helper/Player/Player.h -I Vendor/ffmpeg/include Vendor/ffmpeg/lib/*.dylib Vendor/ffmpeg/lib/libass.a -lc++ -liconv -framework CoreText -Xlinker -rpath -Xlinker "$PWD/Vendor/ffmpeg/lib" Helper/Player/Ass.swift Sources/pikapik/Tools/Player/SubtitleParser.swift scripts/test-ass.swift -o build/test-ass && build/test-ass
```

The scan of subtitle tracks inside a video, the audio switch and the subtitle logic (`Helper/Player/Subtitles.swift`) use videos that the test makes with ffmpeg (an MKV with two audio and two subtitle tracks, mov_text, ASS with a font attached to the file, and WebVTT, picture tracks in PGS, VobSub and DVB, a two-minute file, damaged copies; the test writes the PGS file itself and ffmpeg’s own encoders make VobSub and DVB from it). ASS is checked for the picture libass draws from the file, a script file next to the video and the script in the MKV, with the font from the file. The picture subtitles are checked for the decoded bitmap, the time they are shown, their place and scale over the video (also with black bars), the lift above the panel and the memory limit. The audio switch is checked for a time that does not jump, a pause that stays, and 40 quick switches with seeks. It needs the bundled FFmpeg:

```bash
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 -import-objc-header Helper/Player/Player.h -I Vendor/ffmpeg/include Vendor/ffmpeg/lib/*.dylib Vendor/ffmpeg/lib/libass.a -lc++ -liconv -framework CoreText -Xlinker -rpath -Xlinker "$PWD/Vendor/ffmpeg/lib" Helper/Player/{Ass,Engine,PictureSubtitles,SubtitleScanner,Subtitles}.swift Extensions/MediaReader/{Demuxer,Formats,Codecs,AudioDecoder}.swift Sources/pikapik/Tools/Player/{PlayerLogic,SubtitleParser}.swift scripts/test-tracks.swift -o build/test-tracks && build/test-tracks
```

AirPlay video (`Helper/Player/AirPlay*.swift`, direct build only) works when the owner picks a receiver with the system AirPlay button on the player panel: the window hands the playing film to an `AVPlayer`, and the helper serves it as HLS from the Mac. `AirPlaySource` reads the film once (key frames and tracks), `AirPlayPlaylists` cuts it into pieces of about six seconds at real key frames and writes the lists, and every piece is built only when the receiver asks for it by `AirPlaySegmentWriter` (`AVAssetWriter`, fragmented MP4): H.264 and HEVC unchanged, VP9 and AV1 re-encoded to HEVC with an H.264 variant next to it, sound as a separate track (AAC, AC-3, E-AC-3 and ALAC as they are, FLAC as ALAC, the rest as AAC), text subtitles as WebVTT and picture subtitles burnt into the frame while the track is chosen. A piece that takes longer than 90 seconds, for example because a network drive stalls, is given up only once its stalled read is back, so the next piece never reads or decodes beside it. `AirPlaySession` starts when the system list of receivers closes (macOS gives no earlier sign that a receiver was chosen): it opens `AirPlayServer` on the Mac’s own address with a fresh 128-bit token for every showing and reads the film only when the first request arrives. A film it can't open is not read again for every request: the session answers each one with an error and tells the player once, and the player says the video can't be sent instead of blaming the device or the network. If no receiver takes over within 20 seconds (40 if one has already asked) it closes; it also closes and frees its cache when the film ends, when the owner leaves AirPlay and when pikapik quits. The server answers only `GET` and `HEAD` for the exact paths it knows, never decodes a path, accepts connections only from this Mac’s own networks, drops a connection that sends no valid request within 5 seconds or stays idle for 15, and limits connections (16 served, 16 waiting, 6 per address) so that one without the token holds nothing; the sandbox gets `network.server` and `network.client` only in the player. Its test needs neither a receiver nor the internet nor FFmpeg: it checks the pieces (no gaps, key frames, six seconds, exact jumps), the choice of codecs, the lists and WebVTT, the firewall text, refusal of a wrong token, `..`, encoded and odd paths, a foreign address and a request after closing, the connection limits and timeouts, the session (it reads the film only on request, does not count this Mac’s own addresses as a receiver, opens a broken film once and reports it once, frees everything on close), the cache limit, a piece that takes too long (given up only once its stalled read is back), and builds real audio and video pieces to check that each one plays with the shared first part and starts at its time stamp (a Mac without an H.264 encoder skips the picture part):

```bash
swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 Helper/Player/AirPlayPlaylists.swift Helper/Player/AirPlayServer.swift Helper/Player/AirPlaySegments.swift Helper/Player/AirPlaySession.swift scripts/test-player-airplay.swift -o build/test-player-airplay && build/test-player-airplay
```

The re-encoding paths have a second test that needs the FFmpeg libraries and the `ffmpeg` command (Homebrew, or set `FFMPEG`; it skips without it). It makes small films and checks VP9 and AV1 re-encoded to HEVC and H.264 with the right colours, a twelve-minute film with a key frame every five minutes cut into six-second pieces that start at their time, DTS sound turned into AAC with the right tone, and picture subtitles burnt into the frame only while they are shown, with the limits local playback has: at most 16 pictures at a time and 8192 pixels a side, plus at most 32 million pixels for one piece (`AirPlayPictures.pixelBudget`). The limits are checked first, with FFmpeg's libraries only. AV1 is checked three ways, as the Mac reads it, forced onto the built-in dav1d decoder (`PikaCodec.nativeAV1 = false`) and with VideoToolbox refusing it (`videoToolboxDecodesAV1 = false`), so both decoding paths are tested on every Mac:

```bash
swiftc -swift-version 5 -O -parse-as-library -target arm64-apple-macos14.0 -import-objc-header Extensions/MediaReader/FFmpeg.h -I Vendor/ffmpeg/include Vendor/ffmpeg/lib/*.dylib -Xlinker -rpath -Xlinker "$PWD/Vendor/ffmpeg/lib" Helper/Player/Engine.swift Helper/Player/AirPlay{Burn,Container,Playlists,Segments,Server,Session,Source}.swift Extensions/MediaReader/{Demuxer,Formats,Codecs,AudioDecoder}.swift Sources/pikapik/Tools/Player/PlayerLogic.swift scripts/test-player-airplay-media.swift -o build/test-player-airplay-media && build/test-player-airplay-media
```

### Adding a tool

1. Create a file in `Sources/pikapik/Tools/` with a class that conforms to `Tool`.
2. Add one line to `ToolRegistry.tools` in `Tools/Tool.swift`.
3. Describe it in [`docs/FEATURES.md`](docs/FEATURES.md) under its Settings tab: what it does, how it works, its limits, which edition has it and how to test it by hand. Then run `./scripts/feature-form.sh` so the bug and feature forms list it. CI and `release.sh` fail while the forms and the catalog disagree. A changed tool gets the same update.
4. If users should notice it after the update, add one line to `NewMarks.items` in `UI/NewMarks.swift`: the version that ships it, the tab, the tool’s `id` as the row, and the edition. The tab gets a dot until it is opened and the row a New tag until the tab is left.

### Strings

English is the development language and the keys are the English text. Use `String(localized: "…")` when you need a `String`, and plain literals in SwiftUI (`Text("…")`, `Button("…")`). Every new key goes into `Resources/Localizable.xcstrings` for all 23 languages, and all languages must have the same set of keys. Check with:

```bash
./scripts/check-strings.sh
```

## Constants

Settings keys, paths into macOS, System Settings panes, bundle ids, links and tool ids are written once, in `Core/Constants.swift`: `PreferenceKey`, `SystemPath`, `SystemPane`, `AppConstants` and `ToolID`. Write the name, not the text: `PreferenceKey.appleLanguages`, not `"AppleLanguages"`. A typo in a key or a path gives no error, it just reads nothing. The test checks that every name holds a text, a link or a list of texts, that every name is used, that no two names in one enum hold the same value, apart from `bundleIDPrefix` and `appStoreBundleID` (the App Store app's id is the prefix itself), that no file writes the text of a key, a path, a pane, or a bundle id or link from `AppConstants` instead of its name, and that every link to an issue form names a form in `.github/ISSUE_TEMPLATE`. Files that `scripts/build.sh` also builds into the Player, the fan helper or the extensions are left out; the Player and the fan helper are built without `Constants.swift`:

```bash
swiftc -swift-version 5 -parse-as-library scripts/test-constants.swift -o build/test-constants && build/test-constants
```

## Releasing

```bash
./scripts/release.sh 1.3.0
```

The script bumps the version in `Info.plist`, commits, tags `v1.3.0` and pushes. GitHub Actions does the rest on a `macos-26` runner: builds the universal app, signs it, checks the signature and that the debug symbols come from the same build, waits until the Build workflow has passed for the same commit on `main` (both editions and every test in this file), publishes the `.zip` and `.dmg` to Releases and updates the cask in the [Homebrew tap](https://github.com/dev-pikapik/homebrew-pikapik). If that Build run fails, nothing is published: make `main` green and release the next version. Installed copies pick up the new version on their own. The debug symbols stay with the run for 90 days as the `pikapik-1.3.0-dSYM` artifact, to read crash reports from that version.

Before running the script, add the version to `CHANGELOG.md` under `## [1.3.0] - Unreleased` (the script fills in the date and the link) and add the version’s post to all 23 pages in `docs/whats-new/`: a short title, one sentence, a picture, a few short paragraphs and what to try. Pictures live in `docs/media/whats-new/<version>/`, and `scripts/render-media.sh <card>` draws them in light and dark. The script won’t start until every page has the post. It also stops unless you are on `main` with nothing to push or pull and the Build workflow has passed for that commit, so push the changelog and the posts first and wait until Build is green. The English post becomes the text of the GitHub release; `./scripts/release-notes.sh 1.3.0` shows it.

### Signing

Every release is signed with the same certificate, so macOS keeps the Accessibility and Input Monitoring permissions across updates and the fan helper accepts the next version without a password. The certificate lives in repository secrets:

- `DEVID_P12` and `DEVID_P12_PASSWORD`: the Developer ID Application certificate and private key exported as `.p12`, base64-encoded, and its password. When they are set, the release is signed with Developer ID and sent to Apple for notarization. A release never waits for Apple: with no answer in 15 minutes, the signed build goes out without a notarization ticket. If Apple refuses it, nothing is published.
- `SIGN_P12` and `SIGN_P12_PASSWORD`: a permanent self-issued certificate, used only when there is no Developer ID. Its common name must be `pikapik`.

Without any of these secrets the release job fails on purpose: an ad-hoc signed release would reset everyone's permissions.

## Icon

The icon is `Resources/AppIcon.icon` in Icon Composer format, with light and dark variants. CI compiles it with `actool` on macOS 26. macOS 14 and 15 use the fallback `Resources/AppIcon.icns`, which `build.sh` also uses when `actool` isn't available. The menu bar shows the same `pikapik.svg` as a template image. After changing the icon, regenerate the fallback and the README icon:

```bash
swift scripts/make-icns.swift
```

## Icons in Settings

Settings use three kinds of icons, the same way System Settings does:
- a colored tile (`SectionIcon` in `UI/IconStyle.swift`) marks a place: the sidebar and page headers;
- an app's own icon means the row is that program: Ports, Background, Games, Uninstaller;
- a plain symbol in a 24 pt column marks a fact: Battery, Temperature.

A program without its own icon, such as a command-line tool, gets a gray tile with the `terminal` symbol.

## Symbols

Every SF Symbol name pikapik draws is written once, in `Symbol` (`Core/Symbol.swift`): one case per symbol, named after it, so `"sun.max.fill"` is `.sunMaxFill`. Draw one with `Image(.sunMaxFill)`, `Label("Title", symbol: .sunMaxFill)` or `Button("Title", symbol: .sunMaxFill) { }` (`UI/SymbolViews.swift`), or in AppKit with `NSImage(.sunMaxFill, accessibilityDescription: nil)` (`UI/SymbolImage.swift`, which the Player is built with too), and give a view that shows a symbol a `Symbol`, not a `String`. A misspelled name, or a symbol that the oldest supported macOS doesn't have yet, draws nothing and gives no error. The test checks that every symbol in the catalog exists, that the system's own availability table has it in macOS 14, that the cases are sorted, named after their symbols and all used, and that no file but `SymbolViews.swift` and `SymbolImage.swift` writes `systemName:`, `systemSymbolName:` or `systemImage:`, so no name is typed by hand:

```bash
swiftc -swift-version 5 -parse-as-library Sources/pikapik/Core/Symbol.swift scripts/test-symbols.swift -o build/test-symbols && build/test-symbols
```

## Third-party software

The direct build includes the 7-Zip command line tool (`7zz`) from [www.7-zip.org](https://www.7-zip.org), licensed under the GNU LGPL 2.1 with the unRAR restriction. It runs as a separate program, its license is in the app as `Contents/Resources/7-Zip License.txt`, and its source code is attached to every release as `7-Zip-26.04-source.tar.xz`.

The video player uses [FFmpeg](https://ffmpeg.org) under the GNU LGPL 2.1 or later and [dav1d](https://code.videolan.org/videolan/dav1d) under the BSD 2-Clause license, built as shared libraries in `Contents/Frameworks/` with only LGPL parts enabled. For ASS subtitles it also uses [libass](https://github.com/libass/libass) (ISC), [FreeType](https://freetype.org) (FreeType License) and [HarfBuzz](https://harfbuzz.github.io) (MIT), linked into the player program, and [FriBidi](https://github.com/fribidi/fribidi) (GNU LGPL 2.1), which stays a separate `libfribidi.0.dylib` in `Contents/Frameworks/` that you can replace with your own build. All six licenses are in the app as `Contents/Resources/Player Licenses.txt`, the Player page opens them, and the exact sources are attached to every release. The App Store build has no player, so none of these libraries are in it.

The archive test opens RAR samples from the test suite of [libarchive](https://github.com/libarchive/libarchive) (`libarchive/test`), decoded from its `.uu` files with their names kept: `test_read_format_rar.rar`, `test_read_format_rar5_compressed.rar`, `test_read_format_rar_encryption_data.rar` and `test_rar_multivolume_single_file.part1.rar` to `part3.rar`, in `scripts/rar-corpus/`. They are under the BSD 2-Clause license, Copyright (c) 2003-2018 Tim Kientzle and the libarchive authors; libarchive's `COPYING` with the full text is next to them. They are only for the test and are not in the app.
