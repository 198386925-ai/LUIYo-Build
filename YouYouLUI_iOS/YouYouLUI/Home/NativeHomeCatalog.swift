import Foundation

/// One icon slot rendered by the native homepage.
struct NativeIconEntry: Decodable, Identifiable {
    let id: Int
    let title: String
    let category: String
    let searchText: String
    let files: [String]
}

/// The complete homepage catalog shipped inside Web/.
struct NativeIconCatalog: Decodable {
    let totalSourceItems: Int
    let entries: [NativeIconEntry]

    static func load() -> NativeIconCatalog {
        guard let url = Bundle.main.url(forResource: "native-preview-catalog", withExtension: "json", subdirectory: "Web"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(NativeIconCatalog.self, from: data) else {
            fatalError("Complete homepage catalog is missing")
        }
        return catalog
    }
}
