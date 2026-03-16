import SwiftUI
import CoreGraphics

// ============================================================
// MARK: - Makeup Category
// 7종: Lipstick, Blush, Eyeshadow, Eyeliner, Foundation, Highlight, Eraser
// ============================================================
enum MakeupCategory: String, CaseIterable, Identifiable {
    case lip        = "Lipstick"
    case blush      = "Blusher"
    case eyeShadow  = "Eyeshadow"
    case eyeliner   = "Eyeliner"
    case foundation = "Foundation"
    case highlight  = "Highlight"
    case eraser     = "Eraser"

    var id: String { rawValue }

    var shortLabel: String { rawValue.uppercased() }

    var icon: String {
        switch self {
        case .lip:        return "mouth.fill"
        case .blush:      return "circle.lefthalf.filled"
        case .eyeShadow:  return "eye.fill"
        case .eyeliner:   return "pencil.line"
        case .foundation: return "drop.fill"
        case .highlight:  return "sparkle"
        case .eraser:     return "eraser.fill"
        }
    }

    var isRenderable: Bool { self != .eraser }

    var uvRegions: [CGRect] {
        switch self {
        case .lip:
            return [
                CGRect(x: 0.30, y: 0.620, width: 0.40, height: 0.045),
                CGRect(x: 0.30, y: 0.665, width: 0.40, height: 0.055),
            ]
        case .blush:
            return [
                CGRect(x: 0.06, y: 0.420, width: 0.26, height: 0.18),
                CGRect(x: 0.68, y: 0.420, width: 0.26, height: 0.18),
            ]
        case .eyeShadow:
            return [
                CGRect(x: 0.10, y: 0.255, width: 0.26, height: 0.12),
                CGRect(x: 0.64, y: 0.255, width: 0.26, height: 0.12),
            ]
        case .eyeliner:
            return [
                CGRect(x: 0.13, y: 0.348, width: 0.20, height: 0.020),
                CGRect(x: 0.67, y: 0.348, width: 0.20, height: 0.020),
            ]
        case .foundation:
            return [
                CGRect(x: 0.05, y: 0.10, width: 0.90, height: 0.65),
            ]
        case .highlight:
            return [
                CGRect(x: 0.38, y: 0.12, width: 0.24, height: 0.28),  // 이마/코 브릿지
                CGRect(x: 0.08, y: 0.37, width: 0.18, height: 0.08),  // 좌 광대
                CGRect(x: 0.74, y: 0.37, width: 0.18, height: 0.08),  // 우 광대
            ]
        case .eraser:
            return []
        }
    }

    var colorPresets: [Color] {
        switch self {
        case .lip:
            return [
                Color(red: 0.92, green: 0.78, blue: 0.72),
                Color(red: 0.90, green: 0.55, blue: 0.60),
                Color(red: 0.95, green: 0.45, blue: 0.20),
                Color(red: 0.85, green: 0.10, blue: 0.20),
                Color(red: 0.70, green: 0.15, blue: 0.20),
                Color(red: 0.55, green: 0.15, blue: 0.25),
                Color(red: 0.95, green: 0.75, blue: 0.80),
            ]
        case .blush:
            return [
                Color(red: 0.95, green: 0.78, blue: 0.72),
                Color(red: 0.95, green: 0.60, blue: 0.65),
                Color(red: 0.90, green: 0.50, blue: 0.45),
                Color(red: 0.85, green: 0.45, blue: 0.55),
                Color(red: 0.80, green: 0.35, blue: 0.45),
                Color(red: 0.75, green: 0.55, blue: 0.65),
                Color(red: 0.95, green: 0.85, blue: 0.78),
            ]
        case .eyeShadow:
            return [
                Color(red: 0.70, green: 0.55, blue: 0.80),
                Color(red: 0.30, green: 0.25, blue: 0.50),
                Color(red: 0.55, green: 0.40, blue: 0.30),
                Color(red: 0.15, green: 0.35, blue: 0.60),
                Color(red: 0.50, green: 0.70, blue: 0.65),
                Color(red: 0.15, green: 0.15, blue: 0.15),
                Color(red: 0.85, green: 0.70, blue: 0.55),
            ]
        case .eyeliner:
            return [
                Color(red: 0.08, green: 0.08, blue: 0.10),
                Color(red: 0.28, green: 0.20, blue: 0.15),
                Color(red: 0.12, green: 0.18, blue: 0.40),
                Color(red: 0.55, green: 0.40, blue: 0.20),
                Color(red: 0.45, green: 0.42, blue: 0.48),
                Color(red: 0.90, green: 0.88, blue: 0.85),
                Color(red: 0.82, green: 0.68, blue: 0.30),
            ]
        case .foundation:
            return [
                Color(red: 0.96, green: 0.90, blue: 0.82),
                Color(red: 0.92, green: 0.83, blue: 0.73),
                Color(red: 0.87, green: 0.75, blue: 0.65),
                Color(red: 0.80, green: 0.67, blue: 0.55),
                Color(red: 0.72, green: 0.58, blue: 0.45),
                Color(red: 0.60, green: 0.47, blue: 0.35),
                Color(red: 0.48, green: 0.38, blue: 0.28),
            ]
        case .highlight:
            return [
                Color(red: 0.96, green: 0.90, blue: 0.78),
                Color(red: 0.88, green: 0.72, blue: 0.42),
                Color(red: 0.95, green: 0.92, blue: 0.88),
                Color(red: 0.90, green: 0.72, blue: 0.65),
                Color(red: 0.72, green: 0.58, blue: 0.38),
                Color(red: 0.85, green: 0.85, blue: 0.90),
                Color(red: 0.95, green: 0.75, blue: 0.80),
            ]
        case .eraser:
            return [.white]
        }
    }
}

// ============================================================
// MARK: - Brush Type
// 6종: Brush, Pencil, Airbrush, Sponge, Smudge, Layer
// ============================================================
enum BrushType: String, CaseIterable, Identifiable {
    case brush    = "Brush"
    case pencil   = "Pencil"
    case airbrush = "Airbrush"
    case sponge   = "Sponge"
    case smudge   = "Smudge"
    case layer    = "Layer"

    var id: String { rawValue }

    var shortLabel: String { rawValue.uppercased() }

    var icon: String {
        switch self {
        case .brush:    return "paintbrush.pointed.fill"
        case .pencil:   return "pencil"
        case .airbrush: return "aqi.medium"
        case .sponge:   return "seal.fill"
        case .smudge:   return "scribble.variable"
        case .layer:    return "square.stack.3d.up.fill"
        }
    }
}

// ============================================================
// MARK: - Makeup Tool
// 부위별 선택 가능한 메이크업 도구 (20종)
// ============================================================
enum MakeupTool: String, CaseIterable, Identifiable {
    case foundationBrush = "파운데이션 브러쉬"
    case airbrush        = "에어브러쉬"
    case blend           = "블렌드"
    case smooth          = "스무드"
    case foundation      = "파운데이션"
    case highlight       = "하이라이트"
    case contour         = "컨투어"
    case browPencil      = "브로우 펜슬"
    case browBrush       = "브로우 브러쉬"
    case browPowder      = "브로우 파우더"
    case browGel         = "브로우 젤"
    case eyeshadow       = "아이섀도우"
    case blendBrush      = "블렌드 브러쉬"
    case smudge          = "스머지"
    case eyeliner        = "아이라이너"
    case detail          = "디테일"
    case lipBrush        = "립 브러쉬"
    case lipPencil       = "립 펜슬"
    case gloss           = "글로스"
    case blusher         = "블러셔"

    var id: String { rawValue }
    var shortLabel: String { rawValue }

    var icon: String {
        switch self {
        case .foundationBrush, .foundation: return "paintbrush.fill"
        case .airbrush:      return "aqi.medium"
        case .blend:         return "scribble.variable"
        case .smooth:        return "seal.fill"
        case .highlight:     return "sparkle"
        case .contour:       return "oval"
        case .browPencil:    return "pencil"
        case .browBrush:     return "paintbrush.pointed.fill"
        case .browPowder:    return "circle.fill"
        case .browGel:       return "drop.fill"
        case .eyeshadow:     return "eye.fill"
        case .blendBrush:    return "paintbrush.fill"
        case .smudge:        return "scribble.variable"
        case .eyeliner:      return "pencil.line"
        case .detail:        return "pencil"
        case .lipBrush:      return "mouth.fill"
        case .lipPencil:     return "pencil.tip"
        case .gloss:         return "drop.fill"
        case .blusher:       return "circle.lefthalf.filled"
        }
    }

    var maxAlpha: CGFloat {
        switch self {
        case .eyeliner, .browPencil, .lipPencil, .detail: return 0.90
        case .eyeshadow, .browPowder:              return 0.72
        case .foundationBrush, .foundation:        return 0.35
        case .lipBrush, .gloss:                    return 0.85
        case .blusher:                             return 0.55
        case .highlight:                           return 0.50
        case .contour:                             return 0.60
        case .browBrush, .browGel:                 return 0.65
        case .airbrush:                            return 0.28
        case .blend, .blendBrush:                  return 0.22
        case .smooth:                              return 0.15
        case .smudge:                              return 0.48
        }
    }

    var isHardEdge: Bool {
        switch self {
        case .eyeliner, .browPencil, .lipPencil, .detail: return true
        default: return false
        }
    }

    // 툴별 디폴트 강도 — 펜슬/라이너는 얇고 정밀하게 시작
    var defaultIntensity: Double {
        switch self {
        case .eyeliner, .browPencil, .lipPencil, .detail: return 0.15
        case .contour, .browGel, .smudge:                 return 0.18
        case .eyeshadow, .browBrush, .browPowder:         return 0.20
        case .lipBrush, .gloss:                           return 0.22
        case .blusher, .highlight:                        return 0.18
        case .foundation, .foundationBrush:               return 0.20
        case .airbrush, .blend, .blendBrush, .smooth:     return 0.15
        }
    }

    // 툴별 디폴트 브러쉬 크기 — 펜슬은 최소, 브러쉬는 중간
    var defaultBrushSize: Double {
        switch self {
        case .eyeliner, .browPencil, .lipPencil, .detail: return 0.08
        case .browGel, .browBrush, .smudge:               return 0.12
        case .eyeshadow, .browPowder, .lipBrush:          return 0.15
        case .contour, .highlight, .blusher:              return 0.18
        case .gloss:                                      return 0.14
        case .foundation, .foundationBrush:               return 0.20
        case .airbrush, .blend, .blendBrush, .smooth:     return 0.18
        }
    }

    var colorPresets: [Color] {
        switch self {
        case .foundationBrush, .foundation, .smooth, .airbrush:
            return [
                Color(red: 0.96, green: 0.90, blue: 0.82),
                Color(red: 0.92, green: 0.83, blue: 0.73),
                Color(red: 0.87, green: 0.75, blue: 0.65),
                Color(red: 0.80, green: 0.67, blue: 0.55),
                Color(red: 0.72, green: 0.58, blue: 0.45),
                Color(red: 0.60, green: 0.47, blue: 0.35),
            ]
        case .blend, .blendBrush:
            return [
                Color(red: 0.96, green: 0.90, blue: 0.82),
                Color(red: 0.92, green: 0.83, blue: 0.73),
                Color(red: 0.87, green: 0.75, blue: 0.65),
                Color(red: 0.80, green: 0.67, blue: 0.55),
                Color(red: 0.72, green: 0.58, blue: 0.45),
                Color(red: 0.95, green: 0.92, blue: 0.88),
            ]
        case .highlight:
            return [
                Color(red: 0.98, green: 0.95, blue: 0.88),
                Color(red: 0.96, green: 0.88, blue: 0.70),
                Color(red: 0.88, green: 0.72, blue: 0.42),
                Color(red: 0.95, green: 0.92, blue: 0.88),
                Color(red: 0.85, green: 0.85, blue: 0.92),
                Color(red: 0.98, green: 0.82, blue: 0.90),
            ]
        case .contour:
            return [
                Color(red: 0.65, green: 0.50, blue: 0.38),
                Color(red: 0.55, green: 0.40, blue: 0.30),
                Color(red: 0.45, green: 0.35, blue: 0.28),
                Color(red: 0.38, green: 0.28, blue: 0.22),
                Color(red: 0.60, green: 0.48, blue: 0.42),
                Color(red: 0.70, green: 0.58, blue: 0.50),
            ]
        case .browPencil, .browBrush, .browPowder, .browGel:
            return [
                Color(red: 0.35, green: 0.25, blue: 0.18),
                Color(red: 0.50, green: 0.38, blue: 0.28),
                Color(red: 0.62, green: 0.48, blue: 0.36),
                Color(red: 0.25, green: 0.18, blue: 0.12),
                Color(red: 0.15, green: 0.10, blue: 0.08),
                Color(red: 0.70, green: 0.58, blue: 0.45),
            ]
        case .eyeshadow, .smudge:
            return [
                Color(red: 0.70, green: 0.55, blue: 0.80),
                Color(red: 0.30, green: 0.25, blue: 0.50),
                Color(red: 0.55, green: 0.40, blue: 0.30),
                Color(red: 0.15, green: 0.35, blue: 0.60),
                Color(red: 0.15, green: 0.15, blue: 0.15),
                Color(red: 0.85, green: 0.70, blue: 0.55),
            ]
        case .eyeliner, .detail:
            return [
                Color(red: 0.08, green: 0.08, blue: 0.10),
                Color(red: 0.28, green: 0.20, blue: 0.15),
                Color(red: 0.12, green: 0.18, blue: 0.40),
                Color(red: 0.55, green: 0.40, blue: 0.20),
                Color(red: 0.45, green: 0.42, blue: 0.48),
                Color(red: 0.82, green: 0.68, blue: 0.30),
            ]
        case .lipBrush, .lipPencil, .gloss:
            return [
                Color(red: 0.92, green: 0.78, blue: 0.72),
                Color(red: 0.90, green: 0.55, blue: 0.60),
                Color(red: 0.95, green: 0.45, blue: 0.20),
                Color(red: 0.85, green: 0.10, blue: 0.20),
                Color(red: 0.70, green: 0.15, blue: 0.20),
                Color(red: 0.95, green: 0.75, blue: 0.80),
            ]
        case .blusher:
            return [
                Color(red: 0.95, green: 0.78, blue: 0.72),
                Color(red: 0.95, green: 0.60, blue: 0.65),
                Color(red: 0.90, green: 0.50, blue: 0.45),
                Color(red: 0.85, green: 0.45, blue: 0.55),
                Color(red: 0.80, green: 0.35, blue: 0.45),
                Color(red: 0.95, green: 0.85, blue: 0.78),
            ]
        }
    }
}

// ============================================================
// MARK: - Tool Layer State
// ============================================================
struct ToolLayerState {
    var tool: MakeupTool
    var selectedColor: Color
    var intensity: Double   // 0.0 ~ 1.0
    var brushSize: Double   // 0.0 ~ 1.0

    init(tool: MakeupTool) {
        self.tool = tool
        self.selectedColor = tool.colorPresets[0]
        self.intensity = tool.defaultIntensity
        self.brushSize = tool.defaultBrushSize
    }
}

// ============================================================
// MARK: - Face Region
// 8종: 전체/이마/눈썹/눈/코/입술/볼/턱
// ============================================================
enum FaceRegion: String, CaseIterable, Identifiable {
    case full     = "전체"
    case forehead = "이마"
    case eyebrow  = "눈썹"
    case eye      = "눈"
    case nose     = "코"
    case lip      = "입술"
    case cheek    = "볼"
    case jaw      = "턱"

    var id: String { rawValue }

    var tools: [MakeupTool] {
        switch self {
        case .full:     return [.foundationBrush, .airbrush, .blend, .smooth]
        case .forehead: return [.foundation, .highlight, .contour, .blend]
        case .eyebrow:  return [.browPencil, .browBrush, .browPowder, .browGel]
        case .eye:      return [.eyeshadow, .blendBrush, .smudge, .eyeliner, .detail]
        case .nose:     return [.contour, .highlight, .blend, .detail]
        case .lip:      return [.lipBrush, .lipPencil, .gloss, .blend]
        case .cheek:    return [.blusher, .airbrush, .highlight, .blend]
        case .jaw:      return [.contour, .blend, .highlight]
        }
    }

    var icon: String {
        switch self {
        case .full:     return "face.smiling.fill"
        case .forehead: return "arrow.up.circle.fill"
        case .eyebrow:  return "eyebrow"
        case .eye:      return "eye.fill"
        case .nose:     return "nose"
        case .lip:      return "mouth.fill"
        case .cheek:    return "oval.fill"
        case .jaw:      return "arrow.down.circle.fill"
        }
    }
}

// ============================================================
// MARK: - Interaction Mode
// rotate: 팬 제스처 = 카메라 오빗 / paint: 팬 제스처 = 얼굴 텍스처 페인팅
// ============================================================
enum InteractionMode: Equatable {
    case rotate
    case paint
}

// ============================================================
// MARK: - Per-Category Makeup State
// ============================================================
struct MakeupLayerState {
    var category: MakeupCategory
    var selectedColor: Color
    var intensity: Double       // 0.0 ~ 1.0
    var brushSize: Double       // 0.0 ~ 1.0
    var isEnabled: Bool

    init(category: MakeupCategory) {
        self.category = category
        self.selectedColor = category.colorPresets[0]
        self.intensity = 0.0
        self.brushSize = 0.5
        self.isEnabled = true
    }
}

// ============================================================
// MARK: - Makeup Texture Renderer
// ============================================================
enum MakeupTextureRenderer {
    static let textureSize = CGSize(width: 1024, height: 1024)

    static func render(layers: [MakeupLayerState]) -> UIImage? {
        let activeLayers = layers.filter {
            $0.isEnabled && $0.intensity > 0.005 && $0.category.isRenderable
        }
        guard !activeLayers.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: textureSize, format: format).image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.clear(CGRect(origin: .zero, size: textureSize))

            for layer in activeLayers {
                let baseColor = UIColor(layer.selectedColor)
                for uvRect in layer.category.uvRegions {
                    let scale = 0.3 + layer.brushSize * 1.2
                    let scaledRect = uvRect.scaledFromCenter(by: scale)
                    let pixelRect = scaledRect.scaled(to: textureSize)
                    drawSoftMakeup(ctx: cgCtx, rect: pixelRect,
                                   color: baseColor, intensity: CGFloat(layer.intensity),
                                   category: layer.category)
                }
            }
        }
    }

    // MakeupTool 기반 브러시 스트로크 페인팅
    static func drawBrushStroke(ctx: CGContext, rect: CGRect, color: UIColor,
                                 intensity: CGFloat, maxAlpha: CGFloat, isHardEdge: Bool) {
        let steps = 16
        ctx.saveGState()
        for i in stride(from: steps, through: 1, by: -1) {
            let t = CGFloat(i) / CGFloat(steps)
            let alpha: CGFloat = isHardEdge
                ? max(0, (t - 0.35) / 0.65) * intensity * maxAlpha
                : t * t * intensity * maxAlpha
            let insetX = rect.width  * (1.0 - t) * 0.5
            let insetY = rect.height * (1.0 - t) * 0.5
            let stepRect = rect.insetBy(dx: insetX, dy: insetY)
            color.withAlphaComponent(alpha).setFill()
            let path: UIBezierPath = isHardEdge
                ? UIBezierPath(roundedRect: stepRect, cornerRadius: stepRect.height * 0.3)
                : UIBezierPath(ovalIn: stepRect)
            path.fill()
        }
        ctx.restoreGState()
    }

    static func drawSoftMakeup(
        ctx: CGContext, rect: CGRect,
        color: UIColor, intensity: CGFloat,
        category: MakeupCategory
    ) {
        let steps = 16

        let maxAlpha: CGFloat
        switch category {
        case .lip:        maxAlpha = 0.88
        case .blush:      maxAlpha = 0.55
        case .eyeShadow:  maxAlpha = 0.72
        case .eyeliner:   maxAlpha = 0.92
        case .foundation: maxAlpha = 0.35
        case .highlight:  maxAlpha = 0.50
        case .eraser:     return
        }

        ctx.saveGState()
        for i in stride(from: steps, through: 1, by: -1) {
            let t = CGFloat(i) / CGFloat(steps)
            let alpha = t * t * intensity * maxAlpha
            let insetX = rect.width  * (1.0 - t) * 0.5
            let insetY = rect.height * (1.0 - t) * 0.5
            let stepRect = rect.insetBy(dx: insetX, dy: insetY)

            color.withAlphaComponent(alpha).setFill()

            let path: UIBezierPath
            switch category {
            case .lip:
                path = UIBezierPath(roundedRect: stepRect, cornerRadius: stepRect.height * 0.45)
            case .eyeliner:
                path = UIBezierPath(roundedRect: stepRect, cornerRadius: stepRect.height * 0.4)
            case .foundation, .highlight:
                path = UIBezierPath(roundedRect: stepRect, cornerRadius: stepRect.width * 0.15)
            default:
                path = UIBezierPath(ovalIn: stepRect)
            }
            path.fill()
        }
        ctx.restoreGState()
    }
}

// ============================================================
// MARK: - CGRect Helpers
// ============================================================
extension CGRect {
    func scaled(to size: CGSize) -> CGRect {
        CGRect(x: minX * size.width, y: minY * size.height,
               width: width * size.width, height: height * size.height)
    }

    func scaledFromCenter(by scale: CGFloat) -> CGRect {
        let newW = width * scale
        let newH = height * scale
        return CGRect(x: midX - newW / 2, y: midY - newH / 2, width: newW, height: newH)
    }
}

// ============================================================
// MARK: - Saved Models (Supabase)
// ============================================================
struct MakeupLook: Identifiable, Codable {
    let id: UUID
    var name: String
    var layers: [MakeupLayer]
    var createdAt: Date
    var thumbnailURL: String?

    init(id: UUID = UUID(), name: String, layers: [MakeupLayer] = [], createdAt: Date = .now) {
        self.id = id; self.name = name; self.layers = layers; self.createdAt = createdAt
    }
}

struct MakeupLayer: Identifiable, Codable {
    let id: UUID
    var category: String
    var colorHex: String
    var intensity: Double

    init(from state: MakeupLayerState) {
        self.id = UUID()
        self.category = state.category.rawValue
        self.colorHex = UIColor(state.selectedColor).hexString
        self.intensity = state.intensity
    }
}

// ============================================================
// MARK: - UIColor Extensions
// ============================================================
extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8)  & 0xFF) / 255
        let b = CGFloat(int & 0xFF)          / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
