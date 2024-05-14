//
//  ContentView.swift
//  DetectAcneApp
//
//  Created by Lisa Kuchyna on 2024-03-05.
//

import SwiftUI

import Photos
import BackgroundTasks


var ml = MLWork()


struct ContentView: View {
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var showCameraView = false
    
    let observer = PhotoLibraryObserver.shared

    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                AppImage()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .offset(y: -130)
                    .padding(.bottom, -130)


                VStack(alignment: .center) {
                    Text("Status: \(authorizationStatus.description)")
                                .font(.title)
                    NavigationLink(destination: CameraView()) {
                        Text("Open Camera")
                            .padding()
                            .background(Color("LightGreen"))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    
                }
                
                Spacer()
            }
            .navigationBarTitle("Welcome to MiSkin!")
        }
        .onAppear {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    
                }
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }
}

extension PHAuthorizationStatus {
    var description: String {
        switch self {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    private var lastCheckedDate: Date?

    static let shared = PhotoLibraryObserver()

        private override init() {
            super.init()
            PHPhotoLibrary.shared().register(self)
        }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        print("HERE")

        DispatchQueue.main.async {
            print("START")
            ml.scheduleAppRefresh()
               
        }
    }


    // кожні 20 днів робити перевірку
    func checkForNewPhotos(completion: @escaping (PhotoFetchResult) -> Void) {
        
        if let lastCheckedDate = lastCheckedDate, Date().timeIntervalSince(lastCheckedDate) < 20 * 24 * 60 * 60 {
            completion(.noNewPhotos)
            print("here")
            return
        }

        if lastCheckedDate == nil {
            self.lastCheckedDate = Date()
            completion(.noNewPhotos)
            print("in check d")
            return
        }

        let fetchOptions = PHFetchOptions()

        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date.distantPast
        fetchOptions.predicate = NSPredicate(format: "creationDate > %@", twoDaysAgo as CVarArg)

        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        if fetchResult.count > 0 {

            self.lastCheckedDate = Date()
             ml.scheduleAppRefresh()
            completion(.newPhotos)
        } else {
            completion(.noNewPhotos)
        }
    
    }

}


enum PhotoFetchResult {
    case newPhotos
    case noNewPhotos
    case failed
}



