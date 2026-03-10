import SceneKit
import ARKit
import CoreImage

// ============================================================
// MARK: - FaceScanData
//
// 파이프라인:
//   1. ARKit capture → 캐노니컬 메시 생성 (CanonicalFaceMesh)
//   2. ARKit 정점 KNN 보간으로 캐노니컬 메시를 사용자 얼굴에 피팅
//   3. 피팅된 정점 + 캐노니컬 UV로 카메라 이미지 텍스처 베이킹
//   4. 결과: 구멍 없는 완전한 위상의 3D 얼굴 모델 + 실제 얼굴 텍스처
//
// 이전 방식 (ARKit hollow mask + eye fill):
//   → ARKit mask는 눈/입에 구멍이 있어 구조적으로 메이크업 앱에 부적합
//   → 어떤 fill 방식(flat fan / 구면 보간)도 실제 눈꺼풀 위상을 생성할 수 없음
//
// 현재 방식 (캐노니컬 full-topology):
//   → 캐노니컬 메시는 눈 소켓 포함, 구멍 없음
//   → ARKit 데이터로 사용자 얼굴 형태에 맞게 변형
//   → 카메라 텍스처가 눈 영역 실제 모습(홍채/동공 포함)을 표현
// ============================================================
struct FaceScanData: Equatable {
    static func == (lhs: FaceScanData, rhs: FaceScanData) -> Bool {
        lhs.vertices == rhs.vertices
    }

    // 캐노니컬 메시 기반 정점/법선/UV/인덱스 (ARKit KNN 피팅 후)
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let textureCoordinates: [SIMD2<Float>]
    let triangleIndices: [Int16]
    let faceTexture: UIImage?

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
    // 캐노니컬 메시는 이미 완전한 위상 → 추가 eye fill 불필요
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
    // MARK: ARKit 캡처 → FaceScanData (캐노니컬 파이프라인)
    //
    // 1. CanonicalFaceMesh 생성 (구멍 없는 전체 위상)
    // 2. ARKit 정점으로 캐노니컬 메시 KNN 피팅
    // 3. 피팅된 메시 + 캐노니컬 UV로 텍스처 베이킹
    // ──────────────────────────────────────────
    static func capture(
        faceAnchor: ARFaceAnchor,
        frame: ARFrame,
        viewportSize: CGSize
    ) -> FaceScanData {
        let arkitVerts = faceAnchor.geometry.vertices.map { $0 }

        // 1. 캐노니컬 메시 생성
        let canonical = CanonicalFaceMesh.generate()

        // 2. ARKit 정점으로 피팅 (KNN 보간, 눈 소켓 형태 보존)
        let fitted = canonical.fitted(to: arkitVerts)

        // 3. 피팅된 정점 + 캐노니컬 UV로 카메라 텍스처 베이킹
        //    캐노니컬 UV는 [0,1]×[0,1] 그리드 → 눈 영역도 커버
        //    → 베이킹 결과물에 실제 홍채/동공이 정확한 위치에 표현됨
        let texture = bakeTexture(
            vertices: fitted.vertices,
            uvCoordinates: fitted.uvCoordinates,
            triangleIndices: fitted.triangleIndices,
            faceTransform: faceAnchor.transform,
            camera: frame.camera,
            capturedImage: frame.capturedImage,
            viewportSize: viewportSize
        )

        return FaceScanData(
            vertices: fitted.vertices,
            normals: fitted.normals,
            textureCoordinates: fitted.uvCoordinates,
            triangleIndices: fitted.triangleIndices,
            faceTexture: texture
        )
    }

    // ──────────────────────────────────────────
    // MARK: 텍스처 베이킹 (per-pixel 바리센트릭 보간)
    //
    // 삼각형별로 UV 공간(텍스처 아틀라스)을 래스터라이즈하여
    // 각 텍셀이 대응하는 카메라 픽셀을 샘플링
    //
    // 캐노니컬 UV [0,1]×[0,1]을 사용하므로:
    //   - 텍스처 아틀라스 전체가 고르게 사용됨
    //   - 눈 소켓 정점 → 실제 눈 픽셀 샘플링 → 텍스처에 실제 눈 표현
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

        let imgW = cgImage.width   // portrait 기준 ≈960
        let imgH = cgImage.height  // portrait 기준 ≈1280
        guard imgW > 0, imgH > 0,
              let provider = cgImage.dataProvider,
              let pixelData = provider.data,
              let srcBytes = CFDataGetBytePtr(pixelData) else { return nil }
        let srcBPR = cgImage.bytesPerRow
        let srcBPP = max(3, cgImage.bitsPerPixel / 8)

        // ── 정점 3D → 카메라 픽셀 좌표 ──
        // viewportSize = 카메라 이미지 실제 크기 → 화면 비율 왜곡 없음
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

            // 텍스처 공간 UV 좌표 (픽셀 단위)
            let u0 = SIMD2<Float>(uvCoordinates[i0].x * sz, uvCoordinates[i0].y * sz)
            let u1 = SIMD2<Float>(uvCoordinates[i1].x * sz, uvCoordinates[i1].y * sz)
            let u2 = SIMD2<Float>(uvCoordinates[i2].x * sz, uvCoordinates[i2].y * sz)

            // 대응 카메라 픽셀 좌표
            let c0 = camPoints[i0], c1 = camPoints[i1], c2 = camPoints[i2]

            // 바운딩 박스
            let minX = max(0, Int((min(u0.x, u1.x, u2.x)).rounded(.down)))
            let maxX = min(texSize - 1, Int((max(u0.x, u1.x, u2.x)).rounded(.up)))
            let minY = max(0, Int((min(u0.y, u1.y, u2.y)).rounded(.down)))
            let maxY = min(texSize - 1, Int((max(u0.y, u1.y, u2.y)).rounded(.up)))
            guard maxX >= minX, maxY >= minY else { continue }

            // 바리센트릭 계수 (분모)
            let denom = (u1.y - u2.y) * (u0.x - u2.x) + (u2.x - u1.x) * (u0.y - u2.y)
            guard abs(denom) > 0.01 else { continue }
            let inv = 1.0 / denom

            for py in minY...maxY {
                let fy = Float(py) + 0.5
                for px in minX...maxX {
                    let fx = Float(px) + 0.5

                    // 바리센트릭 좌표 계산
                    let w0 = ((u1.y - u2.y) * (fx - u2.x) + (u2.x - u1.x) * (fy - u2.y)) * inv
                    let w1 = ((u2.y - u0.y) * (fx - u2.x) + (u0.x - u2.x) * (fy - u2.y)) * inv
                    let w2 = 1.0 - w0 - w1
                    guard w0 >= -0.002, w1 >= -0.002, w2 >= -0.002 else { continue }

                    // 카메라 이미지 좌표 보간
                    let camX = min(imgW - 1, max(0, Int((w0 * c0.x + w1 * c1.x + w2 * c2.x).rounded())))
                    let camY = min(imgH - 1, max(0, Int((w0 * c0.y + w1 * c1.y + w2 * c2.y).rounded())))

                    // 카메라 픽셀 샘플링
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

        // 경계 seam 최소화 스무딩
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
    // MARK: 기본 메시 (사진 선택 / ARKit 없는 경우)
    // 캐노니컬 메시의 변형 없는 기본 형태 사용
    // ──────────────────────────────────────────
    static func generateDefaultMesh(faceImage: UIImage?) -> FaceScanData {
        let canonical = CanonicalFaceMesh.generate()
        return FaceScanData(
            vertices: canonical.vertices,
            normals: canonical.normals,
            textureCoordinates: canonical.uvCoordinates,
            triangleIndices: canonical.triangleIndices,
            faceTexture: faceImage
        )
    }
}
