//
//  detectAcneOneMoreTimeApp.swift
//  detectAcneOneMoreTime
//
//  Created by Lisa Kuchyna on 2024-01-09.
//

import SwiftUI
import FirebaseCore
import BackgroundTasks
import TensorFlowLite
import FirebaseMLModelDownloader
import Photos


class AppDelegate: NSObject, UIApplicationDelegate {

    var window: UIWindow?
    let observer = PhotoLibraryObserver.shared
    let taskId = "com.naukma.detectAcneOneMoreTime"

    func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()

        PHPhotoLibrary.shared().register(observer)
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
                self.handleAppRefresh(task: task)
        }

        return true
  }



    func handleAppRefresh(task: BGProcessingTask) {  // для регулярної перевірки
        // Schedule the next background task
        scheduleNextAppRefresh()

        // Perform task
        observer.checkForNewPhotos { result in
            switch result {
            case .newPhotos:
                task.setTaskCompleted(success: true) // якщо є нові фото -> відбувається перевірка
                MLWork().scheduleAppRefresh()
            case .noNewPhotos:
                task.setTaskCompleted(success: true)
            case .failed:
                task.setTaskCompleted(success: false)
            }
        }
    }

    func scheduleNextAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 24 * 60 * 60) // 20 days
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Unable to submit task: \(error.localizedDescription)")
        }
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

            observer.checkForNewPhotos { result in
                switch result {
                case .newPhotos:
                    completionHandler(.newData)
                    MLWork().scheduleAppRefresh()
                case .noNewPhotos:
                    completionHandler(.noData)
                case .failed:
                    completionHandler(.failed)
                }
            }
        }

}


@main
struct detectAcneOneMoreTimeApp: App {
    @Environment(\.scenePhase) private var phase
    var ml = MLWork()
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: phase) { newPhase in
            switch newPhase {
            case .background: ml.scheduleAppRefresh()
            default: break
            }
        }
        
    }
    
    
}

