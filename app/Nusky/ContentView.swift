import SwiftUI

final class BrowserModel: ObservableObject {
    @Published var address = "https://example.com"
    @Published var items: [DrawItem] = []
    @Published var contentHeight: CGFloat = 0
    @Published var status = ""

    func load() {
        var s = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else {
            status = "Endereço inválido"
            return
        }

        status = "Carregando…"
        let width = Float(UIScreen.main.bounds.width)

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            let html = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let items = Engine.render(html: html, width: width)
            let height = items.map { $0.y + $0.fontSize * 1.3 }.max() ?? 0

            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    self.status = error.localizedDescription
                    return
                }
                self.items = items
                self.contentHeight = height + 16
                self.status = "\(items.count) linhas"
            }
        }.resume()
    }
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Endereço", text: $model.address, onCommit: model.load)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)

                Button("Ir", action: model.load)
            }
            .padding(8)

            Text(model.status)
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    ForEach(model.items) { item in
                        Text(item.text)
                            .font(.system(size: item.fontSize, weight: item.bold ? .bold : .regular))
                            .offset(x: item.x, y: item.y)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: model.contentHeight, alignment: .topLeading)
            }
        }
        .onAppear { model.load() }
    }
}