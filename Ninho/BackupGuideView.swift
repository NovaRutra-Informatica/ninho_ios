import SwiftUI
import UniformTypeIdentifiers

struct BackupGuideView: View {
    @EnvironmentObject private var store: NinhoStore
    @State private var importing = false
    @State private var pending: URL?
    @State private var export: URL?
    @State private var cloudConfirmation = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Seu caminho guardado", systemImage: "externaldrive.badge.checkmark").font(.title2.weight(.semibold))
                    Text("O Ninho cria uma cópia compacta por dia e a atualiza quando seus dados mudam. Mantém os últimos 7 dias, sem exigir que você salve manualmente.")
                    Text("Leva perfil, preferências, tutoriais, cursos, matérias, aulas, questões, respostas registradas, progresso, agenda e planos da Íris que você salvou. Nomes, vínculos e notas dos materiais também ficam guardados.")
                    Text("PDFs, vídeos, outros anexos e pesos de IA ficam de fora. A análise conserva apenas os agregados locais limitados a 90 dias e sua preferência de acompanhamento, sem logs de texto ou uso de outros aplicativos. Uma sessão do cronômetro ainda em andamento não entra. Após restaurar, importe novamente os anexos que quiser abrir.").font(.subheadline).foregroundStyle(.secondary)
                    if let date = store.compactBackupDate { Text("Última cópia local: \(date)").font(.footnote).accessibilityIdentifier("backup.lastDate") }
                    if !store.compactBackupNotice.isEmpty { Text(store.compactBackupNotice).font(.footnote) }
                }.ninhoCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("Continuar depois de reinstalar", systemImage: "icloud").font(.headline)
                    Toggle("Copiar automaticamente para o iCloud Drive", isOn: Binding(get: { store.cloudBackupEnabled }, set: { enabled in Task { await store.setCloudBackupEnabled(enabled) } }))
                        .accessibilityIdentifier("backup.iCloud")
                    Text("Opcional. Ao ativar, o iOS recebe somente o arquivo compacto. A sincronização depende de sua conta, espaço e conexão. O aplicativo continua funcionando offline.").font(.subheadline).foregroundStyle(.secondary)
                    if !store.cloudBackupNotice.isEmpty { Text(store.cloudBackupNotice).font(.footnote) }
                    Button { cloudConfirmation = true } label: { Label("Recuperar do iCloud", systemImage: "icloud.and.arrow.down").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(store.busy).accessibilityIdentifier("backup.restoreCloud")
                    if !store.cloudRecoveryNotice.isEmpty { Text(store.cloudRecoveryNotice).font(.footnote) }
                    Text("Em uma instalação vazia, uma cópia válida já disponível pode recuperar seu perfil antes das perguntas. Se o iCloud ainda estiver baixando ou não aparecer, use Recuperar e tente novamente. A recuperação nunca substitui automaticamente uma coleção existente.").font(.footnote).foregroundStyle(.secondary)
                }.ninhoCard()
                VStack(alignment: .leading, spacing: 14) {
                    Label("Guardar em Arquivos ou outra nuvem", systemImage: "folder").font(.headline)
                    Button { Task { export = await store.exportCompactBackup() } } label: { Label("Preparar cópia compacta", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(store.busy).accessibilityIdentifier("backup.exportCompact")
                    if let export { ShareLink(item: export) { Label("Salvar cópia em Arquivos", systemImage: "folder.badge.plus") }.buttonStyle(.bordered) }
                    Button { importing = true } label: { Label("Restaurar cópia compacta de Arquivos", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(store.busy).accessibilityIdentifier("backup.importCompact")
                    Text("Escolha iCloud Drive ou um provedor que você já usa no seletor do iPhone. Essa exportação é manual e usa o arquivo .compact.zip do Ninho; o backup ZIP completo com anexos continua nos Ajustes.").font(.footnote).foregroundStyle(.secondary)
                }.ninhoCard()
                VStack(alignment: .leading, spacing: 12) {
                    Text("O que acontece ao apagar o aplicativo?").font(.headline)
                    Text("Apagar o Ninho remove seu armazenamento privado, inclusive cópias locais. Para continuar depois, mantenha uma cópia fora do aplicativo: iCloud Drive, Arquivos ou backup do iPhone. O Backup do iCloud do próprio sistema também pode incluir a cópia compacta, conforme seus ajustes; restaurar esse backup do aparelho é diferente de apenas reinstalar o Ninho.")
                    Text("Sem uma cópia disponível fora do aplicativo, não é possível recuperar dados após a exclusão. O iOS controla as cópias em segundo plano: não prometemos executar todo dia se você não abrir o Ninho. A cópia é atualizada quando o aplicativo pode trabalhar, após seus dados serem salvos.")
                }.font(.footnote).foregroundStyle(.secondary).ninhoCard()
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }.background(NinhoStyle.canvas).navigationTitle("Backup leve").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.compactBackup")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                switch result { case .success(let urls): pending = urls.first; case .failure(let error): store.error = error.localizedDescription }
            }
            .confirmationDialog("Recuperar o perfil e os estudos desta cópia?", isPresented: Binding(get: { pending != nil || cloudConfirmation }, set: { if !$0 { pending = nil; cloudConfirmation = false } }), titleVisibility: .visible) {
                Button("Restaurar cópia", role: .destructive) {
                    let chosen = pending, cloud = cloudConfirmation; pending = nil; cloudConfirmation = false
                    Task {
                        await store.flushPreferences()
                        guard !store.hasPendingPreferences else { return }
                        if let chosen { await store.restoreBackup(chosen, compact: true) }
                        else if cloud { await store.recoverCompactFromCloud() }
                    }
                }
            } message: { Text("Os dados serão conferidos antes da troca. A coleção atual permanece no aparelho para recuperação; arquivos de materiais e modelos não serão copiados. Uma tentativa de baixar do iCloud pode precisar de tempo e conexão.") }
    }
}

struct InitialBackupRecoveryCard: View {
    @EnvironmentObject private var store: NinhoStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.cloudRecoveryNotice.isEmpty { Text(store.cloudRecoveryNotice).font(.footnote) }
            NavigationLink { BackupGuideView() } label: { Label("Já usava o Ninho? Recuperar meu perfil", systemImage: "icloud.and.arrow.down") }
                .buttonStyle(.bordered).accessibilityIdentifier("welcome.restoreBackup")
        }
    }
}
