//
//  MLWork.swift
//  detectAcneOneMoreTime
//
//  Created by Lisa Kuchyna on 2024-03-08.
//

import Foundation
import TensorFlowLite
import FirebaseMLModelDownloader
import Photos
import Vision
import UIKit
import UserNotifications


var currentAcneTendency:[AcneTendency] = []


struct AcneTendency {
    var hasAcne: Bool
    var acneSeverity: Int
}


class MLWork: ObservableObject {
    
    @Published var verdictText: String = ""
    
    func scheduleAppRefresh() {
        Task {
            // Load ML models
            guard let modelPath = Bundle.main.path(forResource: "acne_classification_model10", ofType: "tflite") else {
                fatalError("Model not found.")
            }
            guard let modelBinarPath = Bundle.main.path(forResource: "acnebinar_classification_model", ofType: "tflite") else {
                fatalError("Model not found.")
            }
            do {
                let interpreter = try Interpreter(modelPath: modelPath)
                let interpreterBinar = try Interpreter(modelPath: modelBinarPath)
                
                // Fetch photos from the gallery
                let photoAssets = PHAsset.fetchAssets(with: .image, options: nil)
                
                currentAcneTendency.removeAll()
                            
                for index in 0..<photoAssets.count {
                    let image = try await requestImage(for: photoAssets[index])
                    await detectFaces(photo: image, in: image.cgImage!, with: interpreter, withBinar: interpreterBinar)
                }
                
                print(currentAcneTendency)
                
                self.giveVerdict()
                
               
            } catch {
                print("Error loading ML model: \(error)")
            }
            
        }
        
        
    }
    
    private func requestImage(for asset: PHAsset) async throws -> UIImage {
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true
            requestOptions.deliveryMode = .highQualityFormat
            
            return try await withCheckedThrowingContinuation { continuation in
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 224, height: 224), contentMode: .aspectFill, options: requestOptions) { image, _ in
                    if let image = image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: NSError(domain: "Image Loading", code: 2, userInfo: nil))
                    }
                }
            }
        }
    
    private func detectFaces(photo image: UIImage, in cgImage: CGImage, with interpreter: Interpreter, withBinar interpreterBinar: Interpreter) async {
        
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let faces = VNDetectFaceRectanglesRequest { [self] request, error in
            
            guard error == nil else {
                print("Failed to detect faces:", error!)
                return
            }
            
            if let results = request.results as? [VNFaceObservation], !results.isEmpty {
                
                results.forEach { faceObservation in
                    
                    let boundingBox = faceObservation.boundingBox
                    let x = boundingBox.origin.x * image.size.width
                    let y = (1 - boundingBox.origin.y - boundingBox.height) * image.size.height
                    let width = boundingBox.width * image.size.width
                    let height = boundingBox.height * image.size.height

                    let expandedBoundingBox = CGRect(x: max(0, x - width * 0.1),
                                                      y: max(0, y - height * 0.2),
                                                      width: min(image.size.width - x, width * 1.2),
                                                      height: min(image.size.height - y, height * 1.5))

                    let faceRect = expandedBoundingBox

                    guard let croppedCGImage = image.cgImage?.cropping(to: faceRect) else { return }
                    let resizedImage = self.resized(image: croppedCGImage, to: CGSize(width: 224, height: 224))
                    
                    // беремо фото з камери
                    guard let imageFromCamera = capturedImageData else { return }
                    
                    if let userImage = UIImage(data: imageFromCamera) {
                       

                        let resizedImage1 = userImage.resized(to: CGSize(width: 96, height: 96))! // userImage
                        let resizedImage2 = image.resized(to: CGSize(width: 96, height: 96))!


                        let faceComparator = SFaceCompare(firstFace: resizedImage1, secondFace: resizedImage2)
                        faceComparator.compareFaces { result in   // compare user face and detected
                            switch result {
                            case .success(let areSimilar):
                                if areSimilar {

                                    self.analyzeImage(resizedImage!, with: interpreter, withBinar: interpreterBinar, amount: results.count) // go to ml models
                                    print("Faces are similar.")
                                } else {
                                    print("Faces are not similar.")
                                }
                            case .failure(let error):
                                print("Error occurred: \(error)")
                            }
                        }
                    }

                }
            } else {
                print("No faces detected.")
            }
        }


        #if targetEnvironment(simulator)

        faces.usesCPUOnly = true

        #endif

    
        do {

            try requestHandler.perform([faces])

        } catch {

            print("Error analyzing image: \(error)")

            return

        }
        
    }

    private func analyzeImage(_ image: CGImage, with interpreter: Interpreter, withBinar interpreterBinar: Interpreter, amount all: Int){
        
        do {
            guard let context = CGContext(
                data: nil,
                width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) else {
                return
            }
            
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let imageData = context.data else { return }
            
            var inputData = Data()
            
            print("entered")
            
            // Image Normalization
            for row in 0..<224 {
                for col in 0..<224 {
                    let offset = 4 * (row * context.width + col)
                    let red = imageData.load(fromByteOffset: offset + 1, as: UInt8.self)
                    let green = imageData.load(fromByteOffset: offset + 2, as: UInt8.self)
                    let blue = imageData.load(fromByteOffset: offset + 3, as: UInt8.self)
                    
                    // Normalize channel values to [0.0, 1.0].
                    var normalizedRed = Float32(red) / 255.0
                    var normalizedGreen = Float32(green) / 255.0
                    var normalizedBlue = Float32(blue) / 255.0
                    
                    // Append normalized values to Data object in RGB order.
                    let elementSize = MemoryLayout.size(ofValue: normalizedRed)
                    var bytes = [UInt8](repeating: 0, count: elementSize)
                    memcpy(&bytes, &normalizedRed, elementSize)
                    inputData.append(&bytes, count: elementSize)
                    memcpy(&bytes, &normalizedGreen, elementSize)
                    inputData.append(&bytes, count: elementSize)
                    memcpy(&bytes, &normalizedBlue, elementSize)
                    inputData.append(&bytes, count: elementSize)
                }
            }
            
            // Run Inference
            try interpreter.allocateTensors()
            try interpreter.copy(inputData, toInputAt: 0)
            try interpreter.invoke()
            
            // Process Output
            let output = try interpreter.output(at: 0)
            let probabilities = UnsafeMutableBufferPointer<Float32>.allocate(capacity: 1000)
            output.data.copyBytes(to: probabilities)
            
            // Load Labels
            guard let labelPath = Bundle.main.path(forResource: "retrained_labels", ofType: "txt") else { return }
            let fileContents = try? String(contentsOfFile: labelPath)
            guard let labels = fileContents?.components(separatedBy: "\n") else { return }


            var max = Float32(0.0)
            var index = 0
            for i in labels.indices {
                print("\(labels[i]): \(probabilities[i])")
                if probabilities[i] > max {
                    max = probabilities[i]
                    index = i
                }
            }
            
            try interpreterBinar.allocateTensors()
            try interpreterBinar.copy(inputData, toInputAt: 0)
            try interpreterBinar.invoke()
            
            let outputBinar = try interpreterBinar.output(at: 0)
            let probabilitiesBinar = UnsafeMutableBufferPointer<Float32>.allocate(capacity: 1000)
            outputBinar.data.copyBytes(to: probabilitiesBinar)
            
            var tendency = AcneTendency(hasAcne: true, acneSeverity: index)
            
            if probabilitiesBinar[0] > 0.45 {
                tendency.hasAcne = false
            } else {
                tendency.hasAcne = true
            }

            currentAcneTendency.append(tendency)
            
        } catch {
            print("Error: \(error)")
        }
    }
    

    func compareFaces(image1: UIImage, image2: UIImage) {
        let requestHandler = VNImageRequestHandler(cgImage: image1.cgImage!, options: [:])
        let requestHandler2 = VNImageRequestHandler(cgImage: image2.cgImage!, options: [:])


            let threshold:Float = 0.5
                
                let detectFaceRequest = VNDetectFaceRectanglesRequest { request, error in
                    guard let observations = request.results as? [VNFaceObservation], observations.count > 2 else {
                        fatalError("Unexpected result type from VNDetectFaceRectanglesRequest")
                    }
                    
                    // Perform face recognition comparison if at least two faces are detected
                    let similarity = self.calculateSimilarity(observations[0], observations[1])
                    
                    // Handle the result based on the similarity score
                    if similarity > threshold {
                        print("Faces are similar")
                    } else {
                        print("Faces are not similar")
                    }
                }
        
                #if targetEnvironment(simulator)

                detectFaceRequest.usesCPUOnly = true

                #endif
                
                do {
                    try requestHandler.perform([detectFaceRequest])
                    try requestHandler2.perform([detectFaceRequest])
                } catch {
                    print("Error performing face detection: \(error)")
                }
            }

            func calculateSimilarity(_ observation1: VNFaceObservation, _ observation2: VNFaceObservation) -> Float {
                // Extract bounding boxes from the observations
                let boundingBox1 = observation1.boundingBox
                let boundingBox2 = observation2.boundingBox
                
                // Calculate similarity using bounding box overlap area
                let intersection = boundingBox1.intersection(boundingBox2)
                let union = boundingBox1.union(boundingBox2)
                let overlapArea = intersection.size.width * intersection.size.height
                let similarity = overlapArea / union.size.width / union.size.height
                
                return Float(similarity)
            }

    
    private func resized(image: CGImage, to newSize: CGSize) -> CGImage? {
        let context = CGContext(data: nil,
                                width: Int(newSize.width),
                                height: Int(newSize.height),
                                bitsPerComponent: image.bitsPerComponent,
                                bytesPerRow: 0,
                                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: image.bitmapInfo.rawValue)
        
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(origin: .zero, size: newSize))
        
        return context?.makeImage()
    }
    
    func giveVerdict() {
        guard currentAcneTendency.count >= 2 else {
            print("Error: Insufficient data for comparison.")
            return
        }

        var verdictText = ""
        var consecutiveAcneCount = 0 // лічильник для підрядних акне

        for (oldEntry, newEntry) in zip(currentAcneTendency.dropLast(), currentAcneTendency.dropFirst()) {
            if !oldEntry.hasAcne && newEntry.hasAcne {
                consecutiveAcneCount = 1 // якщо з'явилося нове акне, почати лічильник знову
                verdictText = "Acne has appeared"
                sendNotification(message: verdictText)
            } else if oldEntry.hasAcne && newEntry.hasAcne {
                if oldEntry.acneSeverity < newEntry.acneSeverity {
                    verdictText = "Acne severity got worse"
                    sendNotification(message: verdictText)
                } else {
                    verdictText = "Acne severity got better"
                    sendNotification(message: verdictText)
                }
                consecutiveAcneCount += 1 // збільшуємо лічильник акне
                if consecutiveAcneCount >= 10 {
                    verdictText = "Acne is stable" // якщо акне стабільно протягом 10 фотографій підряд
                    sendNotification(message: verdictText)
                }
            } else {
                consecutiveAcneCount = 0 // якщо немає акне на цій фотографії, обнулити лічильник
            }
        }

        if verdictText.isEmpty {
            print("Notification: No changes in acne tendency")
        }
    }


    
    func sendNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Acne Alert"
        content.body = message
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "acneNotification", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error adding notification request: \(error.localizedDescription)")
            } else {
                print("Notification request added successfully")
            }
        }
    }

}


        
extension UIImage {
    func resized(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}


