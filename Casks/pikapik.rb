cask "pikapik" do
  version "1.14.0"
  sha256 "d01e53fd46ef21b225f8864aa0202c6f4cc517fef5e6550726e400cc0377647f"

  url "https://github.com/dev-pikapik/pikapik/releases/download/v#{version}/pikapik.zip"
  name "pikapik"
  desc "Menu bar tools for keys, windows and the Dock, plus Keep Awake"
  homepage "https://github.com/dev-pikapik/pikapik"

  auto_updates true
  depends_on macos: :sonoma

  app "pikapik.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/pikapik.app"], must_succeed: false
  end

  uninstall_preflight_steps do
    run "{{appdir}}/pikapik.app/Contents/MacOS/pikapik", args: ["--uninstall"], must_succeed: false
  end

  uninstall quit: "com.pikapik.app.direct"

  zap trash: "~/Library/Preferences/com.pikapik.app.direct.plist"

  caveats <<~EOS
    pikapik needs two permissions in System Settings › Privacy & Security:
      Accessibility and Input Monitoring
    The app opens a window that walks you through them.
  EOS
end
