import UIKit
import Vision
//import SameFace

public struct SFaceCompare {

    // MARK: - Properties
    private let firstFace: UIImage
    private let secondFace: UIImage
    private let matchingCoefficient: Double

    // MARK: - Initializer
    /**
     Instantiates face compare process for given faces.

     - parameter firstFace: The first detected face image.
     - parameter secondFace: The second detected face image.
     - parameter matchingCoefficient: The matching coefficient threshold for similarity.
     */
    public init(firstFace: UIImage, secondFace: UIImage, matchingCoefficient: Double = 1.0) {
        self.firstFace = firstFace
        self.secondFace = secondFace
        self.matchingCoefficient = matchingCoefficient
    }

    // MARK: - Public methods
    /**
     Compares two detected faces.

     - parameter completion: A closure to be called once the comparison is completed.
     - parameter result: The result of the comparison containing whether faces are similar or not.
     */
    public func compareFaces(completion: @escaping (Result<Bool, Error>) -> Void ) {
        guard let firstPixelBuffer = firstFace.pixelBuffer(),
              let secondPixelBuffer = secondFace.pixelBuffer() else {
            completion(.failure(SFaceError.invalidInput))
            return
        }

        do {
            let net = try Faces(configuration: .init())
            let firstOutput = try net.prediction(data: firstPixelBuffer).output
            let secondOutput = try net.prediction(data: secondPixelBuffer).output
            let result = calculateDifference(firstOutput, secondOutput)
            completion(.success(result < matchingCoefficient))
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - Private methods
    private func calculateDifference(_ first: MLMultiArray, _ second: MLMultiArray) -> Double {
        var difference: Double = 0.0
        for index in 0..<first.count {
            let diff = (Double(truncating: first[index]) - Double(truncating: second[index]))
            difference += (diff * diff)
        }
        return difference.squareRoot()
    }
}

// MARK: - Extensions
extension UIImage {
    func pixelBuffer() -> CVPixelBuffer? {
        guard let cgImage = self.cgImage else { return nil }
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let width = cgImage.width
        let height = cgImage.height
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          width,
                                          height,
                                          kCVPixelFormatType_32BGRA,
                                          options as CFDictionary,
                                          &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let context = CGContext(data: pixelData,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        guard let ctx = context else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1.0, y: -1.0)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        return buffer
    }
}

enum SFaceError: Error {
    case invalidInput
}

