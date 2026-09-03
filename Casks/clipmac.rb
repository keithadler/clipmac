# Homebrew cask for Clip for Mac. Submit to homebrew/cask after the first public release,
# or install from this file: brew install --cask ./Casks/clipmac.rb
cask "clipmac" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHASUM_OF_DMG"

  url "https://github.com/keithadler/clipmac/releases/download/v#{version}/Clip-for-Mac-#{version}.dmg"
  name "Clip for Mac"
  desc "Clipboard history that refuses to capture secrets"
  homepage "https://github.com/keithadler/clipmac"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Clip for Mac.app"
  binary "#{appdir}/Clip for Mac.app/Contents/MacOS/ClipMac", target: "clipmac"
  manpage "docs/clipmac.1"

  uninstall quit: "com.keithadler.clipmac"

  zap trash: [
    "~/Library/Application Support/Clip for Mac",
    "~/Library/Preferences/com.keithadler.clipmac.shared.plist",
  ]

  caveats <<~EOS
    Press ⌥⌘V to open the panel. Auto-paste needs the Accessibility permission
    (System Settings › Privacy & Security › Accessibility); without it, choose an
    item and press ⌘V yourself.
  EOS
end
