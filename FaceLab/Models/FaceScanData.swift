import SceneKit
import ARKit
import CoreImage

// ============================================================
// MARK: - FaceScanData
// ARKit에서 캡처한 얼굴 mesh + 텍스처 데이터
// 3D 뷰어에서 SCNGeometry로 변환하여 렌더링
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

    /// 얼굴 mesh의 바운딩 박스 중심 (카메라 타겟용)
    var meshCenter: SIMD3<Float> {
        guard !vertices.isEmpty else { return .zero }
        let sum = vertices.reduce(SIMD3<Float>.zero, +)
        return sum / Float(vertices.count)
    }

    /// 얼굴 mesh의 최대 반경 (카메라 거리 계산용)
    var meshRadius: Float {
        let center = meshCenter
        return vertices.map { simd_length($0 - center) }.max() ?? 0.1
    }

    // ──────────────────────────────────────────
    // MARK: SCNGeometry 빌더
    // ──────────────────────────────────────────
    func buildGeometry() -> SCNGeometry {
        let vertexData = vertices.withUnsafeBytes { Data($0) }
        let vertexSource = SCNGeometrySource(
            data: vertexData, semantic: .vertex,
            vectorCount: vertices.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let normalData = normals.withUnsafeBytes { Data($0) }
        let normalSource = SCNGeometrySource(
            data: normalData, semantic: .normal,
            vectorCount: normals.count, usesFloatComponents: true,
            componentsPerVector: 3, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        let uvData = textureCoordinates.withUnsafeBytes { Data($0) }
        let uvSource = SCNGeometrySource(
            data: uvData, semantic: .texcoord,
            vectorCount: textureCoordinates.count, usesFloatComponents: true,
            componentsPerVector: 2, bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0, dataStride: MemoryLayout<SIMD2<Float>>.stride
        )

        let indexData = triangleIndices.withUnsafeBytes { Data($0) }
        let element = SCNGeometryElement(
            data: indexData, primitiveType: .triangles,
            primitiveCount: triangleIndices.count / 3,
            bytesPerIndex: MemoryLayout<Int16>.size
        )

        return SCNGeometry(sources: [vertexSource, normalSource, uvSource], elements: [element])
    }

    // ──────────────────────────────────────────
    // MARK: ARKit 캡처 → FaceScanData
    // ──────────────────────────────────────────
    static func capture(
        faceAnchor: ARFaceAnchor,
        frame: ARFrame,
        viewportSize: CGSize
    ) -> FaceScanData {
        let geo = faceAnchor.geometry

        let verts = geo.vertices.map { $0 }
        let uvs   = geo.textureCoordinates.map { $0 }
        let idxs  = geo.triangleIndices.map { $0 }

        // 삼각형 면 법선을 정점에 누적 → smooth normal 계산
        let norms = computeSmoothNormals(vertices: verts, indices: idxs)

        // 정점별 카메라 색상 샘플링 → UV 래스터라이제이션 → 블러 후처리
        let texture = bakeTexture(
            vertices: verts,
            uvCoordinates: uvs,
            triangleIndices: idxs,
            faceTransform: faceAnchor.transform,
            camera: frame.camera,
            capturedImage: frame.capturedImage,
            viewportSize: viewportSize
        )

        return FaceScanData(
            vertices: verts, normals: norms,
            textureCoordinates: uvs, triangleIndices: idxs,
            faceTexture: texture
        )
    }

    // ──────────────────────────────────────────
    // MARK: Smooth Normal 계산
    // 인접 삼각형의 면 법선을 정점에 누적 후 정규화
    // → 회전 시 자연스러운 음영 (Phong shading에 필수)
    // ──────────────────────────────────────────
    private static func computeSmoothNormals(
        vertices: [SIMD3<Float>],
        indices: [Int16]
    ) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: vertices.count)

        for t in stride(from: 0, to: indices.count, by: 3) {
            let i0 = Int(indices[t])
            let i1 = Int(indices[t + 1])
            let i2 = Int(indices[t + 2])

            let edge1 = vertices[i1] - vertices[i0]
            let edge2 = vertices[i2] - vertices[i0]
            let faceNormal = cross(edge1, edge2) // 면적에 비례한 가중치가 자동 적용

            normals[i0] += faceNormal
            normals[i1] += faceNormal
            normals[i2] += faceNormal
        }

        return normals.map { n in
            let len = simd_length(n)
            return len > 1e-6 ? n / len : SIMD3<Float>(0, 0, 1)
        }
    }

    // ──────────────────────────────────────────
    // MARK: 텍스처 베이킹 (per-pixel 바리센트릭 보간)
    // ARKit UV 좌표는 landscape 카메라 이미지 기준으로 설계됨
    // 이미지 회전 없이 UV → landscape 픽셀 좌표로 직접 샘플링
    // → 왜곡 없는 정확한 얼굴 텍스처 베이킹
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

        let imgW = cgImage.width   // portrait 기준 width (≈960)
        let imgH = cgImage.height  // portrait 기준 height (≈1280)
        guard imgW > 0, imgH > 0,
              let provider = cgImage.dataProvider,
              let pixelData = provider.data,
              let srcBytes = CFDataGetBytePtr(pixelData) else { return nil }
        let srcBPR = cgImage.bytesPerRow
        let srcBPP = max(3, cgImage.bitsPerPixel / 8)

        // ── 정점 3D → 카메라 픽셀 좌표 ──
        // viewportSize에 카메라 이미지 실제 크기를 사용 → 화면 비율 왜곡 없음
        // (이전 방식: 화면 크기 390×844 → 카메라 960×1280 비율 불일치로 세로 압축)
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

        // seam 최소 스무딩 (per-pixel 샘플링 덕에 블러 최소화)
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
    // MARK: 기본 mesh 생성 (사진 선택용)
    // ──────────────────────────────────────────
    static func generateDefaultMesh(faceImage: UIImage?) -> FaceScanData {
        var verts: [SIMD3<Float>] = []
        var uvs:   [SIMD2<Float>] = []
        var idxs:  [Int16] = []

        let rows = 64
        let cols = 64

        for row in 0...rows {
            for col in 0...cols {
                let u = Float(col) / Float(cols)
                let v = Float(row) / Float(rows)

                // 타원체 전면부 (코 높이 돌출 포함)
                let theta = (u - 0.5) * .pi * 0.8
                let phi   = (v - 0.5) * .pi * 1.0

                // 기본 구면
                var x = sin(theta) * cos(phi) * 0.07
                var y = -sin(phi) * 0.09
                var z = (cos(theta) * cos(phi) - 1.0) * 0.035

                // 코 돌출: UV 중심부에 가우시안 범프
                let du = u - 0.5, dv = v - 0.45
                let noseBump = 0.012 * exp(-(du*du)/(2*0.015) - (dv*dv)/(2*0.02))
                z += Float(noseBump)

                // 눈 오목: 좌우 눈 위치에 오목한 범프
                let leftEye  = 0.004 * exp(-pow(u-0.35, 2)/0.008 - pow(v-0.38, 2)/0.005)
                let rightEye = 0.004 * exp(-pow(u-0.65, 2)/0.008 - pow(v-0.38, 2)/0.005)
                z -= Float(leftEye + rightEye)

                verts.append(SIMD3(x, y, z))
                uvs.append(SIMD2(u, v))
            }
        }

        for row in 0..<rows {
            for col in 0..<cols {
                let tl = Int16(row * (cols + 1) + col)
                let tr = tl + 1
                let bl = tl + Int16(cols + 1)
                let br = bl + 1
                idxs.append(contentsOf: [tl, bl, tr, tr, bl, br])
            }
        }

        let norms = computeSmoothNormals(vertices: verts, indices: idxs)

        return FaceScanData(
            vertices: verts, normals: norms,
            textureCoordinates: uvs, triangleIndices: idxs,
            faceTexture: faceImage
        )
    }
}
