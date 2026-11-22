// Shows the SDK's views for the UI tests. Everything comes from launch environment values,
// and the tokens are synthetic and single use.
import Onshore
import SwiftUI
import UIKit

/// Test only: an install under test has a self-signed certificate.
final class TrustTestServer: NSObject, URLSessionDelegate {
    func urlSession(_ s: URLSession, didReceive c: URLAuthenticationChallenge, completionHandler h: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let t = c.protectionSpace.serverTrust { h(.useCredential, URLCredential(trust: t)) } else { h(.performDefaultHandling, nil) }
    }
}

@main
struct TestHostApp: App {
    var body: some Scene { WindowGroup { Root() } }
}

struct Root: View {
    private let env = ProcessInfo.processInfo.environment
    @State private var result = ""
    @State private var problem = ""
    @State private var traits = ""

    private var client: SecureClient {
        SecureClient(baseURL: URL(string: env["RV_BASE"] ?? "https://localhost:8443")!, appOrigin: env["RV_APP_ORIGIN"] ?? "", session: URLSession(configuration: .ephemeral, delegate: TrustTestServer(), delegateQueue: nil))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if env["RV_SCREEN"] == "reveal" {
                RevealView(client: client, clientToken: env["RV_TOKEN"] ?? "", hideAfter: TimeInterval(env["RV_HIDE_AFTER"] ?? "") ?? 60, onError: { problem = "\($0)" })
            } else {
                CollectForm(client: client, clientToken: env["RV_TOKEN"] ?? "", labels: ["bvn": "BVN", "email": "Email"], onTokens: { result = $0.values.joined(separator: ",") }, onError: { problem = "\($0)" })
                Button("Inspect") { traits = inspectTextFields() }
            }
            Text(result).accessibilityIdentifier("result")
            Text(problem).accessibilityIdentifier("problem")
            Text(traits).accessibilityIdentifier("traits")
            Spacer()
        }
        .padding()
    }

    /// Reads back what the real text fields ended up with, as the system keyboard sees them.
    private func inspectTextFields() -> String {
        var found: [UITextField] = []
        func walk(_ v: UIView) {
            if let t = v as? UITextField { found.append(t) }
            v.subviews.forEach(walk)
        }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach(walk)
        }
        return found.map { t in
            t.becomeFirstResponder()
            t.text = "sample"
            t.selectedTextRange = t.textRange(from: t.beginningOfDocument, to: t.endOfDocument)
            let copy = t.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil)
            let cut = t.canPerformAction(#selector(UIResponderStandardEditActions.cut(_:)), withSender: nil)
            t.text = ""
            return "keyboard=\(t.keyboardType.rawValue) autocorrect=\(t.autocorrectionType.rawValue) spell=\(t.spellCheckingType.rawValue) capitalize=\(t.autocapitalizationType.rawValue) content=\(t.textContentType?.rawValue ?? "none") copy=\(copy) cut=\(cut)"
        }.joined(separator: "|")
    }
}
