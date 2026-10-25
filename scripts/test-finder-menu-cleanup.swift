import Foundation

@main
struct TestFinderMenuCleanup {
    static func main() {
        let own = "com.pikapik.app.direct.new-file", store = "com.pikapik.app.new-file", dev = "com.pikapik.app.dev.new-file"
        let e2e = "com.pikapik.e2e.menu.b.new-file", rehearsal = "com.pikapik.app.rehearsal.new-file"

        let apps = ["com.apple.finder", "com.pikapik.app.direct", own, "com.pikapik.app.direct.compress", dev, store, e2e, "com.example.files.new-file", "com.pikapikfan.new-file"]
        precondition(MainCopyChoice.sameMenu(own, in: apps) == [own, dev, store, e2e], "running New File extensions of pikapik copies: \(MainCopyChoice.sameMenu(own, in: apps))")
        precondition(MainCopyChoice.sameMenu(rehearsal, in: apps) == [own, dev, store, e2e], "a test copy sees the same copies")
        precondition(MainCopyChoice.sameMenu("com.pikapik.app.compress", in: apps) == ["com.pikapik.app.direct.compress"], "another kind of menu item")
        precondition(MainCopyChoice.sameMenu(own, in: ["com.pikapik.app.direct", "com.pikapik.app", "com.example.files.new-file"]).isEmpty, "apps and other developers are not copies")
        print("running extensions that count as copies: ok")

        let list = """
            +    \(own)(1.53.1)
            +    \(dev)(1.53.2)
            +    \(e2e)(1.52.2)
            +    \(rehearsal)((null))
            +    \(store)(1.53.1)
            -    com.pikapik.e2e.menu.a.new-file(1.52.2)
                 com.pikapik.app.direct.test.new-file(1.53.0)
            +    com.pikapik.app.dev.compress(1.53.2)
            +    com.example.files.new-file(3.1)
            +    com.pikapikfan.new-file(2)
            """
        let off = MainCopyChoice.ignored(own, in: list)
        precondition(!off.contains(own), "the copy never switches off its own extension: \(off)")
        precondition(!off.contains(store), "the App Store extension is never switched off: \(off)")
        precondition(off.allSatisfy { $0.hasSuffix(".new-file") && !$0.hasPrefix("com.example.") && !$0.hasPrefix("com.pikapikfan.") }, "other developers and other kinds are left alone: \(off)")
        precondition(!off.contains("com.pikapik.e2e.menu.a.new-file") && !off.contains("com.pikapik.app.direct.test.new-file"), "only switched-on extensions are switched off: \(off)")
        precondition(off == [dev, e2e, rehearsal], "the dev and test copies' New File goes off, with a version or without: \(off)")
        precondition(MainCopyChoice.ignored("com.pikapik.app.direct.compress", in: list) == ["com.pikapik.app.dev.compress"], "another kind switches off only its own kind")
        precondition(MainCopyChoice.ignored(own, in: "").isEmpty && MainCopyChoice.ignored(own, in: "+    \(own)(1.53.1)\n+    \(store)(1.53.1)\n").isEmpty, "nothing else installed")
        print("the website copy switches off New File of dev and test copies only: ok")
    }
}
