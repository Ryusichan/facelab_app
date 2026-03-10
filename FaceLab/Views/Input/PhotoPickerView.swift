import SwiftUI
import PhotosUI
import Vision

// ============================================================
// MARK: - PhotoPickerView
// 사진 라이브러리에서 얼굴 사진 선택
// Vision으로 얼굴 감지 → 기본 mesh에 사진 텍스처 매핑
// ============================================================
struct PhotoPickerView: View {
    @EnvironmentObject var router: AppRouter
    @StateObject private var viewModel = PhotoPickerViewModel()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 24) {
                // 뒤로가기
                HStack {
                    Button {
                        router.goTo(.inputMethod)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("뒤로")
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // 선택된 사진 미리보기 또는 빈 상태
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.secondary.opacity(0.3), lineWidth: 1)
                        )

                    // 얼굴 감지 결과
                    if viewModel.isFaceDetected {
                        Label("얼굴 감지됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout.bold())
                    } else if viewModel.hasAnalyzed {
                        Label("얼굴을 찾을 수 없습니다", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.callout.bold())
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("정면 얼굴 사진을 선택하세요")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // 버튼
                VStack(spacing: 12) {
                    // 사진 선택 버튼
                    PhotosPicker(
                        selection: $viewModel.photoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            viewModel.selectedImage == nil ? "사진 선택" : "다른 사진 선택",
                            systemImage: "photo.on.rectangle"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }

                    // 진행 버튼
                    if viewModel.isFaceDetected {
                        Button {
                            viewModel.buildScanData()
                        } label: {
                            Text("3D 모델 생성")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }

            // 로딩
            if viewModel.isProcessing {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView("분석 중...")
                    .padding(24)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .foregroundStyle(.primary)
        .onChange(of: viewModel.scanData) { _, newValue in
            if let scanData = newValue {
                router.scanData = scanData
                router.goTo(.processing)
            }
        }
    }
}

// MARK: - ViewModel
@MainActor
class PhotoPickerViewModel: ObservableObject {
    @Published var photoItem: PhotosPickerItem? {
        didSet { loadImage() }
    }
    @Published var selectedImage: UIImage?
    @Published var isFaceDetected = false
    @Published var hasAnalyzed = false
    @Published var isProcessing = false
    @Published var scanData: FaceScanData?

    private var faceRect: CGRect? // 감지된 얼굴 영역 (정규화 좌표)

    private func loadImage() {
        guard let item = photoItem else { return }
        hasAnalyzed = false
        isFaceDetected = false

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            selectedImage = image
            await detectFace(in: image)
        }
    }

    private func detectFace(in image: UIImage) async {
        guard let cgImage = image.cgImage else { return }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            if let face = request.results?.first {
                faceRect = face.boundingBox
                isFaceDetected = true
            } else {
                isFaceDetected = false
            }
        } catch {
            isFaceDetected = false
        }
        hasAnalyzed = true
    }

    func buildScanData() {
        guard let image = selectedImage else { return }
        isProcessing = true

        // 얼굴 영역 크롭 → 텍스처로 사용
        let faceTexture = cropFaceRegion(from: image)

        // 기본 mesh + 사진 텍스처
        let data = FaceScanData.generateDefaultMesh(faceImage: faceTexture)
        scanData = data
        isProcessing = false
    }

    private func cropFaceRegion(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage, let rect = faceRect else { return image }

        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)

        // Vision의 정규화 좌표 → 픽셀 좌표 (y축 반전)
        var facePixelRect = CGRect(
            x: rect.origin.x * w,
            y: (1 - rect.origin.y - rect.height) * h,
            width: rect.width * w,
            height: rect.height * h
        )

        // 여유 패딩
        let pad = facePixelRect.width * 0.3
        facePixelRect = facePixelRect.insetBy(dx: -pad, dy: -pad)
        facePixelRect = facePixelRect.intersection(CGRect(x: 0, y: 0, width: w, height: h))

        guard let cropped = cgImage.cropping(to: facePixelRect) else { return image }

        // 512x512로 리사이즈
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512))
        return renderer.image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: 512, height: 512))
        }
    }
}
