#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./scripts/cask.sh 1.3.0 sha256}"
SHA="${2:?Usage: ./scripts/cask.sh 1.3.0 sha256}"

cat <<EOF
cask "pikapik" do
  version "$VERSION"
  sha256 "$SHA"

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

  uninstall quit:   "com.pikapik.app.direct",
            script: {
              executable:   "/usr/bin/env",
              args:         ["#{appdir}/pikapik.app/Contents/MacOS/pikapik", "--uninstall"],
              must_succeed: false,
            }

  zap launchctl: "com.pikapik.app.direct.fans",
      script:    {
        executable:   "/bin/bash",
        args:         ["-c", 'f=/Library/PrivilegedHelperTools/com.pikapik.app.direct.fans; [ ! -e "\$f.turned-off" ] || { "\$f" --restore >/dev/null 2>&1 & p=\$!; (sleep 30; kill \$p) >/dev/null 2>&1 & w=\$!; wait \$p; kill \$w 2>/dev/null; }'],
        sudo:         true,
        must_succeed: false,
      },
      delete:    [
        "/Library/LaunchDaemons/com.pikapik.app.direct.fans.plist",
        "/Library/PrivilegedHelperTools/com.pikapik.app.direct.fans",
        "/Library/PrivilegedHelperTools/com.pikapik.app.direct.fans.new",
        "/Library/PrivilegedHelperTools/com.pikapik.app.direct.fans.turned-off",
      ],
      trash:     [
    "~/Library/Application Scripts/com.pikapik.app.direct.archive",
    "~/Library/Application Scripts/com.pikapik.app.direct.compress",
    "~/Library/Application Scripts/com.pikapik.app.direct.convert",
    "~/Library/Application Scripts/com.pikapik.app.direct.new-file",
    "~/Library/Application Scripts/com.pikapik.app.direct.preview",
    "~/Library/Application Support/pikapik",
    "~/Library/Caches/com.pikapik.app.direct",
    "~/Library/Containers/com.pikapik.app.direct.archive",
    "~/Library/Containers/com.pikapik.app.direct.compress",
    "~/Library/Containers/com.pikapik.app.direct.convert",
    "~/Library/Containers/com.pikapik.app.direct.new-file",
    "~/Library/Containers/com.pikapik.app.direct.preview",
    "~/Library/HTTPStorages/com.pikapik.app.direct",
    "~/Library/Preferences/com.pikapik.app.direct.plist",
  ]

  caveats <<~EOS
    pikapik needs two permissions in System Settings › Privacy & Security:
      Accessibility and Input Monitoring
    The app opens a window that walks you through them.
  EOS
end
EOF
