import SwiftUI
import CoreGraphics

// MARK: - Makeup Category
// MVP 3종: 립, 블러셔, 아이섀도우
// uvRegions: ARKit face geometry의 UV 좌표계 기준 (0.0~1.0, V는 아래로 증가)
enum MakeupCategory: String, CaseIterable, Identifiable {
    case lip       = "Lip"
    case blush     = "Blush"
    case eyeShadow = "Eye"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .lip:       return "mouth.fill"
        case .blush:     return "circle.lefthalf.filled"
        case .eyeShadow: return "eye.fill"
        }
    }

    // ARKit face mesh의 UV 공간에서 각 부위의 영역 정의
    // 이 값은 ARKit face geometry UV map 기준 근사치
    // 실기기에서 테스트 후 미세 조정 가능
    var uvRegions: [CGRect] {
        switch self {
        case .lip:
            return [
                CGRect(x: 0.30, y: 0.620, width: 0.40, height: 0.045), // 윗입술
                CGRect(x: 0.30, y: 0.665, width: 0.40, height: 0.055), // 아랫입술
            ]
        case .blush:
            return [
                CGRect(x: 0.06, y: 0.420, width: 0.26, height: 0.18), // 왼쪽 볼 (카메라 기준)
                CGRect(x: 0.68, y: 0.420, width: 0.26, height: 0.18), // 오른쪽 볼
            ]
        case .eyeShadow:
            return [
                CGRect(x: 0.10, y: 0.255, width: 0.26, height: 0.12), // 왼쪽 눈
                CGRect(x: 0.64, y: 0.255, width: 0.26, height: 0.12), // 오른쪽 눈
            ]
        }
    }

    // 카테고리별 컬러 프리셋 (6개씩)
    var colorPresets: [Color] {
        switch self {
        case .lip:
            return [
                Color(red: 0.85, green: 0.10, blue: 0.20), // 클래식 레드
                Color(red: 0.90, green: 0.45, blue: 0.55), // 코랄 핑크
                Color(red: 0.70, green: 0.20, blue: 0.35), // 베리
                Color(red: 0.85, green: 0.65, blue: 0.55), // 누드
                Color(red: 0.55, green: 0.15, blue: 0.25), // 다크 베리
                Color(red: 0.95, green: 0.75, blue: 0.80), // 베이비 핑크
            ]
        case .blush:
            return [
                Color(red: 0.95, green: 0.60, blue: 0.65), // 피치 핑크
                Color(red: 0.90, green: 0.50, blue: 0.45), // 코랄
                Color(red: 0.85, green: 0.45, blue: 0.55), // 로즈
                Color(red: 0.75, green: 0.55, blue: 0.65), // 모브
                Color(red: 0.95, green: 0.78, blue: 0.72), // 누드 블러셔
                Color(red: 0.80, green: 0.35, blue: 0.45), // 베리 블러셔
            ]
        case .eyeShadow:
            return [
                Color(red: 0.70, green: 0.55, blue: 0.80), // 라벤더
                Color(red: 0.30, green: 0.25, blue: 0.50), // 딥 퍼플
                Color(red: 0.55, green: 0.40, blue: 0.30), // 웜 브라운
                Color(red: 0.15, green: 0.35, blue: 0.60), // 네이비
                Color(red: 0.50, green: 0.70, blue: 0.65), // 세이지 그린
                Color(red: 0.15, green: 0.15, blue: 0.15), // 스모키 블랙
            ]
        }
    }
}

// MARK: - Per-Category Makeup State
// 각 카테고리의 현재 설정 (색상, 강도, on/off)
struct MakeupLayerState {
    var category: MakeupCategory
    var selectedColor: Color
    var intensity: Double    // 0.0(없음) ~ 1.0(최대)
    var isEnabled: Bool

    init(category: MakeupCategory) {
        self.category = category
        self.selectedColor = category.colorPresets[0]
        self.intensity = 0.0
        self.isEnabled = true
    }
}

// MARK: - Makeup Texture Renderer
// CGContext로 메이크업 텍스처를 생성
// ARKit face mesh의 UV 좌표에 맞게 각 부위에 색상을 페인팅
enum MakeupTextureRenderer {
    static let textureSize = CGSize(width: 512, height: 512)

    /// 현재 레이어 상태를 기반으로 메이크업 텍스처 이미지를 생성
    /// - Returns: 알파 채널 포함 UIImage (투명 배경 위에 메이크업 색상)
    static func render(layers: [MakeupLayerState]) -> UIImage? {
        let activeLayers = layers.filter { $0.isEnabled && $0.intensity > 0.005 }
        guard !activeLayers.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1          // 1x 스케일 (성능)
        format.opaque = false     // 알파 채널 활성화 (투명 배경)

        let renderer = UIGraphicsImageRenderer(size: textureSize, format: format)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            // 투명 배경으로 초기화
            cgCtx.clear(CGRect(origin: .zero, size: textureSize))

            for layer in activeLayers {
                let baseColor = UIColor(layer.selectedColor)
                for uvRect in layer.category.uvRegions {
                    let pixelRect = uvRect.scaled(to: textureSize)
                    drawSoftMakeup(
                        ctx: cgCtx,
                        rect: pixelRect,
                        color: baseColor,
                        intensity: CGFloat(layer.intensity),
                        category: layer.category
                    )
                }
            }
        }
    }

    // 부드러운 그라데이션 효과로 메이크업 렌더링
    // 중심부는 불투명, 가장자리로 갈수록 투명해짐 (자연스러운 블렌딩)
    private static func drawSoftMakeup(
        ctx: CGContext,
        rect: CGRect,
        color: UIColor,
        intensity: CGFloat,
        category: MakeupCategory
    ) {
        let steps = 14 // 그라데이션 단계 수 (높을수록 부드러움)

        // 최대 불투명도: 카테고리별로 다르게 설정
        let maxAlpha: CGFloat
        switch category {
        case .lip:       maxAlpha = 0.88
        case .blush:     maxAlpha = 0.55
        case .eyeShadow: maxAlpha = 0.72
        }

        ctx.saveGState()

        for i in stride(from: steps, through: 1, by: -1) {
            let t = CGFloat(i) / CGFloat(steps)
            // 중심으로 갈수록 알파 증가, 가장자리는 0
            let alpha = t * t * intensity * maxAlpha

            let insetX = rect.width  * (1.0 - t) * 0.5
            let insetY = rect.height * (1.0 - t) * 0.5
            let stepRect = rect.insetBy(dx: insetX, dy: insetY)

            color.withAlphaComponent(alpha).setFill()

            let path: UIBezierPath
            switch category {
            case .lip:
                // 입술: 둥근 직사각형
                path = UIBezierPath(roundedRect: stepRect, cornerRadius: stepRect.height * 0.45)
            case .blush, .eyeShadow:
                // 볼/눈: 타원 (자연스러운 페이드)
                path = UIBezierPath(ovalIn: stepRect)
            }
            path.fill()
        }

        ctx.restoreGState()
    }
}

// MARK: - CGRect UV Helper
extension CGRect {
    /// UV 좌표(0~1)를 텍스처 픽셀 좌표로 변환
    func scaled(to size: CGSize) -> CGRect {
        CGRect(
            x: minX * size.width,
            y: minY * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }
}

// MARK: - Saved Makeup Look (Supabase 연동용)
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

// MARK: - Saved Layer (Codable for Supabase DB)
struct MakeupLayer: Identifiable, Codable {
    let id: UUID
    var category: String   // MakeupCategory.rawValue
    var colorHex: String
    var intensity: Double

    init(from state: MakeupLayerState) {
        self.id = UUID()
        self.category = state.category.rawValue
        self.colorHex = UIColor(state.selectedColor).hexString
        self.intensity = state.intensity
    }
}

// MARK: - UIColor Extensions
extension UIColor {
    /// UIColor → HEX 문자열 (#RRGGBB)
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    /// HEX 문자열 → UIColor
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
