import Foundation

enum GenerationRoute: Equatable {
    case auto
    case model(UserSettings.ModelRoute)

    var routeOverride: UserSettings.ModelRoute? {
        switch self {
        case .auto: return nil
        case .model(let route): return route
        }
    }

    func menuTitle(settings: UserSettings = .shared) -> String {
        switch self {
        case .auto:
            return "Auto"
        case .model(let route):
            return route.menuTitle
        }
    }
}

struct PromptImageAttachment {
    let fileName: String
    let mimeType: String
    let data: Data

}

struct GenerationResult {
    let text: String
    let provider: UserSettings.Provider
    let model: String
    var sources: [WebSource] = []
    var usedWebSearch: Bool = false
}
