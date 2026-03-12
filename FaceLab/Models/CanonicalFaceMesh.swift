import ARKit

// ============================================================
// MARK: - CanonicalFaceMesh
//
// 구멍 없는 전체 위상(full-topology) 페이스 메시
//
// 해상도: (cols+1)×(rows+1) = 65×73 = 4745 정점 / 9216 삼각형
//
// 설계 원칙:
//   z-depth를 ARKit 실제 비율에 맞게 설계하여 KNN이 올바른 이웃을 찾도록 함.
//   코 돌출(0.040m), 기본 곡면(0.055m), 눈 소켓(0.014m) 등
//   이전 버전(코 0.014m) 대비 ~3× 깊이 향상 → KNN 매칭 정확도 대폭 개선.
//
// 파라미터화:
//   - 얼굴 너비: 이마(70%) → 광대(100%) → 턱선(80%) → 턱끝(4%)
//   - 코: 코끝(0.040m) + 콧대(0.018m) + 코뿌리(0.006m) + 콧날개 오목 + 콧방울
//   - 눈 소켓: 오목면(0.014m) + 눈꺼풀 림 융기(0.005m)
//   - 눈썹 릿지: 0.007m 돌출
//   - 입술: 윗입술(0.012m) / 아랫입술(0.014m) + 인중 오목 + 입꼬리 오목
//   - 광대뼈: 0.008m 돌출
//   - 볼 오목: 광대 아래 측면 음영
//   - 턱 끝: 0.010m 돌출
//   - 관자놀이: 0.012m 오목
//
// 좌표계: ARKit face-local (카메라 방향 +Z, 피험자 우측 +X)
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
    // MARK: ARKit KNN 피팅 + 눈 소켓 앵커 보정
    //
    // 얼굴 표면 (눈 소켓 외):  ARKit 영향 97% (실제 얼굴 데이터 최우선)
    // 눈 소켓 내부:             ARKit 영향 22% (소켓 형태 보존)
    //                           + ARKit eye transform XY 앵커 보정
    //
    // 눈 소켓 보완 전략:
    //   ARKit는 눈에 구멍이 있어 소켓 내부에 정점이 없음.
    //   대신 faceAnchor.leftEyeTransform / rightEyeTransform으로
    //   실제 안구 중심 위치를 파악하고,
    //   캐노니컬 소켓의 XY 위치를 실제 눈 위치에 맞게 보정.
    // ──────────────────────────────────────────
    func fitted(to arkitVerts: [SIMD3<Float>],
                subjectLeftEyePos: SIMD3<Float>? = nil,
                subjectRightEyePos: SIMD3<Float>? = nil) -> CanonicalFaceMesh {
        let arkitCenter = arkitVerts.reduce(.zero, +) / Float(arkitVerts.count)
        let canonCenter = vertices.reduce(.zero, +) / Float(vertices.count)

        let arkitSpread = arkitVerts.map { simd_length($0 - arkitCenter) }.max() ?? 1
        let canonSpread = vertices.map { simd_length($0 - canonCenter) }.max() ?? 1
        let scale = arkitSpread / max(canonSpread, 1e-6)

        // ── 눈 소켓 앵커 오프셋 계산 ──
        // 캐노니컬 eye center UV 근방 정점들의 스케일된 위치 중심 →
        // ARKit 안구 중심과의 XY 오프셋을 구해 소켓 전체를 올바른 위치로 이동
        func socketXYOffset(eyeUV: SIMD2<Float>, arkitEyePos: SIMD3<Float>?) -> SIMD3<Float> {
            guard let arkitPos = arkitEyePos else { return .zero }
            let r: Float = 0.04  // eye center 근방 UV 반경
            var sum = SIMD3<Float>.zero; var cnt = 0
            for (i, cv) in vertices.enumerated() where simd_length(uvCoordinates[i] - eyeUV) < r {
                sum += arkitCenter + (cv - canonCenter) * scale; cnt += 1
            }
            guard cnt > 0 else { return .zero }
            let canonEyeCenter = sum / Float(cnt)
            // XY만 보정 (Z depth는 KNN + 캐노니컬 형태가 처리)
            return SIMD3(arkitPos.x - canonEyeCenter.x,
                         arkitPos.y - canonEyeCenter.y,
                         0)
        }
        // eyeRightUV = 카메라 좌 = 피험자 우눈 → subjectRightEyePos
        // eyeLeftUV  = 카메라 우 = 피험자 좌눈 → subjectLeftEyePos
        let rightSocketOffset = socketXYOffset(eyeUV: CanonicalFaceMesh.eyeRightUV, arkitEyePos: subjectRightEyePos)
        let leftSocketOffset  = socketXYOffset(eyeUV: CanonicalFaceMesh.eyeLeftUV,  arkitEyePos: subjectLeftEyePos)

        let k = 10

        let fitted: [SIMD3<Float>] = vertices.enumerated().map { (i, cv) in
            let uv = uvCoordinates[i]

            let dL = simd_length(uv - CanonicalFaceMesh.eyeRightUV)
            let dR = simd_length(uv - CanonicalFaceMesh.eyeLeftUV)
            let eyeProx = max(0, 1 - min(dL, dR) / CanonicalFaceMesh.eyeSocketUVRadius)
            // 얼굴 표면: 97% ARKit | 눈 소켓: 22% ARKit (소켓 형태 유지)
            let arkitW  = Float(0.22) + Float(0.75) * (1 - eyeProx)

            let cvS = arkitCenter + (cv - canonCenter) * scale

            // 부분 정렬로 k-nearest 탐색
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

            var result = cvS + (arkitPos - cvS) * arkitW

            // ── 눈 소켓 XY 앵커 보정 ──
            // 소켓 내부 정점: ARKit eye transform XY 위치로 정렬
            // rim에 가까울수록 보정 약화 (rim은 ARKit eyelid vertex가 이미 처리)
            if eyeProx > 0.05 {
                let isRightEye = dL < dR
                let offset = isRightEye ? rightSocketOffset : leftSocketOffset
                let uvDist = min(dL, dR)
                // 소켓 중심: 100% 보정 / rim 경계: 0% 보정
                let rimFade = max(0, 1 - uvDist / (CanonicalFaceMesh.eyeSocketUVRadius * 0.8))
                result += offset * rimFade
            }

            return result
        }

        return CanonicalFaceMesh(vertices: fitted,
                                  normals: Self.smoothNormals(verts: fitted, idxs: triangleIndices),
                                  uvCoordinates: uvCoordinates,
                                  triangleIndices: triangleIndices)
    }

    // ──────────────────────────────────────────
    // MARK: 캐노니컬 3D 위치 (ARKit 비율 맞춤 파라미터화)
    //
    // z-depth를 ARKit 실제 비율에 맞게 설정:
    //   코 끝: 0.040m  → ARKit 코 위치와 매칭되어 KNN 정확도 확보
    //   기본 곡면: 0.055m → 얼굴 테두리-중심 깊이차 현실적
    // ──────────────────────────────────────────
    static func canonicalPosition(u: Float, v: Float) -> SIMD3<Float> {
        let nu = u - 0.5   // 수평 오프셋 (-0.5 ~ +0.5)

        // ── 얼굴 너비 엔벨로프 ──
        // 이마(좁) → 광대(최대) → 턱선(점진) → 턱 끝(급감)
        let wMax: Float = 0.075
        let wFactor: Float
        if v < 0.25 {
            wFactor = 0.70 + 0.30 * (v / 0.25)           // 이마: 70→100%
        } else if v < 0.52 {
            wFactor = 1.00                                  // 광대: 최대
        } else if v < 0.74 {
            wFactor = 1.00 - 0.20 * ((v - 0.52) / 0.22)  // 턱선: 80%까지 좁아짐
        } else {
            wFactor = 0.80 - 0.76 * ((v - 0.74) / 0.26)  // 턱 끝: 급격히 좁아짐
        }
        let width = wMax * wFactor

        let theta = (u - 0.5) * Float.pi * 0.90
        let phi   = (v - 0.5) * Float.pi * 1.05

        var x = width * sin(theta) * cos(phi)
        var y = -Float(0.095) * sin(phi)

        // ── 기본 볼록 곡면 ──
        // 중앙(앞) → 테두리(뒤), 곡률 0.055m (ARKit face depth 비율 반영)
        var z = (cos(theta) * cos(phi) - 1.0) * Float(0.055)

        // ── 코 끝 (ARKit 비율 맞춤: 0.040m 강하게 돌출) ──
        let nvTip = v - 0.575
        z += Float(0.040) * exp(-(nu*nu) / Float(0.0075) - (nvTip*nvTip) / Float(0.011))

        // ── 콧대 (브릿지) ──
        let nvBridge = v - 0.462
        z += Float(0.018) * exp(-(nu*nu) / Float(0.0035) - (nvBridge*nvBridge) / Float(0.017))

        // ── 코 뿌리 (미간~콧대 연결부) ──
        let nvRoot = v - 0.385
        z += Float(0.006) * exp(-(nu*nu) / Float(0.003) - (nvRoot*nvRoot) / Float(0.010))

        // ── 콧날개 오목 (비익 옆면) ──
        for sign: Float in [-1, 1] {
            let aw = u - (0.5 + sign * 0.088), av = v - 0.555
            z -= Float(0.009) * exp(-(aw*aw) / Float(0.0025) - (av*av) / Float(0.008))
        }

        // ── 콧방울 (알라) 미세 돌출 ──
        for sign: Float in [-1, 1] {
            let aw = u - (0.5 + sign * 0.060), av = v - 0.590
            z += Float(0.006) * exp(-(aw*aw) / Float(0.002) - (av*av) / Float(0.005))
        }

        // ── 윗입술 ──
        let ulV = v - 0.670
        z += Float(0.012) * exp(-(nu*nu) / Float(0.011) - (ulV*ulV) / Float(0.005))

        // ── 아랫입술 ──
        let llV = v - 0.712
        z += Float(0.014) * exp(-(nu*nu) / Float(0.013) - (llV*llV) / Float(0.006))

        // ── 인중 오목 ──
        let phV = v - 0.646
        z -= Float(0.005) * exp(-(nu*nu) / Float(0.005) - (phV*phV) / Float(0.003))

        // ── 입 양 끝 오목 ──
        for sign: Float in [-1, 1] {
            let mU = u - (0.5 + sign * 0.098), mV = v - 0.694
            z -= Float(0.006) * exp(-(mU*mU) / Float(0.003) - (mV*mV) / Float(0.003))
        }

        // ── 광대뼈 돌출 ──
        for (cu, cv): (Float, Float) in [(0.238, 0.505), (0.762, 0.505)] {
            let du = (u - cu) / Float(0.12), dv = (v - cv) / Float(0.08)
            z += Float(0.008) * max(0, 1.0 - du*du - dv*dv)
        }

        // ── 볼 오목 (광대 아래, 측면 음영 구조) ──
        for sign: Float in [-1, 1] {
            let bu = u - (0.5 + sign * 0.195), bv = v - 0.595
            z -= Float(0.006) * exp(-(bu*bu) / Float(0.005) - (bv*bv) / Float(0.012))
        }

        // ── 눈썹 릿지 (눈 위 돌출) ──
        for eyeUV in [eyeRightUV, eyeLeftUV] {
            let du = (u - eyeUV.x) / Float(0.10)
            let dv = v - (eyeUV.y - 0.060)
            if abs(du) < 1.4 && abs(dv) < 0.028 {
                z += Float(0.007) * max(0, 1.0 - du*du) * max(0, 1.0 - abs(dv) / Float(0.028))
            }
        }

        // ── 눈 소켓 오목 (구멍 없는 오목면 + 눈꺼풀 림) ──
        for eyeUV in [eyeRightUV, eyeLeftUV] {
            let du = (u - eyeUV.x) / Float(0.112)
            let dv = (v - eyeUV.y) / Float(0.075)
            let r2 = du*du + dv*dv
            if r2 < 2.2 {
                let t = max(0, Float(1) - r2 / Float(2.2))
                z -= Float(0.014) * t        // 소켓 오목 (깊이 증가)
                // 눈꺼풀 림 경계 융기
                if r2 > 0.76 && r2 < 1.56 {
                    let rimT = Float(1) - abs(r2 - Float(1.16)) / Float(0.40)
                    z += Float(0.005) * max(0, rimT)
                }
            }
        }

        // ── 이마 후퇴 ──
        if v < 0.22 {
            z -= Float(0.008) * (1.0 - v / Float(0.22))
        }

        // ── 턱 끝 돌출 ──
        let chinV = v - 0.893
        if v > 0.82 {
            z += Float(0.010) * exp(-(nu*nu) / Float(0.009) - (max(0, chinV)*max(0, chinV)) / Float(0.011))
        }

        // ── 관자놀이 오목 ──
        let absU = abs(u - 0.5)
        if absU > 0.30 && v < 0.40 {
            let tU = (absU - Float(0.30)) / Float(0.20)
            let tV = (Float(0.40) - v) / Float(0.40)
            z -= Float(0.012) * min(1.0, tU) * tV
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
