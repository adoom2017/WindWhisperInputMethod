import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct CustomWordsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.tabSeparatedText, .plainText] }

    let contents: String

    init(contents: String) {
        self.contents = contents
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
            let contents = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.contents = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(contents.utf8))
    }
}

private struct CustomWordDraft: Identifiable, Equatable {
    let id: UUID
    var text: String
    var code: String
    var weight: String

    init(entry: CustomWordEntry) {
        id = entry.id
        text = entry.text
        code = entry.code
        weight = entry.weight.map(String.init) ?? ""
    }

    init(id: UUID = UUID()) {
        self.id = id
        text = ""
        code = ""
        weight = ""
    }
}

@MainActor
private final class CustomWordsEditorModel: ObservableObject {
    @Published var words: [CustomWordDraft]
    @Published var selection = Set<UUID>()
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isImporting = false
    @Published var isExporting = false
    @Published var exportDocument: CustomWordsExportDocument?

    private let store: CustomWordsStore
    private let comments: [String]
    private let onSaved: () -> Void
    private var savedWords: [CustomWordDraft]
    var closeWindow: (() -> Void)?
    private(set) var isClosingAfterSave = false

    init(
        document: CustomWordsDocument,
        store: CustomWordsStore,
        onSaved: @escaping () -> Void
    ) {
        let words = document.entries.map(CustomWordDraft.init(entry:))
        self.words = words
        savedWords = words
        comments = document.comments
        self.store = store
        self.onSaved = onSaved
    }

    var hasUnsavedChanges: Bool {
        words != savedWords
    }

    func addWord() -> UUID {
        let word = CustomWordDraft()
        words.append(word)
        selection = [word.id]
        errorMessage = nil
        statusMessage = nil
        return word.id
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        words.removeAll { selection.contains($0.id) }
        selection.removeAll()
        errorMessage = nil
        statusMessage = nil
    }

    func save() {
        do {
            let saved = try store.save(currentDocument())
            words = saved.entries.map(CustomWordDraft.init(entry:))
            savedWords = words
            errorMessage = nil
            statusMessage = nil
            isClosingAfterSave = true
            onSaved()
            closeWindow?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importWords(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            let current = try currentDocument()
            let imported = try CustomWordsStore(fileURL: url).load()
            let merged = try CustomWordsStore.merging(imported, into: current)
            words = merged.document.entries.map(CustomWordDraft.init(entry:))
            selection = Set(merged.addedEntries.map(\.id))
            errorMessage = nil
            statusMessage = "已导入 \(merged.addedEntries.count) 个词条，跳过 \(merged.skippedCount) 个重复词条。"
        } catch {
            guard !Self.isUserCancelled(error) else { return }
            errorMessage = "导入失败：\(error.localizedDescription)"
            statusMessage = nil
        }
    }

    func prepareExport() {
        do {
            let contents = try CustomWordsStore.contents(for: currentDocument())
            exportDocument = CustomWordsExportDocument(contents: contents)
            errorMessage = nil
            statusMessage = nil
            isExporting = true
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            statusMessage = nil
        }
    }

    func finishExport(_ result: Result<URL, Error>) {
        defer { exportDocument = nil }
        switch result {
        case let .success(url):
            errorMessage = nil
            statusMessage = "已导出到 \(url.lastPathComponent)。"
        case let .failure(error):
            guard !Self.isUserCancelled(error) else { return }
            errorMessage = "导出失败：\(error.localizedDescription)"
            statusMessage = nil
        }
    }

    private func currentDocument() throws -> CustomWordsDocument {
        let entries = try words.enumerated().map { offset, word in
            let trimmedWeight = word.weight.trimmingCharacters(in: .whitespacesAndNewlines)
            let weight: Int?
            if trimmedWeight.isEmpty {
                weight = nil
            } else if let parsedWeight = Int(trimmedWeight), parsedWeight >= 0 {
                weight = parsedWeight
            } else {
                throw CustomWordsStoreError.invalidWeight(offset + 1)
            }
            return CustomWordEntry(
                id: word.id,
                text: word.text,
                code: word.code,
                weight: weight
            )
        }
        return try CustomWordsStore.normalized(
            CustomWordsDocument(comments: comments, entries: entries)
        )
    }

    private static func isUserCancelled(_ error: Error) -> Bool {
        (error as? CocoaError)?.code == .userCancelled
    }
}

private struct CustomWordsEditorView: View {
    @ObservedObject var model: CustomWordsEditorModel
    @FocusState private var focusedWordID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    focusedWordID = model.addWord()
                } label: {
                    Label("添加", systemImage: "plus")
                }

                Button {
                    model.deleteSelection()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(model.selection.isEmpty)
                .help("删除所选词条")
                .accessibilityLabel("删除所选词条")

                Divider()
                    .frame(height: 18)

                Button {
                    model.isImporting = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }

                Button {
                    model.prepareExport()
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }

                Spacer()
                Text("\(model.words.count) 个词条")
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            Table($model.words, selection: $model.selection) {
                TableColumn("词语") { $word in
                    TextField("词语", text: $word.text)
                        .textFieldStyle(.plain)
                        .focused($focusedWordID, equals: word.id)
                }
                .width(min: 180, ideal: 260)

                TableColumn("编码") { $word in
                    TextField("编码", text: $word.code)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 130, ideal: 190)

                TableColumn("权重") { $word in
                    TextField("自动", text: $word.weight)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 90, ideal: 110, max: 140)
            }
            .overlay {
                if model.words.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.badge.plus")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("暂无自定义词")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .onDeleteCommand {
                model.deleteSelection()
            }

            Divider()

            HStack(spacing: 10) {
                if let errorMessage = model.errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else if let statusMessage = model.statusMessage {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                Button("取消", role: .cancel) {
                    model.closeWindow?()
                }
                .keyboardShortcut(.cancelAction)
                Button("保存并应用") {
                    model.save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasUnsavedChanges)
            }
            .padding(12)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 400, idealHeight: 480)
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: [.tabSeparatedText, .plainText],
            allowsMultipleSelection: false,
            onCompletion: model.importWords
        )
        .fileExporter(
            isPresented: $model.isExporting,
            document: model.exportDocument,
            contentType: .tabSeparatedText,
            defaultFilename: "custom_words.tsv",
            onCompletion: model.finishExport
        )
    }
}

@MainActor
final class CustomWordsEditorWindowController: NSWindowController, NSWindowDelegate {
    private let model: CustomWordsEditorModel
    var onWindowClosed: (() -> Void)?

    init(
        document: CustomWordsDocument,
        store: CustomWordsStore,
        onSaved: @escaping () -> Void
    ) {
        let model = CustomWordsEditorModel(document: document, store: store, onSaved: onSaved)
        self.model = model

        let hostingController = NSHostingController(
            rootView: CustomWordsEditorView(model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "管理自定义词"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 480))
        window.contentMinSize = NSSize(width: 640, height: 400)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        model.closeWindow = { [weak window] in
            window?.performClose(nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.hasUnsavedChanges, !model.isClosingAfterSave else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "放弃未保存的修改？"
        alert.informativeText = "关闭后，本次对自定义词的修改不会保留。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "放弃修改")
        alert.addButton(withTitle: "继续编辑")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed?()
    }
}
