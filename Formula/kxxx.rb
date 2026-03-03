class Kxxx < Formula
  desc "Keychain-first secrets CLI for macOS"
  homepage "https://github.com/kxxx-dev/kxxx"
  url "https://github.com/kxxx-dev/kxxx/archive/refs/heads/main.tar.gz"
  version "0.1.0"
  sha256 :no_check
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
