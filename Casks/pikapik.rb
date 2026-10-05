cask "pikapik" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/dev-pikapik/pikapik/releases/download/v#{version}/pikapik.zip"
  name "pikapik"
  desc "Menu bar tools: Ctrl+click works as a plain click"
  homepage "https://github.com/dev-pikapik/pikapik"

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "pikapik.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/pikapik.app"]
    system_command "/usr/bin/tccutil", args: ["reset", "Accessibility", "com.pikapik.app.direct"], must_succeed: false
    system_command "/usr/bin/tccutil", args: ["reset", "ListenEvent", "com.pikapik.app.direct"], must_succeed: false
    system_command "/usr/bin/open", args: ["#{appdir}/pikapik.app"]
  end

  uninstall_preflight do
    system_command "#{appdir}/pikapik.app/Contents/MacOS/pikapik", args: ["--uninstall"], must_succeed: false
  end

  uninstall quit: "com.pikapik.app.direct"

  zap trash: "~/Library/Preferences/com.pikapik.app.direct.plist"

  caveats <<~EOS
    Дай pikapik два доступа в System Settings › Privacy & Security:
      Accessibility и Input Monitoring
    Окно с подсказкой откроется само.
  EOS
end
