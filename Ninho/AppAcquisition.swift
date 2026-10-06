import Foundation
import StoreKit
import Security
import SwiftUI
import NinhoCore

struct StoreKitAppAcquisitionProvider: AppAcquisitionProvider {
    func verifiedAcquisition(refresh: Bool) async throws -> AppAcquisitionRecord {
        do {
            let result: VerificationResult<AppTransaction>
            if refresh { result = try await AppTransaction.refresh() }
            else { result = try await AppTransaction.shared }
            guard case .verified(let transaction) = result else { throw AppAcquisitionFailure.unverified }
            let environment: AppAcquisitionEnvironment
            if transaction.environment == .production { environment = .production }
            else if transaction.environment == .sandbox { environment = .sandbox }
            else { throw AppAcquisitionFailure.unverified }
            return AppAcquisitionRecord(bundleID: transaction.bundleID, appID: transaction.appID,
                                        environment: environment, originalPurchaseDate: transaction.originalPurchaseDate,
                                        signedDate: transaction.signedDate, signedTransaction: result.jwsRepresentation)
        } catch let error as StoreKitError {
            if case .userCancelled = error { throw AppAcquisitionFailure.cancelled }
            throw AppAcquisitionFailure.unavailable
        }
    }
}

actor KeychainAppAcquisitionCache: AppAcquisitionCache {
    private struct Envelope: Codable {
        let version: Int
        let record: AppAcquisitionRecord?
    }
    private let service: String
    init(bundleID: String) { service = bundleID + ".app-acquisition.v1" }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "app-store-production",
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }

    func load() throws -> AppAcquisitionRecord? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 262_144 else {
            throw AppAcquisitionFailure.unavailable
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1 else { throw AppAcquisitionFailure.unavailable }
        return envelope.record
    }

    func suspend() throws { try write(Envelope(version: 1, record: nil)) }

    func save(_ record: AppAcquisitionRecord) throws {
        guard record.environment == .production else { throw AppAcquisitionFailure.unverified }
        try write(Envelope(version: 1, record: record))
    }

    private func write(_ envelope: Envelope) throws {
        let data = try JSONEncoder().encode(envelope)
        guard data.count <= 262_144 else { throw AppAcquisitionFailure.unavailable }
        let values: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppAcquisitionFailure.unavailable }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppAcquisitionFailure.unavailable }
    }
}

@MainActor final class AppAcquisitionModel: ObservableObject {
    @Published private(set) var access: AppAcquisitionAccess?
    @Published private(set) var busy = false
    private let service: AppAcquisitionService
    let isDevelopment: Bool
    let configuration: AppAcquisitionConfiguration

    init() {
        configuration = AppAcquisitionConfiguration(bundleID: Bundle.main.bundleIdentifier ?? "",
                                                    appID: Bundle.main.object(forInfoDictionaryKey: "NinhoAppStoreID") as? String ?? "")
        service = AppAcquisitionService(configuration: configuration, provider: StoreKitAppAcquisitionProvider(),
                                        cache: KeychainAppAcquisitionCache(bundleID: configuration.bundleID))
        #if DEBUG || targetEnvironment(simulator)
        isDevelopment = true
        #else
        isDevelopment = false
        #endif
    }

    var canOpen: Bool { isDevelopment || access?.isGranted == true }

    func open() async {
        guard !isDevelopment, !busy, access == nil else { return }
        busy = true
        access = await service.open()
        busy = false
    }

    func retry() async {
        guard !isDevelopment, !busy else { return }
        busy = true
        access = await service.open()
        busy = false
    }

    func restore() async {
        guard !isDevelopment, !busy else { return }
        busy = true
        access = await service.restore()
        busy = false
    }

    var statusTitle: String {
        if isDevelopment { return "Versão de desenvolvimento" }
        if case .granted(let record, _, _) = access {
            return record.environment == .production ? "Seu Ninho está liberado" : "Teste pela App Store"
        }
        if case .blocked(.notConfigured) = access { return "Esta versão ainda não está pronta" }
        return busy ? "Preparando seu Ninho" : "Vamos confirmar sua aquisição"
    }

    var statusMessage: String {
        if isDevelopment { return "Ambiente local de desenvolvimento. A aquisição da App Store não foi confirmada." }
        switch access {
        case .granted(let record, _, let notice):
            if record.environment == .sandbox { return "Ambiente de teste da Apple, sem cobrança. Esta confirmação não vale como aquisição da versão publicada." }
            switch notice {
            case .cacheUnavailable: return "Aquisição confirmada. Não foi possível guardar a confirmação neste iPhone. Restaure a aquisição antes de ficar offline."
            case .restoreUnavailable: return "Não foi possível contatar a App Store. Sua confirmação anterior continua válida, inclusive offline."
            case .restoreCancelled: return "Restauração cancelada. Sua confirmação anterior continua válida, inclusive offline."
            case nil: return "Aquisição única confirmada pela App Store. Seu uso diário neste iPhone funciona offline, sem assinatura."
            }
        case .blocked(.notConfigured):
            return "Esta instalação não contém as informações necessárias para confirmar sua aquisição. Use a versão distribuída pela App Store."
        case .blocked(.cancelled):
            return "A confirmação foi cancelada. Você pode tentar novamente quando quiser. Seus estudos continuam guardados."
        case .blocked(.unverified), .blocked(.wrongApplication):
            return "A App Store não confirmou a aquisição desta instalação. Restaure usando a conta Apple que adquiriu o Ninho. Seus estudos continuam guardados."
        default:
            return "Conecte-se à internet para confirmar a aquisição pela App Store neste iPhone. Depois, seus estudos funcionam offline. Restaurar não faz uma nova cobrança."
        }
    }
}

struct AppAcquisitionGate<Content: View>: View {
    @EnvironmentObject private var acquisition: AppAcquisitionModel
    @EnvironmentObject private var store: NinhoStore
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if acquisition.canOpen {
                content().task {
                    if store.isUITesting { UIApplication.shared.isIdleTimerDisabled = true }
                    await store.start()
                }
                .safeAreaInset(edge: .top) {
                    if case .granted(_, _, .cacheUnavailable) = acquisition.access {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(acquisition.statusMessage).font(.footnote)
                            Button("Guardar confirmação novamente") { Task { await acquisition.restore() } }
                                .disabled(acquisition.busy)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(NinhoStyle.surface)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        NinhoMascot(size: 130)
                        VStack(spacing: 16) {
                            Text(acquisition.statusTitle).font(.system(.title, design: .rounded, weight: .bold))
                            Text(acquisition.statusMessage).font(.body).foregroundStyle(.secondary)
                            if acquisition.busy { ProgressView("Confirmando com a App Store…") }
                            else if acquisition.configuration.isConfigured {
                                Button { Task { await acquisition.restore() } } label: {
                                    Label("Restaurar aquisição", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).padding(8)
                                }.buttonStyle(.borderedProminent).accessibilityIdentifier("acquisition.restore")
                                Button("Tentar novamente") { Task { await acquisition.retry() } }
                                    .accessibilityIdentifier("acquisition.retry")
                            }
                        }.multilineTextAlignment(.center).ninhoCard()
                    }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
                }.defaultScrollAnchor(.center).background(NinhoStyle.canvas).accessibilityIdentifier("screen.acquisition")
            }
        }.task { await acquisition.open() }
    }
}

struct AppAcquisitionSettings: View {
    @EnvironmentObject private var acquisition: AppAcquisitionModel
    var body: some View {
        Section("Seu Ninho") {
            Label(acquisition.statusTitle, systemImage: "checkmark.shield").font(.headline)
            Text(acquisition.statusMessage).font(.body).foregroundStyle(.secondary)
            if !acquisition.isDevelopment {
                Button("Restaurar aquisição na App Store") { Task { await acquisition.restore() } }
                    .disabled(acquisition.busy).accessibilityIdentifier("settings.restoreAcquisition")
                if acquisition.busy { ProgressView("Confirmando com a App Store…") }
            }
        }
    }
}
