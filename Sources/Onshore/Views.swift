#if canImport(SwiftUI)
import SwiftUI

/// A form that collects values and hands your app only tokens. Its text stays inside this
/// view: there is no binding to read. A value still exists in your app's process while it
/// is typed, so this keeps it out of your code and logs, not out of a compromised app.
@available(iOS 15.0, macOS 12.0, *)
public struct CollectForm: View {
    private let client: SecureClient
    private let clientToken: String
    private let labels: [String: String]
    private let submitLabel: String
    private let onTokens: ([String: String]) -> Void
    private let onError: (VaultError) -> Void

    @State private var fields: [FieldDescription] = []
    @State private var values: [String: String] = [:]
    @State private var invalid: Set<String> = []
    @State private var busy = false
    @Environment(\.scenePhase) private var phase

    public init(client: SecureClient, clientToken: String, labels: [String: String] = [:], submitLabel: String = "Continue", onTokens: @escaping ([String: String]) -> Void, onError: @escaping (VaultError) -> Void = { _ in }) {
        self.client = client
        self.clientToken = clientToken
        self.labels = labels
        self.submitLabel = submitLabel
        self.onTokens = onTokens
        self.onError = onError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(fields, id: \.name) { field in
                VStack(alignment: .leading, spacing: 4) {
                    let title = labels[field.name] ?? field.name
                    Text(title).font(.footnote)
                    entry(title: title, field: field)
                    if invalid.contains(field.name) {
                        Text("Check this value").font(.footnote).foregroundColor(.red)
                    }
                }
            }
            Button(submitLabel) { submit() }.disabled(busy || fields.isEmpty)
        }
        .task { await load() }
        .onDisappear { values = [:] }
    }

    @ViewBuilder private func entry(title: String, field: FieldDescription) -> some View {
        let text = Binding(get: { values[field.name] ?? "" }, set: { values[field.name] = $0; invalid.remove(field.name) })
        #if os(iOS)
        PrivateTextField(title: title, text: text, numeric: Self.numeric(field.dataType))
            .fixedSize(horizontal: false, vertical: true)
            .opacity(phase == .active ? 1 : 0)
            .privacySensitive()
        #else
        TextField(title, text: text).privacySensitive()
        #endif
    }

    static func numeric(_ dataType: String) -> Bool {
        ["bvn", "nin", "ng_11_digit_id", "nuban"].contains(dataType)
    }

    private func load() async {
        do {
            fields = try await client.describe(clientToken: clientToken).fields
        } catch let e as VaultError {
            onError(e)
        } catch {
            onError(.transport)
        }
    }

    private func submit() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let tokens = try await client.collect(clientToken: clientToken, values: values)
                values = [:]
                onTokens(tokens)
            } catch VaultError.validationFailed(let names) {
                invalid = Set(names)
                onError(.validationFailed(fields: names))
            } catch let e as VaultError {
                onError(e)
            } catch {
                onError(.transport)
            }
        }
    }
}

/// Shows revealed values, and hides them after `hideAfter` seconds or when the app leaves
/// the foreground. It cannot stop a screenshot on iOS, but the system marks it private.
@available(iOS 15.0, macOS 12.0, *)
public struct RevealView: View {
    private let client: SecureClient
    private let clientToken: String
    private let hideAfter: TimeInterval
    private let onError: (VaultError) -> Void

    @State private var results: [RevealedValue] = []
    @Environment(\.scenePhase) private var phase

    public init(client: SecureClient, clientToken: String, hideAfter: TimeInterval = 30, onError: @escaping (VaultError) -> Void = { _ in }) {
        self.client = client
        self.clientToken = clientToken
        self.hideAfter = hideAfter
        self.onError = onError
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                if let v = r.value {
                    Text(v).font(.system(.body, design: .monospaced)).privacySensitive()
                } else {
                    Text(r.errorCode == "policy_denied" ? "You do not have access to this" : "Not available").font(.footnote)
                }
            }
        }
        .task {
            do {
                results = try await client.reveal(clientToken: clientToken)
                try await Task.sleep(nanoseconds: UInt64(hideAfter * 1_000_000_000))
                results = []
            } catch is CancellationError {
                results = []
            } catch let e as VaultError {
                onError(e)
            } catch {
                onError(.transport)
            }
        }
        .onChange(of: phase) { p in if p != .active { results = [] } }
        .onDisappear { results = [] }
    }
}

#if os(iOS)
import UIKit

/// SwiftUI's text field has no way to turn off the edit menu or spell checking, so this is
/// UIKit's. SwiftUI's privacy redaction does not reach inside it, so the form hides it itself
/// when the app is not active, which keeps it out of the app switcher's snapshot.
@available(iOS 15.0, *)
private struct PrivateTextField: UIViewRepresentable {
    let title: String
    @Binding var text: String
    let numeric: Bool

    /// No copy, cut, paste, share or look up: nothing leaves the field through a menu.
    final class Field: UITextField {
        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
    }

    final class Coordinator: NSObject {
        var parent: PrivateTextField
        init(_ parent: PrivateTextField) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Field {
        let f = Field()
        f.placeholder = title
        f.accessibilityLabel = title
        f.keyboardType = numeric ? .numberPad : .default
        // The system keyboard learns from an ordinary text field, so all of this stays off.
        f.textContentType = nil
        f.autocorrectionType = .no
        f.spellCheckingType = .no
        f.autocapitalizationType = .none
        f.smartQuotesType = .no
        f.smartDashesType = .no
        f.smartInsertDeleteType = .no
        if #available(iOS 17.0, *) { f.inlinePredictionType = .no }
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) { f.writingToolsBehavior = .none }
        #endif
        f.inputAssistantItem.leadingBarButtonGroups = []
        f.inputAssistantItem.trailingBarButtonGroups = []
        f.textDragInteraction?.isEnabled = false
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return f
    }

    func updateUIView(_ f: Field, context: Context) {
        context.coordinator.parent = self
        if f.text != text { f.text = text }
    }
}
#endif
#endif
