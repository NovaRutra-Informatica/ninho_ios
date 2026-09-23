import SwiftUI
import NinhoCore

struct TutorialTip {
    let title: String
    let detail: String
    let icon: String
}

extension TutorialPage {
    var title: String {
        switch self {
        case .today: "Hoje"
        case .studies: "Meus estudos"
        case .reviews: "Revisões"
        case .focus: "Hora de focar"
        case .materials: "Materiais"
        case .agenda: "Agenda"
        case .progress: "Meu progresso"
        case .assistant: "Minha assistente"
        }
    }
    var tips: [TutorialTip] {
        switch self {
        case .today: [
            .init(title: "Seu ponto de partida", detail: "O compromisso de hoje compara o tempo registrado com sua meta diária. O foguinho ao lado do perfil mostra sua sequência; toque nele para ver o calendário dos dias estudados.", icon: "sun.max"),
            .init(title: "Escolha seu próximo passo", detail: "Toque em Revisões para praticar seus cartões ou nos minutos da semana para abrir o foco. A sugestão usa seus registros locais; não mede domínio do conteúdo.", icon: "sparkles"),
            .init(title: "Seu caminho pelo Ninho", detail: "O menu de vidro embaixo abre Hoje, Estudos, Foco, Revisões e Minha assistente. Seu perfil no alto reúne objetivos, preferências, Materiais, Agenda e Progresso. A data também abre a Agenda.", icon: "square.grid.2x2")]
        case .studies: [
            .init(title: "Do objetivo à próxima aula", detail: "Abra um curso para encontrar suas matérias. Dentro de cada matéria ficam os módulos e as aulas.", icon: "books.vertical"),
            .init(title: "Registre o que aconteceu", detail: "Em uma aula você pode mudar o andamento, escrever notas, iniciar um foco e abrir materiais. Marcar como concluída registra seu avanço; não inventa tempo de estudo.", icon: "checkmark.circle"),
            .init(title: "Construa sua coleção", detail: "Use os botões de adicionar para incluir cursos, matérias, módulos e aulas. Seus dados ficam no aparelho e podem ser levados em um backup.", icon: "plus.circle")]
        case .reviews: [
            .init(title: "Tente lembrar primeiro", detail: "Abra a revisão, leia a pergunta e tente responder antes de revelar a resposta cadastrada.", icon: "rectangle.on.rectangle"),
            .init(title: "Diga como foi", detail: "A avaliação que você escolhe ajusta a próxima revisão. Seja honesto: precisar rever é parte do aprendizado.", icon: "arrow.trianglehead.2.clockwise.rotate.90"),
            .init(title: "Cuide dos seus cartões", detail: "Você pode criar e editar cartões, suspender os que não quer praticar e marcar os que precisam de fonte atualizada ou novo estudo.", icon: "pencil")]
        case .focus: [
            .init(title: "Um tempo que cabe no seu dia", detail: "Escolha uma duração pelos atalhos ou ajuste os minutos. Vincule a matéria e a aula para o tempo entrar no lugar certo.", icon: "timer"),
            .init(title: "Comece, pause, retome", detail: "O relógio acompanha a sessão. Ao concluir, o tempo efetivamente estudado é registrado. Uma pausa não conta como estudo.", icon: "pause.circle")]
        case .materials: [
            .init(title: "Sua biblioteca local", detail: "Importe pelo seletor de arquivos e vincule cada material a uma matéria ou aula. O Ninho mantém uma cópia local.", icon: "folder"),
            .init(title: "Abra e organize", detail: "Toque em um material para visualizar o formato compatível e conferir seus vínculos. Importar um arquivo não significa que a IA já leu seu conteúdo.", icon: "doc.text")]
        case .agenda: [
            .init(title: "Um dia de cada vez", detail: "Escolha a data para consultar as tarefas e provas daquele dia. Use o calendário para chegar a outra semana ou mês.", icon: "calendar"),
            .init(title: "Prepare o que vem pela frente", detail: "Crie tarefas e marque provas com data, matéria e detalhes. Marque uma tarefa como concluída quando terminar.", icon: "checklist")]
        case .progress: [
            .init(title: "Enxergue sua constância", detail: "Os minutos, as aulas concluídas e os dias de sequência vêm dos seus registros. Você acompanha o caminho sem comparar seu ritmo com outras pessoas.", icon: "chart.bar"),
            .init(title: "Observe cada matéria", detail: "Os detalhes por matéria mostram revisões, cobertura e sinais registrados. Poucos dados significam pouca evidência; cobertura não é uma nota de domínio.", icon: "books.vertical")]
        case .assistant: [
            .init(title: "Uma companhia que já vem no Ninho", detail: "A assistente acompanha seus registros com uma análise local leve. Revisões, provas e sinais de dificuldade viram sugestões aqui e na tela Hoje, sem baixar modelos.", icon: "sparkles"),
            .init(title: "Seus objetivos permanecem com você", detail: "Meu perfil guarda seus objetivos, dias disponíveis, tempos e preferências. Edite quando sua rotina mudar; o acompanhamento usa sempre o perfil atual.", icon: "person.crop.circle"),
            .init(title: "Confira o motivo de cada sugestão", detail: "Cada cartão explica os dados e a confiança do sinal. Tempo no aplicativo fica separado de estudo. Poucos registros não provam dificuldade, domínio ou falta de atenção.", icon: "chart.bar")]

        }
    }
}

private struct NinhoTutorialModifier: ViewModifier {
    @EnvironmentObject var store: NinhoStore
    let page: TutorialPage
    @State private var showingTutorial = false

    func body(content: Content) -> some View {
        content
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { store.playNavigationSound(); showingTutorial = true } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 21)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).labelStyle(.iconOnly).accessibilityLabel("Como usar \(page.title)").accessibilityIdentifier("navigation.help")
        } }
        .fullScreenCover(isPresented: $showingTutorial) {
            TutorialWelcomeView(page: page)
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
        }
        .onAppear {
            if store.state.profile?.completedAt != nil,
               !(store.state.profile?.tutorialsSeen.contains(page.rawValue) ?? false),
               !store.isUITesting || ProcessInfo.processInfo.arguments.contains("--test-tutorials") {
                showingTutorial = true
            }
        }
    }
}

private struct TutorialWelcomeView: View {
    @EnvironmentObject private var store: NinhoStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let page: TutorialPage
    @State private var step = 0
    @State private var saving = false
    @State private var failure = ""
    private var motion: Animation? { reduceMotion || store.displaySettings.reducedMotion ? nil : .easeInOut(duration: 0.2) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea().accessibilityHidden(true)
            GeometryReader { geometry in
                VStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                HStack(spacing: 16) {
                                    NinhoMascot(size: 72).frame(height: 88)
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("NO SEU RITMO").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(NinhoStyle.green)
                                        Text(page.title).font(.headline)
                                        HStack(spacing: 6) {
                                            ForEach(page.tips.indices, id: \.self) { index in
                                                Capsule().fill(index <= step ? NinhoStyle.green : NinhoStyle.green.opacity(0.16)).frame(height: 5)
                                            }
                                        }.accessibilityHidden(true)
                                    }
                                    Text("\(step + 1)/\(page.tips.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        .accessibilityIdentifier("tutorial.\(page.rawValue).step")
                                }
                                Image(systemName: page.tips[step].icon).font(.system(size: 26)).foregroundStyle(NinhoStyle.green)
                                    .frame(width: 56, height: 56).background(NinhoStyle.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                                    .accessibilityHidden(true)
                                Text(page.tips[step].title).font(.system(.title2, design: .rounded, weight: .bold))
                                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                                Text(page.tips[step].detail).font(.body).foregroundStyle(.secondary).lineSpacing(5)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !failure.isEmpty { Text(failure).font(.footnote).foregroundStyle(.red) }
                            }.padding(24).id(step).transition(.opacity.combined(with: .scale(scale: 0.98)))
                        }.scrollBounceBehavior(.basedOnSize)
                        HStack(spacing: 12) {
                            Button { store.playNavigationSound(); complete() } label: {
                                Text("Ver depois").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.bordered).accessibilityIdentifier("tutorial.\(page.rawValue).skip")
                            Button {
                                store.playNavigationSound()
                                if step + 1 < page.tips.count { withAnimation(motion) { step += 1 } }
                                else { complete() }
                            } label: {
                                Text(step + 1 == page.tips.count ? "Entendi" : "Próximo")
                                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("tutorial.\(page.rawValue).continue")
                        }.font(.subheadline.weight(.semibold)).tint(NinhoStyle.green).disabled(saving).padding(20)
                    }
                    .frame(maxWidth: 440, maxHeight: max(0, min(590, geometry.size.height - 32)))
                    .background(NinhoStyle.surface, in: RoundedRectangle(cornerRadius: 30))
                    .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(NinhoStyle.green.opacity(0.14), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.16), radius: 30, y: 12)
                    .padding(.horizontal, 20)
                    .ninhoPageTransition()
                    Spacer(minLength: 0)
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutorial.\(page.rawValue).modal")
    }

    private func complete() {
        guard !saving else { return }
        saving = true
        Task {
            await store.flushPreferences()
            if await store.perform(.completeTutorial(page)) { dismiss() }
            else { failure = store.error ?? "Não foi possível salvar agora. Tente novamente." }
            saving = false
        }
    }
}

extension View {
    func ninhoTutorial(_ page: TutorialPage) -> some View { modifier(NinhoTutorialModifier(page: page)).ninhoActivity(MentorRoute(rawValue: page.rawValue) ?? .more) }
}

struct TutorialLibraryView: View {
    @EnvironmentObject var store: NinhoStore
    var body: some View {
        List {
            Section("Conheça cada parte do Ninho") {
                ForEach(TutorialPage.allCases, id: \.self) { page in
                    NavigationLink(page.title) { TutorialDetailView(page: page) }
                }
            }
            Section {
                Button("Mostrar as dicas novamente em cada tela") { Task { await store.flushPreferences(); await store.perform(.resetTutorials) } }
                Text("Você também pode rever qualquer tutorial pelo botão de interrogação da própria tela.").foregroundStyle(.secondary)
            }
        }.navigationTitle("Tutoriais")
    }
}

private struct TutorialDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let page: TutorialPage
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(page.tips.enumerated()), id: \.offset) { _, tip in
                    VStack(alignment: .leading, spacing: 12) {
                        Label(tip.title, systemImage: tip.icon).font(.headline)
                        Text(tip.detail)
                    }.frame(maxWidth: .infinity, alignment: .leading).ninhoCard()
                }
            }.padding(20)
        }.background(NinhoStyle.canvas).navigationTitle(page.title)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }
    }
}
