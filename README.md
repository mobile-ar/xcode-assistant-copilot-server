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
           │  • Context window management │
           └──────────────────────────────┘
```

The server exposes the following OpenAI-compatible endpoints that Xcode connects to:

- `GET /health` — Returns server health status, uptime, and MCP bridge status
- `GET /v1/models` — Lists available Copilot models
- `POST /v1/chat/completions` — Handles chat completions with streaming SSE

For models that only support the Responses API (e.g. Codex models), the server automatically detects this via the model's supported endpoints and internally translates chat completion requests into Responses API calls. The response is then adapted back into the chat completions SSE format, so Xcode always communicates using the same `/v1/chat/completions` endpoint.

## Authentication

The server uses a multi-layered authentication strategy:

1. **Stored OAuth token** — On first use, a GitHub Device Code OAuth flow is triggered. The resulting token is stored at `~/.config/xcode-assistant-copilot-server/github-token.json` (with `0600` permissions) and reused on subsequent launches.
2. **GitHub CLI fallback** — If no stored token is found, the server tries `gh auth token` from the GitHub CLI as a fallback.
3. **Automatic device code flow** — If no token is available at all (GitHub CLI not installed or not authenticated), or if the token exchange is rejected by GitHub (e.g. the `gh` token lacks Copilot scopes), the server automatically initiates a device code flow. You'll be prompted to visit a URL and enter a code in your browser.

The device code flow uses the same OAuth client ID (`Iv1.b507a08c87ecfe98`) as other Copilot integrations (copilot.vim, copilot.el, etc.) to ensure the resulting token has access to the Copilot API.

Once authenticated, the server exchanges your GitHub token for a short-lived Copilot JWT, caches it in memory, and automatically refreshes it before expiry.

## Requirements

### Homebrew install

- **macOS 26** or newer
- **Xcode Command Line Tools 26.x** — any 26.x release is sufficient (`xcode-select --install`). Homebrew builds the binary using the system Swift bundled with the CLT; no separate Swift or Swiftly installation is needed.
- **GitHub Copilot subscription** — Individual, Business, or Enterprise
- **Xcode 26** or newer to use the provider (Xcode 26.3+ for MCP tool support)
- **GitHub CLI** (`gh`) — optional, used as a fallback authentication method

### Manual / source build

- **macOS 26** or newer
- **Swift 6.2.4+** — install via [Swiftly](https://swiftlang.github.io/swiftly/) or Xcode Command Line Tools 26.x
- **GitHub Copilot subscription** — Individual, Business, or Enterprise
- **Xcode 26** or newer to use the provider (Xcode 26.3+ for MCP tool support)
- **GitHub CLI** (`gh`) — optional, used as a fallback authentication method

## Installation

### Install via Homebrew (Recommended)

```sh
brew install mobile-ar/xcode-assistant-copilot-server/xcode-assistant-copilot-server
```
or
```sh
brew tap mobile-ar/xcode-assistant-copilot-server
brew install xcode-assistant-copilot-server
```

### Install manually

#### 1. Clone the repository and build:

```sh
git clone https://github.com/user/xcode-assistant-copilot-server.git
cd xcode-assistant-copilot-server
swift build -c release
sudo cp .build/release/xcode-assistant-copilot-server /usr/local/bin/
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
xcode-assistant-copilot-server
```

The server starts on `http://127.0.0.1:8080` by default.

**On the first run, a default configuration file is created at `~/.config/xcode-assistant-copilot-server/config.json` with MCP bridge support enabled.** You can edit this file to customize the server behavior. See [Configuration](#configuration) for details.

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
| `--config <path>` | `~/.config/xcode-assistant-copilot-server/config.json` | Path to a JSON configuration file |
| `--version` | — | Show the version. |
| `-h, --help` | — | Show help information. |

### Examples

Run on a custom port with debug logging:

```sh
xcode-assistant-copilot-server --port 9090 --log-level debug
```

Run with a custom configuration file:

```sh
xcode-assistant-copilot-server --config /path/to/custom-config.json
```

## Configuration

On first launch, the server creates a default configuration file at `~/.config/xcode-assistant-copilot-server/config.json` with MCP bridge support enabled. You can edit this file directly to customize the server. Use the `--config` flag to load a configuration file from a different path instead.

### Configuration File Format

This is the default config that has Xcode MCP enabled by default. To regenerate the file to it's defaults just delete the file and run `xcode-assistant-copilot-server` again
```json
{
  "mcpServers": {
    "xcode": {
      "type": "local",
      "command": "xcrun",
      "args": ["mcpbridge"],
      "allowedTools": ["*"],
      "timeoutSeconds": 300
    }
  },
  "allowedCliTools": [],
  "bodyLimitMiB": 4,
  "contextRecencyWindow": 3,
  "excludedFilePatterns": [],
  "maxAgentLoopIterations": 20,
  "reasoningEffort": "xhigh",
  "autoApprovePermissions": ["read", "mcp"],
  "timeouts": {
    "requestTimeoutSeconds": 300,
    "streamingEndpointTimeoutSeconds": 300,
    "httpClientTimeoutSeconds": 300
  }
}
```

To use the non MCP version just remove the whole 'xcode' object from the json.
```json
{
  "mcpServers": {},
  "allowedCliTools": [],
  "bodyLimitMiB": 4,
  "contextRecencyWindow": 3,
  "excludedFilePatterns": [],
  "maxAgentLoopIterations": 20,
  "reasoningEffort": "xhigh",
  "autoApprovePermissions": ["read", "mcp"],
  "timeouts": {
    "requestTimeoutSeconds": 300,
    "streamingEndpointTimeoutSeconds": 300,
    "httpClientTimeoutSeconds": 300
  }
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
| `timeoutSeconds` | `number` | Maximum time in seconds to wait for a single MCP tool call to complete before cancelling it and returning a timeout error to the model. Defaults to `300` if omitted. Must be greater than `0`. |

#### `allowedCliTools`

An array of CLI tool names that Copilot is allowed to invoke. Use `["*"]` to allow all CLI tools. Defaults to an empty array (no CLI tools allowed).

#### `bodyLimitMiB`

Maximum request body size in MiB. Defaults to `4`.

#### `excludedFilePatterns`

An array of file path patterns to exclude from Xcode search results sent to Copilot. Matching code blocks are stripped from the context before forwarding.

#### `reasoningEffort`

Controls the reasoning effort level for Copilot responses. Options: `low`, `medium`, `high`, `xhigh`. Defaults to `xhigh`.

The server automatically retries with a lower reasoning effort if the model rejects the configured level, and caches the maximum supported level per model for subsequent requests.

#### `maxAgentLoopIterations`

Maximum number of iterations the agent loop can run before stopping. Each iteration may involve a Copilot API call and one or more MCP tool executions. Defaults to `20`.

#### `contextRecencyWindow`

Controls how many recent assistant+tool interaction pairs are kept in full when the conversation context is compacted. Older tool results are truncated and older tool call arguments are stripped to reduce token usage. The context window limit is automatically resolved per model from the Copilot API (e.g. 128k tokens for GPT-4o, 400k for Codex models), falling back to 128,000 tokens if the API doesn't provide a limit. Defaults to `3`.

#### `autoApprovePermissions`

Controls which permission types are automatically approved without prompting. Can be:

- A boolean (`true` to approve all, `false` to deny all)
- An array of permission kinds: `read`, `write`, `shell`, `mcp`, `url`

Defaults to `["read", "mcp"]`.

#### `timeouts`

An optional object controlling the various timeout durations used by the server. All values are in seconds. If omitted, all fields use their defaults.

| Field | Type | Default | Description |
|---|---|---|---|
| `requestTimeoutSeconds` | `number` | `300` | Maximum time the server waits for a complete streaming response from the Copilot API before cancelling the request and returning a timeout error to Xcode. |
| `streamingEndpointTimeoutSeconds` | `number` | `300` | Per-request `URLRequest` timeout for streaming endpoints (`/chat/completions` and `/responses`). Controls how long the underlying URL session waits before the connection is considered timed out. |
| `httpClientTimeoutSeconds` | `number` | `300` | Session-level `timeoutIntervalForRequest` applied to the shared `URLSession` used by the HTTP client. |

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

The server buffers Copilot's response. If tool calls target MCP tools, it executes them internally via the MCP bridge, appends results to the conversation, and re-requests from Copilot. This continues until a final text response is produced (or `maxAgentLoopIterations` is reached), which is then streamed to Xcode.

To keep payloads within the model's context window, the server automatically compacts the conversation on each iteration: older tool results are truncated and old tool call arguments are stripped, while the most recent interactions (controlled by `contextRecencyWindow`) are preserved in full. The per-model context window limit is resolved from the Copilot models API. Token usage is logged each iteration (e.g. `Current token usage 12000/128000 (9%)`), with a warning when usage exceeds 80%.

## Security

- **Localhost only** — The server binds exclusively to `127.0.0.1` and is not accessible from other machines on the network.
- **User-Agent filtering** — Only requests with a `Xcode/` user-agent are accepted. All other requests are rejected (except the `/health` endpoint, which is exempt from this check).
- **CORS middleware** — The server includes CORS headers (`Access-Control-Allow-Origin: *`) to handle preflight `OPTIONS` requests.
- **Secure token storage** — The OAuth token from the device code flow is stored at `~/.config/xcode-assistant-copilot-server/github-token.json` with `0600` permissions (owner read/write only).
- **In-memory Copilot tokens** — Short-lived Copilot JWT tokens are cached in memory only and automatically refreshed before expiry. They are never written to disk.

## Project Structure

```
Sources/
  XcodeAssistantCopilotServer/          # Library target
    Configuration/                      # Config model and loader
    Handlers/                           # HTTP route handlers (health, models, chat completions)
    Models/                             # Request/response models, MCP messages, OAuth tokens
    Networking/                         # HTTP client, endpoint protocol, request headers
      Endpoints/                        # Concrete endpoint definitions (Copilot API, device flow, etc.)
    Server/                             # Hummingbird server, route registry, middleware (CORS, logging, user-agent)
    Services/                           # Auth, Copilot API, MCP bridge, device flow, SSE parser, signal handler
    Utilities/                          # Logger, prompt formatter, error response builder, extensions

  xcode-assistant-copilot-server/       # Executable target
    App.swift                           # CLI entry point (ArgumentParser)

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
xcode-assistant-copilot-server
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

### Reasoning effort rejected by model

If a model doesn't support the configured reasoning effort level, the server automatically retries with progressively lower levels (`xhigh` → `high` → `medium` → `low`). The maximum supported level is cached per model to avoid repeated retries. No action is needed — this is handled transparently.

## License

See the [LICENSE](LICENSE) file for details.
