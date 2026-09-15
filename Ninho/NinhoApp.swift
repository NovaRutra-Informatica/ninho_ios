import SwiftUI
import UniformTypeIdentifiers
import NinhoCore

@main struct NinhoApp: App {
    @StateObject private var store = NinhoStore()
    var body: some Scene {
        WindowGroup {
            NinhoRootView()
                .environmentObject(store)
                .tint(NinhoStyle.green)
                .preferredColorScheme(store.state.settings.theme == .system ? nil : store.state.settings.theme == .dark ? .dark : .light)
                .task { await store.start() }
        }
    }
}

enum NinhoStyle {
    static let green = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.55, green: 0.78, blue: 0.65, alpha: 1) : UIColor(red: 0.22, green: 0.43, blue: 0.34, alpha: 1) })
    static let amber = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.90, green: 0.67, blue: 0.38, alpha: 1) : UIColor(red: 0.64, green: 0.36, blue: 0.12, alpha: 1) })
}

struct NinhoRootView: View {
    @EnvironmentObject var store: NinhoStore
    @State private var tab = 0
    @State private var importRecovery = false
    @State private var recoveryURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if store.loaded {
                TabView(selection: $tab) {
                    NavigationStack { TodayView(tab: $tab) }.tabItem { Label("Hoje", systemImage: "sun.max") }.tag(0).accessibilityIdentifier("tab.today")
                    NavigationStack { StudiesView() }.tabItem { Label("Estudos", systemImage: "books.vertical") }.tag(1).accessibilityIdentifier("tab.studies")
                    NavigationStack { ReviewsView() }.tabItem { Label("Revisões", systemImage: "rectangle.on.rectangle") }.tag(2).accessibilityIdentifier("tab.reviews")
                    NavigationStack { AgendaView() }.tabItem { Label("Agenda", systemImage: "calendar") }.tag(3).accessibilityIdentifier("tab.agenda")
                    NavigationStack { MoreView() }.tabItem { Label("Mais", systemImage: "square.grid.2x2") }.tag(4).accessibilityIdentifier("tab.more")
                }
                .animation(reducedMotion || store.state.settings.reducedMotion ? nil : .easeInOut(duration: 0.22), value: tab)
            } else {
                VStack(spacing: 20) {
                    Image("owl").resizable().scaledToFit().frame(width: 110, height: 110).accessibilityHidden(true)
                    Text("Seu próximo passo começa aqui.").font(.title2).multilineTextAlignment(.center)
                    if store.busy { ProgressView("Abrindo seu Ninho…") }
                    else {
                        Button("Tentar abrir novamente") { Task { await store.start() } }
                        Button("Restaurar um backup") { importRecovery = true }
                    }
                }.padding(30)
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await store.monitorFocus() }
        }
        .safeAreaInset(edge: .top) {
            if let message = store.focusRecoveryNotice {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Cronômetro", systemImage: "clock.badge.exclamationmark").font(.headline)
                    Text(message).font(.body).accessibilityIdentifier("focus.recoveryNotice")
                    Button("Entendi") { store.focusRecoveryNotice = nil }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
            }
        }
        .alert("Não foi possível concluir", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Entendi") { store.error = nil }
        } message: { Text(store.error ?? "").accessibilityIdentifier("app.error") }
        .fileImporter(isPresented: $importRecovery, allowedContentTypes: [.zip]) { result in
            switch result { case .success(let url): recoveryURL = url; case .failure(let error): store.error = store.friendly(error) }
        }
        .confirmationDialog("Restaurar a coleção deste backup?", isPresented: Binding(get: { recoveryURL != nil }, set: { if !$0 { recoveryURL = nil } }), titleVisibility: .visible) {
            Button("Restaurar") { if let url = recoveryURL { Task { await store.restoreBackup(url) } }; recoveryURL = nil }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject var store: NinhoStore
    @Binding var tab: Int
    private var overview: StudyOverview { StudyEngine.overview(in: store.state) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button { tab = 3 } label: { Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.subheadline.weight(.medium)) }.accessibilityIdentifier("today.calendar")
                        Text("Um passo de cada vez, \(store.state.settings.name.components(separatedBy: " ").first ?? "Alessandro").")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    }
                    Image("owl").resizable().scaledToFit().frame(width: 80, height: 80).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Label("Seu pequeno compromisso de hoje", systemImage: "leaf.fill").font(.headline)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(overview.todayMinutes))").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("de \(store.state.settings.dailyMinutes) minutos").font(.body)
                    }
                    ProgressView(value: min(1, overview.dailyGoalProgress / 100)).tint(NinhoStyle.green)
                    Text(overview.streak > 0 ? "\(overview.streak) dia(s) de constância. Continue no seu ritmo." : "Escolha uma aula e comece. O tempo que você dedicar aparecerá aqui.").font(.body).foregroundStyle(.secondary)
                    Button { tab = 1 } label: { Label("Continuar meus estudos", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).accessibilityIdentifier("today.study")
                }.ninhoCard()
                HStack(spacing: 14) {
                    Button { tab = 2 } label: { metric("Revisões", value: "\(overview.dueCards)", icon: "rectangle.on.rectangle") }.accessibilityIdentifier("today.review")
                    NavigationLink { FocusView() } label: { metric("Minutos na semana", value: "\(Int(overview.weekMinutes))", icon: "timer") }.accessibilityIdentifier("today.focus")
                }.buttonStyle(.plain)
                if let next = overview.upcomingExams.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No seu horizonte", systemImage: "calendar").font(.headline)
                        Text(next.title).font(.title3.weight(.semibold))
                        Text("\(next.date) · \(next.time)").font(.body).foregroundStyle(.secondary)
                        Button("Ver calendário") { tab = 3 }
                    }.ninhoCard()
                }
                ForEach(overview.todayTasks) { task in
                    Button { var updated = task; updated.completed.toggle(); Task { await store.perform(.saveTask(updated)) } } label: {
                        Label(task.title, systemImage: task.completed ? "checkmark.circle.fill" : "circle").font(.body).frame(maxWidth: .infinity, alignment: .leading)
                    }.ninhoCard().accessibilityIdentifier("task.\(task.id)")
                }
                NavigationLink { AssistantView(state: store.state) } label: {
                    HStack { Image(systemName: "sparkles"); VStack(alignment: .leading, spacing: 4) { Text("Converse com a Íris").font(.headline); Text("Uma companhia para organizar seu próximo passo.").font(.body) }; Image(systemName: "chevron.right") }.frame(maxWidth: .infinity, alignment: .leading)
                }.ninhoCard().buttonStyle(.plain)
            }.padding(20)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Hoje").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("screen.today")
    }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).foregroundStyle(NinhoStyle.green); Text(value).font(.system(.title, design: .rounded, weight: .bold)); Text(title).font(.body).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).ninhoCard()
    }
}

extension View {
    func ninhoCard() -> some View { padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24)) }
}

struct MoreView: View {
    @EnvironmentObject var store: NinhoStore
    var body: some View {
        List {
            Section {
                HStack(spacing: 18) { Image("owl").resizable().scaledToFit().frame(width: 68, height: 68); VStack(alignment: .leading) { Text("Ninho").font(.system(.title, design: .rounded, weight: .bold)); Text("Um lugar para aprender no seu ritmo.").font(.body).foregroundStyle(.secondary) } }.padding(.vertical, 8)
            }
            NavigationLink { MaterialsView() } label: { Label("Materiais", systemImage: "folder") }.accessibilityIdentifier("more.materials")
            NavigationLink { FocusView() } label: { Label("Foco", systemImage: "timer") }.accessibilityIdentifier("more.focus")
            NavigationLink { ProgressViewScreen() } label: { Label("Meu progresso", systemImage: "chart.bar") }.accessibilityIdentifier("more.progress")
            NavigationLink { AssistantView(state: store.state) } label: { Label("Minha assistente", systemImage: "sparkles") }.accessibilityIdentifier("more.assistant")
            NavigationLink { SettingsView() } label: { Label("Ajustes e backup", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("more.settings")
            Section { Text("Seus estudos ficam neste iPhone. Exporte um backup para levar a coleção a outro aparelho.").font(.body).foregroundStyle(.secondary) }
        }.navigationTitle("Seu Ninho").accessibilityIdentifier("screen.more")
    }
}
