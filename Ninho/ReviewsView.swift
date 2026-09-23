import SwiftUI
import NinhoCore

struct ReviewsView: View {
    @EnvironmentObject var store: NinhoStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var revealed = false
    @State private var subjectID = ""
    @State private var adding = false
    @State private var due: [ReviewCard] = []
    @State private var loading = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SubjectPicker(selection: $subjectID, allowEmpty: true)
                Text("Revisar é reencontrar o que você aprendeu.").font(.title2.weight(.semibold))
                Text("\(due.count) cartão(ões) disponíveis hoje. Tente responder antes de revelar.").font(.body).foregroundStyle(.secondary)
                if let card = due.first {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(store.state.subjects.first { $0.id == card.subjectId }?.name ?? "Revisão").font(.subheadline.weight(.medium)).foregroundStyle(NinhoStyle.green)
                        Text(card.question).font(.title3).textSelection(.enabled)
                        if revealed {
                            Divider(); Text(card.answer).font(.body).textSelection(.enabled).accessibilityIdentifier("review.answer")
                            if !card.source.isEmpty { Text(card.source).font(.body).foregroundStyle(.secondary) }
                        } else {
                            Button("Mostrar resposta") { withAnimation(store.state.settings.reducedMotion ? nil : .easeInOut(duration: 0.2)) { revealed = true } }.buttonStyle(.borderedProminent).accessibilityIdentifier("review.reveal")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).ninhoCard().accessibilityIdentifier("card.\(card.id)")
                    if revealed {
                        Text("Como foi lembrar?").font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            grade("Não lembrei", .again, card); grade("Com esforço", .hard, card); grade("Lembrei", .good, card); grade("Foi fácil", .easy, card)
                        }
                    }
                } else if loading {
                    ProgressView("Organizando suas revisões…")
                } else {
                    ContentUnavailableView("Por hoje, tudo em dia", systemImage: "checkmark.seal", description: Text("O Ninho organiza o próximo reencontro. Você pode estudar uma aula ou preparar novos cartões."))
                }
                NavigationLink { CardLibraryView() } label: { Label("Organizar meus cartões", systemImage: "rectangle.stack") }
                Button("Criar cartão", systemImage: "plus.circle") { adding = true }.accessibilityIdentifier("add.card")
            }.padding(20)
        }.background(NinhoStyle.canvas).navigationTitle("Revisões").accessibilityIdentifier("screen.reviews").ninhoTutorial(.reviews)
            .task(id: "\(store.revision)-\(subjectID)-\(scenePhase)") {
                guard scenePhase == .active else { return }
                let snapshot = store.state, selection = subjectID.isEmpty ? nil : subjectID
                due = []; revealed = false; loading = true
                while !Task.isCancelled {
                    let worker = Task.detached(priority: .userInitiated) {
                        let date = Date()
                        return (StudyEngine.dueCards(in: snapshot, at: date, subjectId: selection),
                                StudyEngine.nextReviewRefresh(in: snapshot, after: date, subjectId: selection))
                    }
                    let (cards, deadline) = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                    guard !Task.isCancelled else { return }
                    due = cards; loading = false
                    do { try await Task.sleep(for: .seconds(max(0.05, deadline.timeIntervalSinceNow))) }
                    catch { return }
                }
            }
            .onChange(of: due.first?.id) { revealed = false }
            .sheet(isPresented: $adding) { CardEditor(subjectID: subjectID.isEmpty ? store.state.subjects.first?.id ?? "" : subjectID) }
    }
    private func grade(_ title: String, _ rating: Rating, _ card: ReviewCard) -> some View {
        Button(title) { Task { if await store.perform(.reviewCard(id: card.id, rating: rating)) { revealed = false } } }.frame(maxWidth: .infinity).padding(.vertical, 8).buttonStyle(.bordered).disabled(store.busy).accessibilityIdentifier("review.\(rating.rawValue)")
    }
}

struct CardLibraryView: View {
    @EnvironmentObject var store: NinhoStore
    var subjectID = ""
    var lessonID = ""
    @State private var adding = false
    @State private var editing: ReviewCard?
    @State private var deleting: ReviewCard?
    @State private var search = ""
    var body: some View {
        List {
            ForEach(store.state.cards.filter { (subjectID.isEmpty || $0.subjectId == subjectID) && (lessonID.isEmpty || $0.lessonId == lessonID) && (search.isEmpty || $0.question.localizedCaseInsensitiveContains(search)) }) { card in
                VStack(alignment: .leading, spacing: 10) {
                    Button { editing = card } label: { Text(card.question).font(.headline).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading) }
                    Text(card.suspended ? "Pausado" : "Próxima revisão: \(StudyEngine.parseTimestamp(card.dueAt)?.formatted(date: .abbreviated, time: .omitted) ?? card.dueAt)").font(.body).foregroundStyle(.secondary)
                    if card.flag != .none { Text(card.flag == .outdated ? "Você marcou: precisa atualizar" : "Você marcou: reaprender").font(.body).foregroundStyle(NinhoStyle.amber) }
                    Menu("Organizar cartão") {
                        Button("Editar") { editing = card }
                        Button(card.suspended ? "Retomar revisões" : "Pausar revisões") { Task { await store.perform(.suspendCard(id: card.id, suspended: !card.suspended)) } }
                        Button("Marcar como desatualizado") { Task { await store.perform(.flagCard(id: card.id, flag: .outdated)) } }
                        Button("Quero reaprender") { Task { await store.perform(.flagCard(id: card.id, flag: .relearn)) } }
                        Button("Remover classificação") { Task { await store.perform(.flagCard(id: card.id, flag: .none)) } }
                        Button("Excluir cartão", role: .destructive) { deleting = card }
                    }
                }.padding(.vertical, 8).accessibilityIdentifier("card.\(card.id)")
            }
            Button("Novo cartão", systemImage: "plus.circle") { adding = true }.accessibilityIdentifier("add.card")
        }.navigationTitle("Meus cartões").searchable(text: $search, prompt: "Buscar pergunta")
            .sheet(isPresented: $adding) { CardEditor(subjectID: subjectID.isEmpty ? store.state.subjects.first?.id ?? "" : subjectID, lessonID: lessonID) }
            .sheet(item: $editing) { CardEditor(subjectID: $0.subjectId, lessonID: $0.lessonId ?? "", original: $0) }
            .confirmationDialog("Excluir este cartão e seu histórico?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) { Button("Excluir", role: .destructive) { if let card = deleting { Task { await store.perform(.deleteCard(id: card.id)) }; deleting = nil } } }
    }
}

struct CardEditor: View {
    @EnvironmentObject var store: NinhoStore
    @Environment(\.dismiss) private var dismiss
    var subjectID: String
    var lessonID = ""
    var original: ReviewCard? = nil
    @State private var subject = ""
    @State private var lesson = ""
    @State private var question = ""
    @State private var answer = ""
    @State private var source = ""
    @State private var sourceURL = ""
    @State private var formError: String?
    var body: some View {
        NavigationStack {
            Form {
                FormErrorNotice(message: formError)
                Section("Onde guardar") {
                    SubjectPicker(selection: $subject)
                    Picker("Aula", selection: $lesson) { Text("Sem aula específica").tag(""); ForEach(store.state.lessons.filter { $0.subjectId == subject }) { Text($0.title).tag($0.id) } }
                }
                Section("Uma ideia por cartão") {
                    TextField("Pergunta", text: $question, axis: .vertical).lineLimit(3...10).accessibilityIdentifier("form.question")
                    TextField("Resposta", text: $answer, axis: .vertical).lineLimit(4...20).accessibilityIdentifier("form.answer")
                }
                Section("Fonte, para conferir depois") { TextField("Material / página", text: $source); TextField("Link (opcional)", text: $sourceURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("form.url") }
            }.navigationTitle(original == nil ? "Novo cartão" : "Editar cartão")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.accessibilityIdentifier("form.cancel") }; ToolbarItem(placement: .confirmationAction) { Button("Salvar") { save() }.disabled(subject.isEmpty || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy).accessibilityIdentifier("form.save") } }
                .task { subject = subjectID; lesson = lessonID; question = original?.question ?? ""; answer = original?.answer ?? ""; source = original?.source ?? ""; sourceURL = original?.sourceUrl ?? "" }
                .onChange(of: subject) { if !store.state.lessons.contains(where: { $0.id == lesson && $0.subjectId == subject }) { lesson = "" } }
        }
    }
    private func save() {
        var card = original ?? ReviewCard(subjectId: subject)
        card.subjectId = subject; card.lessonId = lesson.isEmpty ? nil : lesson; card.question = question; card.answer = answer; card.source = source; card.sourceUrl = sourceURL
        Task { if await store.perform(.saveCard(card)) { dismiss() } else { formError = store.error } }
    }
}
