import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What went wrong with a secure component call. It never holds a value.
public enum VaultError: Error, Equatable {
    /// The token is unknown, expired, already used, or minted for another app. Ask your server for a new one.
    case invalidClientToken
    /// The fields named failed a format check. The token still works, so the person can correct them.
    case validationFailed(fields: [String])
    /// A policy refused the action.
    case denied
    /// Too many attempts from this address.
    case rateLimited
    /// Anything else the server said, with its code.
    case server(status: Int, code: String)
    /// The response could not be read, or the network failed.
    case transport
}

/// One revealed token's result.
public struct RevealedValue: Equatable, Sendable {
    public let decision: String?
    public let value: String?
    public let errorCode: String?
}

public struct FieldDescription: Equatable, Sendable {
    public let name: String
    public let dataType: String
}

public struct ComponentDescription: Equatable, Sendable {
    public let kind: String
    public let fields: [FieldDescription]
    public let tokens: Int
}

/// Talks to your own install's secure component endpoints.
///
/// This holds no credentials. Your server mints a single-use client token, and hands it to
/// the app: never put a service account key in an app. `appOrigin` is `rvapp://` and your
/// bundle id, listed under Secure components for the vault, and named by your server when
/// it mints the token.
public final class SecureClient: @unchecked Sendable {
    private let baseURL: URL
    private let appOrigin: String
    private let session: URLSession

    /// Pass your own `session` to pin your server's certificate.
    public init(baseURL: URL, appOrigin: String, session: URLSession = SecureClient.defaultSession()) {
        self.baseURL = baseURL
        self.appOrigin = appOrigin
        self.session = session
    }

    /// No cache, no cookies: nothing from these calls is written to disk by the URL loading system.
    public static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }

    public func describe(clientToken: String) async throws -> ComponentDescription {
        let json = try await post("describe", ["client_token": clientToken, "parent_origin": appOrigin])
        let fields = (json["fields"] as? [[String: Any]] ?? []).compactMap { f -> FieldDescription? in
            guard let n = f["name"] as? String else { return nil }
            return FieldDescription(name: n, dataType: f["data_type"] as? String ?? "")
        }
        return ComponentDescription(kind: json["kind"] as? String ?? "", fields: fields, tokens: json["tokens"] as? Int ?? 0)
    }

    /// Sends values, and returns a token for each field. The token is safe to give your app and server.
    public func collect(clientToken: String, values: [String: String]) async throws -> [String: String] {
        let json = try await post("collect", ["client_token": clientToken, "parent_origin": appOrigin, "values": values])
        guard let tokens = json["tokens"] as? [String: String] else { throw VaultError.transport }
        return tokens
    }

    /// Asks for the values behind the tokens the client token names. Policy decides each one.
    public func reveal(clientToken: String) async throws -> [RevealedValue] {
        let json = try await post("reveal", ["client_token": clientToken, "parent_origin": appOrigin])
        return (json["results"] as? [[String: Any]] ?? []).map { r in
            RevealedValue(decision: r["decision"] as? String, value: r["value"] as? String, errorCode: (r["error"] as? [String: Any])?["code"] as? String)
        }
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent("embed/v1/\(path)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { throw VaultError.transport }
        request.httpBody = data
        let reply: (Data, URLResponse)
        do {
            reply = try await session.data(for: request)
        } catch {
            throw VaultError.transport // the system's error can name the URL and token-bearing state
        }
        guard let http = reply.1 as? HTTPURLResponse,
              let json = (try? JSONSerialization.jsonObject(with: reply.0)) as? [String: Any] else { throw VaultError.transport }
        if (200..<300).contains(http.statusCode) { return json }
        let err = json["error"] as? [String: Any] ?? [:]
        let code = err["code"] as? String ?? ""
        switch code {
        case "invalid_client_token": throw VaultError.invalidClientToken
        case "validation_failed":
            let fields = (err["fields"] as? [Any] ?? []).compactMap { ($0 as? [String: Any])?["field"] as? String ?? ($0 as? String) }
            throw VaultError.validationFailed(fields: fields)
        case "policy_denied": throw VaultError.denied
        case "rate_limited", "too_many_requests": throw VaultError.rateLimited
        default: throw VaultError.server(status: http.statusCode, code: code)
        }
    }
}
