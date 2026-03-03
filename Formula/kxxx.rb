class Kxxx < Formula
  desc "Keychain-first secrets CLI for macOS"
  homepage "https://github.com/kxxx-dev/kxxx"
  url "https://github.com/kxxx-dev/kxxx/archive/f1d34e959c8e82e3c4e06abe32ae69f7b37632be.tar.gz"
  version "0.1.0"
  sha256 "139a898d9ec2163faa96f6a6ba0c86878d4b019955350a60f18a5eaf90ae8cb5"
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
