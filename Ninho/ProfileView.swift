import SwiftUI
import NinhoCore

struct ProfileView: View {
    @EnvironmentObject var store: NinhoStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var planTask: Task<Void, Never>?
    @State private var profile = StudentProfile()
    @State private var initialized = false
    @State private var step = 0
    @State private var preparing = false
    @State private var prepared = false
    @State private var entered = false
    @State private var status = ""
    @State private var owlSpeaking = false
    @FocusState private var answerFocused: Bool
    @AppStorage private var savedStep: Int
    let onboarding: Bool

    init(onboarding: Bool) {
        self.onboarding = onboarding
        let arguments = ProcessInfo.processInfo.arguments
        let storageProfile = arguments.contains("--uitesting") ? (ProcessInfo.processInfo.environment["NINHO_TEST_PROFILE"] ?? "test") : "local"
        _savedStep = AppStorage(wrappedValue: 0, "ninho.welcome.step.\(storageProfile)")
    }

    private var motion: Animation? { reduceMotion || store.state.settings.reducedMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8) }
    private var title: String {
        ["Vamos nos conhecer?", "Qual é o seu próximo sonho?", "O que move você?", "O que vamos aprender?", "De onde estamos partindo?", "Como é sua vida hoje?", "Quando cabe um pouco de estudo?", "Qual é o seu ritmo?", "Como você aprende melhor?", "Vamos deixar tudo confortável?", "Seu Ninho está quase pronto."][step]
    }
    private var owlMessage: String {
        ["Oi! Eu sou a Íris. Vou acompanhar seus estudos. Primeiro, como você quer que eu chame você?",
         "Quero conhecer o que você deseja conquistar. Uma aprovação? Uma habilidade nova? Me conta do seu jeito.",
         "Nos dias difíceis, lembrar do motivo ajuda. E, se houver um prazo, podemos nos organizar com calma.",
         "Pode ser uma matéria, um curso inteiro ou uma lista de assuntos. Vamos dar um lugar para cada um deles.",
         "Começar do zero e retomar depois de uma pausa são bons pontos de partida. Quero respeitar o seu.",
         "Trabalho, aulas, família, descanso… Um bom plano precisa conversar com a sua vida real.",
         "Escolha os dias que costumam funcionar. Não precisa estudar todos os dias para construir constância.",
         "É melhor um compromisso possível do que um plano impossível. Você pode ajustar esses tempos depois.",
         "Cada pessoa encontra seu próprio jeito. Me conte o que ajuda e o que costuma atrapalhar.",
         "Alguma coisa pode tornar o estudo mais confortável? Você escolhe o que quer compartilhar comigo.",
         "Obrigada por me contar seu caminho! Confira suas respostas. Depois, podemos preparar seu primeiro plano aqui no iPhone."][step]
    }

    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if onboarding {
                    welcomeHeader.id("welcome.top")
                    if step == 0 { InitialBackupRecoveryCard() }
                } else {
                    Text("Seu caminho, do seu jeito.").font(.system(.title, design: .rounded, weight: .bold))
                    Text("As alterações válidas são salvas automaticamente e usadas nas próximas sugestões. Mudar uma resposta atualiza o acompanhamento local.").foregroundStyle(.secondary)
                }
                Group {
                    if onboarding { questionPage }
                    else { identity; goals; routine; learning; plan; AssistantIdentityCard() }
                }.id(onboarding ? step : 0)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .disabled(preparing)
                if !store.preferencesStatus.isEmpty { Text(store.preferencesStatus).font(.footnote).foregroundStyle(.secondary) }
                if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("profile.status") }
                if planTask != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        ProgressView("Organizando seus tempos e próximos passos…")
                        Text("Análise local embutida. Não é necessário baixar um modelo.").font(.footnote).foregroundStyle(.secondary)
                        Button("Interromper") { planTask?.cancel(); status = "Preparação interrompida. Seu perfil continua salvo." }
                            .buttonStyle(ProfileActionStyle(primary: false, reducedMotion: motion == nil))
                    }.ninhoCard()
                }
            }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(NinhoStyle.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if onboarding {
                navigation.padding(.horizontal, 24).padding(.top, 15).padding(.bottom, 12)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                    .background(NinhoStyle.canvas)
            }
        }
        .navigationTitle(onboarding ? "Vamos começar" : "Meu perfil")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(onboarding ? "screen.welcome" : "screen.profile")
        .task {
            guard !initialized else { return }
            profile = store.state.profile ?? StudentProfile()
            if store.state.profile == nil {
                profile.name = onboarding ? "" : store.state.settings.name
                profile.dailyMinutes = store.state.settings.dailyMinutes
                profile.sessionMinutes = store.state.settings.focusMinutes
            }
            if onboarding { step = WelcomeJourney.resumeStep(saved: savedStep, profile: store.state.profile) }
            initialized = true
            withAnimation(motion) { entered = true }
        }
        .onChange(of: profile.answers) { _, value in
            guard initialized else { return }
            if value != store.state.profile?.answers { prepared = false; store.queueProfile(profile) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { planTask?.cancel(); Task { await store.flushPreferences() } }
        }
        .onDisappear { planTask?.cancel(); Task { await store.flushPreferences() } }
        .ninhoActivity(.profile)
        .onChange(of: step) { _, _ in scroll.scrollTo("welcome.top", anchor: .top) }
        }
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("ninho").font(.system(size: 25, weight: .medium, design: .serif)).foregroundStyle(NinhoStyle.green)
                Spacer()
                Label("Só neste iPhone", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                ForEach(0..<WelcomeJourney.questionCount, id: \.self) { index in
                    Capsule().fill(index <= step ? NinhoStyle.green : NinhoStyle.green.opacity(0.14)).frame(height: 5)
                }
            }.accessibilityLabel(step == WelcomeJourney.reviewStep ? "Perguntas concluídas. Revisão final." : "Pergunta \(step + 1) de \(WelcomeJourney.questionCount)")
            HStack(alignment: .center, spacing: 14) {
                Image("owl").renderingMode(.original).resizable().scaledToFit().frame(width: 94, height: 108)
                    .scaleEffect(entered ? (owlSpeaking ? 1.04 : 1) : 0.75)
                    .rotationEffect(.degrees(entered ? (owlSpeaking ? -5 : 0) : -10))
                    .accessibilityHidden(true)
                Text(owlMessage).font(.system(.subheadline, design: .rounded)).lineSpacing(4)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(NinhoStyle.surface, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(NinhoStyle.green.opacity(0.12), lineWidth: 1))
                    .accessibilityIdentifier("welcome.owlMessage")
            }
            Text(title).font(.system(size: 29, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("welcome.heading")
            Text(step == WelcomeJourney.reviewStep ? "Confira seu perfil antes de começar." : "Pergunta \(step + 1) de 10 · você pode ajustar tudo depois")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: step) {
            guard motion != nil else { owlSpeaking = false; return }
            withAnimation(.easeInOut(duration: 0.22)) { owlSpeaking = true }
            do { try await Task.sleep(for: .milliseconds(260)) } catch { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.58)) { owlSpeaking = false }
        }
    }

    @ViewBuilder private var questionPage: some View {
        switch step {
        case 0:
            questionCard {
                answer("Seu nome", text: $profile.name, limit: 100, hint: "Como você gosta de ser chamado?")
                Text("Sem conta, senha ou cadastro na internet. Só você, seus estudos e um lugar para crescer.").font(.footnote).foregroundStyle(.secondary)
            }
        case 1:
            questionCard { answer("O que você quer conquistar?", text: $profile.goal, limit: 400, hint: "Uma aprovação, aprender algo novo, concluir um curso…") }
        case 2:
            questionCard {
                answer("Por que isso é importante para você?", text: $profile.motivation, limit: 300)
                answer("Você tem um prazo em mente?", text: $profile.targetDate, limit: 40, hint: "Ex.: dezembro de 2026, sem prazo definido")
            }
        case 3:
            questionCard { answer("Quais matérias ou assuntos fazem parte desse caminho?", text: $profile.subjects, limit: 300, hint: "Pode escrever uma lista do seu jeito") }
        case 4:
            questionCard { answer("Como está seu conhecimento hoje?", text: $profile.level, limit: 160, hint: "Iniciante, retomando, já estudo há algum tempo…") }
        case 5:
            questionCard { answer("Como é seu dia e quais compromissos devemos considerar?", text: $profile.routine, limit: 400, hint: "Trabalho, aulas, descanso e os espaços livres entre eles") }
        case 6:
            questionCard {
                daysPicker
                answer("Qual horário funciona melhor?", text: $profile.preferredTime, limit: 160, hint: "Pela manhã, depois do trabalho, depende do dia…")
            }
        case 7:
            questionCard {
                minuteChoice("Tempo disponível por dia", value: $profile.dailyMinutes, range: 5...720, presets: [15, 30, 45, 60], increment: 5)
                minuteChoice("Um bloco confortável de estudo", value: $profile.sessionMinutes, range: 1...180, presets: [15, 25, 45, 60], increment: 1)
            }
        case 8:
            questionCard {
                answer("Quais formas de estudar você prefere?", text: $profile.preferences, limit: 300, hint: "Questões, leitura, vídeos, prática, resumos…")
                answer("O que costuma dificultar seus estudos?", text: $profile.challenges, limit: 400, hint: "Começar, lembrar, organizar matérias, encontrar tempo…")
            }
        case 9:
            questionCard {
                answer("Alguma adaptação que torne o estudo mais confortável?", text: $profile.accessibility, limit: 240, hint: "Opcional: pausas, textos curtos, exemplos passo a passo…")
                Text("Está tudo bem deixar perguntas opcionais em branco. No próximo passo, você poderá conferir seu perfil inteiro.").font(.footnote).foregroundStyle(.secondary)
            }
        default:
            profileSummary
            plan
        }
    }

    private func questionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 24, content: content).padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NinhoStyle.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(NinhoStyle.green.opacity(0.12), lineWidth: 1))
    }

    private var profileSummary: some View {
        questionCard {
            ForEach(Array(summaryRows.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.0).font(.caption).foregroundStyle(.secondary)
                    Text(item.1.isEmpty ? "Ainda não informado" : item.1).font(.subheadline)
                }
            }
        }
    }
    private var summaryRows: [(String, String)] {
        [("Seu nome", profile.name), ("Objetivo", profile.goal), ("Motivação", profile.motivation),
         ("Prazo", profile.targetDate), ("Matérias", profile.subjects), ("Ponto de partida", profile.level),
         ("Rotina", profile.routine), ("Dias e horário", profile.availableDays.map { dayNames[$0] ?? $0 }.joined(separator: ", ") + (profile.preferredTime.isEmpty ? "" : " · " + profile.preferredTime)),
         ("Seu ritmo", "\(profile.dailyMinutes) min por dia · blocos de \(profile.sessionMinutes) min"),
         ("Preferências", profile.preferences), ("Dificuldades", profile.challenges), ("Adaptações", profile.accessibility)]
    }
    private var dayNames: [String: String] { ["mon": "Seg", "tue": "Ter", "wed": "Qua", "thu": "Qui", "fri": "Sex", "sat": "Sáb", "sun": "Dom"] }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Como podemos chamar você?").font(.title3.bold())
            answer("Seu nome", text: $profile.name, limit: 100)
            Text("Aqui não há conta, senha ou servidor. Seu perfil acompanha o backup da sua coleção.").font(.body).foregroundStyle(.secondary)
        }.ninhoCard()
    }
    private var goals: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Seus objetivos").font(.title3.bold())
            answer("O que você quer conquistar?", text: $profile.goal, limit: 400, hint: "Uma aprovação, aprender algo novo, concluir um curso…")
            answer("Por que isso é importante para você?", text: $profile.motivation, limit: 300)
            answer("Você tem uma data ou prazo em mente?", text: $profile.targetDate, limit: 40, hint: "Ex.: dezembro de 2026, sem prazo definido")
            answer("Quais matérias entram nesse caminho?", text: $profile.subjects, limit: 300)
            answer("De onde você está começando?", text: $profile.level, limit: 160, hint: "Iniciante, retomando, já estudo há algum tempo…")
        }.ninhoCard()
    }
    private var routine: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sua rotina real").font(.title3.bold())
            answer("Como é seu dia e quais compromissos devemos considerar?", text: $profile.routine, limit: 400)
            daysPicker
            minuteChoice("Tempo disponível por dia", value: $profile.dailyMinutes, range: 5...720, presets: [15, 30, 45, 60], increment: 5)
            minuteChoice("Um bloco confortável de estudo", value: $profile.sessionMinutes, range: 1...180, presets: [15, 25, 45, 60], increment: 1)
            answer("Qual horário funciona melhor?", text: $profile.preferredTime, limit: 160)
        }.ninhoCard()
    }
    private var learning: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Como ajudar você a aprender").font(.title3.bold())
            answer("O que costuma dificultar seus estudos?", text: $profile.challenges, limit: 400, hint: "Tempo, começar, lembrar, organizar matérias…")
            answer("Que formas de estudar você prefere?", text: $profile.preferences, limit: 300, hint: "Questões, leitura, vídeos, prática, resumos…")
            answer("Alguma adaptação que torne o estudo mais confortável?", text: $profile.accessibility, limit: 240, hint: "Opcional. Ex.: pausas frequentes, textos curtos, exemplos passo a passo.")
        }.ninhoCard()
    }
    private var plan: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Seu primeiro plano", systemImage: "sparkles").font(.title3.bold())
            Text("A Íris organiza seus dias, blocos de foco e próximas revisões com uma análise local leve, que já vem no Ninho.")
            Text("\(profile.dailyMinutes) minutos por dia, em \(profile.availableDays.count) dia(s) da semana. \(profile.goal)")
            if !profile.plan.isEmpty {
                Text(profile.plan).textSelection(.enabled)
                Text(profile.planProfileRevision == store.state.profile?.revision && profile.planStatus == "ready" ? "Seu plano salvo. As sugestões atuais acompanham os registros em Minha assistente." : "Este plano corresponde a respostas anteriores. Prepare uma nova sugestão.").font(.footnote).foregroundStyle(.secondary)
            }
            Button(profile.plan.isEmpty ? "Preparar meu plano local" : "Atualizar meu plano") { beginPreparation(enterAfter: false) }
                .buttonStyle(ProfileActionStyle(primary: true, reducedMotion: motion == nil)).disabled(preparing || !readyToFinish)
            Text("Sem chatbot, conta ou download. O acompanhamento mostra de onde vem cada sugestão e informa quando ainda há poucos dados.").font(.footnote).foregroundStyle(.secondary)
            if !onboarding { NavigationLink("Rever tutoriais do aplicativo") { TutorialLibraryView() } }
        }.ninhoCard()
    }
    private var readyToFinish: Bool { !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !profile.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !profile.availableDays.isEmpty }
    private var navigation: some View {
        HStack(spacing: 16) {
            if step > 0 {
                Button("Voltar") { Task { await move(to: step - 1) } }
                    .buttonStyle(ProfileActionStyle(primary: false, reducedMotion: motion == nil))
                    .disabled(preparing).accessibilityIdentifier("welcome.back")
            }
            Spacer()
            if step < WelcomeJourney.reviewStep {
                Button(step == 9 ? "Conferir meu perfil" : "Continuar") { Task { await move(to: step + 1) } }
                    .buttonStyle(ProfileActionStyle(primary: true, reducedMotion: motion == nil))
                    .disabled(preparing || !WelcomeJourney.canContinue(profile: profile, step: step))
                    .accessibilityIdentifier("welcome.continue")
            } else {
                Button(prepared ? "Entrar no meu Ninho" : "Preparar e começar") {
                    if prepared { Task { await finish() } }
                    else { beginPreparation(enterAfter: true) }
                }.buttonStyle(ProfileActionStyle(primary: true, reducedMotion: motion == nil)).disabled(!readyToFinish || preparing)
                    .accessibilityIdentifier("welcome.finish")
            }
        }
    }
    private func answer(_ label: String, text: Binding<String>, limit: Int, hint: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.headline)
            TextField(hint.isEmpty ? label : hint, text: Binding(get: { text.wrappedValue }, set: { value in
                var bounded = value
                while bounded.utf16.count > limit { bounded.removeLast() }
                text.wrappedValue = bounded
            }), axis: .vertical)
                .font(.system(.body, design: .rounded)).lineLimit(2...6).textFieldStyle(.plain)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(NinhoStyle.canvas, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(NinhoStyle.green.opacity(0.25), lineWidth: 1.5))
                .focused($answerFocused).accessibilityLabel(label)
            Text("\(text.wrappedValue.utf16.count)/\(limit)").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
    private var daysPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Em quais dias costuma ter tempo?").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68))], spacing: 10) {
                ForEach(["mon", "tue", "wed", "thu", "fri", "sat", "sun"], id: \.self) { day in
                    Button {
                        if profile.availableDays.contains(day) { profile.availableDays.removeAll { $0 == day } }
                        else { profile.availableDays.append(day) }
                    } label: { Text(dayNames[day] ?? day).frame(maxWidth: .infinity) }
                        .buttonStyle(ProfileActionStyle(primary: profile.availableDays.contains(day), reducedMotion: motion == nil))
                        .accessibilityAddTraits(profile.availableDays.contains(day) ? .isSelected : [])
                }
            }
        }
    }
    private func minuteChoice(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, presets: [Int], increment: Int) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(label).font(.headline)
            HStack(spacing: 16) {
                Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - increment) } label: { Image(systemName: "minus") }
                    .buttonStyle(ProfileActionStyle(primary: false, reducedMotion: motion == nil)).disabled(value.wrappedValue <= range.lowerBound)
                    .accessibilityLabel("Diminuir \(label)")
                VStack(spacing: 2) {
                    TextField("Minutos", text: Binding(get: { String(value.wrappedValue) }, set: { text in
                        if let minutes = Int(text) { value.wrappedValue = min(range.upperBound, max(range.lowerBound, minutes)) }
                    })).font(.system(size: 30, weight: .medium, design: .rounded)).multilineTextAlignment(.center)
                        .keyboardType(.numberPad).textFieldStyle(.plain).focused($answerFocused).accessibilityLabel(label)
                    Text("minutos").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + increment) } label: { Image(systemName: "plus") }
                    .buttonStyle(ProfileActionStyle(primary: false, reducedMotion: motion == nil)).disabled(value.wrappedValue >= range.upperBound)
                    .accessibilityLabel("Aumentar \(label)")
            }.padding(14).background(NinhoStyle.canvas, in: RoundedRectangle(cornerRadius: 18))
            HStack(spacing: 9) {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes)") { value.wrappedValue = minutes }
                        .buttonStyle(ProfileActionStyle(primary: value.wrappedValue == minutes, reducedMotion: motion == nil))
                        .accessibilityLabel("\(label): \(minutes) minutos")
                }
            }
        }
    }
    private func move(to destination: Int) async {
        answerFocused = false
        preparing = true; defer { preparing = false }
        store.queueProfile(profile); await store.flushPreferences()
        guard !store.hasPendingPreferences else { status = "Ainda não foi possível salvar. Suas respostas continuam aqui."; return }
        savedStep = min(WelcomeJourney.reviewStep, max(0, destination))
        status = ""
        withAnimation(motion) { step = savedStep }
    }
    private func beginPreparation(enterAfter: Bool) {
        guard !preparing else { return }
        answerFocused = false; preparing = true
        planTask = Task {
            defer { preparing = false; planTask = nil }
            store.queueProfile(profile); await store.flushPreferences()
            guard !Task.isCancelled else { return }
            guard let saved = store.state.profile, saved.answers == profile.answers, !store.hasPendingPreferences else {
                status = "Ainda não foi possível salvar seu perfil. Tente novamente."; return
            }
            do {
                let report = try await store.prepareLocalPlan()
                try Task.checkCancellation()
                guard var current = store.state.profile, current.revision == saved.revision else {
                    status = "Seu perfil mudou. Prepare o plano com as respostas atuais."; return
                }
                current.plan = report.plan; current.planStatus = "ready"; current.planProfileRevision = current.revision
                guard await store.perform(.updateProfile(current)) else { status = "Não foi possível salvar o plano. Suas respostas foram preservadas."; return }
                try Task.checkCancellation()
                profile = store.state.profile ?? current; prepared = true
                status = "Plano preparado com seus tempos e registros, salvo neste iPhone."
                if enterAfter { await finish() }
            } catch is CancellationError { status = "Preparação interrompida. Você pode continuar quando quiser." }
            catch { status = "Não foi possível preparar o plano: \(store.friendly(error))" }
        }
    }
    private func finish() async {
        answerFocused = false
        var completed = profile; completed.completedAt = StudyEngine.timestamp(Date())
        store.queueProfile(completed); await store.flushPreferences()
        if store.hasPendingPreferences { status = "Não foi possível salvar. Seus campos continuam aqui para tentar novamente." }
        else { savedStep = 0 }
    }
}

private struct ProfileActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    let primary: Bool
    let reducedMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(primary ? NinhoStyle.surface : NinhoStyle.green)
            .padding(.horizontal, 17).padding(.vertical, 14)
            .background(primary ? NinhoStyle.green : NinhoStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(NinhoStyle.green.opacity(primary ? 0 : 0.22), lineWidth: 1.5))
            .shadow(color: NinhoStyle.green.opacity(enabled ? (primary ? 0.28 : 0.10) : 0), radius: 0, x: 0, y: configuration.isPressed ? 1 : 3)
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(enabled ? 1 : 0.45)
            .animation(reducedMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
