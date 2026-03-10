import ARKit

// ============================================================
// MARK: - CanonicalFaceMesh
//
// 구멍 없는 전체 위상(full-topology) 페이스 메시
//
// 해상도: (cols+1)×(rows+1) = 65×73 = 4745 정점 / 9216 삼각형
//   → 이전(35×39=1365) 대비 3.5× 향상 → 크게 향상된 얼굴 디테일
//
// 파라미터화 특징:
//   - 얼굴 윤곽선: 이마/광대/턱선 각각 다른 너비 프로파일 (타원 아님)
//   - 코: 코끝 + 코 브릿지 구별된 가우시안 범프
//   - 눈 소켓: 구멍 없는 오목 표면 + 눈꺼풀 림
//   - 눈썹 릿지: 눈 소켓 위 미세 돌출
//   - 입술: 윗입술 / 아랫입술 구분된 돌출 + 인중 오목
//   - 광대뼈: 측면 미세 돌출
//   - 턱: 중앙 집중된 돌출
//
// 좌표계: ARKit face-local (카메라 방향 -Z, 피험자 우측 +X)
// UV: [0,1]×[0,1] 그리드 (u=0 카메라좌/피험자우, v=0 이마 상단)
// ============================================================
struct CanonicalFaceMesh {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvCoordinates: [SIMD2<Float>]
    let triangleIndices: [Int16]

    static let cols = 64
    static let rows = 72

    // UV 공간에서 눈 중심
    // u=0 → 카메라 좌측(피험자 우측눈), u=1 → 카메라 우측(피험자 좌측눈)
    static let eyeRightUV = SIMD2<Float>(0.315, 0.415)
    static let eyeLeftUV  = SIMD2<Float>(0.685, 0.415)
    static let eyeSocketUVRadius: Float = 0.135

    // ──────────────────────────────────────────
    // MARK: 메시 생성
    // ──────────────────────────────────────────
    static func generate() -> CanonicalFaceMesh {
        var verts = [SIMD3<Float>]()
        var uvs   = [SIMD2<Float>]()
        var idxs  = [Int16]()

        verts.reserveCapacity((cols + 1) * (rows + 1))
        uvs.reserveCapacity((cols + 1) * (rows + 1))

        for row in 0...rows {
            for col in 0...cols {
                let u = Float(col) / Float(cols)
                let v = Float(row) / Float(rows)
                verts.append(canonicalPosition(u: u, v: v))
                uvs.append(SIMD2(u, v))
            }
        }

        idxs.reserveCapacity(cols * rows * 6)
        for row in 0..<rows {
            for col in 0..<cols {
                let tl = Int16(row * (cols + 1) + col)
                let tr = tl + 1
                let bl = tl + Int16(cols + 1)
                let br = bl + 1
                idxs += [tl, bl, tr,  tr, bl, br]
            }
        }

        return CanonicalFaceMesh(vertices: verts,
                                  normals: smoothNormals(verts: verts, idxs: idxs),
                                  uvCoordinates: uvs,
                                  triangleIndices: idxs)
    }

    // ──────────────────────────────────────────
    // MARK: ARKit KNN 피팅
    //
    // 얼굴 표면 (눈 소켓 외):  ARKit 영향 88%
    // 눈 소켓 내부:             ARKit 영향 22% (소켓 형태 보존)
    // k=10 최근접 ARKit 정점의 거리 역수² 가중 평균
    // ──────────────────────────────────────────
    func fitted(to arkitVerts: [SIMD3<Float>]) -> CanonicalFaceMesh {
        let arkitCenter = arkitVerts.reduce(.zero, +) / Float(arkitVerts.count)
        let canonCenter = vertices.reduce(.zero, +) / Float(vertices.count)

        let arkitSpread = arkitVerts.map { simd_length($0 - arkitCenter) }.max() ?? 1
        let canonSpread = vertices.map { simd_length($0 - canonCenter) }.max() ?? 1
        let scale = arkitSpread / max(canonSpread, 1e-6)

        let k = 10

        let fitted: [SIMD3<Float>] = vertices.enumerated().map { (i, cv) in
            let uv = uvCoordinates[i]

            let dL = simd_length(uv - CanonicalFaceMesh.eyeRightUV)
            let dR = simd_length(uv - CanonicalFaceMesh.eyeLeftUV)
            let eyeProx = max(0, 1 - min(dL, dR) / CanonicalFaceMesh.eyeSocketUVRadius)
            let arkitW  = Float(0.22) + Float(0.66) * (1 - eyeProx)

            let cvS = arkitCenter + (cv - canonCenter) * scale

            // 부분 정렬로 k-nearest 탐색 (전체 정렬보다 빠름)
            var heap = [(d2: Float, pos: SIMD3<Float>)]()
            heap.reserveCapacity(k + 1)
            for av in arkitVerts {
                let d2 = simd_length_squared(av - cvS)
                if heap.count < k {
                    heap.append((d2, av))
                    if heap.count == k { heap.sort { $0.d2 < $1.d2 } }
                } else if d2 < heap.last!.d2 {
                    heap[k - 1] = (d2, av)
                    var j = k - 1
                    while j > 0 && heap[j].d2 < heap[j-1].d2 { heap.swapAt(j, j-1); j -= 1 }
                }
            }

            var wSum: Float = 0; var wPos = SIMD3<Float>.zero
            for (d2, pos) in heap {
                let w = 1.0 / (d2 + 1e-8); wPos += pos * w; wSum += w
            }
            let arkitPos = wSum > 0 ? wPos / wSum : cvS

            return cvS + (arkitPos - cvS) * arkitW
        }

        return CanonicalFaceMesh(vertices: fitted,
                                  normals: Self.smoothNormals(verts: fitted, idxs: triangleIndices),
                                  uvCoordinates: uvCoordinates,
                                  triangleIndices: triangleIndices)
    }

    // ──────────────────────────────────────────
    // MARK: 캐노니컬 3D 위치 (고품질 얼굴 파라미터화)
    //
    // 얼굴 윤곽선 + 코/입술/눈썹/광대/턱 디테일
    // ──────────────────────────────────────────
    static func canonicalPosition(u: Float, v: Float) -> SIMD3<Float> {
        // 얼굴 너비 엔벨로프: 이마(좁) → 광대(최대) → 턱(급격히 좁아짐)
        let wMax: Float = 0.073
        let wFactor: Float
        if v < 0.27 {
            wFactor = 0.80 + 0.20 * (v / 0.27)          // 이마: 좁음
        } else if v < 0.56 {
            wFactor = 1.00                                 // 광대: 최대 너비
        } else if v < 0.76 {
            wFactor = 1.00 - 0.14 * ((v - 0.56) / 0.20) // 턱선: 점진적 좁아짐
        } else {
            wFactor = 0.86 - 0.62 * ((v - 0.76) / 0.24) // 턱 끝: 급격히 좁아짐
        }
        let width = wMax * wFactor

        let theta = (u - 0.5) * Float.pi * 0.88
        let phi   = (v - 0.5) * Float.pi * 1.00

        var x = width * sin(theta) * cos(phi)
        var y = -Float(0.090) * sin(phi)
        var z = (cos(theta) * cos(phi) - 1.0) * Float(0.038)

        // ── 코 끝 돌출 ──
        let nu = u - 0.5, nvTip = v - 0.575
        z += Float(0.014) * exp(-(nu*nu) / Float(0.009) - (nvTip*nvTip) / Float(0.013))

        // ── 코 브릿지 (콧대) ──
        let nvBridge = v - 0.470
        z += Float(0.006) * exp(-(nu*nu) / Float(0.004) - (nvBridge*nvBridge) / Float(0.016))

        // ── 코 옆면 오목 (비익 위) ──
        for sign: Float in [-1, 1] {
            let aw = u - (0.5 + sign * 0.085), av = v - 0.550
            z -= Float(0.003) * exp(-(aw*aw) / Float(0.003) - (av*av) / Float(0.010))
        }

        // ── 윗입술 ──
        let ulU = u - 0.5, ulV = v - 0.672
        z += Float(0.005) * exp(-(ulU*ulU) / Float(0.014) - (ulV*ulV) / Float(0.007))

        // ── 아랫입술 ──
        let llU = u - 0.5, llV = v - 0.710
        z += Float(0.006) * exp(-(llU*llU) / Float(0.016) - (llV*llV) / Float(0.008))

        // ── 인중 오목 ──
        let phU = u - 0.5, phV = v - 0.648
        z -= Float(0.002) * exp(-(phU*phU) / Float(0.006) - (phV*phV) / Float(0.004))

        // ── 입 양 끝 오목 ──
        for sign: Float in [-1, 1] {
            let mU = u - (0.5 + sign * 0.10), mV = v - 0.692
            z -= Float(0.002) * exp(-(mU*mU) / Float(0.004) - (mV*mV) / Float(0.004))
        }

        // ── 광대뼈 미세 돌출 ──
        for (cu, cv): (Float, Float) in [(0.235, 0.520), (0.765, 0.520)] {
            let du = (u - cu) / Float(0.13), dv = (v - cv) / Float(0.09)
            z += Float(0.003) * max(0, 1.0 - du*du - dv*dv)
        }

        // ── 눈썹 릿지 ──
        for eyeUV in [eyeRightUV, eyeLeftUV] {
            let du = (u - eyeUV.x) / Float(0.11)
            let dv = v - (eyeUV.y - 0.058)
            if abs(du) < 1.4 && abs(dv) < 0.030 {
                z += Float(0.0030) * max(0, 1.0 - du*du) * max(0, 1.0 - abs(dv) / Float(0.030))
            }
        }

        // ── 눈 소켓 오목 (구멍 없는 표면 + 눈꺼풀 림) ──
        for eyeUV in [eyeRightUV, eyeLeftUV] {
            let du = (u - eyeUV.x) / Float(0.115)
            let dv = (v - eyeUV.y) / Float(0.077)
            let r2 = du*du + dv*dv
            if r2 < 2.2 {
                let t = max(0, Float(1) - r2 / Float(2.2))
                z -= Float(0.008) * t  // 소켓 오목
                // 눈꺼풀 림 (경계 융기)
                if r2 > 0.78 && r2 < 1.58 {
                    let rimT = Float(1) - abs(r2 - Float(1.18)) / Float(0.40)
                    z += Float(0.003) * max(0, rimT)
                }
            }
        }

        // ── 이마 미세 후퇴 ──
        if v < 0.20 {
            z -= Float(0.004) * (1.0 - v / Float(0.20))
        }

        // ── 턱 끝 중앙 돌출 ──
        let chinU = u - 0.5, chinV = v - 0.895
        if v > 0.82 {
            z += Float(0.005) * exp(-(chinU*chinU) / Float(0.010) - (max(0, chinV)*max(0, chinV)) / Float(0.012))
        }

        // ── 관자놀이 오목 ──
        let absU = abs(u - 0.5)
        if absU > 0.32 && v < 0.38 {
            let tU = (absU - Float(0.32)) / Float(0.18)
            let tV = (Float(0.38) - v) / Float(0.38)
            z -= Float(0.006) * min(1.0, tU) * tV
        }

        return SIMD3(x, y, z)
    }

    // ──────────────────────────────────────────
    // MARK: Smooth Normal
    // ──────────────────────────────────────────
    static func smoothNormals(verts: [SIMD3<Float>], idxs: [Int16]) -> [SIMD3<Float>] {
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
}
