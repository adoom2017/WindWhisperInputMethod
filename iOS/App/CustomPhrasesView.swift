import SwiftUI
import Observation

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

    var body: some View {
        List {
            Section {
                if model.loaded && model.document.entries.isEmpty {
                    ContentUnavailableView(
                        "暂无自定义词组",
                        systemImage: "text.badge.plus",
                        description: Text("点击右上角添加常用词组和快捷编码。")
                    )
                }
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
                Text("仅用于小鹤音形。保存后风语键盘会自动更新。点击词组可编辑，向左滑动可删除。")
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
