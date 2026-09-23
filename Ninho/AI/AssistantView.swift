import SwiftUI
import NinhoCore

@MainActor struct AssistantView: View {
    @EnvironmentObject private var store: NinhoStore
    let state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 20) {
                    Image("owl").renderingMode(.original).resizable().scaledToFit().frame(width: 92, height: 112).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Estou aqui para acompanhar seu caminho.").font(.system(.title2, design: .serif))
                        Text("A cada estudo registrado, um próximo passo mais próximo de você.").foregroundStyle(.secondary)
                    }
                }
                Label("Análise local embutida · sempre offline", systemImage: "leaf")
                    .font(.subheadline.weight(.medium)).foregroundStyle(NinhoStyle.green).accessibilityIdentifier("assistant.embedded")
                AssistantIdentityCard()
                if store.mentor.generatedAt == nil { ProgressView("Organizando seus registros…") }
                ForEach(store.mentor.suggestions) { suggestion in MentorSuggestionCard(suggestion: suggestion) }
                VStack(alignment: .leading, spacing: 15) {
                    Label("Um plano que cabe na sua vida", systemImage: "calendar").font(.headline)
                    Text(store.mentor.plan).font(.body).textSelection(.enabled)
                    NavigationLink { ProfileView(onboarding: false) } label: { Label("Ajustar meu perfil e preferências", systemImage: "person.crop.circle") }
                        .buttonStyle(.bordered).accessibilityIdentifier("assistant.profile")
                }.ninhoCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label("De onde vêm as sugestões", systemImage: "chart.bar").font(.headline)
                    Text(store.mentor.sampleDescription).font(.subheadline)
                    Text("Dificuldades usam as avaliações que você marcou, com suavização e um mínimo de 8 respostas em 3 cartões. Horários habituais exigem 6 inícios de foco em 3 dias. Poucos dados não viram conclusões sobre você.").font(.subheadline).foregroundStyle(.secondary)
                    Text("A análise é estatística e está incluída no aplicativo. Não é um modelo de linguagem, não lê PDFs automaticamente e não mede atenção, domínio ou seu uso de outros aplicativos.").font(.footnote).foregroundStyle(.secondary)
                }.ninhoCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Seu uso do Ninho", systemImage: "iphone").font(.headline)
                    Text("\(store.mentor.visits) visitas a telas · \(Int(store.mentor.activeMinutes)) min com o aplicativo ativo")
                    Text("Agregados locais dos últimos 90 dias. Esse tempo fica separado das sessões de estudo, não entra na sua meta e não indica aprendizado. Para ao sair do Ninho ou após 60 segundos sem interação. Você pode desligar ou apagar os registros no perfil.").font(.footnote).foregroundStyle(.secondary)
                    if !store.activityNotice.isEmpty { Text(store.activityNotice).font(.footnote).foregroundStyle(.secondary) }
                }.ninhoCard()
            }.padding(20)
        }.background(NinhoStyle.canvas).navigationTitle("Minha assistente").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.assistant").ninhoTutorial(.assistant)
            .onAppear { store.refreshOverview() }
    }
}

struct MentorSuggestionCard: View {
    let suggestion: MentorSuggestion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(suggestion.confidence, systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(NinhoStyle.green)
            Text(suggestion.title).font(.system(.title3, design: .rounded, weight: .semibold))
            Text(suggestion.detail).font(.body)
            Text(suggestion.evidence).font(.footnote).foregroundStyle(.secondary)
            NavigationLink { destination } label: { Label(actionLabel, systemImage: "arrow.right").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).accessibilityIdentifier("assistant.action.\(suggestion.id)")
        }.frame(maxWidth: .infinity, alignment: .leading).ninhoCard()
    }
    private var actionLabel: String {
        switch suggestion.route {
        case .reviews: "Abrir revisões"
        case .agenda: "Ver minha agenda"
        case .profile: "Ajustar meu perfil"
        case .studies: "Retomar meus estudos"
        default: "Preparar um foco"
        }
    }
    @ViewBuilder private var destination: some View {
        switch suggestion.route {
        case .reviews: ReviewsView()
        case .agenda: AgendaView()
        case .profile: ProfileView(onboarding: false)
        case .studies: StudiesView()
        default: FocusView(subjectID: suggestion.subjectID)
        }
    }
}
