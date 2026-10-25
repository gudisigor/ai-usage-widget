import Foundation
import Security

// MARK: - Helpers

private func runProcess(_ path: String, _ args: [String]) async -> String? {
    await Task.detached(priority: .utility) { () -> String? in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }.value
}

private func readJSONFile(_ relativePath: String) -> [String: Any]? {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

private func httpGetJSON(_ url: String, headers: [String: String], unauthorized: String) async throws -> [String: Any] {
    var req = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    let data: Data
    let resp: URLResponse
    do { (data, resp) = try await URLSession.shared.data(for: req) }
    catch { throw UsageError.message(t("errNoConn")) }
    guard let http = resp as? HTTPURLResponse else { throw UsageError.message(t("errBadResp")) }
    if http.statusCode == 401 || http.statusCode == 403 { throw UsageError.message(unauthorized) }
    guard http.statusCode == 200 else { throw UsageError.http(http.statusCode) }
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        throw UsageError.message(t("errFormat"))
    }
    return json
}

private func number(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }

private func parseISO(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}

private func clampRemaining(usedPercent: Double) -> Double { min(100, max(0, 100 - usedPercent)) }

/// Monthly billing cycle from a known charge day: bar = share of the cycle still left until the next charge.
private func billingWindow(anchor: Date, now: Date = Date()) -> UsageWindow {
    let cal = Calendar.current
    let day = cal.component(.day, from: anchor)
    let time = cal.dateComponents([.hour, .minute, .second], from: anchor)
    func charge(monthOffset: Int) -> Date {
        let base = cal.date(byAdding: .month, value: monthOffset, to: cal.date(from: cal.dateComponents([.year, .month], from: now))!)!
        let last = cal.range(of: .day, in: .month, for: base)!.upperBound - 1   // 31st → last day of short months
        var c = cal.dateComponents([.year, .month], from: base)
        c.day = min(day, last); c.hour = time.hour; c.minute = time.minute; c.second = time.second
        return cal.date(from: c)!
    }
    let nextOffset = charge(monthOffset: 0) > now ? 0 : 1
    let next = charge(monthOffset: nextOffset)
    let prev = charge(monthOffset: nextOffset - 1)
    let left = max(0, min(1, next.timeIntervalSince(now) / next.timeIntervalSince(prev)))
    return UsageWindow(remaining: left * 100, resetsAt: next, renewal: true)
}

// MARK: - Claude (Claude Code OAuth token → /api/oauth/usage)

struct ClaudeProvider: UsageProvider {
    private static let service = "Claude Code-credentials"
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"   // Claude Code's public OAuth client

    /// Full keychain JSON (so we can write it back unchanged apart from the tokens).
    private func loadCredentials() async -> [String: Any]? {
        if let raw = await runProcess("/usr/bin/security", ["find-generic-password", "-s", Self.service, "-w"]),
           let data = raw.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           json["claudeAiOauth"] is [String: Any] { return json }
        return nil
    }

    private func saveCredentials(_ json: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service]
        return SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess
    }

    /// Exchanges the refresh token for a new access token and stores the rotated pair.
    private func refresh(_ creds: [String: Any]) async throws -> [String: Any] {
        guard var oauth = creds["claudeAiOauth"] as? [String: Any],
              let refreshToken = oauth["refreshToken"] as? String else {
            throw UsageError.message(t("errClaudeExpired"))
        }
        var req = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": Self.clientID])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { throw UsageError.message(t("errNoConn")) }
        guard http.statusCode == 200,
              let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = body["access_token"] as? String else {
            throw UsageError.message(t("errClaudeExpired"))
        }
        oauth["accessToken"] = access
        if let r = body["refresh_token"] as? String { oauth["refreshToken"] = r }
        if let exp = number(body["expires_in"]) { oauth["expiresAt"] = Int((Date().timeIntervalSince1970 + exp) * 1000) }
        var out = creds
        out["claudeAiOauth"] = oauth
        // The refresh token is single-use: if this write fails, tell the user rather than lose the login silently.
        guard saveCredentials(out) else { throw UsageError.message(t("errKeychain")) }
        return out
    }

    private func validToken() async throws -> String {
        guard var creds = await loadCredentials() else {
            throw UsageError.message(t("errClaudeNo"))
        }
        let oauth = creds["claudeAiOauth"] as? [String: Any] ?? [:]
        let expiresAt = (number(oauth["expiresAt"]) ?? 0) / 1000
        if expiresAt - Date().timeIntervalSince1970 < 600 {
            // Claude Code may have refreshed in the meantime; re-read before spending the one-time token.
            if let fresh = await loadCredentials() { creds = fresh }
            let o = creds["claudeAiOauth"] as? [String: Any] ?? [:]
            if ((number(o["expiresAt"]) ?? 0) / 1000) - Date().timeIntervalSince1970 < 600 {
                // Not expired yet and Claude Code is running: it will renew its own token, don't race it.
                // Already expired: an idle Claude Code won't, so we do it.
                let o2 = creds["claudeAiOauth"] as? [String: Any] ?? [:]
                let alreadyExpired = ((number(o2["expiresAt"]) ?? 0) / 1000) < Date().timeIntervalSince1970
                if !alreadyExpired, await runProcess("/usr/bin/pgrep", ["-x", "claude"]) != nil {
                    throw UsageError.message(t("errWaitClaude"))
                }
                creds = try await refresh(creds)
            }
        }
        guard let token = (creds["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String else {
            throw UsageError.message(t("errClaudeNo"))
        }
        return token
    }

    func isAvailable() async -> Bool { await loadCredentials() != nil }

    func fetch() async throws -> ProviderSnapshot {
        let token = try await validToken()
        let json = try await httpGetJSON(
            "https://api.anthropic.com/api/oauth/usage",
            headers: ["Authorization": "Bearer \(token)",
                      "anthropic-beta": "oauth-2025-04-20",
                      "Accept": "application/json",
                      "User-Agent": "claude-code/2.0"],
            unauthorized: t("errClaudeExpired"))

        func window(_ key: String) -> UsageWindow? {
            guard let w = json[key] as? [String: Any], let used = number(w["utilization"]) else { return nil }
            return UsageWindow(remaining: clampRemaining(usedPercent: used), resetsAt: parseISO(w["resets_at"] as? String))
        }

        // Monthly = days until the subscription charge, anchored on the subscription start date.
        var monthly: UsageWindow?
        if let profile = try? await httpGetJSON(
            "https://api.anthropic.com/api/oauth/profile",
            headers: ["Authorization": "Bearer \(token)", "anthropic-beta": "oauth-2025-04-20", "User-Agent": "claude-code/2.0"],
            unauthorized: ""),
           let org = profile["organization"] as? [String: Any],
           let start = parseISO(org["subscription_created_at"] as? String) {
            monthly = billingWindow(anchor: start)
        }
        return ProviderSnapshot(session: window("five_hour"), weekly: window("seven_day"), monthly: monthly)
    }
}

// MARK: - ChatGPT (Codex CLI token → /backend-api/wham/usage)

struct ChatGPTProvider: UsageProvider {
    /// The id_token (a JWT we already hold locally) carries the subscription period; only its day-of-month matters.
    static func subscriptionAnchor(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let auth = claims["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        return parseISO(auth["chatgpt_subscription_active_until"] as? String)
            ?? parseISO(auth["chatgpt_subscription_active_start"] as? String)
    }

    func isAvailable() async -> Bool { readJSONFile(".codex/auth.json") != nil }

    func fetch() async throws -> ProviderSnapshot {
        guard let auth = readJSONFile(".codex/auth.json"),
              let tokens = auth["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String else {
            throw UsageError.message(t("errGPTNo"))
        }
        var headers = ["Authorization": "Bearer \(token)",
                       "Accept": "application/json",
                       "User-Agent": "codex_cli_rs"]
        if let account = tokens["account_id"] as? String { headers["ChatGPT-Account-Id"] = account }

        let json = try await httpGetJSON(
            "https://chatgpt.com/backend-api/wham/usage",
            headers: headers,
            unauthorized: t("errGPTExpired"))

        guard let limits = json["rate_limit"] as? [String: Any] else { throw UsageError.message(t("errNoLimits")) }

        var snap = ProviderSnapshot()
        if let idToken = tokens["id_token"] as? String, let anchor = Self.subscriptionAnchor(idToken) {
            snap.monthly = billingWindow(anchor: anchor)
        }
        for key in ["primary_window", "secondary_window"] {
            guard let w = limits[key] as? [String: Any], let used = number(w["used_percent"]) else { continue }
            var reset: Date?
            if let at = number(w["reset_at"]) { reset = Date(timeIntervalSince1970: at) }
            else if let after = number(w["reset_after_seconds"]) { reset = Date().addingTimeInterval(after) }
            let win = UsageWindow(remaining: clampRemaining(usedPercent: used), resetsAt: reset)
            // Bucket by real window length, so a plan change can't mislabel rows.
            let secs = number(w["limit_window_seconds"]) ?? 0
            if secs <= 86_400 + 3_600 * 6 { snap.session = win }
            else if secs <= 8 * 86_400 { snap.weekly = win }
            else { snap.monthly = win }
        }
        return snap
    }
}
