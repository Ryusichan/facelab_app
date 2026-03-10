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
    // MARK: 텍스처 베이킹 (개선)
    // 1단계: 정점별 카메라 색상 샘플링
    // 2단계: 삼각형별 3-정점 평균색 래스터라이제이션
    // 3단계: CIGaussianBlur로 seam 스무딩
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
        let texSize = 1024 // 고해상도 (512 → 1024)

        // ── 카메라 이미지 → portrait CGImage ──
        let ciImage = CIImage(cvPixelBuffer: capturedImage).oriented(.right)
        let ciCtx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = ciCtx.createCGImage(ciImage, from: ciImage.extent) else { return nil }

        let imgW = cgImage.width
        let imgH = cgImage.height
        guard let provider = cgImage.dataProvider,
              let pixelData = provider.data,
              let bytes = CFDataGetBytePtr(pixelData) else { return nil }
        let bytesPerRow = cgImage.bytesPerRow
        let bpp = cgImage.bitsPerPixel / 8

        // ── 정점별 3D → 스크린 좌표 프로젝션 ──
        let screenPoints: [CGPoint] = vertices.map { v in
            let world4 = faceTransform * SIMD4<Float>(v.x, v.y, v.z, 1)
            return camera.projectPoint(
                SIMD3(world4.x, world4.y, world4.z),
                orientation: .portrait, viewportSize: viewportSize
            )
        }

        // ── 정점별 카메라 색상 샘플링 ──
        struct RGB { var r: CGFloat; var g: CGFloat; var b: CGFloat }
        let vertexColors: [RGB] = screenPoints.map { sp in
            let px = max(0, min(imgW - 1, Int(sp.x / viewportSize.width * CGFloat(imgW))))
            let py = max(0, min(imgH - 1, Int(sp.y / viewportSize.height * CGFloat(imgH))))
            let offset = py * bytesPerRow + px * bpp
            return RGB(
                r: CGFloat(bytes[offset]) / 255,
                g: CGFloat(bytes[offset + 1]) / 255,
                b: CGFloat(bytes[offset + 2]) / 255
            )
        }

        // ── 삼각형별 래스터라이제이션 (3정점 평균색) ──
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let sz = CGFloat(texSize)

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: texSize, height: texSize), format: format
        )

        let rawTexture = renderer.image { ctx in
            for t in stride(from: 0, to: triangleIndices.count, by: 3) {
                let i0 = Int(triangleIndices[t])
                let i1 = Int(triangleIndices[t + 1])
                let i2 = Int(triangleIndices[t + 2])

                // 3 정점 색상 평균 (flat shading보다 부드러움)
                let c0 = vertexColors[i0], c1 = vertexColors[i1], c2 = vertexColors[i2]
                let avgColor = UIColor(
                    red:   (c0.r + c1.r + c2.r) / 3,
                    green: (c0.g + c1.g + c2.g) / 3,
                    blue:  (c0.b + c1.b + c2.b) / 3,
                    alpha: 1
                )

                let p0 = CGPoint(x: CGFloat(uvCoordinates[i0].x) * sz,
                                 y: CGFloat(uvCoordinates[i0].y) * sz)
                let p1 = CGPoint(x: CGFloat(uvCoordinates[i1].x) * sz,
                                 y: CGFloat(uvCoordinates[i1].y) * sz)
                let p2 = CGPoint(x: CGFloat(uvCoordinates[i2].x) * sz,
                                 y: CGFloat(uvCoordinates[i2].y) * sz)

                let path = UIBezierPath()
                path.move(to: p0)
                path.addLine(to: p1)
                path.addLine(to: p2)
                path.close()
                avgColor.setFill()
                path.fill()
            }
        }

        // ── Gaussian 블러로 삼각형 seam 스무딩 ──
        guard let rawCG = rawTexture.cgImage else { return rawTexture }
        let rawCI = CIImage(cgImage: rawCG)
        let blurred = rawCI.clampedToExtent()
            .applyingGaussianBlur(sigma: 1.2)
            .cropped(to: rawCI.extent)

        guard let finalCG = ciCtx.createCGImage(blurred, from: blurred.extent) else {
            return rawTexture
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

        let rows = 32
        let cols = 32

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
