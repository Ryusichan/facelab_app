import SceneKit
import ARKit
import CoreImage

// ============================================================
// MARK: - FaceScanData
//
// 파이프라인:
//   1. ARKit ARFaceGeometry → 실제 얼굴 윤곽 정점/법선/UV/인덱스 직접 사용
//   2. 정점 3D 위치 → 카메라 이미지 투영 → 텍스처 베이킹
//   결과: ARKit 측정 기반 실제 얼굴 형태 + 실제 얼굴 텍스처
//
// ARKit face geometry 특성:
//   - ~1220 정점, ~2304 삼각형
//   - 눈/입 영역에 구멍 존재 (ARFaceGeometry 구조적 특성)
//   - 코 높이, 얼굴 윤곽, 볼 폭 등 실제 얼굴 형태를 정확히 반영
// ============================================================
struct FaceScanData: Equatable {
    static func == (lhs: FaceScanData, rhs: FaceScanData) -> Bool {
        lhs.vertices == rhs.vertices
    }

    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let textureCoordinates: [SIMD2<Float>]
    let triangleIndices: [Int16]
    let faceTexture: UIImage?

    // 눈 데이터 (face mesh 경계 에지 분석으로 산출 — face-local 좌표계)
    // - leftEyePosition / rightEyePosition: 눈 구멍 테두리 정점 무게중심 (안구 배치 위치)
    // - leftEyeHoleRadius / rightEyeHoleRadius: 눈 구멍 반경 × 1.65 (안구 전체 반경)
    // - leftIrisRadius / rightIrisRadius: 카메라 이미지 픽셀 스캔으로 측정한 실제 홍채 반경 (미터)
    // - leftIrisColor / rightIrisColor: 촬영 시 카메라에서 샘플링한 홍채 색상
    let leftEyePosition:    SIMD3<Float>?
    let rightEyePosition:   SIMD3<Float>?
    let leftEyeHoleRadius:  Float
    let rightEyeHoleRadius: Float
    let leftIrisRadius:     Float
    let rightIrisRadius:    Float
    let leftIrisColor:  UIColor
    let rightIrisColor: UIColor

    // ──────────────────────────────────────────
    // MARK: 얼굴 메시 통계 (카메라 배치용)
    // ──────────────────────────────────────────
    var meshCenter: SIMD3<Float> {
        guard !vertices.isEmpty else { return .zero }
        return vertices.reduce(.zero, +) / Float(vertices.count)
    }

    var meshRadius: Float {
        let c = meshCenter
        return vertices.map { simd_length($0 - c) }.max() ?? 0.1
    }

    // ──────────────────────────────────────────
    // MARK: SCNGeometry 빌더
    // ──────────────────────────────────────────
    func buildGeometry() -> SCNGeometry {
        return Self.makeGeometry(verts: vertices, norms: normals,
                                 uvs: textureCoordinates, idxs: triangleIndices)
    }

    // ──────────────────────────────────────────
    // MARK: SCNGeometry 생성 헬퍼
    // ──────────────────────────────────────────
    private static func makeGeometry(
        verts: [SIMD3<Float>], norms: [SIMD3<Float>],
        uvs: [SIMD2<Float>], idxs: [Int16]
    ) -> SCNGeometry {
        let vSrc = SCNGeometrySource(data: verts.withUnsafeBytes { Data($0) },
            semantic: .vertex, vectorCount: verts.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride)
        let nSrc = SCNGeometrySource(data: norms.withUnsafeBytes { Data($0) },
            semantic: .normal, vectorCount: norms.count,
            usesFloatComponents: true, componentsPerVector: 3,
            bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride)
        let uvSrc = SCNGeometrySource(data: uvs.withUnsafeBytes { Data($0) },
            semantic: .texcoord, vectorCount: uvs.count,
            usesFloatComponents: true, componentsPerVector: 2,
            bytesPerComponent: 4, dataOffset: 0, dataStride: MemoryLayout<SIMD2<Float>>.stride)
        let elem = SCNGeometryElement(data: idxs.withUnsafeBytes { Data($0) },
            primitiveType: .triangles, primitiveCount: idxs.count / 3, bytesPerIndex: 2)
        return SCNGeometry(sources: [vSrc, nSrc, uvSrc], elements: [elem])
    }

    // ──────────────────────────────────────────
    // MARK: ARKit 캡처 → FaceScanData
    //
    // ARKit ARFaceGeometry를 직접 사용:
    //   - 실제 얼굴 윤곽, 코 높이, 볼 폭 등 측정값 그대로 반영
    //   - 캐노니컬 메시 변환 없음 → 왜곡 없는 실제 얼굴 형태
    // ──────────────────────────────────────────
    static func capture(
        faceAnchor: ARFaceAnchor,
        frame: ARFrame,
        viewportSize: CGSize
    ) -> FaceScanData {
        let geom = faceAnchor.geometry

        let vertices = geom.vertices.map { SIMD3<Float>($0) }
        let uvs      = geom.textureCoordinates.map { SIMD2<Float>($0) }
        let indices  = geom.triangleIndices.map { $0 }
        let normals  = Self.smoothNormals(verts: vertices, idxs: indices)

        // ── 눈 구멍 중심/크기: face mesh 경계 에지 분석 ──
        // ARKit eye transform의 좌표계가 face mesh 정점 좌표계와 다를 수 있으므로
        // 순수하게 face mesh의 구멍(hole) 테두리 정점만으로 눈 위치를 산출
        let eyeHoles = Self.findEyeHoleCentersFromMesh(vertices: vertices, indices: indices)

        // ── 홍채 색상 샘플링 ──
        // 안구 중심(world space)을 카메라 이미지에 투영 → 홍채 영역 픽셀 평균
        let leftEyeWorld  = SIMD3<Float>(faceAnchor.leftEyeTransform.columns.3.x,
                                         faceAnchor.leftEyeTransform.columns.3.y,
                                         faceAnchor.leftEyeTransform.columns.3.z)
        let rightEyeWorld = SIMD3<Float>(faceAnchor.rightEyeTransform.columns.3.x,
                                         faceAnchor.rightEyeTransform.columns.3.y,
                                         faceAnchor.rightEyeTransform.columns.3.z)
        let leftIris  = sampleIrisColor(eyeWorldPos: leftEyeWorld,
                                        camera: frame.camera,
                                        capturedImage: frame.capturedImage)
        let rightIris = sampleIrisColor(eyeWorldPos: rightEyeWorld,
                                        camera: frame.camera,
                                        capturedImage: frame.capturedImage)

        // ── 실제 홍채 반경 측정 ──
        // 카메라 이미지에서 홍채 경계(limbal ring)를 픽셀 스캔 → 미터 환산
        let fallbackIrisR = eyeHoles.leftRadius * (1.0 / 1.65) * 0.92
        let leftIrisR  = measureIrisRadius(eyeWorldPos: leftEyeWorld,
                                           camera: frame.camera,
                                           capturedImage: frame.capturedImage,
                                           fallback: fallbackIrisR)
        let rightIrisR = measureIrisRadius(eyeWorldPos: rightEyeWorld,
                                           camera: frame.camera,
                                           capturedImage: frame.capturedImage,
                                           fallback: fallbackIrisR)

        let texture = bakeTexture(
            vertices: vertices,
            uvCoordinates: uvs,
            triangleIndices: indices,
            faceTransform: faceAnchor.transform,
            camera: frame.camera,
            capturedImage: frame.capturedImage,
            viewportSize: viewportSize
        )

        return FaceScanData(
            vertices: vertices,
            normals: normals,
            textureCoordinates: uvs,
            triangleIndices: indices,
            faceTexture: texture,
            leftEyePosition:    eyeHoles.leftPos,
            rightEyePosition:   eyeHoles.rightPos,
            leftEyeHoleRadius:  eyeHoles.leftRadius,
            rightEyeHoleRadius: eyeHoles.rightRadius,
            leftIrisRadius:     leftIrisR,
            rightIrisRadius:    rightIrisR,
            leftIrisColor:      leftIris,
            rightIrisColor:     rightIris
        )
    }

    // ──────────────────────────────────────────
    // MARK: 텍스처 베이킹 (per-pixel 바리센트릭 보간)
    //
    // 삼각형별로 UV 공간을 래스터라이즈하여
    // 각 텍셀이 대응하는 카메라 픽셀을 샘플링
    // ──────────────────────────────────────────
    private static func bakeTexture(
        vertices: [SIMD3<Float>],
        uvCoordinates: [SIMD2<Float>],
        triangleIndices: [Int16],
        faceTransform: simd_float4x4,
        camera: ARCamera,
        capturedImage: CVPixelBuffer,
        viewportSize: CGSize
    ) -> UIImage? {
        let texSize = 1024

        // ── 카메라 이미지 → portrait 방향으로 회전 ──
        let ciImage = CIImage(cvPixelBuffer: capturedImage).oriented(.right)
        let ciCtx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ciCtx.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let imgW = cgImage.width
        let imgH = cgImage.height
        guard imgW > 0, imgH > 0,
              let provider = cgImage.dataProvider,
              let pixelData = provider.data,
              let srcBytes = CFDataGetBytePtr(pixelData) else { return nil }
        let srcBPR = cgImage.bytesPerRow
        let srcBPP = max(3, cgImage.bitsPerPixel / 8)

        // ── 정점 3D → 카메라 픽셀 좌표 ──
        let cameraViewport = CGSize(width: Double(imgW), height: Double(imgH))
        let camPoints: [SIMD2<Float>] = vertices.map { v in
            let w = faceTransform * SIMD4<Float>(v.x, v.y, v.z, 1)
            let sp = camera.projectPoint(SIMD3(w.x, w.y, w.z),
                                         orientation: .portrait,
                                         viewportSize: cameraViewport)
            return SIMD2<Float>(
                Float(max(0.0, min(Double(imgW - 1), sp.x))),
                Float(max(0.0, min(Double(imgH - 1), sp.y)))
            )
        }

        // ── 출력 버퍼 (RGBA, 4 bytes/pixel) ──
        let dstBPP = 4
        let dstBPR = texSize * dstBPP
        var dstBuf = [UInt8](repeating: 0, count: texSize * dstBPR)
        let sz = Float(texSize)

        // ── 삼각형별 per-pixel 래스터라이제이션 ──
        for t in stride(from: 0, to: triangleIndices.count, by: 3) {
            let i0 = Int(triangleIndices[t])
            let i1 = Int(triangleIndices[t + 1])
            let i2 = Int(triangleIndices[t + 2])

            let u0 = SIMD2<Float>(uvCoordinates[i0].x * sz, uvCoordinates[i0].y * sz)
            let u1 = SIMD2<Float>(uvCoordinates[i1].x * sz, uvCoordinates[i1].y * sz)
            let u2 = SIMD2<Float>(uvCoordinates[i2].x * sz, uvCoordinates[i2].y * sz)

            let c0 = camPoints[i0], c1 = camPoints[i1], c2 = camPoints[i2]

            let minX = max(0, Int((min(u0.x, u1.x, u2.x)).rounded(.down)))
            let maxX = min(texSize - 1, Int((max(u0.x, u1.x, u2.x)).rounded(.up)))
            let minY = max(0, Int((min(u0.y, u1.y, u2.y)).rounded(.down)))
            let maxY = min(texSize - 1, Int((max(u0.y, u1.y, u2.y)).rounded(.up)))
            guard maxX >= minX, maxY >= minY else { continue }

            let denom = (u1.y - u2.y) * (u0.x - u2.x) + (u2.x - u1.x) * (u0.y - u2.y)
            guard abs(denom) > 0.01 else { continue }
            let inv = 1.0 / denom

            for py in minY...maxY {
                let fy = Float(py) + 0.5
                for px in minX...maxX {
                    let fx = Float(px) + 0.5

                    let w0 = ((u1.y - u2.y) * (fx - u2.x) + (u2.x - u1.x) * (fy - u2.y)) * inv
                    let w1 = ((u2.y - u0.y) * (fx - u2.x) + (u0.x - u2.x) * (fy - u2.y)) * inv
                    let w2 = 1.0 - w0 - w1
                    guard w0 >= -0.002, w1 >= -0.002, w2 >= -0.002 else { continue }

                    let camX = min(imgW - 1, max(0, Int((w0 * c0.x + w1 * c1.x + w2 * c2.x).rounded())))
                    let camY = min(imgH - 1, max(0, Int((w0 * c0.y + w1 * c1.y + w2 * c2.y).rounded())))

                    let srcOff = camY * srcBPR + camX * srcBPP
                    let dstOff = py * dstBPR + px * dstBPP
                    dstBuf[dstOff]     = srcBytes[srcOff]
                    dstBuf[dstOff + 1] = srcBytes[srcOff + 1]
                    dstBuf[dstOff + 2] = srcBytes[srcOff + 2]
                    dstBuf[dstOff + 3] = 255
                }
            }
        }

        // ── 픽셀 버퍼 → CGImage ──
        guard let ctx = CGContext(
            data: &dstBuf,
            width: texSize, height: texSize,
            bitsPerComponent: 8,
            bytesPerRow: dstBPR,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let outCG = ctx.makeImage() else { return nil }

        let outCI = CIImage(cgImage: outCG)
        let blurred = outCI.clampedToExtent()
            .applyingGaussianBlur(sigma: 0.6)
            .cropped(to: outCI.extent)
        guard let finalCG = ciCtx.createCGImage(blurred, from: blurred.extent) else {
            return UIImage(cgImage: outCG)
        }
        return UIImage(cgImage: finalCG)
    }

    // ──────────────────────────────────────────
    // MARK: 홍채 색상 샘플링
    //
    // 안구 중심 world 좌표를 카메라 이미지에 투영
    // 중심(동공) 제외, 홍채 영역(안쪽~바깥쪽 링)의 픽셀 색상 평균
    // ──────────────────────────────────────────
    private static func sampleIrisColor(
        eyeWorldPos: SIMD3<Float>,
        camera: ARCamera,
        capturedImage: CVPixelBuffer
    ) -> UIColor {
        let defaultBrown = UIColor(red: 0.40, green: 0.25, blue: 0.12, alpha: 1)

        let ciImage = CIImage(cvPixelBuffer: capturedImage).oriented(.right)
        let ciCtx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ciCtx.createCGImage(ciImage, from: ciImage.extent) else {
            return defaultBrown
        }

        let imgW = cgImage.width, imgH = cgImage.height
        let viewport = CGSize(width: Double(imgW), height: Double(imgH))
        let sp = camera.projectPoint(eyeWorldPos, orientation: .portrait, viewportSize: viewport)
        let cx = Int(sp.x), cy = Int(sp.y)

        guard cx > 10, cy > 10, cx < imgW - 10, cy < imgH - 10,
              let provider = cgImage.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else { return defaultBrown }

        let bpp = max(3, cgImage.bitsPerPixel / 8)
        let bpr = cgImage.bytesPerRow

        // 홍채 링: 동공(innerR) 바깥 ~ 홍채 외곽(outerR)
        // 960px 이미지 기준 innerR≈4px, outerR≈12px
        let innerR = max(3, imgW / 240)
        let outerR = max(8, imgW / 80)

        var rSum: Float = 0, gSum: Float = 0, bSum: Float = 0
        var count = 0
        for dy in -outerR...outerR {
            for dx in -outerR...outerR {
                let r2 = dx*dx + dy*dy
                guard r2 >= innerR*innerR && r2 <= outerR*outerR else { continue }
                let px = cx + dx, py = cy + dy
                guard px >= 0 && px < imgW && py >= 0 && py < imgH else { continue }
                let off = py * bpr + px * bpp
                rSum += Float(bytes[off])
                gSum += Float(bytes[off + 1])
                bSum += Float(bytes[off + 2])
                count += 1
            }
        }

        guard count > 0 else { return defaultBrown }
        return UIColor(
            red:   CGFloat(rSum / Float(count)) / 255,
            green: CGFloat(gSum / Float(count)) / 255,
            blue:  CGFloat(bSum / Float(count)) / 255,
            alpha: 1
        )
    }

    // ──────────────────────────────────────────
    // MARK: 홍채 반경 측정 (카메라 이미지 픽셀 스캔)
    //
    // 알고리즘:
    //   1. 안구 중심을 portrait 이미지에 투영
    //   2. 8방향 ray를 쏴서 어두운 홍채 → 밝은 공막 경계를 탐색
    //   3. 평균 픽셀 반경 산출
    //   4. 1mm 오프셋 두 점을 투영해 픽셀/미터 스케일 계산 → 미터 환산
    //   5. 실패 시 fallback 반환 (face mesh holeR 기반)
    // ──────────────────────────────────────────
    private static func measureIrisRadius(
        eyeWorldPos: SIMD3<Float>,
        camera: ARCamera,
        capturedImage: CVPixelBuffer,
        fallback: Float
    ) -> Float {
        let ciImage = CIImage(cvPixelBuffer: capturedImage).oriented(.right)
        let ciCtx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ciCtx.createCGImage(ciImage, from: ciImage.extent) else { return fallback }

        let imgW = cgImage.width, imgH = cgImage.height
        guard imgW > 0, imgH > 0 else { return fallback }
        let viewport = CGSize(width: Double(imgW), height: Double(imgH))

        let sp = camera.projectPoint(eyeWorldPos, orientation: .portrait, viewportSize: viewport)
        let cx = Int(sp.x), cy = Int(sp.y)
        guard cx > 40, cy > 40, cx < imgW - 40, cy < imgH - 40 else { return fallback }

        guard let provider = cgImage.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else { return fallback }
        let bpp = max(3, cgImage.bitsPerPixel / 8)
        let bpr = cgImage.bytesPerRow

        // 8방향 ray — 홍채(어두움)에서 공막(밝음)으로 전환되는 픽셀 위치 탐색
        var irisPixelRadii: [Float] = []
        for i in 0..<8 {
            let angle = Float(i) * Float.pi / 4
            for r in 4..<120 {
                let px = cx + Int(Float(r) * cos(angle))
                let py = cy + Int(Float(r) * sin(angle))
                guard px >= 0, px < imgW, py >= 0, py < imgH else { break }
                let off = py * bpr + px * bpp
                let brightness = (Float(bytes[off]) + Float(bytes[off+1]) + Float(bytes[off+2])) / 3.0
                // 150 이상 = 공막 또는 피부 (밝음)
                if brightness > 150 {
                    irisPixelRadii.append(Float(r))
                    break
                }
            }
        }
        // 최소 4방향 탐지 성공해야 신뢰 가능
        guard irisPixelRadii.count >= 4 else { return fallback }

        // 이상치 제거: 중앙값 ±40% 범위만 사용
        let sorted = irisPixelRadii.sorted()
        let median = sorted[sorted.count / 2]
        let filtered = irisPixelRadii.filter { abs($0 - median) < median * 0.4 }
        guard !filtered.isEmpty else { return fallback }
        let avgPixelR = filtered.reduce(0, +) / Float(filtered.count)

        // 픽셀 → 미터 변환: 1mm 오프셋 두 점을 투영해 픽셀/미터 스케일 산출
        let sp0 = camera.projectPoint(eyeWorldPos,
                                      orientation: .portrait, viewportSize: viewport)
        let sp1 = camera.projectPoint(eyeWorldPos + SIMD3<Float>(0.001, 0, 0),
                                      orientation: .portrait, viewportSize: viewport)
        let pxPerMm = Float(hypot(sp1.x - sp0.x, sp1.y - sp0.y))
        guard pxPerMm > 0.5 else { return fallback }

        let irisMeters = (avgPixelR / pxPerMm) * 0.001  // mm → m
        // 인체 홍채 반경 범위: 4.5 ~ 8.5mm 로 클램프
        return max(0.0045, min(0.0085, irisMeters))
    }

    // ──────────────────────────────────────────
    // MARK: 스무스 법선 계산
    // ──────────────────────────────────────────
    private static func smoothNormals(verts: [SIMD3<Float>], idxs: [Int16]) -> [SIMD3<Float>] {
        var norms = [SIMD3<Float>](repeating: .zero, count: verts.count)
        for t in stride(from: 0, to: idxs.count, by: 3) {
            let i0 = Int(idxs[t]), i1 = Int(idxs[t+1]), i2 = Int(idxs[t+2])
            let fn = cross(verts[i1] - verts[i0], verts[i2] - verts[i0])
            norms[i0] += fn; norms[i1] += fn; norms[i2] += fn
        }
        return norms.map { n in
            let l = simd_length(n); return l > 1e-6 ? n / l : SIMD3(0, 0, 1)
        }
    }

    // ──────────────────────────────────────────
    // MARK: 기본 메시 (ARKit 없는 경우)
    // ──────────────────────────────────────────
    static func generateDefaultMesh(faceImage: UIImage?) -> FaceScanData {
        let canonical = CanonicalFaceMesh.generate()
        return FaceScanData(
            vertices: canonical.vertices,
            normals: canonical.normals,
            textureCoordinates: canonical.uvCoordinates,
            triangleIndices: canonical.triangleIndices,
            faceTexture: faceImage,
            leftEyePosition:    nil,
            rightEyePosition:   nil,
            leftEyeHoleRadius:  0.011,
            rightEyeHoleRadius: 0.011,
            leftIrisRadius:     0.006,
            rightIrisRadius:    0.006,
            leftIrisColor:  UIColor(red: 0.40, green: 0.25, blue: 0.12, alpha: 1),
            rightIrisColor: UIColor(red: 0.40, green: 0.25, blue: 0.12, alpha: 1)
        )
    }

    // ──────────────────────────────────────────
    // MARK: 눈 구멍 중심/크기 찾기 (연결 컴포넌트 분석)
    //
    // ARKit face mesh 경계에는 3종류가 있음:
    //   1. 얼굴 외곽선 (가장 큰 연결 컴포넌트)
    //   2. 눈 구멍 × 2 (소규모 컴포넌트, Y 높음)
    //   3. 입 구멍 (소규모 컴포넌트, Y 낮음)
    //
    // 연결 컴포넌트 BFS로 분리 → 최대 컴포넌트(외곽선) 제거
    // → Y 기준 상위 2개 = 눈 구멍 (좌표계 오염 없이 정확한 위치)
    // ──────────────────────────────────────────
    private static func findEyeHoleCentersFromMesh(
        vertices: [SIMD3<Float>],
        indices: [Int16]
    ) -> (leftPos: SIMD3<Float>?, leftRadius: Float,
          rightPos: SIMD3<Float>?, rightRadius: Float) {

        struct Edge: Hashable {
            let a: Int, b: Int
            init(_ u: Int, _ v: Int) { a = min(u, v); b = max(u, v) }
        }

        // 1. 경계 에지 수집 (삼각형 1개에만 속한 에지)
        var edgeCount = [Edge: Int]()
        for t in stride(from: 0, to: indices.count, by: 3) {
            let i0 = Int(indices[t]), i1 = Int(indices[t+1]), i2 = Int(indices[t+2])
            edgeCount[Edge(i0, i1), default: 0] += 1
            edgeCount[Edge(i1, i2), default: 0] += 1
            edgeCount[Edge(i2, i0), default: 0] += 1
        }

        // 2. 경계 정점 인접 그래프 구성
        var adj = [Int: [Int]]()
        for (edge, count) in edgeCount where count == 1 {
            adj[edge.a, default: []].append(edge.b)
            adj[edge.b, default: []].append(edge.a)
        }
        guard !adj.isEmpty else { return (nil, 0.011, nil, 0.011) }

        // 3. BFS로 연결 컴포넌트 분리
        var visited = Set<Int>()
        var components = [[Int]]()
        for start in adj.keys.sorted() {
            guard !visited.contains(start) else { continue }
            var component = [Int]()
            var queue = [start]
            while !queue.isEmpty {
                let v = queue.removeFirst()
                guard !visited.contains(v) else { continue }
                visited.insert(v)
                component.append(v)
                for nb in adj[v, default: []] where !visited.contains(nb) {
                    queue.append(nb)
                }
            }
            components.append(component)
        }

        // 4. 가장 큰 컴포넌트 = 얼굴 외곽 경계선 → 제외
        guard let maxSize = components.map({ $0.count }).max() else {
            return (nil, 0.011, nil, 0.011)
        }
        let innerHoles = components.filter { $0.count < maxSize }
        guard innerHoles.count >= 2 else { return (nil, 0.011, nil, 0.011) }

        // 5. 평균 Y 기준 내림차순 정렬 → 상위 2개 = 눈 구멍 (입은 Y가 낮아 제외)
        let sortedHoles = innerHoles.map { comp -> (avgY: Float, verts: [SIMD3<Float>]) in
            let verts = comp.map { vertices[$0] }
            let avgY = verts.map { $0.y }.reduce(0, +) / Float(verts.count)
            return (avgY, verts)
        }.sorted { $0.avgY > $1.avgY }

        let hole1Verts = sortedHoles[0].verts
        let hole2Verts = sortedHoles[1].verts

        // 6. X 기준 좌/우 눈 분리 (더 큰 X = left, 더 작은 X = right)
        let cx1 = hole1Verts.map { $0.x }.reduce(0, +) / Float(hole1Verts.count)
        let cx2 = hole2Verts.map { $0.x }.reduce(0, +) / Float(hole2Verts.count)
        let leftVerts  = cx1 >= cx2 ? hole1Verts : hole2Verts
        let rightVerts = cx1 >= cx2 ? hole2Verts : hole1Verts

        // 7. 눈 구멍 중심·반경 계산
        func holeInfo(_ verts: [SIMD3<Float>]) -> (SIMD3<Float>, Float)? {
            guard !verts.isEmpty else { return nil }
            let center = verts.reduce(.zero, +) / Float(verts.count)
            // 구멍 테두리 정점까지의 평균 거리 = 눈 구멍 반경
            let avgDist = verts.map { simd_length($0 - center) }.reduce(0, +) / Float(verts.count)
            let holeR = max(0.008, avgDist)
            // 안구 반경 = 구멍 반경 × 1.2 (기본 20% 증가)
            let eyeR = holeR * 1.65
            // 안구 중심 Z:
            //   d > eyeR 이면 구면 전면이 face 표면 뒤에 위치 → 돌출 없음
            //   d = eyeR * 1.3 → 전면이 림 기준 0.3*holeR 안쪽에 위치
            //   face mesh 구멍(hole)을 통해 단면 95%가 보임 (실제 눈 소켓 구조)
            let d = eyeR * 1.1
            let eyeCenter = SIMD3<Float>(center.x, center.y, center.z - d)
            return (eyeCenter, eyeR)
        }

        let left  = holeInfo(leftVerts)
        let right = holeInfo(rightVerts)
        return (left?.0, left?.1 ?? 0.011, right?.0, right?.1 ?? 0.011)
    }
}
