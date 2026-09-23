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
                .preferredColorScheme(store.displaySettings.theme == .system ? nil : store.displaySettings.theme == .dark ? .dark : .light)
                .task { await store.start() }
        }
    }
}

enum NinhoStyle {
    static let canvas = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.075, green: 0.078, blue: 0.086, alpha: 1) : .systemGroupedBackground })
    static let surface = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.13, green: 0.135, blue: 0.15, alpha: 1) : .secondarySystemGroupedBackground })
    static let green = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.55, green: 0.78, blue: 0.65, alpha: 1) : UIColor(red: 0.22, green: 0.43, blue: 0.34, alpha: 1) })
    static let amber = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.90, green: 0.67, blue: 0.38, alpha: 1) : UIColor(red: 0.64, green: 0.36, blue: 0.12, alpha: 1) })
}

struct NinhoRootView: View {
    @EnvironmentObject var store: NinhoStore
    @State private var tab = 0
    @State private var importRecovery = false
    @State private var recoveryURL: URL?
    @State private var pendingDestination: NativeStudyDestination?
    @State private var showProgress = false
    @State private var navigationRoots = (0..<5).map { _ in UUID() }
    @StateObject private var systemRoutes = SystemRouteRequests.shared
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if store.loaded && store.state.profile?.completedAt == nil {
                ProfileView(onboarding: true)
            } else if store.loaded {
                TabView(selection: $tab) {
                    NavigationStack { TodayView(tab: $tab).ninhoProfileShortcut() }.id(navigationRoots[0]).tabItem { Label("Hoje", systemImage: "sun.max") }.tag(0).accessibilityIdentifier("tab.today")
                    NavigationStack { StudiesView().ninhoProfileShortcut() }.id(navigationRoots[1]).tabItem { Label("Estudos", systemImage: "books.vertical") }.tag(1).accessibilityIdentifier("tab.studies")
                    NavigationStack { FocusView().ninhoProfileShortcut() }.id(navigationRoots[2]).tabItem { Label("Foco", systemImage: "timer") }.tag(2).accessibilityIdentifier("tab.focus")
                    NavigationStack { ReviewsView().ninhoProfileShortcut() }.id(navigationRoots[3]).tabItem { Label("Revisões", systemImage: "rectangle.on.rectangle") }.tag(3).accessibilityIdentifier("tab.reviews")
                    NavigationStack { AssistantView(state: store.state).ninhoProfileShortcut() }.id(navigationRoots[4]).tabItem { Label("Assistente", systemImage: "sparkles") }.tag(4).accessibilityIdentifier("tab.assistant")
                }
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) { navigationDock }
            } else {
                VStack(spacing: 20) {
                    Image("owl").renderingMode(.original).resizable().scaledToFit().frame(width: 110, height: 110).accessibilityHidden(true)
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
            store.setAppActive(scenePhase == .active)
            if scenePhase == .active { store.refreshOverview(); await store.monitorFocus() }
        }
        .simultaneousGesture(TapGesture().onEnded { store.recordInteraction() })
        .onOpenURL { url in
            guard let destination = NativeStudyDestination(url: url) else { return }
            pendingDestination = destination
            openPendingDestination()
        }
        .onChange(of: store.loaded) { _, _ in openPendingDestination() }
        .onChange(of: store.state.profile?.completedAt) { _, _ in openPendingDestination() }
        .onChange(of: systemRoutes.pendingRoute) { _, route in
            guard let route, let destination = NativeStudyDestination(rawValue: route) else { return }
            systemRoutes.pendingRoute = nil
            pendingDestination = destination
            openPendingDestination()
        }
        .onAppear {
            if let route = systemRoutes.pendingRoute, let destination = NativeStudyDestination(rawValue: route) {
                systemRoutes.pendingRoute = nil
                pendingDestination = destination
            }
            openPendingDestination()
        }
        .sheet(isPresented: $showProgress) {
            NavigationStack {
                ProgressViewScreen()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { showProgress = false } } }
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in store.recordInteraction() })
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

    private func openPendingDestination() {
        guard store.loaded, store.state.profile?.completedAt != nil,
              let destination = pendingDestination else { return }
        pendingDestination = nil
        // An external shortcut must reveal the destination even if its tab had a detail open.
        // Ordinary timer actions and tab taps keep the existing navigation roots.
        navigationRoots[destination.tabIndex] = UUID()
        tab = destination.tabIndex
        showProgress = destination == .progress
    }

    private var navigationDock: some View {
        HStack(spacing: 2) {
            dockItem("Hoje", icon: "sun.max", value: 0, id: "today")
            dockItem("Estudos", icon: "books.vertical", value: 1, id: "studies")
            dockItem("Foco", icon: "timer", value: 2, id: "focus")
            dockItem("Revisões", icon: "rectangle.on.rectangle", value: 3, id: "reviews")
            dockItem("Assistente", icon: "sparkles", value: 4, id: "assistant")
        }
        .padding(6)
        .background(reducedTransparency ? Color(.secondarySystemBackground) : .clear, in: Capsule())
        .glassEffect(.clear.interactive(), in: .capsule)
        .animation(reducedMotion || store.state.settings.reducedMotion ? nil : .easeInOut(duration: 0.18), value: tab)
        .padding(.horizontal, 16).padding(.bottom, 8)
        .accessibilityIdentifier("navigation.glassDock")
    }

    private func dockItem(_ label: String, icon: String, value: Int, id: String) -> some View {
        Button { tab = value } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19, weight: tab == value ? .semibold : .regular))
                Text(label).font(.caption2.weight(tab == value ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }.frame(maxWidth: .infinity).frame(minHeight: 46)
                .foregroundStyle(tab == value ? NinhoStyle.green : Color.primary)
                .background(tab == value ? NinhoStyle.green.opacity(0.14) : .clear, in: Capsule())
        }.buttonStyle(.plain)
            .accessibilityIdentifier("tab.\(id)")
            .accessibilityAddTraits(tab == value ? .isSelected : [])
    }
}

struct TodayView: View {
    @EnvironmentObject var store: NinhoStore
    @Binding var tab: Int
    private var overview: StudyOverview { store.overview }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink { AgendaView() } label: { Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.subheadline.weight(.medium)) }.accessibilityIdentifier("today.calendar")
                        Text("Um passo de cada vez, \(store.state.settings.name.components(separatedBy: " ").first ?? "Alessandro").")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    }
                    Image("owl").renderingMode(.original).resizable().scaledToFit().frame(width: 80, height: 80).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Label("Seu pequeno compromisso de hoje", systemImage: "leaf.fill").font(.headline)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(overview.todayMinutes))").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("de \(store.state.settings.dailyMinutes) minutos").font(.body)
                    }
                    ProgressView(value: min(1, overview.dailyGoalProgress / 100)).tint(NinhoStyle.green)
                    Text("O tempo das sessões salvas aparece aqui. Cada pequeno bloco conta.").font(.body).foregroundStyle(.secondary)
                    Button { tab = 1 } label: { Label("Continuar meus estudos", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).accessibilityIdentifier("today.study")
                }.ninhoCard()
                HStack(spacing: 14) {
                    Button { tab = 3 } label: { metric("Revisões", value: "\(overview.dueCards)", icon: "rectangle.on.rectangle") }.accessibilityIdentifier("today.review")
                    Button { tab = 2 } label: { metric("Minutos na semana", value: "\(Int(overview.weekMinutes))", icon: "timer") }.accessibilityIdentifier("today.focus")
                }.buttonStyle(.plain)
                if let suggestion = store.mentor.suggestions.first {
                    MentorSuggestionCard(suggestion: suggestion).accessibilityIdentifier("today.nextStep")
                }
                if let next = overview.upcomingExams.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No seu horizonte", systemImage: "calendar").font(.headline)
                        Text(next.title).font(.title3.weight(.semibold))
                        Text("\(next.date) · \(next.time)").font(.body).foregroundStyle(.secondary)
                        NavigationLink("Ver calendário") { AgendaView() }
                    }.ninhoCard()
                }
                ForEach(overview.todayTasks) { task in
                    Button { var updated = task; updated.completed.toggle(); Task { await store.perform(.saveTask(updated)) } } label: {
                        Label(task.title, systemImage: task.completed ? "checkmark.circle.fill" : "circle").font(.body).frame(maxWidth: .infinity, alignment: .leading)
                    }.ninhoCard().accessibilityIdentifier("task.\(task.id)")
                }
                NavigationLink { AssistantView(state: store.state) } label: {
                    HStack { Image(systemName: "sparkles"); VStack(alignment: .leading, spacing: 4) { Text("Minha assistente").font(.headline); Text("Seu plano e sugestões que acompanham seus estudos.").font(.body) }; Image(systemName: "chevron.right") }.frame(maxWidth: .infinity, alignment: .leading)
                }.ninhoCard().buttonStyle(.plain)
            }.padding(20)
        }.background(NinhoStyle.canvas).navigationTitle("Hoje").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("screen.today").ninhoTutorial(.today)
    }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).foregroundStyle(NinhoStyle.green); Text(value).font(.system(.title, design: .rounded, weight: .bold)); Text(title).font(.body).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).ninhoCard()
    }
}

extension View {
    func ninhoCard() -> some View { padding(20).background(NinhoStyle.surface, in: RoundedRectangle(cornerRadius: 24)) }
    func ninhoProfileShortcut() -> some View {
        modifier(NinhoHeaderShortcuts())
    }
}

struct MoreView: View {
    @EnvironmentObject var store: NinhoStore
    @State private var clearingActivity = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 18) { Image("owl").renderingMode(.original).resizable().scaledToFit().frame(width: 68, height: 68); VStack(alignment: .leading) { Text("Ninho").font(.system(.title, design: .rounded, weight: .bold)); Text("Um lugar para aprender no seu ritmo.").font(.body).foregroundStyle(.secondary) } }.padding(.vertical, 8)
            }
            NavigationLink { ProfileView(onboarding: false) } label: { Label("Meu perfil e objetivos", systemImage: "person.crop.circle") }.accessibilityIdentifier("more.profile")
            NavigationLink { SettingsView() } label: { Label("Preferências e backup", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("more.settings")
            NavigationLink { MaterialsView() } label: { Label("Materiais", systemImage: "folder") }.accessibilityIdentifier("more.materials")
            NavigationLink { AgendaView() } label: { Label("Agenda", systemImage: "calendar") }.accessibilityIdentifier("more.agenda")
            NavigationLink { ProgressViewScreen() } label: { Label("Meu progresso", systemImage: "chart.bar") }.accessibilityIdentifier("more.progress")
            NavigationLink { AssistantView(state: store.state) } label: { Label("Minha assistente", systemImage: "sparkles") }.accessibilityIdentifier("more.assistant")
            NavigationLink { WidgetsGuideView() } label: { Label("Widgets e atalhos", systemImage: "square.grid.2x2") }.accessibilityIdentifier("more.widgets")
            Section("Seu uso, sob seu controle") {
                Toggle("Registrar navegação local", isOn: Binding(get: { store.navigationTrackingEnabled }, set: { enabled in Task { await store.setNavigationTracking(enabled) } }))
                    .accessibilityIdentifier("profile.trackNavigation")
                Text("Guarda visitas e tempo ativo por tela por até 90 dias, só neste iPhone. Para ao sair do aplicativo ou após 60 segundos sem interação. Não entra na meta de estudo e não acompanha outros aplicativos.").font(.footnote).foregroundStyle(.secondary)
                Button("Apagar histórico local de uso", role: .destructive) { clearingActivity = true }.accessibilityIdentifier("profile.clearActivity")
                Text("Também apaga os agregados de inícios e pausas usados para sugerir horários. Seus estudos, respostas, perfil e sessões continuam salvos.").font(.footnote).foregroundStyle(.secondary)
                if !store.activityNotice.isEmpty { Text(store.activityNotice).font(.footnote).foregroundStyle(.secondary) }
            }
            Section { Text("Seus estudos ficam neste iPhone. Exporte um backup para levar a coleção a outro aparelho.").font(.body).foregroundStyle(.secondary) }
        }.navigationTitle("Meu perfil").accessibilityIdentifier("screen.more").ninhoActivity(.more)
            .confirmationDialog("Apagar os agregados locais de navegação e rotina?", isPresented: $clearingActivity, titleVisibility: .visible) {
                Button("Apagar histórico de uso", role: .destructive) { Task { await store.clearLocalActivity() } }
            }
    }
}
