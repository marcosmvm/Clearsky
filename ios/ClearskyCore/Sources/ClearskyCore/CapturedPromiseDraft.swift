import Foundation

/// Best-effort guess at what kind of content the iOS Share Sheet handed us.
///
/// The Share Sheet extension only sees an `NSItemProvider` and its declared UTType —
/// it cannot open Mail.app or the Messages database to know for certain. `.email` is a
/// heuristic: the extension context's host app identifier or the presence of a mail
/// item type (`public.email-message` / an `NSExtensionItem` with an `attributedTitle`
/// sourced from Mail) is used to prefer `.email`; every other plain-text or URL share
/// (Messages, Notes, Safari selection, third-party apps) defaults to `.text`. Nothing
/// downstream should treat this as authoritative — it is a display hint only, never
/// used to change triage rules.
public enum CapturedPromiseSource: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case text
    case email
}

/// The raw material captured from the Share Sheet, before a person has triaged it.
///
/// This is intentionally the smallest possible record: a share extension has seconds
/// of runtime and no access to the rest of the app's data, so it cannot resolve a
/// `CapturedPromiseDraft` into a full triage item (that needs the confirm/edit screen,
/// built separately). `CapturedPromiseDraft` is the inbox row that screen reads from —
/// one per share action, append-only until a person confirms or discards it.
public struct CapturedPromiseDraft: Equatable, Hashable, Sendable, Codable {
    public let id: String
    public let sharedText: String
    public let capturedAt: Date
    public let source: CapturedPromiseSource

    public init(id: String, sharedText: String, capturedAt: Date, source: CapturedPromiseSource) {
        self.id = id
        self.sharedText = sharedText
        self.capturedAt = capturedAt
        self.source = source
    }
}
