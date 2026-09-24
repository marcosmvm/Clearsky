import UIKit
import UniformTypeIdentifiers
import ClearskyCore

/// The Share Sheet's principal class (`NSExtensionPrincipalClass` in `Info.plist`).
///
/// This is capture only, on purpose: a share extension gets seconds of runtime and
/// none of the main app's state, so it cannot triage anything — it reads whatever
/// plain text or URL the Share Sheet handed it, wraps it in a `CapturedPromiseDraft`,
/// appends it to the App Group inbox via `SharedDraftStore`, and dismisses. No UI is
/// shown; a person sees the system Share Sheet's own "posting" animation and control,
/// nothing from this view controller.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        captureSharedItem()
    }

    private func captureSharedItem() {
        guard
            let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = extensionItem.attachments?.first
        else {
            finish()
            return
        }

        let source = Self.inferSource(from: provider)

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] value, _ in
                self?.save(text: value as? String, source: source)
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] value, _ in
                self?.save(text: (value as? URL)?.absoluteString, source: source)
            }
        } else {
            finish()
        }
    }

    /// Best-effort guess at `CapturedPromiseSource`, documented on the type itself:
    /// the extension has no public API to ask "which app shared this", so this only
    /// checks whether the item provider declares an email-message-shaped UTType
    /// (`public.email-message` / `com.apple.mail.email`). Mail frequently shares as
    /// plain text instead, in which case this — correctly, per the doc comment on
    /// `CapturedPromiseSource` — falls through to `.text`.
    private static func inferSource(from provider: NSItemProvider) -> CapturedPromiseSource {
        let emailTypeIdentifiers = ["public.email-message", "com.apple.mail.email"]
        let isEmail = emailTypeIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
        return isEmail ? .email : .text
    }

    private func save(text: String?, source: CapturedPromiseSource) {
        defer { finish() }

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let defaults = UserDefaults(suiteName: SharedDraftStore.appGroupIdentifier) else { return }

        let draft = CapturedPromiseDraft(
            id: UUID().uuidString,
            sharedText: text,
            capturedAt: Date(),
            source: source
        )
        SharedDraftStore(defaults: defaults).append(draft)
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
