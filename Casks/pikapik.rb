cask "pikapik" do
  version "1.3.0"
  sha256 "ca07f09b2ea1f2c6ed8d0d3d2259fd91c15c137b87bc2d7bb8251cce01ea1420"

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
