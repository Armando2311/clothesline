import SwiftUI
import ClotheslineCore

struct NoteEditor: View {
    @ObservedObject var model: AppModel
    let item: HangingItem?
    @State private var text: String
    @State private var noteID: UUID?
    @State private var saved = false
    init(model: AppModel, item: HangingItem?) {
        self.model = model; self.item = item; _text = State(initialValue: item?.text ?? ""); _noteID = State(initialValue: item?.id)
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(item == nil ? "Hang a new note" : "Edit your note").font(.title2.bold())
            TextEditor(text: $text).font(.body).border(Color.secondary.opacity(0.2)).accessibilityLabel("Note content")
            HStack {
                Text(saved ? "Saved on your line" : "Your note stays in Clothesline.").foregroundStyle(.secondary)
                Spacer()
                Button("Save Note") {
                    if let id = noteID { model.editNote(id,text: text) } else { noteID = model.hang(text: text,source: .manual); if noteID == nil { return } }
                    saved = true
                }.keyboardShortcut("s").disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (noteID != nil && model.board.item(noteID!) == nil))
            }
        }.padding(20).onChange(of: text) { _ in saved = false }
    }
}
