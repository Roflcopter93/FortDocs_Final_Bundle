import Foundation
import SwiftUI

/// A manager responsible for synchronising local changes with the remote CloudKit database.
///
/// The original implementation relied on `DispatchQueue.main.async` to update the
/// `pendingChanges` property from background notifications. This introduced a race condition
/// because the array was read and modified from multiple threads without any synchronisation.
/// This refactored version embraces Swift Concurrency and isolates the mutable state in
/// an actor. All mutations to the `pendingChanges` collection occur on the actor, and the
/// UI-facing `pendingChanges` property is updated from the main actor only. This ensures
/// thread‑safety without sacrificing responsiveness.
public final class SyncManager: ObservableObject {
    /// Published collection of pending changes that require upload to the server.
    /// Access to this property is confined to the main actor; consumers should observe
    /// it on the main thread.
    @MainActor @Published public private(set) var pendingChanges: [SyncChange] = []

    /// An actor that serialises access to the internal array of changes. Using an actor
    /// eliminates data races when multiple tasks enqueue or dequeue changes concurrently.
    private let changesActor = ChangesActor()

    public init() {}

    // MARK: - Handling Changes

    /// Enqueue a new change detected by the Core Data context.
    /// - Parameter change: A representation of the change that occurred.
    ///
    /// This method captures the change on a background task and appends it to the
    /// actor‑protected array. Once the actor has updated its state the current
    /// snapshot is published back to the main actor.
    @MainActor
    public func handleCoreDataChange(_ change: SyncChange) {
        Task {
            await changesActor.add(change)
            let snapshot = await changesActor.snapshot()
            await MainActor.run {
                self.pendingChanges = snapshot
            }
        }
    }

    /// Upload all pending changes to the server.
    ///
    /// This asynchronous method drains the internal queue of changes atomically and then
    /// performs the network upload. On completion the `pendingChanges` property is
    /// cleared on the main actor. Callers should `await` this method from a background
    /// task.
    public func uploadPendingChanges() async throws {
        // Drain the actor's queue atomically. This ensures another call to
        // `handleCoreDataChange` cannot interleave and reintroduce a race.
        let changes = await changesActor.consume()
        guard !changes.isEmpty else { return }
        // Perform network upload here. The details of CloudKit uploads are omitted for
        // brevity; callers should implement their own logic to transform `changes`
        // into CKRecords and save them to the server.
        // ...
        // After a successful upload, clear the published state on the main actor.
        await MainActor.run {
            self.pendingChanges.removeAll()
        }
    }

    /// Clear all local state related to synchronisation. This method empties the
    /// change queue and resets the published property. It should be called when the
    /// user logs out or when a catastrophic error occurs that requires a reset.
    public func clearSyncData() async {
        await changesActor.reset()
        await MainActor.run {
            self.pendingChanges.removeAll()
        }
    }
}

/// An actor that serialises access to an array of `SyncChange` objects.
/// By using an actor we guarantee that only one task at a time can mutate
/// the underlying array, thereby preventing data races. The actor exposes
/// methods for adding, snapshotting and consuming changes.
public actor ChangesActor {
    private var changes: [SyncChange] = []

    /// Append a single change to the queue.
    /// - Parameter change: The change to append.
    func add(_ change: SyncChange) {
        changes.append(change)
    }

    /// Return a snapshot of all pending changes without removing them.
    /// - Returns: An array containing the current pending changes.
    func snapshot() -> [SyncChange] {
        return changes
    }

    /// Atomically return and remove all pending changes.
    /// - Returns: The changes that were pending at the time of the call.
    func consume() -> [SyncChange] {
        let current = changes
        changes.removeAll()
        return current
    }

    /// Remove all pending changes without returning them. Use this when resetting the
    /// synchronisation state.
    func reset() {
        changes.removeAll()
    }
}

/// A representation of a change that needs to be synchronised with the server.
///
/// The real project defines richer change representations for documents and folders.
/// This placeholder encompasses both types to ensure the synchronisation manager
/// compiles in isolation. In the actual app this enum should mirror the shape of
/// your Core Data models and provide sufficient context to construct `CKRecord`s.
public enum SyncChange {
    case document(Document)
    case folder(Folder)
}

/// A minimal stand‑in for the real `Document` model used by the application.
/// The original model includes much more metadata; this stub exists solely to
/// satisfy the compiler in this isolated file. You should replace it with your
/// existing model type or import it if defined elsewhere.
public struct Document: Identifiable {
    public let id: UUID
    public init(id: UUID = .init()) { self.id = id }
}

/// A minimal stand‑in for the real `Folder` model used by the application.
/// As with `Document`, replace this with your actual model or import it from
/// another module.
public struct Folder: Identifiable {
    public let id: UUID
    public init(id: UUID = .init()) { self.id = id }
}