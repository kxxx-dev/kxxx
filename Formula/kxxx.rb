class Kxxx < Formula
  desc "Keychain-first secrets CLI for macOS"
  homepage "https://github.com/kxxx-dev/kxxx"
  url "https://github.com/kxxx-dev/kxxx/archive/c35325451f14beec2cdc83462cba44a2b30c7298.tar.gz"
  version "0.1.0"
  sha256 "e829a871effccc6181b01088c892cdcd1b636f175326166461ea2b334faef365"
  license "MIT"

  depends_on :macos

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"bin/kxxx"
    zsh_completion.install libexec/"completions/_kxxx"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/kxxx --help")
  end
end
