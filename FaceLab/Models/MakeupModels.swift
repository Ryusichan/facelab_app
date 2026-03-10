import SwiftUI
import CoreGraphics

// ============================================================
// MARK: - Makeup Category
// 5종: Lipstick, Blusher, Eyeshadow, Foundation, Eraser
// ============================================================
enum MakeupCategory: String, CaseIterable, Identifiable {
    case lip        = "Lipstick"
    case blush      = "Blusher"
    case eyeShadow  = "Eyeshadow"
    case foundation = "Foundation"
    case eraser     = "Eraser"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .lip:        return "mouth.fill"
        case .blush:      return "circle.lefthalf.filled"
        case .eyeShadow:  return "eye.fill"
        case .foundation: return "drop.fill"
        case .eraser:     return "eraser.fill"
        }
    }

    /// 렌더링 대상인지 (Eraser는 렌더링하지 않음)
    var isRenderable: Bool {
        self != .eraser
    }

    // ARKit face mesh UV 공간 영역 정의
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
        case .foundation:
            return [
                // 얼굴 전체 (이마 ~ 턱)
                CGRect(x: 0.05, y: 0.10, width: 0.90, height: 0.65),
            ]
        case .eraser:
            return [] // 지우개는 특정 영역 없음
        }
    }

    // 카테고리별 컬러 프리셋 (7개씩)
    var colorPresets: [Color] {
        switch self {
        case .lip:
            return [
                Color(red: 0.92, green: 0.78, blue: 0.72), // 누드
                Color(red: 0.90, green: 0.55, blue: 0.60), // 핑크
                Color(red: 0.95, green: 0.45, blue: 0.20), // 오렌지
                Color(red: 0.85, green: 0.10, blue: 0.20), // 클래식 레드
                Color(red: 0.70, green: 0.15, blue: 0.20), // 딥 레드
                Color(red: 0.55, green: 0.15, blue: 0.25), // 다크 베리
                Color(red: 0.95, green: 0.75, blue: 0.80), // 베이비 핑크
            ]
        case .blush:
            return [
                Color(red: 0.95, green: 0.78, blue: 0.72), // 누드 피치
                Color(red: 0.95, green: 0.60, blue: 0.65), // 피치 핑크
                Color(red: 0.90, green: 0.50, blue: 0.45), // 코랄
                Color(red: 0.85, green: 0.45, blue: 0.55), // 로즈
                Color(red: 0.80, green: 0.35, blue: 0.45), // 베리
                Color(red: 0.75, green: 0.55, blue: 0.65), // 모브
                Color(red: 0.95, green: 0.85, blue: 0.78), // 라이트 피치
            ]
        case .eyeShadow:
            return [
                Color(red: 0.70, green: 0.55, blue: 0.80), // 라벤더
                Color(red: 0.30, green: 0.25, blue: 0.50), // 딥 퍼플
                Color(red: 0.55, green: 0.40, blue: 0.30), // 웜 브라운
                Color(red: 0.15, green: 0.35, blue: 0.60), // 네이비
                Color(red: 0.50, green: 0.70, blue: 0.65), // 세이지 그린
                Color(red: 0.15, green: 0.15, blue: 0.15), // 스모키 블랙
                Color(red: 0.85, green: 0.70, blue: 0.55), // 골드
            ]
        case .foundation:
            return [
                Color(red: 0.96, green: 0.90, blue: 0.82), // 아이보리
                Color(red: 0.92, green: 0.83, blue: 0.73), // 라이트 베이지
                Color(red: 0.87, green: 0.75, blue: 0.65), // 미디엄 베이지
                Color(red: 0.80, green: 0.67, blue: 0.55), // 탄
                Color(red: 0.72, green: 0.58, blue: 0.45), // 카라멜
                Color(red: 0.60, green: 0.47, blue: 0.35), // 딥 탄
                Color(red: 0.48, green: 0.38, blue: 0.28), // 에스프레소
            ]
        case .eraser:
            return [.white] // 지우개 색상은 미사용
        }
    }
}

// ============================================================
// MARK: - Per-Category Makeup State
// ============================================================
struct MakeupLayerState {
    var category: MakeupCategory
    var selectedColor: Color
    var intensity: Double       // 0.0 ~ 1.0
    var brushSize: Double       // 0.0 ~ 1.0 (UV 영역 스케일 팩터)
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
// CGContext 기반 UV 공간 메이크업 텍스처 생성
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

        let renderer = UIGraphicsImageRenderer(size: textureSize, format: format)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.clear(CGRect(origin: .zero, size: textureSize))

            for layer in activeLayers {
                let baseColor = UIColor(layer.selectedColor)
                for uvRect in layer.category.uvRegions {
                    // brushSize로 영역 스케일 (0.3 ~ 1.5배)
                    let scale = 0.3 + layer.brushSize * 1.2
                    let scaledRect = uvRect.scaledFromCenter(by: scale)
                    let pixelRect = scaledRect.scaled(to: textureSize)

                    drawSoftMakeup(
                        ctx: cgCtx, rect: pixelRect,
                        color: baseColor,
                        intensity: CGFloat(layer.intensity),
                        category: layer.category
                    )
                }
            }
        }
    }

    private static func drawSoftMakeup(
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
        case .foundation: maxAlpha = 0.35
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
            case .foundation:
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
        CGRect(
            x: minX * size.width, y: minY * size.height,
            width: width * size.width, height: height * size.height
        )
    }

    /// 중심 기준으로 스케일
    func scaledFromCenter(by scale: CGFloat) -> CGRect {
        let newW = width * scale
        let newH = height * scale
        return CGRect(
            x: midX - newW / 2, y: midY - newH / 2,
            width: newW, height: newH
        )
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
        self.id = id
        self.name = name
        self.layers = layers
        self.createdAt = createdAt
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
