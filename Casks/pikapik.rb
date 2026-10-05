cask "pikapik" do
  version "1.0.2"
  sha256 "92c7d03cd46c5d4e61b5c04a5b35cba0bac5dbcad1ebc9d8ed164f1758fb43d0"

  url "https://github.com/dev-pikapik/pikapik/releases/download/v#{version}/pikapik.zip"
  name "pikapik"
  desc "Menu bar tools: Ctrl+click works as a plain click"
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
    Дай pikapik два доступа в System Settings › Privacy & Security:
      Accessibility и Input Monitoring
    Окно с подсказкой откроется само.
  EOS
end
