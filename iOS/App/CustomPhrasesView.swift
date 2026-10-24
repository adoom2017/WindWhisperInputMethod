import SwiftUI
import Observation
import UniformTypeIdentifiers

/// The phrase file as written by every platform: UTF-8 `词条<Tab>编码<Tab>可选权重`.
private struct CustomPhrasesFile: FileDocument {
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

@MainActor
@Observable
private final class CustomPhrasesModel {
    private(set) var document = CustomWordsDocument.empty
    private(set) var loaded = false
    var errorMessage: String?

    private func store() throws -> CustomWordsStore {
        CustomWordsStore(fileURL: try KeyboardSharedStorage.userDataURL()
            .appendingPathComponent("custom_words.tsv"))
    }

    func load() {
        do {
            document = try store().load()
            loaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ entry: CustomWordEntry) throws {
        var updated = document
        if let index = updated.entries.firstIndex(where: { $0.id == entry.id }) {
            updated.entries[index] = entry
        } else {
            updated.entries.append(entry)
        }
        document = try store().save(updated)
    }

    /// Reads a phrase file; importing it replaces the whole list, on every platform.
    func readImport(from url: URL) throws -> CustomWordsDocument {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try CustomWordsStore(fileURL: url).load()
    }

    func replace(with imported: CustomWordsDocument) throws {
        document = try store().save(imported)
    }

    func exportFile() throws -> CustomPhrasesFile {
        CustomPhrasesFile(contents: try CustomWordsStore.contents(for: document))
    }

    func delete(at offsets: IndexSet) {
        var updated = document
        updated.entries.remove(atOffsets: offsets)
        do {
            document = try store().save(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CustomPhrasesView: View {
    @State private var model = CustomPhrasesModel()
    @State private var editingEntry: CustomWordEntry?
    @State private var isImporting = false
    @State private var exportFile: CustomPhrasesFile?
    @State private var pendingImport: CustomWordsDocument?
    @State private var statusMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(model.document.entries) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: entry.text)
                                .foregroundStyle(.primary)
                            Text(verbatim: entry.code)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: model.delete)
            } footer: {
                if !model.document.entries.isEmpty {
                    Text("仅用于小鹤音形。保存后风语键盘会自动更新。点击词组可编辑，向左滑动可删除。")
                }
            }
        }
        .overlay {
            if model.loaded && model.document.entries.isEmpty {
                ContentUnavailableView {
                    Label("暂无自定义词组", systemImage: "text.badge.plus")
                } description: {
                    Text("为常用的句子设置 1～4 个字母的编码，用小鹤音形打出编码即可上屏。也可以从右上角导入 Mac 或 Windows 版导出的词组文件。")
                } actions: {
                    Button("添加词组") {
                        editingEntry = CustomWordEntry(text: "", code: "")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("自定义词组")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加词组", systemImage: "plus") {
                    editingEntry = CustomWordEntry(text: "", code: "")
                }
                .disabled(!model.loaded)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("导入或导出", systemImage: "ellipsis.circle") {
                    Button("导入词组…", systemImage: "square.and.arrow.down") {
                        isImporting = true
                    }
                    Button("导出词组…", systemImage: "square.and.arrow.up") {
                        do {
                            exportFile = try model.exportFile()
                        } catch {
                            model.errorMessage = "导出失败：\(error.localizedDescription)"
                        }
                    }
                    .disabled(model.document.entries.isEmpty)
                }
                .disabled(!model.loaded)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.tabSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                pendingImport = try model.readImport(from: url)
            } catch {
                model.errorMessage = "导入失败：\(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "替换全部词组",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            titleVisibility: .visible,
            presenting: pendingImport
        ) { imported in
            Button("替换为 \(imported.entries.count) 个词组", role: .destructive) {
                do {
                    try model.replace(with: imported)
                    statusMessage = "已用导入文件替换全部词组，共 \(imported.entries.count) 个。"
                } catch {
                    model.errorMessage = "导入失败：\(error.localizedDescription)"
                }
            }
            Button("取消", role: .cancel) { }
        } message: { imported in
            Text("当前的 \(model.document.entries.count) 个词组将被文件中的 \(imported.entries.count) 个词组替换，此操作无法撤销。")
        }
        .fileExporter(
            isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } }),
            document: exportFile,
            contentType: .tabSeparatedText,
            defaultFilename: "custom_words.tsv"
        ) { result in
            switch result {
            case .success:
                statusMessage = "已导出 \(model.document.entries.count) 个词组。"
            case .failure(let error):
                model.errorMessage = "导出失败：\(error.localizedDescription)"
            }
        }
        .alert("完成", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("好", role: .cancel) { }
        } message: {
            Text(statusMessage ?? "")
        }
        .task { model.load() }
        .sheet(item: $editingEntry) { entry in
            CustomPhraseEditor(entry: entry, model: model)
        }
        .alert("无法更新词库", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct CustomPhraseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomWordEntry
    @State private var errorMessage: String?
    private let model: CustomPhrasesModel
    private let isNew: Bool

    init(entry: CustomWordEntry, model: CustomPhrasesModel) {
        _draft = State(initialValue: entry)
        self.model = model
        isNew = !model.document.entries.contains { $0.id == entry.id }
    }

    private var validCode: Bool {
        let code = draft.code.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...4).contains(code.count)
            && code.allSatisfy { $0.isASCII && $0.isLetter }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("词组") {
                    TextField("例如：稍后联系你", text: $draft.text, axis: .vertical)
                }
                Section {
                    TextField("例如：shlx", text: $draft.code)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("快捷编码")
                } footer: {
                    Text("输入 1～4 个英文字母，保存时自动转为小写。使用小鹤音形输入该编码，即可在候选中选择词组。")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isNew ? "添加词组" : "编辑词组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try model.save(draft)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(!validCode || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
