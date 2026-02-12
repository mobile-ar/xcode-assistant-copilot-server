# Xcode Assistant Copilot Server

A Swift-based local server for macOS that bridges [GitHub Copilot](https://github.com/features/copilot) with Xcode's Code Intelligence. It acts as an **OpenAI-compatible proxy**, translating Xcode's requests into GitHub Copilot API calls.

No API keys to manage, no third-party accounts — just your GitHub Copilot subscription.

## How It Works

```
Xcode  ──►  Local Server (localhost:8080)  ──►  GitHub Copilot API
           ┌──────────────────────────────┐
           │  • GitHub device code OAuth  │
           │  • Manages Copilot tokens    │
           │  • Streams SSE responses     │
           │  • Optional MCP agent loop   │
           └──────────────────────────────┘
```

The server exposes two OpenAI-compatible endpoints that Xcode connects to:

- `GET /v1/models` — Lists available Copilot models
- `POST /v1/chat/completions` — Handles chat completions with streaming SSE

## Authentication

The server uses a multi-layered authentication strategy:

1. **Stored OAuth token** — On first use, a GitHub Device Code OAuth flow is triggered. The resulting token is stored at `~/.config/xcode-assistant-copilot-server/github-token.json` (with `0600` permissions) and reused on subsequent launches.
2. **GitHub CLI fallback** — If no stored token is found, the server tries `gh auth token` from the GitHub CLI as a fallback.
3. **Automatic device code flow** — If the Copilot token exchange fails (e.g. the `gh` token lacks Copilot scopes), the server automatically initiates a device code flow. You'll be prompted to visit a URL and enter a code in your browser.

The device code flow uses the same OAuth client ID (`Iv1.b507a08c87ecfe98`) as other Copilot integrations (copilot.vim, copilot.el, etc.) to ensure the resulting token has access to the Copilot API.

Once authenticated, the server exchanges your GitHub token for a short-lived Copilot JWT, caches it in memory, and automatically refreshes it before expiry.

## Requirements

- **macOS 26** or newer
- **Swift 6.2.3+** (install via [Swiftly](https://swiftlang.github.io/swiftly/))
- **GitHub Copilot subscription** — Individual, Business, or Enterprise
- **Xcode 26** or newer (Xcode 26.3+ for MCP tool support)
- **GitHub CLI** (`gh`) — optional, used as a fallback authentication method

## Installation

### Install via Homebrew (Recommended)

```sh
brew install mobile-ar/xcode-assistant-copilot-sever/xcode-assistant-copilot-sever
```
or
```sh
brew tap mobile-ar/xcode-assistant-copilot-sever
brew install xcode-assistant-copilot-sever
```

### Install manually

#### 1. Clone the repository and build:

```sh
git clone https://github.com/user/xcode-assistant-copilot-sever.git
cd xcode-assistant-copilot-sever
swift build -c release
sudo cp .build/release/xcode-assistant-copilot-sever /usr/local/bin/
```

#### 2. Source your shell config after copying the app

```sh
source ~/.zshrc
```
or exec your Shell
```sh
exec zsh
```
or **re-start your terminal** if none of the avobe works.

## Setup

### 1. Run the Server

```sh
xcode-assistant-copilot-sever
```

The server starts on `http://127.0.0.1:8080` by default.

**On the first run, if no stored OAuth token is found, the server will prompt you to authenticate via the GitHub device code flow:**

```
[INFO] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[INFO] GitHub authentication required.
[INFO] Please visit: https://github.com/login/device
[INFO] and enter code: ABCD-1234
[INFO] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Open the URL, enter the code, and authorize the application. The token is stored for future use.

### 2. (Optional) Install GitHub CLI

If you prefer to authenticate via the GitHub CLI instead of the device code flow:

```sh
brew install gh
gh auth login
```

### 3. Connect Xcode

1. Open **Xcode → Settings → Intelligence**
2. Click **Add a provider**
3. Select **Locally hosted**
4. Set the port to `8080` (or whichever port you configured)
5. Give it a description (e.g. "Copilot")
6. Click **Add**

#### Optional: Enable Tool Support

Under the provider's **Advanced** settings in Xcode:

- Enable **Allow tools** to let Copilot use tool calling
- Enable **Xcode Tools** under MCP (requires Xcode 26.3+) for MCP agent capabilities

## CLI Options

| Option | Default | Description |
|---|---|---|
| `--port <number>` | `8080` | Port to listen on (1–65535) |
| `--log-level <level>` | `info` | Log verbosity: `none`, `error`, `warning`, `info`, `debug`, `all` |
| `--config <path>` | — | Path to a JSON configuration file |
| `--version` | — | Show the version. |
| `-h, --help` | — | Show help information. |

### Examples

Run on a custom port with debug logging:

```sh
xcode-assistant-copilot-sever --port 9090 --log-level debug
```

Run with a custom configuration file:

```sh
xcode-assistant-copilot-sever --config ./config.json
```

## Configuration

The server can be configured via a JSON file passed with the `--config` flag. If no config file is provided, sensible defaults are used.

### Configuration File Format

```json
{
  "mcpServers": {
    "xcode": {
      "type": "local",
      "command": "xcrun",
      "args": ["mcpbridge"],
      "allowedTools": ["*"]
    }
  },
  "allowedCliTools": [],
  "bodyLimitMiB": 4,
  "excludedFilePatterns": [],
  "reasoningEffort": "xhigh",
  "autoApprovePermissions": ["read", "mcp"]
}
```

### Configuration Options

#### `mcpServers`

A dictionary of MCP (Model Context Protocol) server configurations. Each entry defines an MCP server that the agent loop can use for tool execution.

| Field | Type | Description |
|---|---|---|
| `type` | `string` | Server type: `local`, `stdio`, `http`, or `sse` |
| `command` | `string` | Command to spawn (for `local`/`stdio` types) |
| `args` | `[string]` | Arguments for the command |
| `env` | `{string: string}` | Environment variables |
| `cwd` | `string` | Working directory |
| `url` | `string` | URL (for `http`/`sse` types) |
| `headers` | `{string: string}` | HTTP headers (for `http`/`sse` types) |
| `allowedTools` | `[string]` | List of allowed tool names, or `["*"]` for all |
| `timeout` | `number` | Timeout in seconds |

#### `allowedCliTools`

An array of CLI tool names that Copilot is allowed to invoke. Use `["*"]` to allow all CLI tools. Defaults to an empty array (no CLI tools allowed).

#### `bodyLimitMiB`

Maximum request body size in MiB. Defaults to `4`.

#### `excludedFilePatterns`

An array of file path patterns to exclude from Xcode search results sent to Copilot. Matching code blocks are stripped from the context before forwarding.

#### `reasoningEffort`

Controls the reasoning effort level for Copilot responses. Options: `low`, `medium`, `high`, `xhigh`. Defaults to `xhigh`.

#### `autoApprovePermissions`

Controls which permission types are automatically approved without prompting. Can be:

- A boolean (`true` to approve all, `false` to deny all)
- An array of permission kinds: `read`, `write`, `shell`, `mcp`, `url`

Defaults to `["read", "mcp"]`.

## Operating Modes

### Direct Proxy Mode (Default)

When no MCP servers are configured, the server operates as a transparent streaming proxy:

```
Xcode → Server → Copilot API
Xcode ← Server ← Copilot API (SSE stream)
```

Tool calls from Copilot are forwarded directly to Xcode, which handles tool execution and sends results back in subsequent requests.

### Agent Mode (MCP Enabled)

When MCP servers are configured (e.g. `xcrun mcpbridge`), the server runs an internal agent loop:

```
Xcode → Server → Copilot API
                    ↕ (internal tool loop)
               MCP Bridge ↔ xcrun mcpbridge
                    ↓
Xcode ← Server (final streamed response)
```

The server buffers Copilot's response. If tool calls target MCP tools, it executes them internally via the MCP bridge, appends results to the conversation, and re-requests from Copilot. This continues until a final text response is produced, which is then streamed to Xcode.

## Security

- **Localhost only** — The server binds exclusively to `127.0.0.1` and is not accessible from other machines on the network.
- **User-Agent filtering** — Only requests with a `Xcode/` user-agent are accepted. All other requests are rejected.
- **Secure token storage** — The OAuth token from the device code flow is stored at `~/.config/xcode-assistant-copilot-server/github-token.json` with `0600` permissions (owner read/write only).
- **In-memory Copilot tokens** — Short-lived Copilot JWT tokens are cached in memory only and automatically refreshed before expiry. They are never written to disk.

## Project Structure

```
Sources/
  XcodeAssistantCopilotServer/          # Library target
    Configuration/                      # Config model and loader
    Handlers/                           # HTTP route handlers
    Models/                             # Request/response models
    Server/                             # Hummingbird server, middleware
    Services/                           # Auth, Copilot API, MCP bridge, SSE
    Utilities/                          # Logger, prompt formatter

  xcode-assistant-copilot-sever/        # Executable target
    App.swift                           # CLI entry point

Tests/
  XcodeAssistantCopilotServerTests/     # Unit tests
```

## Troubleshooting

### Device code flow not starting

The device code flow requires an internet connection to reach `github.com`. Make sure you can access `https://github.com/login/device` in your browser.

### "Copilot subscription required" errors

This means authentication succeeded but your GitHub account does not have an active Copilot subscription. Verify your subscription at [github.com/settings/copilot](https://github.com/settings/copilot).

### Token exchange fails after device code flow

If you previously authenticated but the token has been revoked or expired, delete the stored token and restart the server:

```sh
rm ~/.config/xcode-assistant-copilot-server/github-token.json
xcode-assistant-copilot-sever
```

The server will trigger a fresh device code flow.

### "GitHub CLI not found" warnings

This is not an error — it just means `gh` is not installed. The server will use the device code flow instead. If you want to suppress this warning, install the GitHub CLI:

```sh
brew install gh
gh auth login
```

### Server starts but Xcode can't connect

- Confirm the port matches between the server and Xcode settings.
- Make sure Xcode's Intelligence provider is set to **Locally hosted**.
- Check that no firewall is blocking localhost connections.
- Try running with `--log-level debug` for more details.

### MCP bridge fails to start

- MCP support requires **Xcode 26.3** or newer.
- Make sure `xcrun mcpbridge` is available by running it manually in the terminal.
- The server will continue without MCP support if the bridge fails to start.

## License

See the [LICENSE](LICENSE) file for details.
