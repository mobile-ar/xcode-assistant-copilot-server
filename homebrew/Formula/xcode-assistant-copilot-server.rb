class XcodeAssistantCopilotServer < Formula
  desc "Local server bridging GitHub Copilot with Xcode Code Intelligence"
  homepage "https://github.com/mobile-ar/xcode-assistant-copilot-server"
  url "https://github.com/mobile-ar/xcode-assistant-copilot-server/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "MIT"
  head "https://github.com/mobile-ar/xcode-assistant-copilot-server.git", branch: "main"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  depends_on macos: :tahoe

  def install
    (buildpath/"Sources/xcode-assistant-copilot-server/Version.generated.swift").atomic_write(
      "let appVersion = \"#{version}\"\n",
    )
    system "swift", "build",
           "--disable-sandbox",
           "-c", "release",
           "--scratch-path", buildpath/".build"
    bin.install ".build/release/xcode-assistant-copilot-server"
    pkgetc.install "config.json" => "config.json.default"
  end

  service do
    run [opt_bin/"xcode-assistant-copilot-server"]
    keep_alive true
    log_path var/"log/xcode-assistant-copilot-server.log"
    error_log_path var/"log/xcode-assistant-copilot-server-error.log"
    working_dir HOMEBREW_PREFIX
  end

  def caveats
    <<~EOS
      To start the server as a background service:
        brew services start xcode-assistant-copilot-server

      Or run it manually:
        xcode-assistant-copilot-server

      The server listens on http://127.0.0.1:8080 by default.

      To use a custom port:
        xcode-assistant-copilot-server --port 9090

      To use a configuration file:
        xcode-assistant-copilot-server --config #{pkgetc}/config.json

      A default configuration file has been installed to:
        #{pkgetc}/config.json.default

      To connect Xcode:
        1. Open Xcode → Settings → Intelligence
        2. Click "Add a provider"
        3. Select "Locally hosted"
        4. Set the port to 8080 (or your custom port)
        5. Give it a description (e.g. "Copilot")
        6. Click "Add"

      On first run, you will be prompted to authenticate via
      GitHub's device code flow. Your OAuth token is stored at:
        ~/.config/xcode-assistant-copilot-server/github-token.json
    EOS
  end

  test do
    port = free_port
    pid = fork do
      exec bin/"xcode-assistant-copilot-server", "--port", port.to_s, "--log-level", "none"
    end

    begin
      sleep 5

      # The server requires GitHub auth, so /v1/models returns 401.
      # curl without -f always exits 0 regardless of HTTP status.
      output = shell_output(
        "curl -s -o /dev/null -w '%{http_code}' -H 'User-Agent: Xcode/26' http://127.0.0.1:#{port}/v1/models",
      )
      assert_equal "401", output.strip,
        "Expected HTTP 401 from unauthenticated /v1/models request"
    ensure
      Process.kill("TERM", pid)
      Process.wait(pid)
    end
  end
end
