import SwiftUI
import NinhoCore

struct StudiesView: View {
    @EnvironmentObject var store: NinhoStore
    @State private var adding = false
    @State private var query = ""
    var body: some View {
        List {
            Section { Text("Seus cursos, um lugar para cada objetivo.").font(.body).foregroundStyle(.secondary) }
            ForEach(store.state.programs.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { program in
                NavigationLink { ProgramView(programID: program.id) } label: {
                    HStack(spacing: 14) { Image(systemName: program.track == .faculdade ? "graduationcap.fill" : "books.vertical.fill").foregroundStyle(NinhoStyle.green).font(.title2); VStack(alignment: .leading, spacing: 6) { Text(program.name).font(.headline); Text(program.description).font(.body).foregroundStyle(.secondary); Text("\(store.state.subjects.filter { $0.programId == program.id }.count) matérias").font(.subheadline).foregroundStyle(.secondary) } }.padding(.vertical, 8)
                }.accessibilityIdentifier("program.\(program.id)")
            }
            Button { adding = true } label: { Label("Novo curso", systemImage: "plus.circle.fill") }.accessibilityIdentifier("add.program")
        }.searchable(text: $query, prompt: "Buscar curso").navigationTitle("Meus estudos").accessibilityIdentifier("screen.studies")
            .sheet(isPresented: $adding) { HierarchyEditor(kind: .program, parentID: "") }
    }
}

struct ProgramView: View {
    @EnvironmentObject var store: NinhoStore
    let programID: String
    @State private var adding = false
    @State private var editing = false
    var body: some View {
        List {
            ForEach(store.state.subjects.filter { $0.programId == programID }) { subject in
                NavigationLink { SubjectView(subjectID: subject.id) } label: {
                    VStack(alignment: .leading, spacing: 8) { Text(subject.name).font(.headline); let lessons = store.state.lessons.filter { $0.subjectId == subject.id }; Text("\(lessons.filter { $0.status == .done }.count) de \(lessons.count) aulas concluídas").font(.body).foregroundStyle(.secondary) }.padding(.vertical, 6)
                }.accessibilityIdentifier("subject.\(subject.id)")
            }
            Button("Nova matéria", systemImage: "plus.circle") { adding = true }.accessibilityIdentifier("add.subject")
        }.navigationTitle(store.state.programs.first { $0.id == programID }?.name ?? "Curso")
            .toolbar { Button("Editar") { editing = true } }
            .sheet(isPresented: $adding) { HierarchyEditor(kind: .subject, parentID: programID) }
            .sheet(isPresented: $editing) { HierarchyEditor(kind: .program, parentID: "", editingID: programID) }
    }
}

struct SubjectView: View {
    @EnvironmentObject var store: NinhoStore
    let subjectID: String
    @State private var adding = false
    @State private var editing = false
    var body: some View {
        List {
            Section("Sua organização") {
                NavigationLink { MaterialsView(subjectID: subjectID) } label: { Label("Materiais da matéria", systemImage: "folder") }
                NavigationLink { CardLibraryView(subjectID: subjectID) } label: { Label("Cartões da matéria", systemImage: "rectangle.on.rectangle") }
                NavigationLink { FocusView(subjectID: subjectID) } label: { Label("Estudar com foco", systemImage: "timer") }
            }
            Section("Módulos e aulas") {
                ForEach(store.state.courses.filter { $0.subjectId == subjectID }) { course in
                    NavigationLink { CourseView(courseID: course.id) } label: { VStack(alignment: .leading, spacing: 6) { Text(course.title).font(.headline); Text(course.provider).font(.body).foregroundStyle(.secondary) }.padding(.vertical, 6) }.accessibilityIdentifier("course.\(course.id)")
                }
                Button("Novo módulo", systemImage: "plus.circle") { adding = true }.accessibilityIdentifier("add.course")
            }
        }.navigationTitle(store.state.subjects.first { $0.id == subjectID }?.name ?? "Matéria")
            .toolbar { Button("Editar") { editing = true } }
            .sheet(isPresented: $adding) { HierarchyEditor(kind: .course, parentID: subjectID) }
            .sheet(isPresented: $editing) { HierarchyEditor(kind: .subject, parentID: store.state.subjects.first { $0.id == subjectID }?.programId ?? "", editingID: subjectID) }
    }
}

struct CourseView: View {
    @EnvironmentObject var store: NinhoStore
    let courseID: String
    @State private var adding = false
    @State private var editing = false
    @State private var query = ""
    var body: some View {
        List {
            if let course = store.state.courses.first(where: { $0.id == courseID }), let url = URL(string: course.url), ["http", "https"].contains(url.scheme ?? "") {
                Link(destination: url) { Label("Abrir no Estratégia / site do curso", systemImage: "arrow.up.right.square") }
            }
            ForEach(store.state.lessons.filter { $0.courseId == courseID && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query)) }.sorted { $0.order < $1.order }) { lesson in
                NavigationLink { LessonView(lessonID: lesson.id) } label: {
                    HStack(alignment: .top, spacing: 14) { Image(systemName: lesson.status.icon).foregroundStyle(lesson.status == .done ? NinhoStyle.green : .secondary); VStack(alignment: .leading, spacing: 8) { Text(lesson.title).font(.headline); Text(lesson.description).font(.body).foregroundStyle(.secondary).lineLimit(3); let count = store.state.materials.filter { $0.lessonId == lesson.id }.count; Text("\(lesson.status.label) · \(count) material(is)").font(.subheadline).foregroundStyle(.secondary) } }.padding(.vertical, 8)
                }.accessibilityIdentifier("lesson.\(lesson.id)")
            }
            Button("Nova aula", systemImage: "plus.circle") { adding = true }.accessibilityIdentifier("add.lesson")
        }.searchable(text: $query, prompt: "Buscar aula ou conteúdo").navigationTitle("Aulas")
            .toolbar { Button("Editar módulo") { editing = true } }
            .sheet(isPresented: $adding) { HierarchyEditor(kind: .lesson, parentID: courseID) }
            .sheet(isPresented: $editing) { HierarchyEditor(kind: .course, parentID: store.state.courses.first { $0.id == courseID }?.subjectId ?? "", editingID: courseID) }
    }
}

struct LessonView: View {
    @EnvironmentObject var store: NinhoStore
    let lessonID: String
    @State private var notes = ""
    @State private var initializedLessonID: String?
    @State private var editing = false
    @State private var addCard = false
    private var lesson: Lesson? { store.state.lessons.first { $0.id == lessonID } }
    var body: some View {
        Group {
            if let lesson {
                List {
                    Section { Text(lesson.description).font(.body); Picker("Progresso", selection: Binding(get: { lesson.status }, set: { value in Task { await store.perform(.updateLesson(id: lesson.id, status: value)) } })) { ForEach(LessonStatus.allCases, id: \.self) { Text($0.label).tag($0) } }.accessibilityIdentifier("lesson.status") }
                    Section("Seu tempo nesta aula") {
                        let sessions = store.state.sessions.filter { $0.lessonId == lesson.id && $0.durationMinutes > 0 }
                        let seconds = Int(sessions.reduce(0) { $0 + $1.durationMinutes } * 60)
                        Text("\(seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min") · \(sessions.count) \(sessions.count == 1 ? "sessão" : "sessões")")
                            .font(.title3.weight(.semibold)).accessibilityIdentifier("lesson.time")
                        NavigationLink { FocusView(subjectID: lesson.subjectId, lessonID: lesson.id) } label: { Label("Cronometrar esta aula", systemImage: "timer") }.accessibilityIdentifier("lesson.timer")
                    }
                    Section("Materiais desta aula") { MaterialRows(subjectID: lesson.subjectId, lessonID: lesson.id) }
                    Section("Meu resumo") {
                        TextEditor(text: $notes).frame(minHeight: 160).font(.body).accessibilityIdentifier("lesson.notes")
                        Button("Salvar minhas anotações") { Task { await store.perform(.updateLesson(id: lesson.id, notes: notes)) } }.disabled(store.busy).accessibilityIdentifier("lesson.saveNotes")
                    }
                    Section("Aprender e revisar") {
                        Button("Criar cartão desta aula", systemImage: "plus.rectangle.on.rectangle") { addCard = true }.accessibilityIdentifier("lesson.addCard")
                        NavigationLink { CardLibraryView(subjectID: lesson.subjectId, lessonID: lesson.id) } label: { Text("Ver cartões da aula") }
                        if let url = URL(string: lesson.url), ["http", "https"].contains(url.scheme ?? "") { Link("Abrir aula no Estratégia", destination: url) }
                    }
                }.navigationTitle(lesson.title).navigationBarTitleDisplayMode(.inline)
                    .task(id: lessonID) {
                        // Reappearing views must not overwrite unsaved notes.
                        guard initializedLessonID != lessonID else { return }
                        notes = lesson.notes
                        initializedLessonID = lessonID
                    }
                    .toolbar { Button("Editar aula") { editing = true } }
                    .sheet(isPresented: $editing) { HierarchyEditor(kind: .lesson, parentID: lesson.courseId, editingID: lesson.id) }
                    .sheet(isPresented: $addCard) { CardEditor(subjectID: lesson.subjectId, lessonID: lesson.id) }
            } else { ContentUnavailableView("Aula não encontrada", systemImage: "book.closed") }
        }
    }
}

enum HierarchyKind { case program, subject, course, lesson }
struct HierarchyEditor: View {
    @EnvironmentObject var store: NinhoStore
    @Environment(\.dismiss) private var dismiss
    let kind: HierarchyKind
    let parentID: String
    var editingID: String? = nil
    @State private var name = ""
    @State private var details = ""
    @State private var url = ""
    @State private var track = Track.pessoal
    @State private var formError: String?
    private var title: String { switch kind { case .program: "Curso"; case .subject: "Matéria"; case .course: "Módulo"; case .lesson: "Aula" } }
    var body: some View {
        NavigationStack {
            Form {
                FormErrorNotice(message: formError)
                TextField("Nome", text: $name, axis: .vertical).accessibilityIdentifier(kind == .program || kind == .subject ? "form.name" : "form.title")
                if kind == .program { Picker("Objetivo", selection: $track) { Text("Concurso").tag(Track.concurso); Text("Faculdade").tag(Track.faculdade); Text("Pessoal").tag(Track.pessoal) } }
                if kind == .program || kind == .lesson { TextField("Descrição", text: $details, axis: .vertical).accessibilityIdentifier("form.description") }
                if kind == .course || kind == .lesson { TextField("Link da plataforma (opcional)", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("form.url") }
                Text("Você poderá adicionar arquivos e cartões dentro de cada aula.").font(.body).foregroundStyle(.secondary)
            }.navigationTitle("\(editingID == nil ? "Novo" : "Editar") \(title.lowercased())")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.accessibilityIdentifier("form.cancel") }; ToolbarItem(placement: .confirmationAction) { Button("Salvar") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy).accessibilityIdentifier("form.save") } }
                .task { populate() }
        }
    }
    private func populate() {
        guard let editingID else { return }
        switch kind {
        case .program: if let item = store.state.programs.first(where: { $0.id == editingID }) { name = item.name; details = item.description; track = item.track }
        case .subject: name = store.state.subjects.first { $0.id == editingID }?.name ?? ""
        case .course: if let item = store.state.courses.first(where: { $0.id == editingID }) { name = item.title; url = item.url }
        case .lesson: if let item = store.state.lessons.first(where: { $0.id == editingID }) { name = item.title; details = item.description; url = item.url }
        }
    }
    private func save() {
        let id = editingID ?? UUID().uuidString
        let command: StudyCommand
        switch kind {
        case .program:
            var item = store.state.programs.first { $0.id == id } ?? StudyProgram(id: id)
            item.name = name; item.description = details; item.track = track; command = .saveProgram(item)
        case .subject:
            var item = store.state.subjects.first { $0.id == id } ?? Subject(id: id, programId: parentID)
            item.name = name; item.track = store.state.programs.first { $0.id == parentID }?.track ?? .pessoal; command = .saveSubject(item)
        case .course:
            var item = store.state.courses.first { $0.id == id } ?? Course(id: id, subjectId: parentID)
            item.title = name; item.url = url; command = .saveCourse(item)
        case .lesson:
            var item = store.state.lessons.first { $0.id == id } ?? Lesson(id: id, courseId: parentID, subjectId: store.state.courses.first { $0.id == parentID }?.subjectId ?? "", order: (store.state.lessons.filter { $0.courseId == parentID }.map(\.order).max() ?? -1) + 1)
            item.title = name; item.description = details; item.url = url; command = .saveLesson(item)
        }
        Task { if await store.perform(command) { dismiss() } else { formError = store.error } }
    }
}

extension LessonStatus {
    var label: String { switch self { case .notStarted: "Ainda não comecei"; case .inProgress: "Em andamento"; case .done: "Concluída" } }
    var icon: String { switch self { case .notStarted: "circle"; case .inProgress: "circle.lefthalf.filled"; case .done: "checkmark.circle.fill" } }
}

struct FormErrorNotice: View {
    var message: String?
    var body: some View {
        if let message { Section { Label(message, systemImage: "exclamationmark.circle").font(.body).foregroundStyle(.red).accessibilityIdentifier("form.error") } }
    }
}
