import SwiftUI
import UniformTypeIdentifiers
import NinhoCore

struct SettingsView: View {
    @EnvironmentObject var store: NinhoStore
    @State private var settings = Settings()
    @State private var importing = false
    @State private var pendingRestore: URL?
    @State private var exportURL: URL?
    var body: some View {
        Form {
            Section("Do seu jeito") {
                TextField("Seu nome", text: $settings.name).accessibilityIdentifier("settings.name")
                Stepper("Meta diária: \(settings.dailyMinutes) minutos", value: $settings.dailyMinutes, in: 5...720, step: 5).accessibilityIdentifier("settings.dailyMinutes")
                Stepper("Novos cartões por dia: \(settings.newCardsPerDay)", value: $settings.newCardsPerDay, in: 0...200)
                Stepper("Foco: \(settings.focusMinutes) minutos", value: $settings.focusMinutes, in: 1...180)
                Stepper("Pausa sugerida: \(settings.breakMinutes) minutos", value: $settings.breakMinutes, in: 1...60)
                Picker("Aparência", selection: $settings.theme) { Text("Clara").tag(Theme.light); Text("Escura").tag(Theme.dark); Text("Do iPhone").tag(Theme.system) }.accessibilityIdentifier("settings.theme")
                Toggle("Sons do Ninho", isOn: $settings.sound).accessibilityIdentifier("settings.sound")
                Text("Sons curtos ao salvar, revisar e concluir. O modo silencioso do iPhone é respeitado.").font(.body).foregroundStyle(.secondary)
                Toggle("Reduzir animações", isOn: $settings.reducedMotion).accessibilityIdentifier("settings.reducedMotion")
                Button("Salvar ajustes") { Task { await store.perform(.updateSettings(settings)) } }.disabled(store.busy).accessibilityIdentifier("settings.save")
            }
            Section("Sua coleção, com você") {
                Button { Task { exportURL = await store.exportBackup() } } label: { Label("Preparar backup ZIP", systemImage: "square.and.arrow.up") }.disabled(store.busy).accessibilityIdentifier("settings.export")
                if let exportURL { ShareLink(item: exportURL) { Label("Salvar em Arquivos ou compartilhar backup", systemImage: "folder") }.accessibilityIdentifier("settings.shareBackup") }
                Button { importing = true } label: { Label("Restaurar backup do Ninho", systemImage: "square.and.arrow.down") }.disabled(store.busy).accessibilityIdentifier("settings.restore")
                Text("O backup leva aulas, cartões, anotações, provas, tempo registrado e materiais. Use o ZIP do Ninho no Windows para trazer sua coleção. A transferência é manual; não há sincronização automática.").font(.body).foregroundStyle(.secondary)
            }
            Section("Sobre a Íris") {
                Text("A assistente usa Apple Intelligence neste iPhone, sem enviar seus estudos a um servidor. Requer iPhone compatível, iOS 26 e o modelo da Apple disponível. O calendário, os cartões e as recomendações de revisão continuam funcionando quando a IA está indisponível.").font(.body).foregroundStyle(.secondary)
            }
            if store.busy { ProgressView("Cuidando da sua coleção…") }
            if !store.notice.isEmpty { Text(store.notice).font(.body).accessibilityIdentifier("app.notice") }
        }.navigationTitle("Ajustes").accessibilityIdentifier("screen.settings").task { settings = store.state.settings }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                switch result { case .success(let urls): pendingRestore = urls.first; case .failure(let error): store.error = store.friendly(error) }
            }
            .confirmationDialog("Substituir a coleção deste iPhone?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
                Button("Restaurar coleção", role: .destructive) { if let url = pendingRestore { Task { await store.restoreBackup(url); settings = store.state.settings } }; pendingRestore = nil }
            } message: { Text("Os arquivos serão conferidos antes da troca. A coleção anterior será preservada localmente para recuperação. Uma sessão de foco em andamento não faz parte do backup.") }
    }
}

struct ProgressViewScreen: View {
    @EnvironmentObject var store: NinhoStore
    private var overview: StudyOverview { StudyEngine.overview(in: store.state) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Veja o caminho que você já percorreu.").font(.system(.title, design: .rounded, weight: .bold))
                VStack(alignment: .leading, spacing: 12) {
                    Label("\(Int(overview.weekMinutes)) minutos nesta semana", systemImage: "clock")
                    Label("\(overview.lessonsDone) de \(overview.totalLessons) aulas concluídas", systemImage: "checkmark.circle")
                    Label("\(overview.streak) dia(s) de constância", systemImage: "flame")
                    Label("\(overview.flaggedCards) cartão(ões) para atualizar ou reaprender", systemImage: "flag")
                }.font(.headline).ninhoCard()
                Text("Um olhar por matéria").font(.title2.weight(.bold))
                ForEach(overview.subjects) { insight in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) { Text(insight.name).font(.title3.weight(.semibold)); Spacer(); Image(systemName: "leaf").foregroundStyle(NinhoStyle.green) }
                        Text(insight.status).font(.headline).foregroundStyle(NinhoStyle.green)
                        ForEach(Array(insight.signals.enumerated()), id: \.offset) { _, signal in Text(signal).font(.body) }
                        Text("\(insight.reviewedCards) de \(insight.totalCards) cartões já praticados").font(.body.weight(.medium))
                        if let coverage = insight.coveragePercent { ProgressView(value: min(100, coverage), total: 100) }
                        Text("Cartões praticados e tempo dedicado ajudam a acompanhar sua rotina. Eles não medem, sozinhos, o domínio da matéria.").font(.body).foregroundStyle(.secondary)
                        NavigationLink("Abrir matéria") { SubjectView(subjectID: insight.subjectId) }
                    }.ninhoCard()
                }
            }.padding(20)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Meu progresso").accessibilityIdentifier("screen.progress")
    }
}
