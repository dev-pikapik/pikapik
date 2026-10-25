import Foundation

if CommandLine.arguments.contains("--uninstall") {
    if Brew.replacesApp(Brew.ancestors()) { exit(0) }
    LoginItem.shared.apply(false)
    #if !APPSTORE
    AnimationsTool.uninstall()
    KeyRepeatTool.uninstall()
    PointerTool.uninstall()
    DockDisplayTool.uninstall()
    DesktopIconsTool.putBack()
    HiddenFilesTool.putBack()
    HotCorners.putBackAll()
    BackgroundTasks.putBack()
    FanControl.putBackServices()
    if KeepAwake.sleepDisabled(), KeepAwake.shared.restoreLidSleepIfNeeded() { RunLoop.main.run(until: .now + 6) }
    #endif
    DockEdges.restore()
    HotKeyTrace().restore()
    exit(0)
}

#if !APPSTORE
#endif

PikapikApp.main()
