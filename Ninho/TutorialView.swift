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
    @State private var step = 0
    @State private var closed = false
    @State private var replay = false
    private var visible: Bool {
        store.state.profile?.completedAt != nil && !closed &&
        !(store.state.profile?.tutorialsSeen.contains(page.rawValue) ?? false) &&
        (!store.isUITesting || ProcessInfo.processInfo.arguments.contains("--test-tutorials"))
    }
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if visible {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(page.tips[step].title, systemImage: page.tips[step].icon).font(.headline)
                        Spacer()
                        Text("\(step + 1)/\(page.tips.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(page.tips[step].detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Ver depois") { complete() }
                        Spacer()
                        if step > 0 { Button("Anterior") { step -= 1 } }
                        Button(step + 1 == page.tips.count ? "Entendi" : "Próximo") {
                            if step + 1 < page.tips.count { step += 1 } else { complete() }
                        }.buttonStyle(.borderedProminent)
                    }
                }.padding(16).background(NinhoStyle.surface)
                    .overlay(alignment: .bottom) { Divider() }
                    .accessibilityIdentifier("tutorial.\(page.rawValue)")
            }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { replay = true } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 21)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.labelStyle(.iconOnly).accessibilityLabel("Como usar \(page.title)").accessibilityIdentifier("navigation.help")
        } }
        .sheet(isPresented: $replay) { NavigationStack { TutorialDetailView(page: page) } }
        .onChange(of: store.state.profile?.tutorialsSeen) { _, pages in
            if pages?.contains(page.rawValue) == false { closed = false; step = 0 }
        }
    }
    private func complete() {
        Task {
            await store.flushPreferences()
            if await store.perform(.completeTutorial(page)) { closed = true }
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
