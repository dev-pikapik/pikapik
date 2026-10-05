cask "pikapik" do
  version "1.1.0"
  sha256 "d0804d6b527e13a9a98c1ee1c9198cba5cf6448c41cae8a17e209d9556ec79a8"

  url "https://github.com/dev-pikapik/pikapik/releases/download/v#{version}/pikapik.zip"
  name "pikapik"
  desc "Menu bar gaming tools: plain clicks, blocked Ctrl shortcuts and double-space"
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
