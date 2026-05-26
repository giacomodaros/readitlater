//
//  ShareViewController.swift
//  iOS Share Extension
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appOrigin = URL(string: "https://readitlater-theta.vercel.app")!
    private let appGroupIdentifier = "group.com.giacomodaros.library"
    private let tokenKey = "reader.auth.token"
    private let pendingURLKey = "reader.pendingShareURL"

    private let iconView = UIImageView(image: UIImage(systemName: "text.badge.plus"))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleShare() }
    }

    private func handleShare() async {
        do {
            guard let url = try await sharedURL() else {
                showFailure("No article URL found.")
                complete(after: 1.2)
                return
            }

            guard let token = sharedToken() else {
                storePending(url)
                showFailure("Open Library and sign in.")
                complete(after: 1.6)
                return
            }

            try await save(url: url, token: token)
            showSuccess("Saved")
            complete(after: 0.9)
        } catch {
            showFailure("Couldn't save. Try again in a moment.")
            complete(after: 1.6)
        }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit

        titleLabel.text = "Saving to Library"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center

        messageLabel.text = "Preparing article..."
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center

        activityIndicator.startAnimating()

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, messageLabel, activityIndicator])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func sharedURL() async throws -> URL? {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else {
            return nil
        }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try await loadURL(from: provider) {
                return url
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try await loadText(from: provider),
               let url = firstURL(in: text) {
                return url
            }
        }

        return nil
    }

    private func firstURL(in text: String) -> URL? {
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
           ["http", "https"].contains(url.scheme?.lowercased()) {
            return url
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }

    private func sharedToken() -> String? {
        UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: tokenKey)
    }

    private func storePending(_ url: URL) {
        UserDefaults(suiteName: appGroupIdentifier)?.set(url.absoluteString, forKey: pendingURLKey)
    }

    private func save(url: URL, token: String) async throws {
        var request = URLRequest(url: appOrigin.appendingPathComponent("/api/articles"))
        request.timeoutInterval = 20
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": url.absoluteString])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
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
            self?.showFailure("Open Library to finish.")
        }
    }

    private func showSuccess(_ message: String) {
        activityIndicator.stopAnimating()
        iconView.image = UIImage(systemName: "checkmark.circle.fill")
        iconView.tintColor = .systemGreen
        titleLabel.text = message
        messageLabel.text = "Added to your reading list."
    }

    private func showFailure(_ message: String) {
        activityIndicator.stopAnimating()
        iconView.image = UIImage(systemName: "exclamationmark.circle.fill")
        iconView.tintColor = .systemOrange
        titleLabel.text = message
        messageLabel.text = "The article is queued in Library."
    }

    private func complete(after delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
