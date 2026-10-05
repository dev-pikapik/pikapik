cask "pikapik" do
  version "1.2.1"
  sha256 "285daa683abec9f3607c892c96ff4e40f37d7564f411812fe50331132b9e277d"

  url "https://github.com/dev-pikapik/pikapik/releases/download/v#{version}/pikapik.zip"
  name "pikapik"
  desc "Menu bar keyboard tools: block Ctrl shortcuts, stop double spaces, Option+Shift language switch"
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
