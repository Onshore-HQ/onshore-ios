// Drives the SDK against a live install, on macOS, and exits non-zero on any wrong answer.
// Trusts the install's test certificate through its own session, as an app pinning would.
import Foundation
import Onshore

final class TrustTestServer: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge, completionHandler h: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let t = c.protectionSpace.serverTrust { h(.useCredential, URLCredential(trust: t)) } else { h(.performDefaultHandling, nil) }
    }
}

func env(_ k: String) -> String { ProcessInfo.processInfo.environment[k] ?? "" }
var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "  ok    " : "  FAIL  ") + name + (ok ? "" : " " + detail))
    if !ok { failures += 1 }
}

let session = URLSession(configuration: .ephemeral, delegate: TrustTestServer(), delegateQueue: nil)
let client = SecureClient(baseURL: URL(string: env("RV_BASE"))!, appOrigin: env("RV_APP_ORIGIN"), session: session)
let wrongApp = SecureClient(baseURL: URL(string: env("RV_BASE"))!, appOrigin: "rvapp://ng.other.app", session: session)
let value = env("RV_VALUE")

func expectError<T>(_ want: VaultError, _ f: () async throws -> T) async -> Bool {
    do { _ = try await f(); return false } catch let e as VaultError { return e == want } catch { return false }
}

let token = env("RV_COLLECT_TOKEN")
let d = try await client.describe(clientToken: token)
check("iOS: describe names the field", d.kind == "collect" && d.fields.first?.name == "bvn" && d.fields.first?.dataType == "bvn", "\(d)")
check("iOS: another app's origin is refused", await expectError(.invalidClientToken) { try await wrongApp.describe(clientToken: token) })
check("iOS: a typo keeps the token and names the field", await expectError(.validationFailed(fields: ["bvn"])) { try await client.collect(clientToken: token, values: ["bvn": "nope"]) })
let tokens = try await client.collect(clientToken: token, values: ["bvn": value])
check("iOS: collect returns a token, not the value", tokens["bvn"]?.hasPrefix("tok_bvn_") == true && tokens["bvn"]?.contains(value) == false, "\(tokens)")
check("iOS: a client token works once", await expectError(.invalidClientToken) { try await client.collect(clientToken: token, values: ["bvn": value]) })
print("RV_TOKEN=\(tokens["bvn"] ?? "")")
let rv = env("RV_REVEAL_TOKEN")
if !rv.isEmpty {
    let shown = try await client.reveal(clientToken: rv)
    check("iOS: reveal returns the value policy allows", shown.first?.value == env("RV_REVEAL_VALUE"), "\(shown)")
}
let denied = env("RV_DENIED_TOKEN")
if !denied.isEmpty {
    let shown = try await client.reveal(clientToken: denied)
    check("iOS: reveal holds nothing when policy refuses", shown.first?.value == nil && shown.first?.errorCode == "policy_denied", "\(shown)")
}
exit(failures == 0 ? 0 : 1)
