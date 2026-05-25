//
//  ShareViewController.swift
//  iOS Share Extension
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleShare() }
    }

    private func handleShare() async {
        do {
            guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
                  let providers = item.attachments else {
                complete()
                return
            }

            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try await loadURL(from: provider) {
                    openContainingApp(with: url)
                    return
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try await loadText(from: provider),
                   let url = URL(string: text) {
                    openContainingApp(with: url)
                    return
                }
            }

            complete()
        } catch {
            complete()
        }
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: item as? String)
            }
        }
    }

    private func openContainingApp(with url: URL) {
        var components = URLComponents()
        components.scheme = "library"
        components.host = "save"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]

        guard let appURL = components.url else {
            complete()
            return
        }

        extensionContext?.open(appURL) { [weak self] _ in
            self?.complete()
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
