//
//  SceneDelegate.swift
//  GhostKit
//
//  Standard UISceneDelegate that hosts the SwiftUI ContentView as root.
//

import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Build the root SwiftUI content view.
        let contentView = ContentView()

        // Host it inside a UIHostingController so UIKit manages the window.
        let hostingController = UIHostingController(rootView: contentView)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called when the scene is released by the system.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene becomes active.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene is about to resign active.
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from background to foreground.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from foreground to background.
    }
}
