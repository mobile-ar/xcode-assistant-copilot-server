// I don't like to have the HTML and CSS as strings hardcoded here, but adding those as resources are quite annoying and this probably will never change again.
struct HealthHTMLRenderer {

    func render(_ response: HealthResponse) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Xcode Assistant Copilot \u{2014} Status</title>
        \(renderCSS())
        </head>
        <body>
        <div class="container">
        <div class="header">
        <h1>Xcode Assistant Copilot</h1>
        <p>Server Status</p>
        </div>
        \(renderStatusBanner(response.status))
        \(renderUptimeCard(uptimeSeconds: response.uptimeSeconds))
        \(renderMCPBridgeCard(enabled: response.mcpBridge.enabled))
        \(renderAuthenticationCard(response.authentication))
        \(renderLastFetchCard(lastModelFetchTime: response.lastModelFetchTime))
        <div class="footer">xcode-assistant-copilot-server</div>
        </div>
        </body>
        </html>
        """
    }

    private func renderCSS() -> String {
        """
        <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro", "Segoe UI", Roboto, sans-serif;
            background: #f5f5f7;
            color: #1d1d1f;
            padding: 40px 20px;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            margin-bottom: 32px;
        }
        .header h1 {
            font-size: 24px;
            font-weight: 700;
        }
        .header p {
            font-size: 14px;
            color: #86868b;
            margin-top: 4px;
        }
        .status-banner {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            margin-bottom: 24px;
            font-size: 18px;
            font-weight: 600;
        }
        .dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            display: inline-block;
            flex-shrink: 0;
        }
        .card {
            background: #ffffff;
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 16px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.08);
        }
        .card h2 {
            font-size: 13px;
            font-weight: 600;
            color: #86868b;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 8px;
        }
        .card .value {
            font-size: 17px;
            font-weight: 500;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .card .detail {
            font-size: 13px;
            color: #86868b;
            margin-top: 6px;
        }
        .footer {
            text-align: center;
            margin-top: 32px;
            font-size: 12px;
            color: #86868b;
        }
        @media (prefers-color-scheme: dark) {
            body {
                background: #000000;
                color: #f5f5f7;
            }
            .card {
                background: #1c1c1e;
                box-shadow: 0 1px 3px rgba(0,0,0,0.3);
            }
            .card h2 {
                color: #98989d;
            }
            .card .detail {
                color: #98989d;
            }
            .header p {
                color: #98989d;
            }
            .footer {
                color: #98989d;
            }
        }
        </style>
        """
    }

    private func renderStatusBanner(_ status: String) -> String {
        """
        <div class="status-banner">
        <span class="dot" style="background:#34c759;"></span>
        \(status.uppercased())
        </div>
        """
    }

    private func renderUptimeCard(uptimeSeconds: Int) -> String {
        let formatted = formatUptime(uptimeSeconds)
        return """
        <div class="card">
        <h2>Uptime</h2>
        <div class="value">\(formatted)</div>
        <p class="detail">\(uptimeSeconds) seconds</p>
        </div>
        """
    }

    private func renderMCPBridgeCard(enabled: Bool) -> String {
        let dotColor = enabled ? "#34c759" : "#ff3b30"
        let label = enabled ? "Enabled" : "Disabled"
        return """
        <div class="card">
        <h2>MCP Bridge</h2>
        <div class="value"><span class="dot" style="background:\(dotColor);"></span> \(label)</div>
        </div>
        """
    }

    private func renderAuthenticationCard(_ authentication: AuthenticationStatus) -> String {
        let dotColor: String
        let label: String

        switch authentication.state {
        case .authenticated:
            dotColor = "#34c759"
            label = "Authenticated"
        case .tokenExpired:
            dotColor = "#ff9500"
            label = "Token Expired"
        case .notConnected:
            dotColor = "#ff3b30"
            label = "Not Connected"
        }

        var expiryHTML = ""
        if let expiry = authentication.copilotTokenExpiry {
            expiryHTML = "\n<p class=\"detail\">Token Expiry: \(expiry)</p>"
        }

        return """
        <div class="card">
        <h2>Authentication</h2>
        <div class="value"><span class="dot" style="background:\(dotColor);"></span> \(label)</div>\(expiryHTML)
        </div>
        """
    }

    private func renderLastFetchCard(lastModelFetchTime: String?) -> String {
        let value = lastModelFetchTime ?? "Never"
        return """
        <div class="card">
        <h2>Last Model Fetch</h2>
        <div class="value">\(value)</div>
        </div>
        """
    }

    private func formatUptime(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }

        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
        }
        if hours > 0 {
            parts.append("\(hours)h")
        }
        if minutes > 0 {
            parts.append("\(minutes)m")
        }
        if days > 0 {
            if secs > 0 {
                parts.append("\(secs)s")
            }
        } else {
            parts.append("\(secs)s")
        }

        return parts.joined(separator: " ")
    }
}