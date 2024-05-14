//
//  AppImage.swift
//  detectAcneOneMoreTime
//
//  Created by Lisa Kuchyna on 2024-03-25.
//

import SwiftUI

struct AppImage: View {
    var body: some View {
        Image("icon")
            .resizable()
            .clipShape(Circle())
            .overlay {
                Circle().stroke(.white, lineWidth: 4)
            }
            .shadow(radius: 7)
    }
}


struct AppImage_Previews: PreviewProvider {
    static var previews: some View {
        AppImage()
    }
}
