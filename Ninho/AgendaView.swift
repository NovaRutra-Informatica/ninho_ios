import SwiftUI
import NinhoCore

struct AgendaView: View {
    @EnvironmentObject var store: NinhoStore
    @State private var selected = Date()
    @State private var addExam = false
    @State private var addTask = false
    @State private var editingExam: Exam?
    @State private var editingTask: StudyTask?
    @State private var deletingExam: Exam?
    @State private var deletingTask: StudyTask?
    private var day: String { StudyEngine.localDate(selected) }
    var body: some View {
        List {
            Section { DatePicker("Escolha um dia", selection: $selected, displayedComponents: .date).datePickerStyle(.graphical).accessibilityIdentifier("agenda.date") }
            Section("Provas em \(selected.formatted(date: .abbreviated, time: .omitted))") {
                let exams = store.state.exams.filter { $0.date == day }.sorted { $0.time < $1.time }
                if exams.isEmpty { Text("Nenhuma prova neste dia.").foregroundStyle(.secondary) }
                ForEach(exams) { exam in
                    VStack(alignment: .leading, spacing: 8) {
                        Button { editingExam = exam } label: { Label(exam.title, systemImage: exam.completed ? "checkmark.seal.fill" : "calendar.badge.clock").font(.headline).foregroundStyle(.primary) }
                        Text([exam.time, exam.location].filter { !$0.isEmpty }.joined(separator: " · ")).font(.body).foregroundStyle(.secondary)
                        Toggle("Prova realizada", isOn: Binding(get: { exam.completed }, set: { value in var item = exam; item.completed = value; Task { await store.perform(.saveExam(item)) } }))
                    }.padding(.vertical, 6).accessibilityIdentifier("exam.\(exam.id)")
                        .swipeActions { Button("Excluir", role: .destructive) { deletingExam = exam } }
                }
                Button("Marcar prova", systemImage: "plus.circle") { addExam = true }.accessibilityIdentifier("add.exam")
            }
            Section("Pequenos passos do dia") {
                ForEach(store.state.tasks.filter { $0.date == day }) { task in
                    HStack {
                        Button { var item = task; item.completed.toggle(); Task { await store.perform(.saveTask(item)) } } label: { Image(systemName: task.completed ? "checkmark.circle.fill" : "circle").font(.title2) }.buttonStyle(.borderless).accessibilityLabel(task.completed ? "Reabrir tarefa" : "Concluir tarefa")
                        Button { editingTask = task } label: { Text(task.title).strikethrough(task.completed).foregroundStyle(.primary) }.buttonStyle(.borderless)
                    }.accessibilityIdentifier("task.\(task.id)").swipeActions { Button("Excluir", role: .destructive) { deletingTask = task } }
                }
                Button("Nova tarefa", systemImage: "plus.circle") { addTask = true }.accessibilityIdentifier("add.task")
            }
            Section("Próximas provas") {
                ForEach(StudyEngine.overview(in: store.state).upcomingExams) { exam in
                    Button { if let date = DateFormatter.ninhoDay.date(from: exam.date) { selected = date } } label: { VStack(alignment: .leading, spacing: 6) { Text(exam.title).font(.headline); Text(exam.date).font(.body).foregroundStyle(.secondary) } }
                }
            }
        }.navigationTitle("Calendário").accessibilityIdentifier("screen.agenda")
            .sheet(isPresented: $addExam) { AgendaEditor(isExam: true, date: selected) }
            .sheet(isPresented: $addTask) { AgendaEditor(isExam: false, date: selected) }
            .sheet(item: $editingExam) { AgendaEditor(isExam: true, date: selected, originalExam: $0) }
            .sheet(item: $editingTask) { AgendaEditor(isExam: false, date: selected, originalTask: $0) }
            .confirmationDialog("Excluir esta prova?", isPresented: Binding(get: { deletingExam != nil }, set: { if !$0 { deletingExam = nil } }), titleVisibility: .visible) { Button("Excluir", role: .destructive) { if let exam = deletingExam { Task { await store.perform(.deleteExam(id: exam.id)) }; deletingExam = nil } } }
            .confirmationDialog("Excluir esta tarefa?", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }), titleVisibility: .visible) { Button("Excluir", role: .destructive) { if let task = deletingTask { Task { await store.perform(.deleteTask(id: task.id)) }; deletingTask = nil } } }
    }
}

struct AgendaEditor: View {
    @EnvironmentObject var store: NinhoStore
    @Environment(\.dismiss) private var dismiss
    let isExam: Bool
    let date: Date
    var originalExam: Exam? = nil
    var originalTask: StudyTask? = nil
    @State private var title = ""
    @State private var day = Date()
    @State private var time = ""
    @State private var subject = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var formError: String?
    var body: some View {
        NavigationStack {
            Form {
                FormErrorNotice(message: formError)
                TextField(isExam ? "Nome da prova" : "O que você quer fazer?", text: $title, axis: .vertical).accessibilityIdentifier("form.title")
                DatePicker("Data", selection: $day, displayedComponents: .date)
                SubjectPicker(selection: $subject, allowEmpty: true)
                if isExam {
                    TextField("Horário (HH:mm, opcional)", text: $time).keyboardType(.numbersAndPunctuation)
                    TextField("Local", text: $location)
                    TextField("Lembretes e conteúdo", text: $notes, axis: .vertical).lineLimit(3...10).accessibilityIdentifier("form.notes")
                }
            }.navigationTitle(isExam ? "Sua prova" : "Sua tarefa")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.accessibilityIdentifier("form.cancel") }; ToolbarItem(placement: .confirmationAction) { Button("Salvar") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy).accessibilityIdentifier("form.save") } }
                .task {
                    day = date
                    if let item = originalExam { title = item.title; subject = item.subjectId; day = DateFormatter.ninhoDay.date(from: item.date) ?? date; time = item.time; location = item.location; notes = item.notes }
                    if let item = originalTask { title = item.title; subject = item.subjectId; day = DateFormatter.ninhoDay.date(from: item.date) ?? date }
                }
        }
    }
    private func save() {
        let command: StudyCommand
        if isExam {
            var item = originalExam ?? Exam(); item.title = title; item.subjectId = subject; item.date = StudyEngine.localDate(day); item.time = time; item.location = location; item.notes = notes
            command = .saveExam(item)
        } else {
            var item = originalTask ?? StudyTask(); item.title = title; item.subjectId = subject; item.date = StudyEngine.localDate(day)
            command = .saveTask(item)
        }
        Task { if await store.perform(command) { dismiss() } else { formError = store.error } }
    }
}

extension DateFormatter {
    static var ninhoDay: DateFormatter { let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false; return formatter }
}
