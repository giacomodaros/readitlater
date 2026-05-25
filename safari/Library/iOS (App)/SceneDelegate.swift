//
//  SceneDelegate.swift
//  iOS (App)
//
//  Created by Giacomo on 25/05/26.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let _ = (scene as? UIWindowScene) else { return }
        if let url = connectionOptions.urlContexts.first?.url {
            handle(url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handle(url)
    }

    private func handle(_ url: URL) {
        guard url.scheme == "library", url.host == "save",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let articleURL = URL(string: rawURL) else {
            return
        }

        UserDefaults.standard.set(articleURL.absoluteString, forKey: "reader.pendingShareURL")
        NotificationCenter.default.post(name: .sharedArticleURLReceived, object: articleURL)
    }

}

extension Notification.Name {
    static let sharedArticleURLReceived = Notification.Name("sharedArticleURLReceived")
}
