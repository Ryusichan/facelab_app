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
            faceTexture: texture
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
            faceTexture: faceImage
        )
    }
}
