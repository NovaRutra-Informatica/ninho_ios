import Foundation

public struct AppAcquisitionConfiguration: Sendable, Equatable {
    public let bundleID: String
    public let appID: UInt64?

    public init(bundleID: String, appID: String) {
        self.bundleID = bundleID
        self.appID = appID.allSatisfy({ $0.isASCII && $0.isNumber }) ? UInt64(appID) : nil
    }

    public var isConfigured: Bool {
        !bundleID.isEmpty && !bundleID.contains("$(") && (appID ?? 0) > 0
    }
}

public enum AppAcquisitionEnvironment: String, Codable, Sendable {
    case production, sandbox
}

// Only a StoreKit .verified result or the app's protected Keychain may supply this record.
// Decoding JSON or checking these fields does not verify an App Store signature.
public struct AppAcquisitionRecord: Codable, Sendable, Equatable {
    public let version: Int
    public let bundleID: String
    public let appID: UInt64?
    public let environment: AppAcquisitionEnvironment
    public let originalPurchaseDate: Date
    public let signedDate: Date
    public let signedTransaction: String

    public init(bundleID: String, appID: UInt64?, environment: AppAcquisitionEnvironment,
                originalPurchaseDate: Date, signedDate: Date, signedTransaction: String, version: Int = 1) {
        self.version = version
        self.bundleID = bundleID
        self.appID = appID
        self.environment = environment
        self.originalPurchaseDate = originalPurchaseDate
        self.signedDate = signedDate
        self.signedTransaction = signedTransaction
    }

    public func matches(_ configuration: AppAcquisitionConfiguration) -> Bool {
        guard configuration.isConfigured, version == 1, bundleID == configuration.bundleID,
              !signedTransaction.isEmpty, signedTransaction.utf8.count <= 131_072,
              originalPurchaseDate.timeIntervalSince1970.isFinite,
              signedDate.timeIntervalSince1970.isFinite else { return false }
        switch environment {
        case .production: return appID == configuration.appID
        case .sandbox: return appID == nil || appID == configuration.appID
        }
    }
}

public enum AppAcquisitionFailure: Error, Sendable, Equatable {
    case notConfigured, unverified, wrongApplication, unavailable, cancelled
}

public enum AppAcquisitionSource: Sendable, Equatable {
    case store, deviceCache
}

public enum AppAcquisitionNotice: Sendable, Equatable {
    case cacheUnavailable, restoreUnavailable, restoreCancelled
}

public enum AppAcquisitionAccess: Sendable, Equatable {
    case granted(AppAcquisitionRecord, AppAcquisitionSource, AppAcquisitionNotice?)
    case blocked(AppAcquisitionFailure)

    public var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }
}

public protocol AppAcquisitionProvider: Sendable {
    func verifiedAcquisition(refresh: Bool) async throws -> AppAcquisitionRecord
}

public protocol AppAcquisitionCache: Sendable {
    func load() async throws -> AppAcquisitionRecord?
    // Persist a denial before contacting the store; success must survive process termination.
    func suspend() async throws
    func save(_ record: AppAcquisitionRecord) async throws
    func remove() async throws
}

public actor AppAcquisitionService {
    private let configuration: AppAcquisitionConfiguration
    private let provider: any AppAcquisitionProvider
    private let cache: any AppAcquisitionCache
    private var cacheIsTrusted = true

    public init(configuration: AppAcquisitionConfiguration, provider: any AppAcquisitionProvider,
                cache: any AppAcquisitionCache) {
        self.configuration = configuration
        self.provider = provider
        self.cache = cache
    }

    public func open() async -> AppAcquisitionAccess {
        guard configuration.isConfigured else { return .blocked(.notConfigured) }
        if let record = await savedProductionAcquisition() {
            return .granted(record, .deviceCache, nil)
        }
        return await verify(refresh: false)
    }

    public func restore() async -> AppAcquisitionAccess {
        guard configuration.isConfigured else { return .blocked(.notConfigured) }
        return await verify(refresh: true)
    }

    private func savedProductionAcquisition() async -> AppAcquisitionRecord? {
        guard cacheIsTrusted, let record = try? await cache.load(), record.environment == .production,
              record.matches(configuration) else { return nil }
        return record
    }

    private func verify(refresh: Bool) async -> AppAcquisitionAccess {
        let previous = await savedProductionAcquisition()
        do {
            try Task.checkCancellation()
            try await cache.suspend()
            cacheIsTrusted = false
        } catch {
            if let previous { return .granted(previous, .deviceCache, .restoreUnavailable) }
            return .blocked(error is CancellationError ? .cancelled : .unavailable)
        }
        do {
            try Task.checkCancellation()
            let record = try await provider.verifiedAcquisition(refresh: refresh)
            try Task.checkCancellation()
            guard record.matches(configuration) else { throw AppAcquisitionFailure.wrongApplication }
            if record.environment == .sandbox {
                return .granted(record, .store, nil)
            }
            do {
                try await cache.save(record)
                cacheIsTrusted = true
                return .granted(record, .store, nil)
            } catch {
                return .granted(record, .store, .cacheUnavailable)
            }
        } catch {
            let failure = error is CancellationError ? .cancelled : (error as? AppAcquisitionFailure ?? .unavailable)
            if failure == .unverified || failure == .wrongApplication {
                try? await cache.remove()
            } else if let previous {
                do {
                    try await cache.save(previous)
                    cacheIsTrusted = true
                    return .granted(previous, .deviceCache, failure == .cancelled ? .restoreCancelled : .restoreUnavailable)
                } catch {
                    return .granted(previous, .deviceCache, .cacheUnavailable)
                }
            }
            return .blocked(failure)
        }
    }
}
