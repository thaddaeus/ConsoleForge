import Foundation
import SwiftUI

struct SessionConfiguration: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "New Session"
    var workingDirectory: String = "~"
    var model: String?
    var allowedTools: [String]?
    var disallowedTools: [String]?
    var systemPrompt: String?
    var appendSystemPrompt: String?
    var initialPrompt: String?
    var permissionMode: PermissionMode?
    var mcpConfigPath: String?
    var autoStart: Bool = false
    var tabColorHex: String = "#007AFF"
    var tabIconName: String = "terminal"
    var effortLevel: String?
    var additionalFlags: String = ""
    var continueSession: Bool = false
    var folderID: UUID?

    enum PermissionMode: String, Codable, CaseIterable, Identifiable {
        case `default` = "default"
        case plan = "plan"
        case autoEdit = "auto-edit"
        case fullAuto = "full-auto"
        case bypassPermissions = "bypassPermissions"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .default: return "Default"
            case .plan: return "Plan"
            case .autoEdit: return "Auto Edit"
            case .fullAuto: return "Full Auto"
            case .bypassPermissions: return "Bypass Permissions"
            }
        }
    }

    var tabColor: Color {
        Color(hex: tabColorHex) ?? .blue
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
