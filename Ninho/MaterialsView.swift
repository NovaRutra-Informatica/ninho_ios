import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import QuickLook
import AVKit
import NinhoCore

struct MaterialsView: View {
    @EnvironmentObject var store: NinhoStore
    var subjectID = ""
    var lessonID = ""
    var body: some View {
        List {
            Section { Text("Guarde PDFs, resumos, imagens, documentos, vídeos e áudios. O arquivo é copiado para o Ninho e fica disponível offline.").font(.body).foregroundStyle(.secondary) }
            MaterialRows(subjectID: subjectID, lessonID: lessonID)
        }.navigationTitle(lessonID.isEmpty ? "Materiais" : "Materiais da aula").accessibilityIdentifier("screen.materials").ninhoTutorial(.materials)
    }
}

struct MaterialRows: View {
    @EnvironmentObject var store: NinhoStore
    var subjectID = ""
    var lessonID = ""
    @State private var importing = false
    private var materials: [NinhoCore.Material] { store.state.materials.filter { (subjectID.isEmpty || $0.subjectId == subjectID) && (lessonID.isEmpty || $0.lessonId == lessonID) } }
    var body: some View {
        ForEach(materials) { material in
            NavigationLink { MaterialDetailView(materialID: material.id) } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: material.type == "pdf" ? "doc.richtext" : ["mp4", "mov", "webm", "mkv"].contains(material.type) ? "play.rectangle" : "doc").font(.title2).foregroundStyle(NinhoStyle.green)
                    VStack(alignment: .leading, spacing: 6) { Text(material.name).font(.headline).lineLimit(3); Text("\(material.type.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(material.size), countStyle: .file))").font(.body).foregroundStyle(.secondary); if lessonID.isEmpty, let lesson = store.state.lessons.first(where: { $0.id == material.lessonId }) { Text(lesson.title).font(.body).foregroundStyle(.secondary) } }
                }.padding(.vertical, 6)
            }.accessibilityIdentifier("material.\(material.id)")
        }
        if materials.isEmpty { Text("Ainda não há arquivos aqui. Adicione o PDF ou seu material desta aula.").font(.body).foregroundStyle(.secondary) }
        Button { importing = true } label: { Label(lessonID.isEmpty ? "Adicionar arquivos" : "Adicionar arquivos à aula", systemImage: "plus.circle.fill") }.disabled(store.busy).accessibilityIdentifier(lessonID.isEmpty ? "add.material" : "lesson.addMaterial")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await store.importFiles(urls, subjectId: subjectID, lessonId: lessonID) }
                case .failure(let error): store.error = store.friendly(error)
                }
            }
        if !store.notice.isEmpty { Text(store.notice).font(.body).foregroundStyle(.secondary).accessibilityIdentifier("app.notice") }
    }
}

struct MaterialDetailView: View {
    @EnvironmentObject var store: NinhoStore
    @Environment(\.dismiss) private var dismiss
    let materialID: String
    @State private var url: URL?
    @State private var failure: String?
    @State private var notes = ""
    @State private var subjectID = ""
    @State private var lessonID = ""
    @State private var initializedMaterialID: String?
    @State private var deleting = false
    private var material: NinhoCore.Material? { store.state.materials.first { $0.id == materialID } }
    var body: some View {
        Group {
            if let material {
                List {
                    Section {
                        if let url { NavigationLink { MaterialPreview(url: url, kind: material.type).navigationTitle(material.name).navigationBarTitleDisplayMode(.inline) } label: { Label("Abrir material", systemImage: "doc.text.magnifyingglass") }.accessibilityIdentifier("material.open")
                            ShareLink(item: url) { Label("Compartilhar uma cópia", systemImage: "square.and.arrow.up") }
                        } else if let failure { Text(failure).foregroundStyle(.red); Button("Tentar abrir novamente") { Task { await loadURL() } } } else { ProgressView("Conferindo arquivo…") }
                        Text("\(material.type.uppercased()) · \(ByteCountFormatter.string(fromByteCount: Int64(material.size), countStyle: .file))").font(.body).foregroundStyle(.secondary)
                    }
                    Section("Organização") {
                        SubjectPicker(selection: $subjectID, allowEmpty: true).accessibilityIdentifier("material.subject")
                        Picker("Aula", selection: $lessonID) { Text("Na matéria, sem aula").tag(""); ForEach(store.state.lessons.filter { $0.subjectId == subjectID }) { lesson in Text("\(store.state.courses.first { $0.id == lesson.courseId }?.title ?? "") — \(lesson.title)").tag(lesson.id) } }.accessibilityIdentifier("material.lesson")
                        TextEditor(text: $notes).frame(minHeight: 120).font(.body).accessibilityIdentifier("form.notes")
                        Button("Salvar organização e notas") { Task { await store.perform(.updateMaterial(id: material.id, subjectId: subjectID, lessonId: lessonID, notes: notes)) } }.disabled(store.busy).accessibilityIdentifier("form.save")
                    }
                    Section { Button("Remover da biblioteca", role: .destructive) { deleting = true } }
                }.task(id: materialID) {
                    if initializedMaterialID != materialID {
                        notes = material.notes; subjectID = material.subjectId; lessonID = material.lessonId
                        url = nil; failure = nil
                        initializedMaterialID = materialID
                    }
                    // Revalidate the file on return without resetting the draft.
                    await loadURL()
                }
                    .onChange(of: subjectID) { if !lessonID.isEmpty && !store.state.lessons.contains(where: { $0.id == lessonID && $0.subjectId == subjectID }) { lessonID = "" } }
                    .confirmationDialog("Remover este material da biblioteca?", isPresented: $deleting, titleVisibility: .visible) { Button("Remover", role: .destructive) { Task { if await store.perform(.removeMaterial(id: material.id)) { dismiss() } } } } message: { Text("O arquivo original fora do Ninho será preservado.") }
            } else { ContentUnavailableView("Material não encontrado", systemImage: "doc.questionmark") }
        }.navigationTitle("Seu material").navigationBarTitleDisplayMode(.inline)
    }
    private func loadURL() async {
        let requestedID = materialID
        do {
            let resolved = try await store.materialURL(requestedID)
            guard !Task.isCancelled, initializedMaterialID == requestedID else { return }
            url = resolved; failure = nil
        } catch {
            guard !Task.isCancelled, initializedMaterialID == requestedID else { return }
            url = nil; failure = store.friendly(error)
        }
    }
}

struct MaterialPreview: View {
    let url: URL
    let kind: String
    var body: some View {
        Group {
            if kind == "pdf" { PDFReader(url: url) }
            else if ["mp4", "mov", "m4a", "mp3", "aac", "wav"].contains(kind) { LocalMediaPlayer(url: url) }
            else { QuickLookFile(url: url) }
        }.accessibilityIdentifier("material.preview")
    }
}

struct PDFReader: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        if let document = PDFDocument(url: url), document.pageCount > 0 {
            let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical; view.document = document
            view.accessibilityIdentifier = "material.pdf"
            view.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: container.leadingAnchor), view.trailingAnchor.constraint(equalTo: container.trailingAnchor), view.topAnchor.constraint(equalTo: container.topAnchor), view.bottomAnchor.constraint(equalTo: container.bottomAnchor)])
        } else {
            let label = UILabel(); label.numberOfLines = 0; label.text = "Não foi possível abrir este PDF. Ele pode estar incompleto ou protegido. Volte para compartilhar ou importar outra cópia."
            label.font = .preferredFont(forTextStyle: .body); label.adjustsFontForContentSizeCategory = true
            label.accessibilityIdentifier = "material.pdfError"; label.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24), label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24), label.centerYAnchor.constraint(equalTo: container.centerYAnchor)])
        }
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {}
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) { uiView.subviews.compactMap { $0 as? PDFView }.forEach { $0.document = nil } }
}

struct QuickLookFile: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) { if context.coordinator.url != url { context.coordinator.url = url; controller.reloadData() } }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}

struct LocalMediaPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var playbackError: String?
    var body: some View {
        VideoPlayer(player: player).overlay {
            if let playbackError { Text(playbackError).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
        }.task(id: url) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                player = AVPlayer(url: url)
                playbackError = nil
            } catch { player = nil; playbackError = "Não foi possível preparar este material sem interromper outros áudios: \(error.localizedDescription)" }
        }.onDisappear { player?.pause(); player = nil }
    }
}

struct SubjectPicker: View {
    @EnvironmentObject var store: NinhoStore
    @Binding var selection: String
    var allowEmpty = false
    var body: some View {
        Picker("Matéria", selection: $selection) {
            if allowEmpty { Text("Geral").tag("") }
            ForEach(store.state.subjects) { subject in Text(subject.name).tag(subject.id) }
        }
    }
}
