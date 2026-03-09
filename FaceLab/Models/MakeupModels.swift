import SwiftUI

// MARK: - Brush Types
enum BrushType: String, CaseIterable, Identifiable {
    case foundation = "Foundation"
    case blush = "Blush"
    case eyeshadow = "Eyeshadow"
    case lipstick = "Lipstick"
    case contour = "Contour"
    case highlighter = "Highlighter"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .foundation:  return "paintbrush"
        case .blush:       return "circle.lefthalf.filled"
        case .eyeshadow:   return "eye"
        case .lipstick:    return "mouth"
        case .contour:     return "shadow"
        case .highlighter: return "sparkles"
        }
    }

    /// Face region indices that this brush targets (ARKit face geometry regions)
    var targetRegion: FaceRegion {
        switch self {
        case .foundation:  return .fullFace
        case .blush:       return .cheeks
        case .eyeshadow:   return .eyes
        case .lipstick:    return .lips
        case .contour:     return .jawline
        case .highlighter: return .forehead
        }
    }
}

// MARK: - Face Regions
enum FaceRegion {
    case fullFace
    case cheeks
    case eyes
    case lips
    case jawline
    case forehead
}

// MARK: - Brush Settings
struct BrushSettings {
    var type: BrushType = .lipstick
    var color: Color = .red
    var opacity: Double = 0.6
    var size: Double = 0.5 // 0.0 ~ 1.0

    var uiColor: UIColor {
        UIColor(color)
    }
}

// MARK: - Makeup Look (saved preset)
struct MakeupLook: Identifiable, Codable {
    let id: UUID
    var name: String
    var layers: [MakeupLayer]
    var createdAt: Date
    var thumbnailURL: String?

    init(id: UUID = UUID(), name: String, layers: [MakeupLayer] = [], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.layers = layers
        self.createdAt = createdAt
    }
}

// MARK: - Individual Makeup Layer
struct MakeupLayer: Identifiable, Codable {
    let id: UUID
    var brushType: String // BrushType.rawValue
    var colorHex: String
    var opacity: Double
    var size: Double

    init(id: UUID = UUID(), brush: BrushSettings) {
        self.id = id
        self.brushType = brush.type.rawValue
        self.colorHex = brush.uiColor.hexString
        self.opacity = brush.opacity
        self.size = brush.size
    }
}

// MARK: - Color Hex Extension
extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
