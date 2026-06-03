//
//  ViewController.swift
//  Shared (App)
//
//  Native reader app and Safari-extension container.
//

import SwiftUI
import Combine
import WebKit
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
typealias PlatformImage = UIImage

extension Notification.Name {
    static let readerChromeVisibilityChanged = Notification.Name("readerChromeVisibilityChanged")
}

final class ReaderHostingController: UIHostingController<ReaderRootView> {
    private var statusBarHidden = false
    private var observer: NSObjectProtocol?

    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .slide
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        statusBarHidden
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observer = NotificationCenter.default.addObserver(
            forName: .readerChromeVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let visible = notification.object as? Bool else { return }
            self?.statusBarHidden = !visible
            self?.setNeedsStatusBarAppearanceUpdate()
            self?.view.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

extension UIViewController {
    var topMostPresentedController: UIViewController {
        presentedViewController?.topMostPresentedController ?? self
    }
}

struct NavigationGestureConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        GestureConfiguringViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? GestureConfiguringViewController)?.configure()
    }

    final class GestureConfiguringViewController: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            configure()
        }

        func configure() {
            guard let navigationController else { return }
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
            navigationController.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
#elseif os(macOS)
import Cocoa
import SafariServices
typealias PlatformViewController = NSViewController
typealias PlatformImage = NSImage
#endif

let extensionBundleIdentifier = "com.giacomodaros.library.Extension"
let appBaseURL = URL(string: "https://readitlater-theta.vercel.app")!
let appGroupIdentifier = "group.com.giacomodaros.library"

extension View {
    @ViewBuilder
    func readerNativeSearchable(
        active: Bool,
        text: Binding<String>,
        isPresented: Binding<Bool>
    ) -> some View {
        if active {
            self.searchable(text: text, isPresented: isPresented, placement: .automatic, prompt: "Search")
        } else {
            self
        }
    }

    @ViewBuilder
    func readerPaneScrollObserver(
        threshold: CGFloat = 58,
        _ onScrolledChange: @escaping (Bool) -> Void
    ) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > threshold
            } action: { oldValue, newValue in
                guard oldValue != newValue else { return }
                onScrolledChange(newValue)
            }
        } else {
            self
        }
        #else
        if #available(macOS 15.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > threshold
            } action: { oldValue, newValue in
                guard oldValue != newValue else { return }
                onScrolledChange(newValue)
            }
        } else {
            self
        }
        #endif
    }

    @ViewBuilder
    func readerSystemChromeHidden(_ hidden: Bool) -> some View {
        #if os(iOS)
        self
            .statusBarHidden(hidden)
            .persistentSystemOverlays(hidden ? .hidden : .automatic)
        #else
        self
        #endif
    }

    @ViewBuilder
    func readerGlassIconButton(theme: ReaderTheme, prominent: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                self
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .buttonStyle(.glassProminent)
            } else {
                self
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .buttonStyle(.glass)
            }
        } else {
            self
                .font(.system(size: 16, weight: .semibold, design: .default))
                .buttonStyle(.plain)
                .readerGlassPressAnimation()
        }
    }

    @ViewBuilder
    func readerGlassBarBackground(theme: ReaderTheme) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background {
                    Capsule(style: .continuous)
                        .fill(theme.glassBase)
                }
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                .shadow(color: .black.opacity(theme == .offWhite ? 0.12 : 0.42), radius: 24, y: 12)
        } else {
            self.background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(theme.hairline)
                    }
                    .shadow(color: .black.opacity(theme == .offWhite ? 0.16 : 0.55), radius: 28, y: 14)
            }
        }
    }

    @ViewBuilder
    func readerStableGlassCircle(theme: ReaderTheme) -> some View {
        let shape = Circle()
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .buttonStyle(.plain)
                .readerGlassPressAnimation()
                .background {
                    shape
                        .fill(theme.glassBase)
                        .overlay {
                            shape.strokeBorder(theme.hairline.opacity(theme.isDark ? 0.7 : 0.45))
                        }
                }
                .glassEffect(.regular.interactive(), in: shape)
                .shadow(color: .black.opacity(theme == .offWhite ? 0.08 : 0.30), radius: 18, y: 9)
        } else {
            self
                .buttonStyle(.plain)
                .readerGlassPressAnimation()
                .background {
                    shape
                        .fill(theme.glassBase)
                        .overlay {
                            shape.strokeBorder(theme.hairline.opacity(theme.isDark ? 0.7 : 0.45))
                        }
                        .shadow(color: .black.opacity(theme == .offWhite ? 0.10 : 0.34), radius: 18, y: 9)
                }
        }
    }
}

struct ReaderGlassPressModifier: ViewModifier {
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.93 : 1)
            .opacity(isPressed ? 0.76 : 1)
            .brightness(isPressed ? -0.025 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
            )
    }
}

extension View {
    func readerGlassPressAnimation() -> some View {
        modifier(ReaderGlassPressModifier())
    }

    @ViewBuilder
    func readerGlassBarButton(theme: ReaderTheme) -> some View {
        self
            .font(.system(size: 16, weight: .semibold, design: .default))
            .buttonStyle(.plain)
            .readerGlassPressAnimation()
    }

    @ViewBuilder
    func nativeGlassCapsule(theme: ReaderTheme) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background {
                    Capsule(style: .continuous)
                        .fill(theme.glassBase)
                }
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            self.background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(theme.hairline)
                    }
            }
        }
    }

    @ViewBuilder
    func readerGlassPanelBackground(theme: ReaderTheme) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self
                .background {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(theme.glassBase)
                }
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(theme == .offWhite ? 0.10 : 0.34), radius: 22, y: 12)
        } else {
            self.background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(theme.hairline)
                    }
                    .shadow(color: .black.opacity(theme == .offWhite ? 0.14 : 0.45), radius: 24, y: 12)
            }
        }
    }

    @ViewBuilder
    func glassEffectIfAvailable<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
        }
    }
}

class ViewController: PlatformViewController {
    @IBOutlet var webView: WKWebView?

    #if os(iOS)
    private var hostingController: ReaderHostingController?
    private var statusBarHidden = false
    private var statusBarObserver: NSObjectProtocol?
    #elseif os(macOS)
    private var hostingView: NSHostingView<ReaderRootView>?
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        webView?.removeFromSuperview()

        let root = ReaderRootView(store: ReaderStore())

        #if os(iOS)
        let hosting = ReaderHostingController(rootView: root)
        hostingController = hosting
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        statusBarObserver = NotificationCenter.default.addObserver(
            forName: .readerChromeVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let visible = notification.object as? Bool else { return }
            self?.statusBarHidden = !visible
            self?.setNeedsStatusBarAppearanceUpdate()
            self?.view.window?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
        }
        #elseif os(macOS)
        let hosting = NSHostingView(rootView: root)
        hostingView = hosting
        view.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        #endif
    }

    #if os(iOS)
    override var prefersStatusBarHidden: Bool {
        statusBarHidden
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .slide
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        statusBarHidden
    }

    override var childForStatusBarHidden: UIViewController? {
        nil
    }

    override var childForStatusBarStyle: UIViewController? {
        hostingController
    }

    deinit {
        if let statusBarObserver {
            NotificationCenter.default.removeObserver(statusBarObserver)
        }
    }
    #endif

    #if os(macOS)
    override func viewDidAppear() {
        super.viewDidAppear()

        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unifiedCompact
    }
    #endif
}

struct ReaderUser: Codable {
    let id: String
    let email: String
    let name: String?
}

struct AuthResponse: Codable {
    let user: ReaderUser
    let token: String
}

struct ReaderLabel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String
}

struct ArticleSummary: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let author: String?
    let description: String?
    let siteName: String?
    let image: String?
    let favicon: String?
    let publishedAt: Date?
    let archived: Bool
    let readAt: Date?
    let ttr: Int?
    let createdAt: Date
    let updatedAt: Date?
    let labels: [ReaderLabel]
}

extension ArticleSummary {
    func updating(archived: Bool? = nil, readAt: Date?? = nil) -> ArticleSummary {
        ArticleSummary(
            id: id,
            title: title,
            author: author,
            description: description,
            siteName: siteName,
            image: image,
            favicon: favicon,
            publishedAt: publishedAt,
            archived: archived ?? self.archived,
            readAt: readAt ?? self.readAt,
            ttr: ttr,
            createdAt: createdAt,
            updatedAt: Date(),
            labels: labels
        )
    }
}

struct Article: Codable, Identifiable {
    let id: String
    let url: String
    let title: String
    let author: String?
    let description: String?
    let content: String
    let siteName: String?
    let publishedAt: Date?
    let ttr: Int?
    let archived: Bool
    let readAt: Date?
    let labels: [ReaderLabel]
}

extension Article {
    init(summary: ArticleSummary) {
        self.id = summary.id
        self.url = ""
        self.title = summary.title
        self.author = summary.author
        self.description = summary.description
        self.content = summary.description ?? ""
        self.siteName = summary.siteName
        self.publishedAt = summary.publishedAt
        self.ttr = summary.ttr
        self.archived = summary.archived
        self.readAt = summary.readAt
        self.labels = summary.labels
    }

    var isHydratedForReader: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updating(archived: Bool? = nil, readAt: Date?? = nil) -> Article {
        Article(
            id: id,
            url: url,
            title: title,
            author: author,
            description: description,
            content: content,
            siteName: siteName,
            publishedAt: publishedAt,
            ttr: ttr,
            archived: archived ?? self.archived,
            readAt: readAt ?? self.readAt,
            labels: labels
        )
    }
}

struct Highlight: Codable, Identifiable, Hashable {
    let id: String
    let articleId: String
    let text: String
    let startOffset: Int
    let endOffset: Int
    let color: String
    let note: String?
    let createdAt: Date
}

struct CachedLibrary: Codable {
    var articles: [ArticleSummary]
    var details: [String: Article]
    var progress: [String: Double]
    var updatedAt: Date

    init(articles: [ArticleSummary], details: [String: Article], progress: [String: Double], updatedAt: Date) {
        self.articles = articles
        self.details = details
        self.progress = progress
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        articles = try container.decode([ArticleSummary].self, forKey: .articles)
        details = try container.decode([String: Article].self, forKey: .details)
        progress = try container.decodeIfPresent([String: Double].self, forKey: .progress) ?? [:]
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

final class ArticleCache {
    static let shared = ArticleCache()

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = ReaderAPI.makeDateDecodingStrategy()
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func load(account: String, archived: Bool, search: String) -> CachedLibrary? {
        guard search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = try? Data(contentsOf: fileURL(account: account, archived: archived)) else {
            return nil
        }
        return try? decoder.decode(CachedLibrary.self, from: data)
    }

    func save(account: String, archived: Bool, articles: [ArticleSummary], details: [String: Article], progress: [String: Double]) {
        let payload = CachedLibrary(articles: articles, details: details, progress: progress, updatedAt: Date())
        guard let data = try? encoder.encode(payload) else { return }
        let url = fileURL(account: account, archived: archived)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func fileURL(account: String, archived: Bool) -> URL {
        let safeAccount = account
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9._-]", with: "_", options: .regularExpression)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryReader", isDirectory: true)
        return directory.appendingPathComponent("\(safeAccount)-\(archived ? "archive" : "library").json")
    }
}

struct ServerError: Codable {
    let error: String
}

enum ReaderAPIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an invalid response."
        case .server(let message):
            message
        }
    }
}

final class TokenStore {
    static let shared = TokenStore()
    private let tokenKey = "reader.auth.token"
    private let emailKey = "reader.auth.email"
    private let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? .standard

    var token: String? {
        get {
            if let token = defaults.string(forKey: tokenKey) {
                return token
            }
            if let legacyToken = UserDefaults.standard.string(forKey: tokenKey) {
                defaults.set(legacyToken, forKey: tokenKey)
                defaults.synchronize()
                return legacyToken
            }
            return nil
        }
        set {
            defaults.set(newValue, forKey: tokenKey)
            UserDefaults.standard.set(newValue, forKey: tokenKey)
            defaults.synchronize()
        }
    }

    var email: String? {
        get {
            if let email = defaults.string(forKey: emailKey) {
                return email
            }
            if let legacyEmail = UserDefaults.standard.string(forKey: emailKey) {
                defaults.set(legacyEmail, forKey: emailKey)
                defaults.synchronize()
                return legacyEmail
            }
            return nil
        }
        set {
            defaults.set(newValue, forKey: emailKey)
            UserDefaults.standard.set(newValue, forKey: emailKey)
            defaults.synchronize()
        }
    }

    func signOut() {
        token = nil
        email = nil
    }
}

final class ReaderAPI {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    init(baseURL: URL = appBaseURL, session: URLSession = .shared, tokenStore: TokenStore = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = Self.makeDateDecodingStrategy()
        self.decoder = decoder
    }

    static func makeDateDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }

            let standard = ISO8601DateFormatter()
            if let date = standard.date(from: value) { return date }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
        }
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let response: AuthResponse = try await send(path: "api/auth/login", method: "POST", body: [
            "email": email,
            "password": password,
        ])
        tokenStore.token = response.token
        tokenStore.email = response.user.email
        return response
    }

    func register(email: String, password: String, name: String) async throws -> AuthResponse {
        var body = ["email": email, "password": password]
        if !name.isEmpty { body["name"] = name }
        let response: AuthResponse = try await send(path: "api/auth/register", method: "POST", body: body)
        tokenStore.token = response.token
        tokenStore.email = response.user.email
        return response
    }

    func articles(archived: Bool = false, search: String = "", since: Date? = nil) async throws -> [ArticleSummary] {
        var items = [URLQueryItem(name: "mode", value: archived ? "archive" : "inbox")]
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
        }
        if let since {
            items.append(URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since)))
        }
        return try await send(path: "api/articles", queryItems: items)
    }

    func article(id: String) async throws -> Article {
        try await send(path: "api/articles/\(id)")
    }

    func save(
        url: String,
        html: String? = nil,
        source: String? = nil,
        metadataOnly: Bool? = nil,
        title: String? = nil,
        author: String? = nil,
        siteName: String? = nil,
        description: String? = nil,
        content: String? = nil,
        wordCount: Int? = nil,
        archived: Bool? = nil,
        readAt: Bool? = nil
    ) async throws -> Article {
        try await send(path: "api/articles", method: "POST", body: SaveArticleBody(
            url: url,
            html: html,
            source: source,
            metadataOnly: metadataOnly,
            title: title,
            author: author,
            siteName: siteName,
            description: description,
            content: content,
            wordCount: wordCount,
            archived: archived,
            readAt: readAt
        ))
    }

    func setArchived(_ archived: Bool, articleId: String) async throws -> Article {
        try await send(path: "api/articles/\(articleId)", method: "PATCH", body: ["archived": archived])
    }

    func setRead(_ read: Bool, articleId: String) async throws -> Article {
        try await send(path: "api/articles/\(articleId)", method: "PATCH", body: PatchArticleBody(readAt: read))
    }

    func deleteArticle(id: String) async throws {
        let _: EmptyResponse = try await send(path: "api/articles/\(id)", method: "DELETE")
    }

    func importMatterCSV(data: Data) async throws -> MatterImportResult {
        try await sendRaw(
            path: "api/import/matter",
            method: "POST",
            contentType: "text/csv; charset=utf-8",
            bodyData: data
        )
    }

    private func send<Response: Decodable>(path: String, method: String = "GET", queryItems: [URLQueryItem] = []) async throws -> Response {
        try await send(path: path, method: method, queryItems: queryItems, bodyData: nil)
    }

    private func send<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body) async throws -> Response {
        try await send(path: path, method: method, queryItems: [], bodyData: encoder.encode(body))
    }

    private func send<Response: Decodable>(path: String, method: String, queryItems: [URLQueryItem], bodyData: Data?) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw ReaderAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = tokenStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReaderAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? decoder.decode(ServerError.self, from: data)
            throw ReaderAPIError.server(error?.error ?? "Request failed.")
        }
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func sendRaw<Response: Decodable>(
        path: String,
        method: String,
        contentType: String,
        bodyData: Data
    ) async throws -> Response {
        guard let url = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)?.url else {
            throw ReaderAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let token = tokenStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ReaderAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? decoder.decode(ServerError.self, from: data)
            throw ReaderAPIError.server(error?.error ?? "Request failed.")
        }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct EmptyResponse: Codable {}

private struct PatchArticleBody: Encodable {
    let archived: Bool?
    let readAt: Bool?

    init(archived: Bool? = nil, readAt: Bool? = nil) {
        self.archived = archived
        self.readAt = readAt
    }
}

private struct SaveArticleBody: Encodable {
    let url: String
    let html: String?
    let source: String?
    let metadataOnly: Bool?
    let title: String?
    let author: String?
    let siteName: String?
    let description: String?
    let content: String?
    let wordCount: Int?
    let archived: Bool?
    let readAt: Bool?
}

struct MatterImportResult: Codable, Equatable {
    var totalRows = 0
    var queued = 0
    var archived = 0
    var skipped = 0
    var failed = 0
    var lastError: String?

    var imported: Int { queued + archived }

    var summary: String {
        var parts = ["Parsed \(totalRows)", "Imported \(imported)"]
        parts.append("\(queued) inbox")
        parts.append("\(archived) archive")
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if failed > 0 { parts.append("\(failed) failed") }
        if imported == 0, let lastError {
            parts.append(lastError)
        }
        return parts.joined(separator: " · ")
    }
}

private struct MatterImportRecord {
    let title: String
    let author: String
    let publisher: String
    let wordCount: Int?
    let url: String
    let inQueue: Bool
    let read: Bool

    var normalizedURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let parsed = URL(string: normalized) else { return nil }
        guard parsed.scheme == "http" || parsed.scheme == "https" else { return nil }
        return parsed
    }

    var fallbackHTML: String {
        let titleValue = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorValue = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let publisherValue = publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = titleValue.isEmpty ? normalizedURL?.host ?? "Imported article" : titleValue
        let byline = authorValue.isEmpty ? "" : "<p class=\"byline\">By \(Self.escape(authorValue))</p>"
        let publisherMeta = publisherValue.isEmpty ? "" : "<meta property=\"og:site_name\" content=\"\(Self.escape(publisherValue))\">"
        let publisherLine = publisherValue.isEmpty ? "" : "<p>Publisher: \(Self.escape(publisherValue))</p>"
        let sourceLine = normalizedURL.map { "<p>Original URL: <a href=\"\(Self.escape($0.absoluteString))\">\(Self.escape($0.absoluteString))</a></p>" } ?? ""

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(Self.escape(displayTitle))</title>
        \(publisherMeta)
        </head>
        <body>
        <article>
        <h1>\(Self.escape(displayTitle))</h1>
        \(byline)
        \(publisherLine)
        \(sourceLine)
        <p>This article was imported from Matter using the saved library history export. The original article link, title, author, publisher, queue state, read state, and word count are preserved so it can be organized in Library even when the source page cannot be fetched during import.</p>
        <p>Open the original URL from the article menu to read the full source page if the archived text is not available in this export.</p>
        <p>The Matter export does not always include the full article body. Library keeps this import as a durable entry with the original source attached, then places it in Inbox or Archive according to the Matter queue field.</p>
        </article>
        </body>
        </html>
        """
    }

    var fallbackContent: String {
        let titleValue = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorValue = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let publisherValue = publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleParagraph = titleValue.isEmpty ? "" : "<p><strong>\(Self.escape(titleValue))</strong></p>"
        let byline = authorValue.isEmpty ? "" : "<p>By \(Self.escape(authorValue))</p>"
        let publisherLine = publisherValue.isEmpty ? "" : "<p>\(Self.escape(publisherValue))</p>"
        let sourceLine = normalizedURL.map { "<p><a href=\"\(Self.escape($0.absoluteString))\">\(Self.escape($0.absoluteString))</a></p>" } ?? ""
        return """
        \(titleParagraph)
        \(byline)
        \(publisherLine)
        \(sourceLine)
        <p>This article was imported from Matter using the saved library history export. The original article link, title, author, publisher, queue state, read state, and word count are preserved so it can be organized in Library even when the source page cannot be fetched during import.</p>
        <p>Open the original URL from the article menu to read the full source page if the archived text is not available in this export.</p>
        <p>The Matter export does not always include the full article body. Library keeps this import as a durable entry with the original source attached, then places it in Inbox or Archive according to the Matter queue field.</p>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private enum MatterCSVError: LocalizedError {
    case unreadable
    case missingColumns([String])
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "The Matter CSV could not be read."
        case .missingColumns(let columns):
            "The Matter CSV is missing: \(columns.joined(separator: ", "))."
        case .empty:
            "The Matter CSV appears to be empty or contains no importable URLs."
        }
    }
}

private enum MatterCSVParser {
    static func records(from data: Data) throws -> [MatterImportRecord] {
        guard let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw MatterCSVError.unreadable
        }
        let text = decoded
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MatterCSVError.empty }

        let rows = parseRows(text)
        guard let header = rows.first else {
            let fallback = fallbackRecords(from: text)
            if fallback.isEmpty { throw MatterCSVError.empty }
            return fallback
        }
        var columns: [String: Int] = [:]
        for (index, value) in header.enumerated() {
            let key = normalizedHeader(value)
            guard !key.isEmpty, columns[key] == nil else { continue }
            columns[key] = index
        }

        var missing: [String] = []
        if columns["url"] == nil { missing.append("URL") }
        if columns["in queue"] == nil { missing.append("In Queue") }
        if !missing.isEmpty {
            let fallback = fallbackRecords(from: text)
            if !fallback.isEmpty { return fallback }
            throw MatterCSVError.missingColumns(missing)
        }

        let urlIndex = columns["url"]!
        let queueIndex = columns["in queue"]!
        let readIndex = columns["read"]
        let titleIndex = columns["title"]
        let authorIndex = columns["author"]
        let publisherIndex = columns["publisher"]
        let wordCountIndex = columns["word count"]

        let parsed: [MatterImportRecord] = rows.dropFirst().compactMap { (row: [String]) -> MatterImportRecord? in
            guard !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                return nil
            }
            let url = value(in: row, at: urlIndex)
            guard !url.isEmpty else { return nil }
            return MatterImportRecord(
                title: titleIndex.map { value(in: row, at: $0) } ?? "",
                author: authorIndex.map { value(in: row, at: $0) } ?? "",
                publisher: publisherIndex.map { value(in: row, at: $0) } ?? "",
                wordCount: wordCountIndex.flatMap { Int(value(in: row, at: $0)) },
                url: url,
                inQueue: parseBool(value(in: row, at: queueIndex)),
                read: readIndex.map { parseBool(value(in: row, at: $0)) } ?? false
            )
        }
        if parsed.isEmpty {
            let fallback = fallbackRecords(from: text)
            if !fallback.isEmpty { return fallback }
            throw MatterCSVError.empty
        }
        return parsed
    }

    private static func value(in row: [String], at index: Int) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{feff}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func parseBool(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "y":
            return true
        default:
            return false
        }
    }

    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default:
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func fallbackRecords(from text: String) -> [MatterImportRecord] {
        let pattern = #"https?://[^\s,"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var seen = Set<String>()
        return matches.compactMap { match in
            let raw = nsText.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,);]}>"))
            guard !raw.isEmpty, seen.insert(raw).inserted else { return nil }
            let host = URL(string: raw)?.host?.replacingOccurrences(of: "www.", with: "") ?? raw
            return MatterImportRecord(
                title: host,
                author: "",
                publisher: host,
                wordCount: nil,
                url: raw,
                inQueue: false,
                read: false
            )
        }
    }
}

@MainActor
final class ReaderStore: ObservableObject {
    @Published var articles: [ArticleSummary] = []
    @Published var inboxArticles: [ArticleSummary] = []
    @Published var archiveArticles: [ArticleSummary] = []
    @Published var selectedArticle: Article?
    @Published var selectedId: String?
    @Published var search = ""
    @Published var archived = false
    @Published var loading = false
    @Published var authMode: AuthMode = .login
    @Published var email = TokenStore.shared.email ?? ""
    @Published var password = ""
    @Published var name = ""
    @Published var errorMessage: String?
    @Published var themePreference: ReaderTheme = ReaderTheme.load()
    @Published var systemColorScheme: ColorScheme = .light
    @Published var textSize: Double = {
        let stored = UserDefaults.standard.double(forKey: "reader.native.textSize")
        return stored == 0 ? 19 : stored
    }()
    @Published var lineSpacing: Double = {
        let stored = UserDefaults.standard.double(forKey: "reader.native.lineSpacing")
        return stored == 0 ? 8 : stored
    }()
    @Published var readerFont: ReaderFont = ReaderFont.load()

    @Published var selectionMode = false
    @Published var selectedIds: Set<String> = []
    @Published var highlightsVersion = 0

    @Published private(set) var readingProgress: [String: Double] = [:]

    let api = ReaderAPI()
    let tokenStore = TokenStore.shared
    private let cache = ArticleCache.shared
    let highlights = HighlightStore.shared
    private var articleDetails: [String: Article] = [:]
    private var persistedProgress: [String: Double] = [:]
    private var prefetchingArticleIds = Set<String>()
    private var cacheSaveWorkItem: DispatchWorkItem?
    private var markingReadArticleIds = Set<String>()
    private var transientProgress: [String: Double] = [:]
    private var lastInboxFetch: Date?
    private var lastArchiveFetch: Date?
    private var backgroundFetchTask: Task<Void, Never>?
    private var loadGeneration = 0

    var theme: ReaderTheme {
        themePreference.resolved(for: systemColorScheme)
    }

    var isSignedIn: Bool {
        tokenStore.token != nil
    }

    func bootstrap() {
        consumePendingShareURL()
        guard isSignedIn else { return }
        loadCachedArticles()
        loadCachedSnapshots()
        Task { await refreshAll() }
    }

    func refreshAll() async {
        await loadArticles()
        // Refresh opposite mode in background so search across both
        // and switching tabs is instant.
        backgroundFetchTask?.cancel()
        backgroundFetchTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshOppositeMode()
        }
    }

    private func refreshOppositeMode() async {
        let target = !archived
        do {
            let fetched = try await api.articles(archived: target, search: "")
            if target {
                archiveArticles = fetched
                lastArchiveFetch = Date()
            } else {
                inboxArticles = fetched
                lastInboxFetch = Date()
            }
            persistSideCache(archived: target, articles: fetched)
        } catch {
            // Silent; user-visible flow is the active mode.
        }
    }

    private func loadCachedSnapshots() {
        guard let account = tokenStore.email else { return }
        if let inbox = cache.load(account: account, archived: false, search: "") {
            inboxArticles = inbox.articles
            articleDetails.merge(inbox.details) { current, _ in current }
            readingProgress.merge(inbox.progress) { current, _ in current }
            persistedProgress.merge(inbox.progress) { current, _ in current }
        }
        if let arch = cache.load(account: account, archived: true, search: "") {
            archiveArticles = arch.articles
            articleDetails.merge(arch.details) { current, _ in current }
            readingProgress.merge(arch.progress) { current, _ in current }
            persistedProgress.merge(arch.progress) { current, _ in current }
        }
    }

    private func persistSideCache(archived: Bool, articles: [ArticleSummary]) {
        guard let account = tokenStore.email else { return }
        cache.save(
            account: account,
            archived: archived,
            articles: articles,
            details: articleDetails,
            progress: readingProgress
        )
    }

    func consumePendingShareURL() {
        let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
        let rawPendingURL = sharedDefaults?.string(forKey: "reader.pendingShareURL")
            ?? UserDefaults.standard.string(forKey: "reader.pendingShareURL")

        guard let rawURL = rawPendingURL,
              let url = URL(string: rawURL) else {
            return
        }
        sharedDefaults?.removeObject(forKey: "reader.pendingShareURL")
        UserDefaults.standard.removeObject(forKey: "reader.pendingShareURL")
        Task { await add(url: url.absoluteString) }
    }

    func authenticate() async {
        do {
            errorMessage = nil
            if authMode == .login {
                _ = try await api.login(email: email, password: password)
            } else {
                _ = try await api.register(email: email, password: password, name: name)
            }
            password = ""
            await loadArticles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        tokenStore.signOut()
        articles = []
        selectedArticle = nil
        selectedId = nil
        articleDetails = [:]
        readingProgress = [:]
        persistedProgress = [:]
        transientProgress = [:]
        markingReadArticleIds.removeAll()
        cacheSaveWorkItem?.cancel()
    }

    func setTheme(_ value: ReaderTheme) {
        themePreference = value
        UserDefaults.standard.set(value.rawValue, forKey: "reader.native.theme")
    }

    func setTextSize(_ value: Double) {
        textSize = value
        UserDefaults.standard.set(value, forKey: "reader.native.textSize")
    }

    func setLineSpacing(_ value: Double) {
        lineSpacing = value
        UserDefaults.standard.set(value, forKey: "reader.native.lineSpacing")
    }

    func setReaderFont(_ value: ReaderFont) {
        readerFont = value
        UserDefaults.standard.set(value.rawValue, forKey: "reader.native.font")
    }

    func setArchiveMode(_ value: Bool) {
        guard archived != value else { return }
        archived = value
        search = ""
        selectionMode = false
        selectedIds.removeAll()
        // Swap to cached side immediately so list stays populated.
        withAnimation(.none) {
            articles = value ? archiveArticles : inboxArticles
        }
        if let selectedId, !articles.contains(where: { $0.id == selectedId }) {
            selectedArticle = nil
            self.selectedId = nil
        }
    }

    func applyLocalSearch() {
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            withAnimation(.none) {
                articles = archived ? archiveArticles : inboxArticles
            }
            return
        }

        let terms = trimmedSearch
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .split(separator: " ")
            .map(String.init)

        let candidates = mergeSummaries(existing: inboxArticles, incoming: archiveArticles)
        let results = candidates.filter { summary in
            let detail = articleDetails[summary.id]
            let haystack = [
                summary.title,
                summary.author ?? "",
                summary.description ?? "",
                summary.siteName ?? "",
                detail?.url ?? "",
                detail?.content ?? "",
            ]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

            return terms.allSatisfy { haystack.contains($0) }
        }

        withAnimation(.none) {
            articles = results
        }
    }

    func loadArticles() async {
        var generation = loadGeneration
        do {
            loadGeneration &+= 1
            generation = loadGeneration
            let queryArchived = archived
            let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSearch.isEmpty {
                withAnimation(.none) {
                    articles = queryArchived ? archiveArticles : inboxArticles
                }
            } else {
                applyLocalSearch()
                loading = false
                return
            }
            loading = true
            errorMessage = nil
            let fetched: [ArticleSummary]
            if trimmedSearch.isEmpty {
                fetched = try await api.articles(archived: queryArchived, search: "")
            } else {
                async let inboxResultsRequest = api.articles(archived: false, search: trimmedSearch)
                async let archResultsRequest = api.articles(archived: true, search: trimmedSearch)
                let inboxResults = try await inboxResultsRequest
                let archResults = try await archResultsRequest
                let combined = inboxResults + archResults
                fetched = combined.sorted {
                    if $0.createdAt != $1.createdAt {
                        return $0.createdAt > $1.createdAt
                    }
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            }
            guard generation == loadGeneration,
                  queryArchived == archived,
                  trimmedSearch == search.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            withAnimation(.none) {
                articles = fetched
            }
            if trimmedSearch.isEmpty {
                if queryArchived {
                    archiveArticles = fetched
                    lastArchiveFetch = Date()
                } else {
                    inboxArticles = fetched
                    lastInboxFetch = Date()
                }
            }
            loading = false
            saveCache()
            if selectedId == nil, let first = articles.first {
                selectedId = first.id
                selectedArticle = articleDetails[first.id] ?? Article(summary: first)
            } else if articles.isEmpty {
                selectedArticle = nil
                selectedId = nil
            } else if let selectedId, !articles.contains(where: { $0.id == selectedId }) {
                selectedArticle = nil
                self.selectedId = nil
            }
            prefetchMissingArticles()
        } catch {
            if isCancellation(error) {
                if generation == loadGeneration {
                    loading = false
                }
                return
            }
            loading = false
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func select(_ article: ArticleSummary) async -> Article {
        await prepareArticleForOpen(article)
    }

    func cachedArticleForOpen(_ article: ArticleSummary) -> Article? {
        if let selectedArticle,
           selectedArticle.id == article.id,
           selectedArticle.isHydratedForReader {
            return selectedArticle
        }
        guard let cached = articleDetails[article.id],
              cached.isHydratedForReader else {
            return nil
        }
        return cached
    }

    @discardableResult
    func prepareArticleForOpen(_ article: ArticleSummary) async -> Article {
        selectedId = article.id
        if let cached = cachedArticleForOpen(article) {
            selectedArticle = cached
            return cached
        }

        do {
            let fetched = try await api.article(id: article.id)
            articleDetails[article.id] = fetched
            selectedArticle = fetched
            saveCache()
            return fetched
        } catch {
            errorMessage = error.localizedDescription
            let fallback = articleDetails[article.id] ?? Article(summary: article)
            selectedArticle = fallback
            return fallback
        }
    }

    private func prefetchMissingArticles() {
        guard search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let missing = articles
            .prefix(6)
            .map(\.id)
            .filter { articleDetails[$0] == nil && !prefetchingArticleIds.contains($0) }

        guard !missing.isEmpty else { return }
        prefetchingArticleIds.formUnion(missing)

        Task {
            for id in missing {
                do {
                    let fetched = try await api.article(id: id)
                    articleDetails[id] = fetched
                    if selectedId == id, selectedArticle?.url.isEmpty != false {
                        selectedArticle = fetched
                    }
                    saveCache()
                } catch {
                    // Keep prefetch silent; explicit opens still surface errors.
                }
                prefetchingArticleIds.remove(id)
            }
        }
    }

    func add(url: String) async {
        do {
            errorMessage = nil
            let saved = try await api.save(url: url)
            articleDetails[saved.id] = saved
            resetProgressForFreshArticle(saved.id)
            await loadArticles()
            selectedId = saved.id
            selectedArticle = saved
            resetProgressForFreshArticle(saved.id)
            saveCache()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isKnownArticle(id: String) -> Bool {
        articleDetails[id] != nil
            || inboxArticles.contains(where: { $0.id == id })
            || archiveArticles.contains(where: { $0.id == id })
    }

    private func clearProgress(for articleId: String) {
        readingProgress.removeValue(forKey: articleId)
        persistedProgress.removeValue(forKey: articleId)
        transientProgress.removeValue(forKey: articleId)
    }

    private func resetProgressForFreshArticle(_ articleId: String) {
        clearProgress(for: articleId)
        persistSideCache(archived: false, articles: inboxArticles)
        persistSideCache(archived: true, articles: archiveArticles)
    }

    func toggleArchive() async {
        guard let article = selectedArticle else { return }
        await setArchived(!article.archived, articleId: article.id)
    }

    func setArchived(_ archived: Bool, articleId: String) async {
        guard let article = selectedArticle, article.id == articleId else { return }
        let targetArchived = archived
        let locallyUpdated = article.updating(archived: targetArchived)
        selectedArticle = locallyUpdated
        articleDetails[article.id] = locallyUpdated
        articles = articles.map { summary in
            summary.id == article.id ? summary.updating(archived: targetArchived) : summary
        }
        moveSummaryBetweenSideCaches(summary(for: locallyUpdated))
        if self.archived != targetArchived {
            articles.removeAll { $0.id == article.id }
            selectedId = nil
        }
        saveCache()
        do {
            let updated = try await api.setArchived(targetArchived, articleId: article.id)
            articleDetails[article.id] = updated
            selectedArticle = selectedArticle?.id == article.id ? updated : selectedArticle
            saveCache()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleRead(_ summary: ArticleSummary) async {
        await setRead(summary.readAt == nil, articleId: summary.id)
    }

    func setRead(_ read: Bool, articleId: String) async {
        let targetReadAt: Date? = read ? Date() : nil
        articles = articles.compactMap { summary in
            guard summary.id == articleId else { return summary }
            let updated = summary.updating(readAt: .some(targetReadAt))
            return updated
        }
        if let selectedArticle, selectedArticle.id == articleId {
            self.selectedArticle = selectedArticle.updating(readAt: .some(targetReadAt))
        }
        if let detail = articleDetails[articleId] {
            articleDetails[articleId] = detail.updating(readAt: .some(targetReadAt))
        }
        saveCache()
        do {
            let updated = try await api.setRead(read, articleId: articleId)
            articleDetails[articleId] = updated
            selectedArticle = selectedArticle?.id == articleId ? updated : selectedArticle
            saveCache()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setArchived(_ targetArchived: Bool, summary: ArticleSummary) async {
        let removedIndex = articles.firstIndex(where: { $0.id == summary.id })
        let updatedSummary = summary.updating(archived: targetArchived)
        articles.removeAll { $0.id == summary.id }
        if let detail = articleDetails[summary.id] {
            articleDetails[summary.id] = detail.updating(archived: targetArchived)
        }
        moveSummaryBetweenSideCaches(updatedSummary)
        if selectedId == summary.id {
            selectedId = nil
            selectedArticle = nil
        }
        saveCache()
        do {
            let updated = try await api.setArchived(targetArchived, articleId: summary.id)
            articleDetails[summary.id] = updated
            saveCache()
        } catch {
            if let removedIndex, !articles.contains(where: { $0.id == summary.id }) {
                articles.insert(summary, at: min(removedIndex, articles.count))
            }
            moveSummaryBetweenSideCaches(summary)
            errorMessage = error.localizedDescription
        }
    }

    func archive(_ summary: ArticleSummary) async {
        await setArchived(true, summary: summary)
    }

    func unarchive(_ summary: ArticleSummary) async {
        await setArchived(false, summary: summary)
    }

    func delete(_ summary: ArticleSummary) async {
        let removedIndex = articles.firstIndex(where: { $0.id == summary.id })
        let removedDetail = articleDetails[summary.id]
        articles.removeAll { $0.id == summary.id }
        articleDetails.removeValue(forKey: summary.id)
        readingProgress.removeValue(forKey: summary.id)
        persistedProgress.removeValue(forKey: summary.id)
        transientProgress.removeValue(forKey: summary.id)
        if selectedId == summary.id {
            selectedId = nil
            selectedArticle = nil
        }
        saveCache()
        do {
            try await api.deleteArticle(id: summary.id)
        } catch {
            if let removedIndex, !articles.contains(where: { $0.id == summary.id }) {
                articles.insert(summary, at: min(removedIndex, articles.count))
            }
            if let removedDetail {
                articleDetails[summary.id] = removedDetail
            }
            saveCache()
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ article: Article) async {
        await delete(summary(for: article))
    }

    func setRead(_ read: Bool, article: Article) async {
        await setRead(read, articleId: article.id)
    }

    func progress(for articleId: String) -> Double {
        transientProgress[articleId] ?? readingProgress[articleId] ?? 0
    }

    func progressPercent(for articleId: String) -> Int {
        Int((progress(for: articleId) * 100).rounded())
    }

    // MARK: - Selection mode

    func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func enterSelectionMode(initial: String? = nil) {
        selectionMode = true
        selectedIds.removeAll()
        if let initial { selectedIds.insert(initial) }
    }

    func exitSelectionMode() {
        selectionMode = false
        selectedIds.removeAll()
    }

    func bulkArchive() async {
        let targets = articles.filter { selectedIds.contains($0.id) }
        let target = !archived
        for summary in targets {
            await setArchived(target, summary: summary)
        }
        exitSelectionMode()
    }

    func bulkDelete() async {
        let targets = articles.filter { selectedIds.contains($0.id) }
        for summary in targets {
            await delete(summary)
        }
        exitSelectionMode()
    }

    func bulkMarkRead(_ read: Bool) async {
        let targets = articles.filter { selectedIds.contains($0.id) }
        for summary in targets {
            await setRead(read, articleId: summary.id)
        }
        exitSelectionMode()
    }

    // MARK: - Exports

    func exportEPUB() async -> URL? {
        let summaries = articles.filter { selectedIds.contains($0.id) }
        guard !summaries.isEmpty else { return nil }
        var articleObjects: [Article] = []
        for summary in summaries {
            if let cached = articleDetails[summary.id] {
                articleObjects.append(cached)
            } else if let fetched = try? await api.article(id: summary.id) {
                articleDetails[summary.id] = fetched
                articleObjects.append(fetched)
            } else {
                articleObjects.append(Article(summary: summary))
            }
        }
        let title = summaries.count == 1 ? summaries[0].title : "Library export (\(summaries.count) articles)"
        let data = MinimalEPUB.build(title: title, articles: articleObjects)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-\(Int(Date().timeIntervalSince1970)).epub")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportHighlightsCSV() -> URL? {
        guard let account = tokenStore.email else { return nil }
        let stored = highlights.all(account: account)
        let allArticles = Dictionary(uniqueKeysWithValues: (inboxArticles + archiveArticles).map { ($0.id, $0) })
        var lines: [String] = ["article_title,article_url,site,highlight,created_at"]
        let formatter = ISO8601DateFormatter()
        for entry in stored {
            let summary = allArticles[entry.articleId]
            let title = summary?.title ?? ""
            let site = summary?.siteName ?? ""
            let urlString = (articleDetails[entry.articleId]?.url) ?? ""
            let row = [title, urlString, site, entry.text, formatter.string(from: entry.createdAt)]
                .map { csvEscape($0) }
                .joined(separator: ",")
            lines.append(row)
        }
        let csv = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("highlights-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func exportLibraryCSV() async -> URL? {
        guard let account = tokenStore.email else { return nil }
        do {
            async let inboxRequest = api.articles(archived: false, search: "")
            async let archiveRequest = api.articles(archived: true, search: "")
            let latestInbox = try await inboxRequest
            let latestArchive = try await archiveRequest
            inboxArticles = latestInbox
            archiveArticles = latestArchive
            persistSideCache(archived: false, articles: latestInbox)
            persistSideCache(archived: true, articles: latestArchive)
            if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                articles = archived ? latestArchive : latestInbox
            }
        } catch {
            // Fall back to local cache; exporting stale data is better than failing.
        }

        let allHighlights = highlights.all(account: account)
        let highlightCounts = Dictionary(grouping: allHighlights, by: \.articleId).mapValues(\.count)
        var lines = ["Title,Author,Publisher,URL,Tags,Word Count,In Queue,Favorited,Read,Highlight Count,Last Interaction Date,File Id"]
        let dateFormatter = Self.csvDateFormatter

        for summary in mergedLibrarySummaries() {
            let detail = await detailForExport(summary)
            let urlString = detail?.url ?? ""
            let wordCount = detail.map { wordCountString(for: $0) } ?? ""
            let tags = summary.labels.map(\.name).joined(separator: "; ")
            let inQueue = summary.archived ? "False" : "True"
            let read = summary.readAt == nil ? "False" : "True"
            let lastInteraction = summary.updatedAt ?? summary.readAt ?? summary.createdAt
            let row = [
                summary.title,
                summary.author ?? "",
                summary.siteName ?? "",
                urlString,
                tags,
                wordCount,
                inQueue,
                "",
                read,
                String(highlightCounts[summary.id] ?? 0),
                dateFormatter.string(from: lastInteraction),
                summary.id,
            ]
            .map { csvEscape($0) }
            .joined(separator: ",")
            lines.append(row)
        }

        let csv = lines.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func importMatterCSV(from url: URL) async -> MatterImportResult? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            return await importMatterCSV(data: try Data(contentsOf: url))
        } catch {
            loading = false
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func importMatterCSV(data: Data) async -> MatterImportResult? {
        do {
            errorMessage = nil
            loading = true
            defer { loading = false }

            let result = try await api.importMatterCSV(data: data)
            await refreshAll()
            if result.failed > 0, let lastError = result.lastError {
                errorMessage = "Matter import finished with \(result.failed) failure\(result.failed == 1 ? "" : "s"). Last error: \(lastError)"
            }
            return result
        } catch {
            loading = false
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func saveMatterRecord(_ record: MatterImportRecord, normalizedURL: URL, shouldArchive: Bool) async throws -> Article {
        do {
            let saved = try await api.save(url: normalizedURL.absoluteString)
            if isMatterPlaceholder(saved) {
                try? await api.deleteArticle(id: saved.id)
                return try await api.save(url: normalizedURL.absoluteString)
            }
            return saved
        } catch {
            throw ReaderAPIError.server("Could not fetch full article from Matter URL: \(error.localizedDescription)")
        }
    }

    private func isMatterPlaceholder(_ article: Article) -> Bool {
        let content = article.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return true }
        let normalized = content.lowercased()
        return normalized.contains("imported from matter")
            || normalized.contains("matter export does not always include")
            || normalized.contains("saved library history export")
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static var csvDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    private func mergedLibrarySummaries() -> [ArticleSummary] {
        var byId: [String: ArticleSummary] = [:]
        for summary in inboxArticles + archiveArticles + articles {
            byId[summary.id] = summary
        }
        return byId.values.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func detailForExport(_ summary: ArticleSummary) async -> Article? {
        if let detail = articleDetails[summary.id] {
            return detail
        }
        do {
            let fetched = try await api.article(id: summary.id)
            articleDetails[summary.id] = fetched
            return fetched
        } catch {
            return nil
        }
    }

    private func wordCountString(for article: Article) -> String {
        let text = ArticleTextExtractor.paragraphs(from: article.content).joined(separator: " ")
        let count = text
            .split { $0.isWhitespace || $0.isNewline }
            .filter { !$0.isEmpty }
            .count
        return count == 0 ? "" : String(count)
    }

    // MARK: - Highlights

    func storedHighlights(for articleId: String) -> [String] {
        guard let account = tokenStore.email else { return [] }
        return highlights.highlights(account: account, articleId: articleId).map { $0.text }
    }

    func addHighlight(_ text: String, articleId: String) {
        guard let account = tokenStore.email else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        highlights.add(account: account, articleId: articleId, text: trimmed)
        highlightsVersion &+= 1
    }

    func removeHighlight(_ text: String, articleId: String) {
        guard let account = tokenStore.email else { return }
        highlights.remove(account: account, articleId: articleId, text: text)
        highlightsVersion &+= 1
    }

    func replaceHighlights(_ texts: [String], articleId: String) {
        guard let account = tokenStore.email else { return }
        highlights.replace(account: account, articleId: articleId, highlights: texts)
        highlightsVersion &+= 1
    }

    func summary(for article: Article) -> ArticleSummary {
        if let summary = articles.first(where: { $0.id == article.id }) {
            return summary
        }
        return ArticleSummary(
            id: article.id,
            title: article.title,
            author: article.author,
            description: article.description,
            siteName: article.siteName,
            image: nil,
            favicon: nil,
            publishedAt: article.publishedAt,
            archived: article.archived,
            readAt: article.readAt,
            ttr: article.ttr,
            createdAt: Date(),
            updatedAt: nil,
            labels: article.labels
        )
    }

    func articleURL(for summary: ArticleSummary) -> URL {
        if let url = articleDetails[summary.id]?.url,
           let parsed = URL(string: url) {
            return parsed
        }
        return appBaseURL
    }

    func setProgress(_ value: Double, articleId: String, forcePersist: Bool = false, markReadOnCompletion: Bool = true) {
        let progress = max(0, min(1, value))
        let previous = self.progress(for: articleId)
        let crossedTop = progress <= 0.002 && previous > 0.002
        let crossedEnd = progress >= 0.995 && previous < 0.995
        guard forcePersist || abs(previous - progress) >= 0.03 || crossedTop || crossedEnd else { return }
        if forcePersist || crossedTop || crossedEnd {
            transientProgress.removeValue(forKey: articleId)
            readingProgress[articleId] = progress
        } else {
            transientProgress[articleId] = progress
        }
        if forcePersist || crossedTop || crossedEnd {
            persistedProgress[articleId] = progress
            saveCache()
        }
        if markReadOnCompletion,
           progress >= 0.995,
           selectedArticle?.id == articleId,
           selectedArticle?.readAt == nil,
           !markingReadArticleIds.contains(articleId) {
            markingReadArticleIds.insert(articleId)
            Task {
                await setRead(true, articleId: articleId)
                markingReadArticleIds.remove(articleId)
            }
        }
    }

    @discardableResult
    private func loadCachedArticles() -> CachedLibrary? {
        guard let account = tokenStore.email,
              let cached = cache.load(account: account, archived: archived, search: search) else {
            return nil
        }
        articleDetails.merge(cached.details) { current, _ in current }
        readingProgress.merge(cached.progress) { current, _ in current }
        persistedProgress.merge(cached.progress) { current, _ in current }
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            articles = cached.articles
        }
        if let selectedId, selectedArticle == nil {
            selectedArticle = articleDetails[selectedId]
        }
        return cached
    }

    private func saveCache() {
        guard let account = tokenStore.email,
              search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let isArchived = archived
        let articlesSnapshot = articles
        let detailsSnapshot = articleDetails
        let progressSnapshot = readingProgress
        cacheSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            ArticleCache.shared.save(
                account: account,
                archived: isArchived,
                articles: articlesSnapshot,
                details: detailsSnapshot,
                progress: progressSnapshot
            )
        }
        cacheSaveWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func moveSummaryBetweenSideCaches(_ summary: ArticleSummary) {
        inboxArticles.removeAll { $0.id == summary.id }
        archiveArticles.removeAll { $0.id == summary.id }
        if summary.archived {
            archiveArticles = mergeSummaries(existing: archiveArticles, incoming: [summary])
        } else {
            inboxArticles = mergeSummaries(existing: inboxArticles, incoming: [summary])
        }
        persistSideCache(archived: false, articles: inboxArticles)
        persistSideCache(archived: true, articles: archiveArticles)
    }

    private func mergeSummaries(existing: [ArticleSummary], incoming: [ArticleSummary]) -> [ArticleSummary] {
        guard !incoming.isEmpty else { return existing }

        var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for article in incoming {
            byId[article.id] = article
        }

        return byId.values.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

enum AuthMode {
    case login
    case register
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case system
    case offWhite
    case darkGray
    case oled

    var id: String { rawValue }

    static let displayOrder: [ReaderTheme] = [.offWhite, .darkGray, .oled, .system]

    static func load() -> ReaderTheme {
        guard let raw = UserDefaults.standard.string(forKey: "reader.native.theme"),
              let theme = ReaderTheme(rawValue: raw) else {
            return .system
        }
        return theme
    }

    var label: String {
        switch self {
        case .system: "System"
        case .offWhite: "Paper"
        case .darkGray: "Graphite"
        case .oled: "OLED"
        }
    }

    var background: Color {
        switch self {
        case .system:
            #if os(iOS)
            Color(uiColor: .systemBackground)
            #else
            Color(nsColor: .windowBackgroundColor)
            #endif
        case .offWhite: Color(red: 0.965, green: 0.965, blue: 0.955)
        case .darkGray: Color(red: 0.075, green: 0.075, blue: 0.08)
        case .oled: .black
        }
    }

    var panel: Color {
        switch self {
        case .system:
            #if os(iOS)
            Color(uiColor: .secondarySystemBackground).opacity(0.86)
            #else
            Color(nsColor: .controlBackgroundColor).opacity(0.86)
            #endif
        case .offWhite: Color.white.opacity(0.74)
        case .darkGray: Color(red: 0.13, green: 0.13, blue: 0.14).opacity(0.92)
        case .oled: Color(red: 0.035, green: 0.035, blue: 0.04).opacity(0.96)
        }
    }

    var settingsPanel: Color {
        switch self {
        case .system:
            #if os(iOS)
            Color(uiColor: .secondarySystemGroupedBackground)
            #else
            Color(nsColor: .controlBackgroundColor).opacity(0.94)
            #endif
        case .offWhite:
            Color.white.opacity(0.84)
        case .darkGray:
            Color(red: 0.16, green: 0.16, blue: 0.17).opacity(0.98)
        case .oled:
            Color(red: 0.105, green: 0.105, blue: 0.115).opacity(0.98)
        }
    }

    var glassBase: Color {
        switch self {
        case .system:
            #if os(iOS)
            Color(uiColor: .secondarySystemBackground).opacity(0.56)
            #else
            Color(nsColor: .controlBackgroundColor).opacity(0.56)
            #endif
        case .offWhite:
            Color.white.opacity(0.52)
        case .darkGray:
            Color(red: 0.08, green: 0.08, blue: 0.085).opacity(0.72)
        case .oled:
            Color.black.opacity(0.78)
        }
    }

    var glassLens: Color {
        switch self {
        case .system:
            #if os(iOS)
            Color(uiColor: .systemBackground).opacity(0.58)
            #else
            Color(nsColor: .windowBackgroundColor).opacity(0.58)
            #endif
        case .offWhite:
            Color.white.opacity(0.72)
        case .darkGray:
            Color.white.opacity(0.10)
        case .oled:
            Color.white.opacity(0.08)
        }
    }

    var selectedPanel: Color {
        switch self {
        case .system: Color.primary.opacity(0.08)
        case .offWhite: Color.black.opacity(0.08)
        case .darkGray, .oled: Color.white.opacity(0.13)
        }
    }

    var primary: Color {
        switch self {
        case .system: Color.primary
        case .offWhite: Color(red: 0.08, green: 0.08, blue: 0.085)
        case .darkGray, .oled: Color.white.opacity(0.95)
        }
    }

    var secondary: Color {
        switch self {
        case .system: Color.secondary
        case .offWhite: Color.black.opacity(0.56)
        case .darkGray, .oled: Color.white.opacity(0.62)
        }
    }

    var hairline: Color {
        switch self {
        case .system: Color.primary.opacity(0.12)
        case .offWhite: Color.black.opacity(0.10)
        case .darkGray, .oled: Color.white.opacity(0.12)
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .offWhite: .light
        case .darkGray, .oled: .dark
        }
    }

    var isDark: Bool {
        switch self {
        case .darkGray, .oled:
            true
        case .system, .offWhite:
            false
        }
    }

    func resolved(for colorScheme: ColorScheme) -> ReaderTheme {
        guard self == .system else { return self }
        return colorScheme == .dark ? .darkGray : .offWhite
    }
}

enum ReaderFont: String, CaseIterable, Identifiable {
    case system
    case serif
    case rounded
    case monospaced

    var id: String { rawValue }

    static func load() -> ReaderFont {
        guard let raw = UserDefaults.standard.string(forKey: "reader.native.font"),
              let font = ReaderFont(rawValue: raw) else {
            return .system
        }
        return font
    }

    var label: String {
        switch self {
        case .system: "SF"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .monospaced: "Mono"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }

    #if os(iOS)
    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .system:
            return .systemFont(ofSize: size, weight: .regular)
        case .serif:
            let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withDesign(.serif) ?? UIFontDescriptor()
            return UIFont(descriptor: descriptor, size: size)
        case .rounded:
            let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                .withDesign(.rounded) ?? UIFontDescriptor()
            return UIFont(descriptor: descriptor, size: size)
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
    #endif
}

struct ReaderRootView: View {
    @StateObject var store: ReaderStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if store.isSignedIn {
                LibraryView(store: store)
            } else {
                AuthView(store: store)
            }
        }
        .task {
            store.systemColorScheme = colorScheme
            store.bootstrap()
        }
        .onChange(of: colorScheme) { _, newValue in
            store.systemColorScheme = newValue
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .sharedArticleURLReceived)) { notification in
            guard let url = notification.object as? URL else { return }
            Task { await store.add(url: url.absoluteString) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            store.consumePendingShareURL()
            guard store.isSignedIn else { return }
            Task { await store.refreshAll() }
        }
        #endif
    }
}

struct AuthView: View {
    @ObservedObject var store: ReaderStore

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 8) {
                Text(store.authMode == .login ? "Sign in" : "Create account")
                    .font(.largeTitle.bold())
                Text("Save and read articles across your devices.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                if store.authMode == .register {
                    TextField("Name", text: $store.name)
                        .textContentType(.name)
                }
                TextField("Email", text: $store.email)
                    .textContentType(.emailAddress)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Password", text: $store.password)
                    .textContentType(store.authMode == .login ? .password : .newPassword)

                if let message = store.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await store.authenticate() }
                } label: {
                    Text(store.authMode == .login ? "Sign in" : "Create account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(store.authMode == .login ? "Create an account" : "Already have an account") {
                    store.authMode = store.authMode == .login ? .register : .login
                    store.errorMessage = nil
                }
                .buttonStyle(.plain)
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

            Spacer()
        }
        .padding(32)
    }
}

struct LibraryView: View {
    @ObservedObject var store: ReaderStore
    @State private var addURL = ""
    @State private var showingAdd = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            #if os(iOS)
            CompactLibraryView(store: store, showingAdd: $showingAdd)
            #else
            splitLayout
            #endif
        }
        .alert("Add article", isPresented: $showingAdd) {
            TextField("https://example.com/article", text: $addURL)
            Button("Save") {
                let value = addURL
                addURL = ""
                Task { await store.add(url: value) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem {
                Button {
                    store.signOut()
                } label: {
                    Label("Sign out", systemImage: "person.crop.circle.badge.xmark")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = store.errorMessage {
                Text(message)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding()
            }
        }
        .preferredColorScheme(store.themePreference.scheme)
    }

    private var splitLayout: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ArticleSidebar(store: store, showingAdd: $showingAdd)
                    .frame(width: sidebarWidth(for: proxy.size.width))
                    .background(store.theme.panel)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(store.theme.hairline)
                            .frame(width: 1)
                    }

                ZStack {
                    store.theme.background
                    if let article = store.selectedArticle {
                        ReaderDetailView(article: article, store: store) {
                            Task { await store.toggleArchive() }
                        } onDelete: {
                            store.selectedArticle = nil
                            store.selectedId = nil
                        }
                    } else {
                        ContentUnavailableView("Select an article", systemImage: "doc.text")
                            .foregroundStyle(store.theme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(store.theme.background)
        }
    }

    private func sidebarWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.28, 260), 380)
    }
}

#if os(iOS)
private enum CompactLibraryPane: Hashable {
    case inbox
    case archive
    case settings
}

struct CompactLibraryView: View {
    private enum SelectionCommand: Hashable {
        case archive
        case read
        case epub
        case delete
    }

    @ObservedObject var store: ReaderStore
    @Binding var showingAdd: Bool
    var onArticleTap: ((ArticleSummary) -> Void)? = nil
    @State private var pane: CompactLibraryPane = .inbox
    @State private var exportShareURL: URL?
    @State private var isExporting = false
    @State private var searchTask: Task<Void, Never>?
    @State private var activeSelectionCommand: SelectionCommand?
    @State private var navigationPath: [ArticleSummary] = []
    @State private var lastArticlePane: CompactLibraryPane = .inbox
    @State private var searchPresented = false
    @State private var contentScrolled = false
    @State private var searchFieldFocused = false
    @State private var searchFocusTask: Task<Void, Never>?
    @State private var searchDismissTask: Task<Void, Never>?
    @State private var pendingSearchDismiss = false
    @State private var tabBarRevealAllowed = true
    @State private var tabBarRevealTask: Task<Void, Never>?
    @Namespace private var selectionLoupeNamespace

    private var isSearching: Bool {
        !store.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchAvailable: Bool {
        !store.selectionMode && pane != .settings
    }

    private var resolvedColorScheme: ColorScheme {
        store.theme.isDark ? .dark : .light
    }

    private var tabBarVisibility: Visibility {
        store.selectionMode || !navigationPath.isEmpty || !tabBarRevealAllowed ? .hidden : .visible
    }

    private let headerHorizontalPadding: CGFloat = 22
    private let headerCommandTopPadding: CGFloat = 16
    private let headerCommandHeight: CGFloat = 44
    private let compactTitleOpticalOffset: CGFloat = 2
    private let compactCollapseThreshold: CGFloat = 36

    var body: some View {
        ZStack(alignment: .bottom) {
            store.theme.background.ignoresSafeArea()

            nativeTabShell
                .background(store.theme.background.ignoresSafeArea())

            if navigationPath.isEmpty && store.selectionMode && pane != .settings {
                bottomBarBackdrop
                selectionToolbar
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.selectionMode)
        .environment(\.colorScheme, resolvedColorScheme)
        .preferredColorScheme(resolvedColorScheme)
        .onChange(of: store.search) { _, _ in
            searchTask?.cancel()
            store.applyLocalSearch()
        }
        .onChange(of: searchPresented) { _, presented in
            if presented {
                focusSearchField()
            } else {
                searchFieldFocused = false
            }
        }
        .onChange(of: navigationPath.isEmpty) { _, isEmpty in
            updateTabBarReveal(forListVisible: isEmpty)
        }
        .sheet(item: Binding(get: {
            exportShareURL.map { ShareableURL(url: $0) }
        }, set: { newValue in
            exportShareURL = newValue?.url
        })) { wrapper in
            ActivityShareSheet(activityItems: [wrapper.url])
        }
    }

    @ViewBuilder
    private func navigationPane(_ contentPane: CompactLibraryPane) -> some View {
        NavigationStack(path: $navigationPath) {
            paneContent(contentPane)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ArticleSummary.self) { article in
                    CompactReaderDestination(summary: article, store: store)
                }
        }
    }

    private func activateSearchField() {
        guard searchAvailable else { return }
        pendingSearchDismiss = false
        searchDismissTask?.cancel()
        searchDismissTask = nil
        searchFieldFocused = true
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            searchPresented = true
        }
        focusSearchField()
    }

    private func focusSearchField() {
        searchFocusTask?.cancel()
        searchFocusTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, searchPresented, !pendingSearchDismiss else { return }
            searchFieldFocused = true
            try? await Task.sleep(nanoseconds: 45_000_000)
            guard !Task.isCancelled, searchPresented, !pendingSearchDismiss else { return }
            searchFieldFocused = true
        }
    }

    private func dismissSearch(clear: Bool = false) {
        searchFocusTask?.cancel()
        searchFocusTask = nil
        searchDismissTask?.cancel()
        searchDismissTask = nil
        pendingSearchDismiss = false
        searchFieldFocused = false
        forceKeyboardDismiss()
        if clear {
            store.search = ""
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            searchPresented = false
        }
    }

    @MainActor
    private func finishSearchDismiss() {
        guard pendingSearchDismiss else { return }
        guard !searchFieldFocused else { return }
        pendingSearchDismiss = false
        searchDismissTask?.cancel()
        searchDismissTask = nil
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            searchPresented = false
        }
    }

    private func handleSearchFieldDidEndEditing() {
        guard pendingSearchDismiss else { return }
        searchDismissTask?.cancel()
        finishSearchDismiss()
    }

    @MainActor
    private func forceKeyboardDismiss() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    private func prepareForArticleOpen() {
        searchFieldFocused = false
        tabBarRevealTask?.cancel()
        tabBarRevealTask = nil
        tabBarRevealAllowed = false
    }

    private func openArticle(_ article: ArticleSummary) {
        prepareForArticleOpen()
        Task { @MainActor in
            await store.prepareArticleForOpen(article)
            if let onArticleTap {
                onArticleTap(article)
            } else if navigationPath.last?.id != article.id {
                navigationPath.append(article)
            }
        }
    }

    private func clearSearchIfNeeded(leavingSearch oldPane: CompactLibraryPane, entering newPane: CompactLibraryPane) {
        guard newPane == .settings else { return }
        store.search = ""
    }

    private func updateTabBarReveal(forListVisible listVisible: Bool) {
        tabBarRevealTask?.cancel()
        tabBarRevealTask = nil

        guard listVisible else {
            tabBarRevealAllowed = false
            return
        }

        tabBarRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                tabBarRevealAllowed = true
            }
        }
    }

    private func refreshForSelectedLibraryPane(_ selectedPane: CompactLibraryPane) {
        switch selectedPane {
        case .inbox:
            lastArticlePane = .inbox
            store.setArchiveMode(false)
            Task { await store.refreshAll() }
        case .archive:
            lastArticlePane = .archive
            store.setArchiveMode(true)
            Task { await store.refreshAll() }
        case .settings:
            store.selectionMode = false
            store.selectedIds.removeAll()
        }
    }

    private func animatePaneSelection(_ selectedPane: CompactLibraryPane) {
        pane = selectedPane
    }

    private func prepareForPaneSelection(_ selectedPane: CompactLibraryPane) -> CompactLibraryPane {
        let oldPane = pane
        navigationPath.removeAll()
        return oldPane
    }

    private func finishPaneSelection(from oldPane: CompactLibraryPane, to selectedPane: CompactLibraryPane) {
        dismissSearch(clear: false)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            contentScrolled = false
        }
        clearSearchIfNeeded(leavingSearch: oldPane, entering: selectedPane)
        refreshForSelectedLibraryPane(selectedPane)
    }

    private func updatePaneSelection(_ selectedPane: CompactLibraryPane) {
        guard pane != selectedPane else { return }

        let oldPane = prepareForPaneSelection(selectedPane)
        animatePaneSelection(selectedPane)
        finishPaneSelection(from: oldPane, to: selectedPane)
    }

    @ViewBuilder
    private var nativeTabShell: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: Binding(get: { pane }, set: { updatePaneSelection($0) })) {
                Tab("Inbox", systemImage: "tray", value: CompactLibraryPane.inbox) {
                    navigationPane(.inbox)
                }
                Tab("Archive", systemImage: "archivebox", value: CompactLibraryPane.archive) {
                    navigationPane(.archive)
                }
                Tab("Settings", systemImage: "gearshape", value: CompactLibraryPane.settings) {
                    navigationPane(.settings)
                }
            }
            .toolbar(tabBarVisibility, for: .tabBar)
        } else {
            TabView(selection: Binding(get: { pane }, set: { updatePaneSelection($0) })) {
                navigationPane(.inbox)
                    .tabItem { Label("Inbox", systemImage: "tray") }
                    .tag(CompactLibraryPane.inbox)
                navigationPane(.archive)
                    .tabItem { Label("Archive", systemImage: "archivebox") }
                    .tag(CompactLibraryPane.archive)
                navigationPane(.settings)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(CompactLibraryPane.settings)
            }
            .toolbar(tabBarVisibility, for: .tabBar)
        }
    }

    @ViewBuilder
    private func paneContent(_ contentPane: CompactLibraryPane) -> some View {
        ZStack(alignment: .top) {
            if contentPane == .settings {
                LibrarySettingsPane(
                    store: store,
                    exportShareURL: $exportShareURL,
                    onScrolledChange: updateContentScrolled
                )
            } else {
                articleList(for: contentPane)
            }

            if searchPresented && contentPane != .settings {
                headerBar(for: contentPane)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(3)
            }

            if contentPane != .settings && !store.selectionMode && !searchPresented {
                listBottomFade
                    .zIndex(2)
            }

            if contentScrolled && !searchPresented {
                compactTopChrome(for: contentPane)
                    .transition(.opacity)
                    .zIndex(4)
            }

            headerCommandOverlay(for: contentPane)
                .zIndex(5)
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.9), value: contentScrolled)
        .animation(.spring(response: 0.30, dampingFraction: 0.9), value: searchPresented)
        .background(store.theme.background.ignoresSafeArea())
        .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: store.selectionMode ? 112 : 0)
        }
    }

    private func selectPane(_ newPane: CompactLibraryPane) {
        updatePaneSelection(newPane)
    }

    private func updateContentScrolled(_ scrolled: Bool) {
        guard contentScrolled != scrolled else { return }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.9)) {
            contentScrolled = scrolled
        }
    }

    @ViewBuilder
    private var listBottomFade: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: store.theme.background.opacity(0.56), location: 0.58),
                        .init(color: store.theme.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 74)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var bottomBarBackdrop: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: store.theme.background.opacity(0.82), location: 0.38),
                        .init(color: store.theme.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 146 + proxy.safeAreaInsets.bottom)
                .padding(.bottom, -proxy.safeAreaInsets.bottom)
            }
        }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var topBarBackdrop: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: store.theme.background, location: 0),
                    .init(color: store.theme.background, location: 0.46),
                    .init(color: store.theme.background.opacity(0.94), location: 0.68),
                    .init(color: store.theme.background.opacity(0.68), location: 0.86),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 178)
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func compactTopChrome(for contentPane: CompactLibraryPane) -> some View {
        ZStack(alignment: .top) {
            topBarBackdrop
            ZStack {
                Text(headerTitle(for: contentPane))
                    .font(.system(.title3, design: .default, weight: .bold))
                    .foregroundStyle(store.theme.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: headerCommandHeight)
            .padding(.horizontal, headerHorizontalPadding)
            .padding(.top, headerCommandTopPadding)
            .offset(y: compactTitleOpticalOffset)
        }
        .frame(height: 178)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func headerBar(for contentPane: CompactLibraryPane) -> some View {
        Group {
            if searchPresented && contentPane != .settings {
                searchHeader
            } else {
                listHeaderBar(for: contentPane)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func listHeaderBar(for contentPane: CompactLibraryPane) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle(for: contentPane))
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .foregroundStyle(store.theme.primary)
                Text(headerSubtitle(for: contentPane))
                    .font(.title3)
                    .foregroundStyle(store.theme.secondary)
            }
            Spacer()
            if store.selectionMode {
                Button("Done") { store.exitSelectionMode() }
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(store.theme.primary)
            } else if contentPane != .settings {
                Color.clear
                    .frame(width: 92, height: 44)
            } else {
                Color.clear
                    .frame(width: 1, height: 44)
            }
        }
    }

    @ViewBuilder
    private var searchHeader: some View {
        HStack(spacing: 10) {
            #if os(iOS)
            NativeSearchField(
                text: $store.search,
                theme: store.theme,
                isFirstResponder: $searchFieldFocused,
                onDidEndEditing: handleSearchFieldDidEndEditing
            )
            .frame(height: 42)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .readerGlassBarBackground(theme: store.theme)
            #else
            TextField("Search", text: $store.search)
                .textFieldStyle(.roundedBorder)
                .frame(height: 42)
            #endif

            Button {
                dismissSearch(clear: true)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
                    .accessibilityLabel("Cancel search")
            }
            .foregroundStyle(store.theme.primary)
            .readerStableGlassCircle(theme: store.theme)
        }
    }

    @ViewBuilder
    private func headerCommandOverlay(for contentPane: CompactLibraryPane) -> some View {
        if contentPane != .settings && !store.selectionMode && !searchPresented {
            HStack {
                Spacer(minLength: 0)
                headerCommandGroup
            }
            .padding(.horizontal, headerHorizontalPadding)
            .padding(.top, headerCommandTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var headerCommandGroup: some View {
        HStack(spacing: 2) {
            Button {
                activateSearchField()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                    .accessibilityLabel("Search")
            }
            .buttonStyle(.plain)
            .foregroundStyle(searchPresented || isSearching ? Color.accentColor : store.theme.primary)
            .readerGlassPressAnimation()

            Menu {
                Button {
                    store.enterSelectionMode()
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                Button {
                    showingAdd = true
                } label: {
                    Label("Add article", systemImage: "plus")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                    .accessibilityLabel("More")
            }
            .foregroundStyle(store.theme.primary)
            .environment(\.colorScheme, resolvedColorScheme)
            .preferredColorScheme(resolvedColorScheme)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .readerGlassBarBackground(theme: store.theme)
    }

    private func headerTitle(for contentPane: CompactLibraryPane) -> String {
        if store.selectionMode {
            return "\(store.selectedIds.count) selected"
        }
        if contentPane == .settings {
            return "Settings"
        }
        if isSearching {
            return "Search"
        }
        return store.archived ? "Archive" : "Inbox"
    }

    private func headerSubtitle(for contentPane: CompactLibraryPane) -> String {
        if contentPane == .settings {
            return "Reading and exports"
        }
        if isSearching {
            return "\(store.articles.count) result\(store.articles.count == 1 ? "" : "s")"
        }
        return "\(store.articles.count) article\(store.articles.count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private func articleList(for contentPane: CompactLibraryPane) -> some View {
        #if os(iOS)
        NativeArticleTable(
            articles: store.articles,
            showHeader: true,
            header: AnyView(
                listHeaderBar(for: contentPane)
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .padding(.bottom, 24)
            ),
            headerHidden: searchPresented,
            selectedIds: store.selectedIds,
            selectionMode: store.selectionMode,
            theme: store.theme,
            isSearching: isSearching,
            progress: { store.progress(for: $0) },
            onTap: { article in
                openArticle(article)
            },
            onToggleSelection: { store.toggleSelection($0) },
            onEnterSelection: { store.enterSelectionMode(initial: $0) },
            onArchive: { article in
                Task {
                    if article.archived {
                        await store.unarchive(article)
                    } else {
                        await store.archive(article)
                    }
                }
            },
            onToggleRead: { article in
                Task { await store.toggleRead(article) }
            },
            onDelete: { article in
                Task { await store.delete(article) }
            },
            onShare: { article in
                exportShareURL = store.articleURL(for: article)
            },
            onScrolledChange: updateContentScrolled
        )
        #else
        List {
            listHeaderBar(for: contentPane)
                .opacity(searchPresented ? 0 : 1)
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .allowsHitTesting(false)

            ForEach(store.articles) { article in
                articleRow(for: article)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 76)
        .listRowSpacing(6)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .contentMargins(.bottom, 0, for: .scrollIndicators)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .readerPaneScrollObserver(threshold: compactCollapseThreshold, updateContentScrolled)
        #endif
    }

    @ViewBuilder
    private func articleRow(for article: ArticleSummary) -> some View {
        let row = ArticleRow(
            article: article,
            selected: store.selectionMode && store.selectedIds.contains(article.id),
            theme: store.theme,
            progress: store.progress(for: article.id),
            showsModeBadge: isSearching,
            selecting: store.selectionMode
        )

        Group {
            if store.selectionMode {
                row
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.toggleSelection(article.id)
                    }
            } else if onArticleTap != nil {
                row
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openArticle(article)
                    }
            } else {
                row
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openArticle(article)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        openArticle(article)
                    }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contextMenu {
            articleMenu(article)
        }
        .environment(\.colorScheme, resolvedColorScheme)
        .preferredColorScheme(resolvedColorScheme)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task {
                    if article.archived {
                        await store.unarchive(article)
                    } else {
                        await store.archive(article)
                    }
                }
            } label: {
                Label(article.archived ? "Unarchive" : "Archive", systemImage: article.archived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(.indigo)
            Button {
                Task { await store.toggleRead(article) }
            } label: {
                Label(article.readAt == nil ? "Read" : "Unread", systemImage: article.readAt == nil ? "checkmark.circle" : "circle")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await store.delete(article) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    @ViewBuilder
    private var selectionToolbar: some View {
        let count = store.selectedIds.count
        HStack(spacing: 8) {
            selectionButton(
                command: .archive,
                systemName: "archivebox",
                title: store.archived ? "Unarchive" : "Archive",
                disabled: count == 0
            ) {
                Task { await store.bulkArchive() }
            }
            selectionButton(command: .read, systemName: "checkmark.circle", title: "Mark Read", disabled: count == 0) {
                Task { await store.bulkMarkRead(true) }
            }
            selectionButton(command: .epub, systemName: "book.closed", title: "Make EPUB", disabled: count == 0 || isExporting) {
                Task {
                    isExporting = true
                    if let url = await store.exportEPUB() {
                        exportShareURL = url
                    }
                    isExporting = false
                }
            }
            selectionButton(command: .delete, systemName: "trash", title: "Delete", disabled: count == 0, destructive: true) {
                Task { await store.bulkDelete() }
            }
        }
        .font(.system(size: 16, weight: .semibold, design: .default))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .readerGlassBarBackground(theme: store.theme)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func selectionButton(
        command: SelectionCommand,
        systemName: String,
        title: String,
        disabled: Bool,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(destructive ? Color.red : store.theme.primary)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
                .accessibilityLabel(title)
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .background(selectionLoupe(for: command))
        .simultaneousGesture(selectionPress(command))
    }

    @ViewBuilder
    private func selectionLoupe(for command: SelectionCommand) -> some View {
        if activeSelectionCommand == command {
            Circle()
                .fill(.clear)
                .matchedGeometryEffect(id: "selection-command-loupe", in: selectionLoupeNamespace)
                .readerGlassBarBackground(theme: store.theme)
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)
        }
    }

    private func selectionPress(_ command: SelectionCommand) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard activeSelectionCommand != command else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                    activeSelectionCommand = command
                }
            }
            .onEnded { _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        if activeSelectionCommand == command {
                            activeSelectionCommand = nil
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private func articleMenu(_ article: ArticleSummary) -> some View {
        Button {
            store.enterSelectionMode(initial: article.id)
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        Button {
            Task { await store.toggleRead(article) }
        } label: {
            Label(article.readAt == nil ? "Mark as Read" : "Mark as Unread", systemImage: article.readAt == nil ? "checkmark.circle" : "circle")
        }
        Button {
            Task {
                if article.archived {
                    await store.unarchive(article)
                } else {
                    await store.archive(article)
                }
            }
        } label: {
            Label(article.archived ? "Unarchive" : "Archive", systemImage: article.archived ? "tray.and.arrow.up" : "archivebox")
        }
        ShareLink(item: store.articleURL(for: article)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button(role: .destructive) {
            Task { await store.delete(article) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

private struct ShareableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

#if os(iOS)
struct NativeArticleTable: UIViewControllerRepresentable {
    let articles: [ArticleSummary]
    let showHeader: Bool
    let header: AnyView
    let headerHidden: Bool
    let selectedIds: Set<String>
    let selectionMode: Bool
    let theme: ReaderTheme
    let isSearching: Bool
    let progress: (String) -> Double
    let onTap: (ArticleSummary) -> Void
    let onToggleSelection: (String) -> Void
    let onEnterSelection: (String) -> Void
    let onArchive: (ArticleSummary) -> Void
    let onToggleRead: (ArticleSummary) -> Void
    let onDelete: (ArticleSummary) -> Void
    let onShare: (ArticleSummary) -> Void
    let onScrolledChange: (Bool) -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.update(with: self)
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(with: self)
    }

    private var reloadSignature: String {
        let articleSignature = articles.map { article in
            [
                article.id,
                article.title,
                article.archived ? "1" : "0",
                article.readAt == nil ? "0" : "1",
                "\(Int((progress(article.id) * 1000).rounded()))"
            ].joined(separator: ":")
        }
        .joined(separator: "|")

        return [
            articleSignature,
            showHeader ? "header" : "no-header",
            selectedIds.sorted().joined(separator: ","),
            selectionMode ? "selecting" : "reading",
            theme.rawValue,
            isSearching ? "search" : "normal"
        ].joined(separator: "#")
    }

    final class Controller: UIViewController, UITableViewDataSource, UITableViewDelegate {
        private let tableView = UITableView(frame: .zero, style: .plain)
        private var model: NativeArticleTable?
        private var lastReloadSignature: String?
        private var lastHeaderHidden: Bool?
        private var lastScrolledState = false
        private let collapseThreshold: CGFloat = 36

        override func viewDidLoad() {
            super.viewDidLoad()

            view.backgroundColor = .clear
            tableView.translatesAutoresizingMaskIntoConstraints = false
            tableView.backgroundColor = .clear
            tableView.separatorStyle = .none
            tableView.rowHeight = UITableView.automaticDimension
            tableView.estimatedRowHeight = 82
            tableView.keyboardDismissMode = .interactive
            tableView.contentInsetAdjustmentBehavior = .never
            tableView.showsVerticalScrollIndicator = true
            tableView.dataSource = self
            tableView.delegate = self
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: "header")

            view.addSubview(tableView)
            NSLayoutConstraint.activate([
                tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        func update(with model: NativeArticleTable) {
            self.model = model
            view.backgroundColor = UIColor(model.theme.background)
            tableView.backgroundColor = .clear
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
            tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

            let signature = model.reloadSignature
            let headerVisibilityChanged = lastHeaderHidden != model.headerHidden
            lastHeaderHidden = model.headerHidden
            guard signature != lastReloadSignature else {
                if headerVisibilityChanged {
                    updateVisibleHeaderCell(with: model)
                }
                return
            }
            lastReloadSignature = signature
            UIView.performWithoutAnimation {
                tableView.reloadData()
                tableView.layoutIfNeeded()
            }
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            1
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            guard let model else { return 0 }
            return model.articles.count + (model.showHeader ? 1 : 0)
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            guard let model else { return UITableViewCell() }

            if model.showHeader && indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "header", for: indexPath)
                configureHeaderCell(cell, with: model)
                return cell
            }

            let article = article(at: indexPath, in: model)
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            configureBaseCell(cell)
            resetSwipeState(for: cell)
            cell.contentConfiguration = UIHostingConfiguration {
                ArticleRow(
                    article: article,
                    selected: model.selectionMode && model.selectedIds.contains(article.id),
                    theme: model.theme,
                    progress: model.progress(article.id),
                    showsModeBadge: model.isSearching,
                    selecting: model.selectionMode
                )
                .background(Color.clear)
            }
            .margins(.all, 0)
            return cell
        }

        private func configureBaseCell(_ cell: UITableViewCell) {
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.selectedBackgroundView = UIView()
            cell.selectionStyle = .none
            cell.preservesSuperviewLayoutMargins = false
            cell.layoutMargins = .zero
            cell.separatorInset = .zero
            cell.clipsToBounds = false
            cell.contentView.clipsToBounds = false
        }

        private func configureHeaderCell(_ cell: UITableViewCell, with model: NativeArticleTable) {
            configureBaseCell(cell)
            cell.contentConfiguration = UIHostingConfiguration {
                model.header
                    .opacity(model.headerHidden ? 0 : 1)
                    .animation(nil, value: model.headerHidden)
                    .background(Color.clear)
            }
            .margins(.all, 0)
        }

        private func updateVisibleHeaderCell(with model: NativeArticleTable) {
            guard model.showHeader else { return }
            let headerIndexPath = IndexPath(row: 0, section: 0)
            guard let cell = tableView.cellForRow(at: headerIndexPath) else { return }
            UIView.performWithoutAnimation {
                configureHeaderCell(cell, with: model)
                cell.layoutIfNeeded()
                tableView.layoutIfNeeded()
            }
        }

        private func resetSwipeState(for cell: UITableViewCell) {
            cell.transform = .identity
            cell.contentView.transform = .identity
            cell.layer.masksToBounds = false
            cell.contentView.layer.masksToBounds = false
            cell.subviews.forEach { subview in
                subview.clipsToBounds = false
                subview.layer.masksToBounds = false
            }
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            guard let model, isArticleRow(indexPath, in: model) else { return }
            let article = article(at: indexPath, in: model)
            if model.selectionMode {
                model.onToggleSelection(article.id)
            } else {
                model.onTap(article)
            }
        }

        func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let model, isArticleRow(indexPath, in: model) else { return nil }
            let article = article(at: indexPath, in: model)

            let archive = UIContextualAction(style: .normal, title: article.archived ? "Unarchive" : "Archive") { _, _, completion in
                model.onArchive(article)
                completion(true)
            }
            archive.image = UIImage(systemName: article.archived ? "tray.and.arrow.up" : "archivebox")
            archive.backgroundColor = .systemIndigo

            let read = UIContextualAction(style: .normal, title: article.readAt == nil ? "Read" : "Unread") { _, _, completion in
                model.onToggleRead(article)
                completion(true)
            }
            read.image = UIImage(systemName: article.readAt == nil ? "checkmark.circle" : "circle")
            read.backgroundColor = .systemGreen

            let configuration = UISwipeActionsConfiguration(actions: [archive, read])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            guard let model, isArticleRow(indexPath, in: model) else { return nil }
            let article = article(at: indexPath, in: model)

            let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
                model.onDelete(article)
                completion(true)
            }
            delete.image = UIImage(systemName: "trash")
            delete.backgroundColor = .systemRed

            let configuration = UISwipeActionsConfiguration(actions: [delete])
            configuration.performsFirstActionWithFullSwipe = true
            return configuration
        }

        func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
            UIView.performWithoutAnimation {
                tableView.visibleCells.forEach(resetSwipeState(for:))
                tableView.layoutIfNeeded()
            }
        }

        func tableView(
            _ tableView: UITableView,
            contextMenuConfigurationForRowAt indexPath: IndexPath,
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard let model, isArticleRow(indexPath, in: model) else { return nil }
            let article = article(at: indexPath, in: model)

            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let select = UIAction(title: "Select", image: UIImage(systemName: "checkmark.circle")) { _ in
                    model.onEnterSelection(article.id)
                }
                let read = UIAction(
                    title: article.readAt == nil ? "Mark as Read" : "Mark as Unread",
                    image: UIImage(systemName: article.readAt == nil ? "checkmark.circle" : "circle")
                ) { _ in
                    model.onToggleRead(article)
                }
                let archive = UIAction(
                    title: article.archived ? "Unarchive" : "Archive",
                    image: UIImage(systemName: article.archived ? "tray.and.arrow.up" : "archivebox")
                ) { _ in
                    model.onArchive(article)
                }
                let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    model.onShare(article)
                }
                let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    model.onDelete(article)
                }
                return UIMenu(children: [select, read, archive, share, delete])
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let model else { return }
            let scrolled = scrollView.contentOffset.y > collapseThreshold
            guard scrolled != lastScrolledState else { return }
            lastScrolledState = scrolled
            model.onScrolledChange(scrolled)
        }

        private func isArticleRow(_ indexPath: IndexPath, in model: NativeArticleTable) -> Bool {
            indexPath.row >= (model.showHeader ? 1 : 0)
        }

        private func article(at indexPath: IndexPath, in model: NativeArticleTable) -> ArticleSummary {
            model.articles[indexPath.row - (model.showHeader ? 1 : 0)]
        }
    }
}
#endif

struct ActivityShareSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> ActivityPresenterViewController {
        let controller = ActivityPresenterViewController()
        controller.activityItems = activityItems
        controller.onFinish = { dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: ActivityPresenterViewController, context: Context) {
        uiViewController.activityItems = activityItems
        uiViewController.onFinish = { dismiss() }
    }

    final class ActivityPresenterViewController: UIViewController {
        var activityItems: [Any] = []
        var onFinish: (() -> Void)?
        private var didPresent = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            presentIfNeeded()
        }

        private func presentIfNeeded() {
            guard !didPresent else { return }
            guard view.window != nil else { return }
            guard !activityItems.isEmpty else {
                onFinish?()
                return
            }

            didPresent = true
            let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
            controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
                self?.onFinish?()
            }
            if let popover = controller.popoverPresentationController {
                popover.sourceView = view
                popover.sourceRect = CGRect(
                    x: view.bounds.midX,
                    y: view.bounds.midY,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = []
            }
            present(controller, animated: true)
        }
    }
}

struct LibrarySettingsPane: View {
    @ObservedObject var store: ReaderStore
    @Binding var exportShareURL: URL?
    var onScrolledChange: (Bool) -> Void = { _ in }
    @State private var showingMatterImporter = false
    @State private var importingMatter = false
    @State private var matterImportMessage: String?

    private var resolvedColorScheme: ColorScheme {
        store.theme.isDark ? .dark : .light
    }

    var body: some View {
        Form {
            Section {
                settingsHeader
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("Appearance") {
                SettingsMenuRow(title: "Theme", value: store.themePreference.label, theme: store.theme) {
                    ForEach(ReaderTheme.displayOrder) { theme in
                        Button {
                            store.setTheme(theme)
                        } label: {
                            if theme == store.themePreference {
                                Label(theme.label, systemImage: "checkmark")
                            } else {
                                Text(theme.label)
                            }
                        }
                    }
                }

                SettingsMenuRow(title: "Font", value: store.readerFont.label, theme: store.theme) {
                    ForEach(ReaderFont.allCases) { font in
                        Button {
                            store.setReaderFont(font)
                        } label: {
                            if font == store.readerFont {
                                Label(font.label, systemImage: "checkmark")
                            } else {
                                Text(font.label)
                            }
                        }
                    }
                }
            }
            .listRowBackground(store.theme.settingsPanel)
            .foregroundStyle(store.theme.primary)

            Section("Reader") {
                HStack {
                    Text("Font size")
                        .foregroundStyle(store.theme.primary)
                    Spacer()
                    Text("\(Int(store.textSize))")
                        .foregroundStyle(store.theme.secondary)
                }
                Slider(value: Binding(get: { store.textSize }, set: { store.setTextSize($0) }), in: 15...30, step: 1)

                HStack {
                    Text("Line spacing")
                        .foregroundStyle(store.theme.primary)
                    Spacer()
                    Text("\(Int(store.lineSpacing))")
                        .foregroundStyle(store.theme.secondary)
                }
                Slider(value: Binding(get: { store.lineSpacing }, set: { store.setLineSpacing($0) }), in: 2...18, step: 1)
            }
            .listRowBackground(store.theme.settingsPanel)

            Section("Highlights") {
                Button {
                    if let url = store.exportHighlightsCSV() {
                        exportShareURL = url
                    }
                } label: {
                    Label("Export highlights CSV", systemImage: "square.and.arrow.up")
                        .foregroundStyle(store.theme.primary)
                }
            }
            .listRowBackground(store.theme.settingsPanel)

            Section("Library") {
                Button {
                    matterImportMessage = nil
                    showingMatterImporter = true
                } label: {
                    Label(importingMatter ? "Importing Matter CSV..." : "Import Matter CSV", systemImage: "square.and.arrow.down")
                        .foregroundStyle(store.theme.primary)
                }
                .disabled(importingMatter)

                Button {
                    Task {
                        if let url = await store.exportLibraryCSV() {
                            exportShareURL = url
                        }
                    }
                } label: {
                    Label("Export library CSV", systemImage: "tablecells")
                        .foregroundStyle(store.theme.primary)
                }

                if let matterImportMessage {
                    Text(matterImportMessage)
                        .font(.footnote)
                        .foregroundStyle(store.theme.secondary)
                }
            }
            .listRowBackground(store.theme.settingsPanel)

            Section {
                Button(role: .destructive) {
                    store.signOut()
                } label: {
                    Label("Sign out", systemImage: "person.crop.circle.badge.xmark")
                }
            } footer: {
                if let email = store.tokenStore.email {
                    Text("Signed in as \(email)")
                }
            }
            .listRowBackground(store.theme.settingsPanel)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .contentMargins(.bottom, 0, for: .scrollIndicators)
        .background(store.theme.background)
        .foregroundStyle(store.theme.primary)
        .tint(store.theme.primary)
        .listSectionSeparatorTint(store.theme.hairline)
        .readerPaneScrollObserver(onScrolledChange)
        .environment(\.colorScheme, resolvedColorScheme)
        .preferredColorScheme(resolvedColorScheme)
        .fileImporter(
            isPresented: $showingMatterImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data]
        ) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                do {
                    let data = try Data(contentsOf: url)
                    importingMatter = true
                    matterImportMessage = nil
                    Task {
                        if let result = await store.importMatterCSV(data: data) {
                            matterImportMessage = result.summary
                        } else {
                            matterImportMessage = store.errorMessage ?? "Matter import failed."
                        }
                        importingMatter = false
                    }
                } catch {
                    importingMatter = false
                    store.errorMessage = error.localizedDescription
                    matterImportMessage = error.localizedDescription
                }
            case .failure(let error):
                matterImportMessage = error.localizedDescription
            }
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(.largeTitle, design: .default, weight: .bold))
                .foregroundStyle(store.theme.primary)
            Text("Reading and exports")
                .font(.title3)
                .foregroundStyle(store.theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }
}

struct NativeSearchField: UIViewRepresentable {
    @Binding var text: String
    let theme: ReaderTheme
    @Binding var isFirstResponder: Bool
    var onDidEndEditing: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            isFirstResponder: $isFirstResponder,
            onDidEndEditing: onDidEndEditing
        )
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.placeholder = "Search"
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.returnKeyType = .search
        searchBar.enablesReturnKeyAutomatically = false
        searchBar.backgroundImage = UIImage()
        searchBar.isTranslucent = true
        searchBar.setShowsCancelButton(false, animated: false)
        applyTheme(to: searchBar)
        DispatchQueue.main.async {
            context.coordinator.applyFocusState(to: searchBar)
        }
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        if searchBar.text != text {
            searchBar.text = text
        }
        applyTheme(to: searchBar)
        if searchBar.showsCancelButton {
            searchBar.setShowsCancelButton(false, animated: false)
        }
        context.coordinator.onDidEndEditing = onDidEndEditing
        context.coordinator.applyFocusState(to: searchBar)
    }

    private func applyTheme(to searchBar: UISearchBar) {
        let dark = theme.isDark
        let textColor = dark ? UIColor.white.withAlphaComponent(0.95) : UIColor.label
        let placeholderColor = dark ? UIColor.white.withAlphaComponent(0.52) : UIColor.secondaryLabel

        UIView.performWithoutAnimation {
            searchBar.overrideUserInterfaceStyle = dark ? .dark : .light
            searchBar.barTintColor = .clear
            searchBar.backgroundColor = .clear
            searchBar.isTranslucent = true
            searchBar.searchTextField.overrideUserInterfaceStyle = dark ? .dark : .light
            searchBar.searchTextField.keyboardAppearance = dark ? .dark : .light
            searchBar.searchTextField.textColor = textColor
            searchBar.searchTextField.defaultTextAttributes = [
                .foregroundColor: textColor,
                .font: UIFont.preferredFont(forTextStyle: .body),
            ]
            searchBar.searchTextField.tintColor = .systemBlue
            searchBar.searchTextField.font = UIFont.preferredFont(forTextStyle: .body)
            searchBar.searchTextField.adjustsFontForContentSizeCategory = true
            searchBar.searchTextField.layer.cornerCurve = .continuous
            searchBar.searchTextField.layer.cornerRadius = 18
            searchBar.searchTextField.layer.borderWidth = 0
            searchBar.searchTextField.clipsToBounds = false
            searchBar.searchTextField.borderStyle = .none
            searchBar.searchTextField.backgroundColor = .clear
            searchBar.searchTextField.textContentType = nil
            searchBar.searchTextField.clearButtonMode = .whileEditing
            searchBar.searchTextField.attributedPlaceholder = NSAttributedString(
                string: "Search",
                attributes: [.foregroundColor: placeholderColor]
            )
            searchBar.searchTextField.leftView?.tintColor = placeholderColor
            searchBar.searchTextField.rightView?.tintColor = placeholderColor
            searchBar.subviews.forEach { subview in
                subview.overrideUserInterfaceStyle = dark ? .dark : .light
                subview.backgroundColor = .clear
            }
            searchBar.layoutIfNeeded()
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var text: Binding<String>
        var isFirstResponder: Binding<Bool>
        var onDidEndEditing: (() -> Void)?
        private var focusToken = 0

        init(
            text: Binding<String>,
            isFirstResponder: Binding<Bool>,
            onDidEndEditing: (() -> Void)?
        ) {
            self.text = text
            self.isFirstResponder = isFirstResponder
            self.onDidEndEditing = onDidEndEditing
        }

        func applyFocusState(to searchBar: UISearchBar) {
            if isFirstResponder.wrappedValue {
                guard !searchBar.searchTextField.isFirstResponder else { return }
                focusToken += 1
                requestFocus(on: searchBar, token: focusToken, remainingAttempts: 8)
            } else if searchBar.searchTextField.isFirstResponder {
                focusToken += 1
                searchBar.searchTextField.resignFirstResponder()
            }
        }

        private func requestFocus(on searchBar: UISearchBar, token: Int, remainingAttempts: Int) {
            DispatchQueue.main.async { [weak self, weak searchBar] in
                guard let self, let searchBar else { return }
                guard token == self.focusToken, self.isFirstResponder.wrappedValue else { return }

                if searchBar.window != nil {
                    searchBar.searchTextField.becomeFirstResponder()
                    if searchBar.searchTextField.isFirstResponder || remainingAttempts <= 0 {
                        return
                    }
                } else if remainingAttempts <= 0 {
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self, weak searchBar] in
                    guard let self, let searchBar else { return }
                    self.requestFocus(on: searchBar, token: token, remainingAttempts: remainingAttempts - 1)
                }
            }
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text.wrappedValue = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            isFirstResponder.wrappedValue = false
            searchBar.searchTextField.resignFirstResponder()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            text.wrappedValue = ""
            isFirstResponder.wrappedValue = false
            searchBar.text = ""
            searchBar.setShowsCancelButton(false, animated: true)
            searchBar.resignFirstResponder()
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            isFirstResponder.wrappedValue = true
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            // Do not mirror transient UIKit end-editing callbacks into SwiftUI.
            // The field can briefly lose first responder during body updates; if
            // we write false here, the next update keeps the keyboard dismissed.
            if !isFirstResponder.wrappedValue {
                onDidEndEditing?()
            }
        }

        func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
            return true
        }
    }
}

struct LibrarySettingsSheet: View {
    @ObservedObject var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: Binding(get: { store.themePreference }, set: { store.setTheme($0) })) {
                        ForEach(ReaderTheme.displayOrder) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    Picker("Font", selection: Binding(get: { store.readerFont }, set: { store.setReaderFont($0) })) {
                        ForEach(ReaderFont.allCases) { font in
                            Text(font.label).tag(font)
                        }
                    }
                }

                Section("Reader") {
                    HStack {
                        Text("Font size")
                        Spacer()
                        Text("\(Int(store.textSize))").foregroundStyle(store.theme.secondary)
                    }
                    Slider(value: Binding(get: { store.textSize }, set: { store.setTextSize($0) }), in: 15...30, step: 1)
                    HStack {
                        Text("Line spacing")
                        Spacer()
                        Text("\(Int(store.lineSpacing))").foregroundStyle(store.theme.secondary)
                    }
                    Slider(value: Binding(get: { store.lineSpacing }, set: { store.setLineSpacing($0) }), in: 2...18, step: 1)
                }

                Section("Highlights") {
                    Button {
                        if let url = store.exportHighlightsCSV() {
                            exportURL = url
                        }
                    } label: {
                        Label("Export highlights CSV", systemImage: "square.and.arrow.up")
                    }
                }

                Section("Library") {
                    Button {
                        Task {
                            if let url = await store.exportLibraryCSV() {
                                exportURL = url
                            }
                        }
                    } label: {
                        Label("Export library CSV", systemImage: "tablecells")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        store.signOut()
                        dismiss()
                    } label: {
                        Label("Sign out", systemImage: "person.crop.circle.badge.xmark")
                    }
                } footer: {
                    if let email = store.tokenStore.email {
                        Text("Signed in as \(email)")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: Binding(get: {
                exportURL.map { ShareableURL(url: $0) }
            }, set: { newValue in
                exportURL = newValue?.url
            })) { wrapper in
                ActivityShareSheet(activityItems: [wrapper.url])
            }
        }
    }
}

struct PadLibraryView: View {
    @ObservedObject var store: ReaderStore
    @Binding var showingAdd: Bool

    var body: some View {
        HStack(spacing: 0) {
            CompactLibraryView(store: store, showingAdd: $showingAdd) { summary in
                Task { await store.select(summary) }
            }
            .frame(minWidth: 340, idealWidth: 390, maxWidth: 440)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(store.theme.hairline)
                    .frame(width: 1)
            }

            ZStack {
                store.theme.background.ignoresSafeArea()
                if let article = store.selectedArticle {
                    ReaderDetailView(article: article, store: store) {
                        Task {
                            await store.toggleArchive()
                            store.selectedArticle = nil
                            store.selectedId = nil
                        }
                    } onDelete: {
                        store.selectedArticle = nil
                        store.selectedId = nil
                    }
                    .id(article.id)
                } else {
                    ContentUnavailableView("Select an article", systemImage: "doc.text")
                        .foregroundStyle(store.theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(store.theme.background)
    }
}

struct CompactReaderDestination: View {
    let summary: ArticleSummary
    @ObservedObject var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var article: Article?
    @State private var chromeVisible = true
    @GestureState private var edgeBackSwipeActive = false

    var body: some View {
        ZStack {
            store.theme.background.ignoresSafeArea()

            if let article {
                ReaderDetailView(article: article, store: store, onChromeVisibilityChange: { visible in
                    chromeVisible = visible
                }, scrollDisabled: edgeBackSwipeActive) {
                    let targetArchived = !(store.selectedArticle?.archived ?? article.archived)
                    let articleSummary = store.summary(for: store.selectedArticle ?? article)
                    dismiss()
                    Task {
                        try? await Task.sleep(nanoseconds: 90_000_000)
                        await store.setArchived(targetArchived, summary: articleSummary)
                    }
                } onDelete: {
                    dismiss()
                }
                .id(article.id)
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { proxy in
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .foregroundStyle(store.theme.primary)
                .readerStableGlassCircle(theme: store.theme)
                .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
                .preferredColorScheme(store.theme.isDark ? .dark : .light)
                .id("reader-back-\(store.theme.rawValue)")
                .padding(.leading, 18)
                .padding(.top, max(proxy.safeAreaInsets.top + 12, 58))
                .opacity(chromeVisible ? 1 : 0)
                .offset(y: chromeVisible ? 0 : -18)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: chromeVisible)
                .allowsHitTesting(chromeVisible)
            }
            .frame(width: 110, height: 168, alignment: .topLeading)
        }
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 34)
                .contentShape(Rectangle())
                .highPriorityGesture(edgeBackGesture)
                .ignoresSafeArea(edges: .vertical)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(store.theme.background, for: .navigationBar)
        .background(store.theme.background.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
        .preferredColorScheme(store.theme.isDark ? .dark : .light)
        .background(NavigationGestureConfigurator().frame(width: 0, height: 0))
        .onAppear {
            postChromeVisibility(chromeVisible)
        }
        .onDisappear {
            postChromeVisibility(true)
        }
        .onChange(of: chromeVisible) { _, visible in
            postChromeVisibility(visible)
        }
        .task(id: summary.id) {
            if let cached = store.cachedArticleForOpen(summary) {
                article = cached
            } else {
                article = await store.prepareArticleForOpen(summary)
            }
        }
    }

    private func postChromeVisibility(_ visible: Bool) {
        NotificationCenter.default.post(name: .readerChromeVisibilityChanged, object: visible)
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .updating($edgeBackSwipeActive) { value, state, _ in
                let horizontal = max(0, value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > 14, horizontal > vertical * 1.35 else { return }
                state = true
            }
            .onEnded { value in
                guard value.translation.width > 70 else { return }
                guard abs(value.translation.height) < 80 else { return }
                dismiss()
            }
    }
}
#endif

struct ArticleSidebar: View {
    @ObservedObject var store: ReaderStore
    @Binding var showingAdd: Bool
    @State private var searchTask: Task<Void, Never>?

    private var isSearching: Bool {
        !store.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.archived ? "Archive" : "Library")
                        .font(.system(.title2, design: .default, weight: .bold))
                        .foregroundStyle(store.theme.primary)
                    Text("\(store.articles.count) articles")
                        .font(.footnote)
                        .foregroundStyle(store.theme.secondary)
                }

                Spacer()

                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button {
                    store.setArchiveMode(!store.archived)
                    Task { await store.refreshAll() }
                } label: {
                    Image(systemName: store.archived ? "tray" : "archivebox")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(store.theme.secondary)
                TextField("Search", text: $store.search)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await store.loadArticles() } }
                if !store.search.isEmpty {
                    Button {
                        store.search = ""
                        Task { await store.loadArticles() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(store.theme.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            List(selection: Binding(get: { store.selectedId }, set: { newValue in
                if let newValue, let summary = store.articles.first(where: { $0.id == newValue }) {
                    Task { await store.select(summary) }
                }
            })) {
                ForEach(store.articles) { article in
                    ArticleRow(
                        article: article,
                        selected: store.selectedId == article.id,
                        theme: store.theme,
                        progress: store.progress(for: article.id),
                        showsModeBadge: isSearching,
                        selecting: false
                    )
                    .tag(article.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        Button {
                            Task { await store.toggleRead(article) }
                        } label: {
                            Label(article.readAt == nil ? "Mark as Read" : "Mark as Unread", systemImage: article.readAt == nil ? "checkmark.circle" : "circle")
                        }
                        Button {
                            Task {
                                if article.archived {
                                    await store.unarchive(article)
                                } else {
                                    await store.archive(article)
                                }
                            }
                        } label: {
                            Label(article.archived ? "Unarchive" : "Archive", systemImage: article.archived ? "tray.and.arrow.up" : "archivebox")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task { await store.delete(article) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task {
                                if article.archived {
                                    await store.unarchive(article)
                                } else {
                                    await store.archive(article)
                                }
                            }
                        } label: {
                            Label(article.archived ? "Unarchive" : "Archive", systemImage: article.archived ? "tray.and.arrow.up" : "archivebox")
                        }
                        .tint(.indigo)
                        Button {
                            Task { await store.toggleRead(article) }
                        } label: {
                            Label(article.readAt == nil ? "Read" : "Unread", systemImage: article.readAt == nil ? "checkmark.circle" : "circle")
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await store.delete(article) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: store.search) { _, _ in
                searchTask?.cancel()
                store.applyLocalSearch()
            }
        }
    }
}

struct ArticleRow: View {
    let article: ArticleSummary
    let selected: Bool
    let theme: ReaderTheme
    let progress: Double
    var showsModeBadge: Bool = false
    var selecting: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(selected ? Color.accentColor : theme.secondary.opacity(0.55))
            }
            VStack(spacing: 4) {
                ArticleFavicon(article: article, theme: theme)
                if article.readAt == nil {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .padding(.top, -2)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(.system(size: 15.5, weight: .bold, design: .default))
                    .lineLimit(2)
                    .foregroundStyle(theme.primary)
                    .lineSpacing(0)
                HStack(spacing: 6) {
                    if showsModeBadge {
                        HStack(spacing: 3) {
                            Image(systemName: article.archived ? "archivebox.fill" : "tray.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(article.archived ? "Archive" : "Inbox")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(theme.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(theme.secondary)
                    }
                    if let siteName = article.siteName {
                        Text(siteName)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(theme.secondary.opacity(0.78))
                    }
                    if let ttr = article.ttr {
                        Text("\(ttr) min")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(theme.secondary.opacity(0.78))
                    }
                    if progress > 0.01 {
                        Spacer(minLength: 0)
                        if progress >= 0.995 {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundStyle(Color.green)
                        } else {
                            Text("\(Int((progress * 100).rounded()))%")
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .monospacedDigit()
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(minHeight: 82, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.selectedPanel)
            }
        }
    }
}

struct ArticleFavicon: View {
    let article: ArticleSummary
    let theme: ReaderTheme

    var body: some View {
        Group {
            if let faviconURL {
                CachedRemoteImage(url: faviconURL) {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: 26, height: 26)
        .padding(5)
        .background(theme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(theme.hairline)
        }
    }

    private var fallback: some View {
        Text(siteInitial)
            .font(.system(size: 13, weight: .bold, design: .default))
            .foregroundStyle(theme.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var faviconURL: URL? {
        guard let favicon = article.favicon, !favicon.isEmpty else { return nil }
        return URL(string: favicon)
    }

    private var siteInitial: String {
        String((article.siteName ?? article.title).prefix(1)).uppercased()
    }
}

final class RemoteImageCache {
    static let shared = RemoteImageCache()
    private let memory = NSCache<NSURL, PlatformImage>()
    private let directory: URL

    private init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryReader/Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL) -> PlatformImage? {
        let key = url as NSURL
        if let cached = memory.object(forKey: key) {
            return cached
        }
        guard let data = try? Data(contentsOf: fileURL(for: url)),
              let image = PlatformImage(data: data) else {
            return nil
        }
        memory.setObject(image, forKey: key)
        return image
    }

    func load(_ url: URL) async -> PlatformImage? {
        if let cached = image(for: url) {
            return cached
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = PlatformImage(data: data) else {
                return nil
            }
            memory.setObject(image, forKey: url as NSURL)
            try? data.write(to: fileURL(for: url), options: .atomic)
            return image
        } catch {
            return nil
        }
    }

    private func fileURL(for url: URL) -> URL {
        let safe = Data(url.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(safe)
    }
}

final class CachedRemoteImageLoader: ObservableObject {
    @Published var image: PlatformImage?
    private var task: Task<Void, Never>?

    func load(url: URL) {
        if let image = RemoteImageCache.shared.image(for: url) {
            self.image = image
            return
        }
        task?.cancel()
        task = Task {
            let loaded = await RemoteImageCache.shared.load(url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.image = loaded
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

struct CachedRemoteImage<Fallback: View>: View {
    let url: URL
    @ViewBuilder let fallback: Fallback
    @StateObject private var loader = CachedRemoteImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                platformImage(image)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback
            }
        }
        .task(id: url) {
            loader.load(url: url)
        }
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}

struct ReaderDetailView: View {
    let article: Article
    @ObservedObject var store: ReaderStore
    var onChromeVisibilityChange: ((Bool) -> Void)?
    var scrollDisabled = false
    let onArchive: () -> Void
    let onDelete: () -> Void
    @State private var showPreferences = false
    @State private var didRestoreScrollPosition = false
    @StateObject private var scrollTracker = ReaderScrollTracker()

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                let outerWidth = min(proxy.size.width, contentWidth)
                let readableWidth = max(1, outerWidth - horizontalPadding * 2)
                TrackableScrollView(onScrollChange: updatePreferenceVisibility) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(article.title)
                                .font(.system(size: titleSize, weight: .bold, design: .default))
                                .foregroundStyle(store.theme.primary)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(byline.uppercased())
                                .font(.system(.caption, design: .default, weight: .medium))
                                .tracking(0.8)
                                .foregroundStyle(store.theme.secondary)
                                .textSelection(.enabled)
                        }

                        Rectangle()
                            .fill(store.theme.hairline)
                            .frame(height: 1)

                        HTMLText(
                            html: article.content,
                            fallback: article.description,
                            articleId: article.id,
                            theme: store.theme,
                            readerFont: store.readerFont,
                            textSize: store.textSize,
                            lineSpacing: store.lineSpacing,
                            highlights: store.storedHighlights(for: article.id),
                            highlightsVersion: store.highlightsVersion,
                            onAddHighlight: { store.addHighlight($0, articleId: article.id) },
                            onRemoveHighlight: { store.removeHighlight($0, articleId: article.id) }
                        )
                            .frame(width: readableWidth, alignment: .leading)
                    }
                    .frame(width: readableWidth, alignment: .leading)
                    .padding(.top, topPadding)
                    .padding(.bottom, 118)
                    .padding(.horizontal, horizontalPadding)
                    .frame(width: outerWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        #if os(iOS)
                        ScrollPositionRestorer(
                            progress: store.progress(for: article.id),
                            didRestore: $didRestoreScrollPosition
                        )
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                        #endif
                    }
                }
                .scrollDisabled(scrollDisabled)
            }

            ReaderCommandBar(store: store, article: article, onArchive: onArchive, onDelete: onDelete)
                .padding(.bottom, 18)
                .opacity(showPreferences ? 1 : 0)
                .offset(y: showPreferences ? 0 : 34)
                .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showPreferences)
                .allowsHitTesting(showPreferences)
        }
        .background(store.theme.background)
        .onAppear {
            didRestoreScrollPosition = false
            let startsAtTop = store.progress(for: article.id) <= 0.02
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showPreferences = startsAtTop
            }
            scrollTracker.lastY = nil
            scrollTracker.lastKnownProgress = store.progress(for: article.id)
            scrollTracker.lastReportedProgress = scrollTracker.lastKnownProgress
            setChromeVisible(startsAtTop, force: true)
        }
        .onDisappear {
            store.setProgress(scrollTracker.lastKnownProgress, articleId: article.id, forcePersist: true)
            setChromeVisible(true, force: true)
        }
        .onChange(of: didRestoreScrollPosition) { _, restored in
            guard restored else { return }
            scrollTracker.lastKnownProgress = store.progress(for: article.id)
            scrollTracker.lastReportedProgress = scrollTracker.lastKnownProgress
            setChromeVisible(false, force: true)
        }
    }

    private var titleSize: CGFloat {
        #if os(macOS)
        48
        #else
        32
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(macOS)
        64
        #else
        22
        #endif
    }

    private var topPadding: CGFloat {
        #if os(macOS)
        48
        #else
        132
        #endif
    }

    private var contentWidth: CGFloat {
        #if os(macOS)
        880
        #else
        720
        #endif
    }

    private func updatePreferenceVisibility(_ state: ReaderScrollState) {
        let y = state.y
        let storedProgress = store.progress(for: article.id)
        if !didRestoreScrollPosition && storedProgress > 0.02 {
            scrollTracker.lastY = y
            setChromeVisible(false)
            return
        }
        scrollTracker.lastKnownProgress = state.progress
        guard let lastScrollY = scrollTracker.lastY else {
            scrollTracker.lastY = y
            setChromeVisible(y > -72)
            reportProgressIfNeeded(state.progress)
            return
        }

        if y >= -8 {
            setChromeVisible(true)
        } else if y > lastScrollY + 2 {
            setChromeVisible(true)
        } else if y < lastScrollY - 2 {
            setChromeVisible(false)
        }
        reportProgressIfNeeded(state.progress)
        scrollTracker.lastY = y
    }

    private func reportProgressIfNeeded(_ progress: Double) {
        let previous = scrollTracker.lastReportedProgress
        guard abs(progress - previous) >= 0.05
            || (progress >= 0.995 && previous < 0.995)
            || (progress <= 0.002 && previous > 0.002) else { return }
        scrollTracker.lastReportedProgress = progress
        store.setProgress(progress, articleId: article.id, markReadOnCompletion: false)
    }

    private func setChromeVisible(_ visible: Bool, force: Bool = false) {
        if showPreferences != visible {
            showPreferences = visible
        } else if !force {
            return
        }
        onChromeVisibilityChange?(visible)
        #if os(iOS)
        NotificationCenter.default.post(name: .readerChromeVisibilityChanged, object: visible)
        #endif
    }

    private var byline: String {
        [article.siteName, article.ttr.map { "\($0) min read" }, article.author]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct ReaderCommandBar: View {
    private enum Command: Hashable {
        case share
        case archive
        case settings
        case more
    }

    @ObservedObject var store: ReaderStore
    let article: Article
    let onArchive: () -> Void
    let onDelete: () -> Void
    @State private var showingSettings = false
    @State private var shareURL: URL?
    @State private var activeCommand: Command?
    @Namespace private var commandLoupeNamespace
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            #if os(iOS)
            Button {
                shareURL = articleURL
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .accessibilityLabel("Share")
            }
            .foregroundStyle(store.theme.primary)
            .readerGlassBarButton(theme: store.theme)
            .background(commandLoupe(for: .share))
            .simultaneousGesture(commandPress(.share))
            .sheet(item: Binding(get: {
                shareURL.map { ShareableURL(url: $0) }
            }, set: { newValue in
                shareURL = newValue?.url
            })) { wrapper in
                ActivityShareSheet(activityItems: [wrapper.url])
                    .ignoresSafeArea()
            }
            #else
            ShareLink(item: articleURL) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .accessibilityLabel("Share")
            }
            .foregroundStyle(store.theme.primary)
            .readerGlassBarButton(theme: store.theme)
            .background(commandLoupe(for: .share))
            .simultaneousGesture(commandPress(.share))
            #endif

            Button(action: onArchive) {
                Image(systemName: currentArticle.archived ? "tray.and.arrow.up" : "archivebox")
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .accessibilityLabel(currentArticle.archived ? "Unarchive" : "Archive")
            }
            .foregroundStyle(store.theme.primary)
            .readerGlassBarButton(theme: store.theme)
            .background(commandLoupe(for: .archive))
            .simultaneousGesture(commandPress(.archive))

            Button {
                showingSettings.toggle()
            } label: {
                Text("Aa")
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .accessibilityLabel("Reader settings")
            }
            .foregroundStyle(store.theme.primary)
            .readerGlassBarButton(theme: store.theme)
            .background(commandLoupe(for: .settings))
            .simultaneousGesture(commandPress(.settings))
            #if os(iOS)
            .sheet(isPresented: $showingSettings) {
                ReaderSettingsPanel(store: store)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .background(.clear)
                    .presentationDetents([.height(282), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.clear)
                    .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
                    .preferredColorScheme(store.theme.isDark ? .dark : .light)
            }
            #else
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                ReaderSettingsPanel(store: store)
                    .frame(width: 340)
                    .padding(18)
                    .background(store.theme.background)
                    .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
                    .preferredColorScheme(store.theme.isDark ? .dark : .light)
            }
            #endif
            .onChange(of: showingSettings) { _, visible in
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    activeCommand = visible ? .settings : nil
                }
            }

            Menu {
                Button {
                    Task { await store.setRead(currentArticle.readAt == nil, article: currentArticle) }
                } label: {
                    Label(currentArticle.readAt == nil ? "Mark as Read" : "Mark as Unread", systemImage: currentArticle.readAt == nil ? "checkmark.circle" : "circle")
                }
                Button {
                    openURL(articleURL)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
                Button(role: .destructive) {
                    Task {
                        await store.delete(article)
                        onDelete()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .accessibilityLabel("More")
            }
            .foregroundStyle(store.theme.primary)
            .readerGlassBarButton(theme: store.theme)
            .background(commandLoupe(for: .more))
            .simultaneousGesture(commandPress(.more))
            .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
            .preferredColorScheme(store.theme.isDark ? .dark : .light)
        }
        .font(.system(size: 16, weight: .semibold, design: .default))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .readerGlassBarBackground(theme: store.theme)
        .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
        .preferredColorScheme(store.theme.isDark ? .dark : .light)
        .padding(.horizontal, 20)
    }

    private var articleURL: URL {
        URL(string: currentArticle.url) ?? appBaseURL
    }

    private var currentArticle: Article {
        store.selectedArticle?.id == article.id ? (store.selectedArticle ?? article) : article
    }

    @ViewBuilder
    private func commandLoupe(for command: Command) -> some View {
        if activeCommand == command {
            Circle()
                .fill(.clear)
                .matchedGeometryEffect(id: "reader-command-loupe", in: commandLoupeNamespace)
                .readerGlassBarBackground(theme: store.theme)
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)
        }
    }

    private func commandPress(_ command: Command) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard activeCommand != command else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                    activeCommand = command
                }
            }
            .onEnded { _ in
                guard command != .settings else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        if activeCommand == command {
                            activeCommand = nil
                        }
                    }
                }
            }
    }
}

struct FallbackGlassIconButtonStyle: ButtonStyle {
    let theme: ReaderTheme
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .default))
            .foregroundStyle(theme.primary)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(theme == .offWhite ? Color.white.opacity(0.42) : Color.white.opacity(0.10))
                    .overlay {
                        Circle()
                            .strokeBorder(theme.hairline)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct ReaderSettingsPanel: View {
    @ObservedObject var store: ReaderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsMenuRow(title: "Theme", value: store.themePreference.label, theme: store.theme) {
                ForEach(ReaderTheme.displayOrder) { theme in
                    Button {
                        store.setTheme(theme)
                    } label: {
                        if theme == store.themePreference {
                            Label(theme.label, systemImage: "checkmark")
                        } else {
                            Text(theme.label)
                        }
                    }
                }
            }

            SettingsMenuRow(title: "Font", value: store.readerFont.label, theme: store.theme) {
                ForEach(ReaderFont.allCases) { font in
                    Button {
                        store.setReaderFont(font)
                    } label: {
                        if font == store.readerFont {
                            Label(font.label, systemImage: "checkmark")
                        } else {
                            Text(font.label)
                        }
                    }
                }
            }

            SettingsSection(title: "Font Size", value: "\(Int(store.textSize))", theme: store.theme) {
                Slider(value: Binding(get: { store.textSize }, set: { store.setTextSize($0) }), in: 15...30, step: 1)
            }

            SettingsSection(title: "Line Spacing", value: "\(Int(store.lineSpacing))", theme: store.theme) {
                Slider(value: Binding(get: { store.lineSpacing }, set: { store.setLineSpacing($0) }), in: 2...18, step: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(Color.clear)
        .tint(store.theme.primary)
        .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
        .foregroundStyle(store.theme.primary)
    }
}

struct SettingsMenuRow<MenuContent: View>: View {
    let title: String
    let value: String
    let theme: ReaderTheme
    @ViewBuilder let menuContent: MenuContent

    init(title: String, value: String, theme: ReaderTheme, @ViewBuilder menuContent: () -> MenuContent) {
        self.title = title
        self.value = value
        self.theme = theme
        self.menuContent = menuContent()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.system(.body, design: .default, weight: .semibold))
                .foregroundStyle(theme.primary)

            Spacer(minLength: 18)

            Menu {
                menuContent
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.system(.body, design: .default, weight: .regular))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .baselineOffset(1)
                }
                .foregroundStyle(theme.secondary)
            }
            .buttonStyle(.plain)
            .environment(\.colorScheme, theme.isDark ? .dark : .light)
            .preferredColorScheme(theme.isDark ? .dark : .light)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 34)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    var value: String?
    let theme: ReaderTheme
    @ViewBuilder let content: Content

    init(title: String, value: String? = nil, theme: ReaderTheme, @ViewBuilder content: () -> Content) {
        self.title = title
        self.value = value
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(.body, design: .default, weight: .semibold))
                Spacer()
                if let value {
                    Text(value)
                        .font(.system(.body, design: .default, weight: .regular))
                        .foregroundStyle(theme.secondary)
                }
            }
            .foregroundStyle(theme.primary)

            content
        }
        .padding(.vertical, 0)
    }
}

struct ReaderScrollState: Equatable {
    let y: CGFloat
    let progress: Double
}

private func readerProgress(contentOffsetY: CGFloat, contentHeight: CGFloat, containerHeight: CGFloat) -> Double {
    let scrollableHeight = contentHeight - containerHeight
    guard scrollableHeight > 1 else { return 0 }
    let offset = min(max(0, contentOffsetY), scrollableHeight)
    guard offset > 1 else { return 0 }
    let remaining = contentHeight - (offset + containerHeight)
    let completionSlack = min(120, max(24, scrollableHeight * 0.08))
    if remaining <= completionSlack { return 1 }
    return min(1, max(0, offset / scrollableHeight))
}

final class ReaderScrollTracker: ObservableObject {
    var lastY: CGFloat?
    var lastKnownProgress: Double = 0
    var lastReportedProgress: Double = 0
}

struct TrackableScrollView<Content: View>: View {
    let onScrollChange: (ReaderScrollState) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        let scrollView = ScrollView {
            legacyOffsetProbe
            content
        }
            .coordinateSpace(name: "readerScroll")

        #if os(iOS)
        if #available(iOS 18.0, *) {
            scrollView
                .onScrollGeometryChange(for: ReaderScrollState.self) { geometry in
                    let progress = readerProgress(
                        contentOffsetY: geometry.contentOffset.y,
                        contentHeight: geometry.contentSize.height,
                        containerHeight: geometry.containerSize.height
                    )
                    return ReaderScrollState(y: -geometry.contentOffset.y, progress: progress)
                } action: { _, state in
                    onScrollChange(state)
                }
        } else {
            scrollView
                .background(ScrollViewOffsetObserver(onScrollChange: onScrollChange).frame(width: 0, height: 0))
        }
        #else
        if #available(macOS 15.0, *) {
            scrollView
                .onScrollGeometryChange(for: ReaderScrollState.self) { geometry in
                    let progress = readerProgress(
                        contentOffsetY: geometry.contentOffset.y,
                        contentHeight: geometry.contentSize.height,
                        containerHeight: geometry.containerSize.height
                    )
                    return ReaderScrollState(y: -geometry.contentOffset.y, progress: progress)
                } action: { _, state in
                    onScrollChange(state)
                }
        } else {
            scrollView
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { y in
                    onScrollChange(ReaderScrollState(y: y, progress: min(1, max(0, -y / 1400))))
                }
        }
        #endif
    }

    private var legacyOffsetProbe: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: ScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("readerScroll")).minY)
        }
        .frame(height: 0)
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if os(iOS)
struct ScrollViewOffsetObserver: UIViewRepresentable {
    let onScrollChange: (ReaderScrollState) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrollChange: onScrollChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onScrollChange = onScrollChange
        context.coordinator.attach(from: view)
    }

    final class Coordinator {
        var onScrollChange: (ReaderScrollState) -> Void
        private weak var scrollView: UIScrollView?
        private var offsetObservation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?

        init(onScrollChange: @escaping (ReaderScrollState) -> Void) {
            self.onScrollChange = onScrollChange
        }

        func attach(from view: UIView) {
            DispatchQueue.main.async {
                guard let scrollView = view.enclosingScrollView else { return }
                guard self.scrollView !== scrollView else {
                    self.emit(scrollView)
                    return
                }
                self.scrollView = scrollView
                self.offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    self?.emit(scrollView)
                }
                self.sizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [weak self] scrollView, _ in
                    self?.emit(scrollView)
                }
                self.emit(scrollView)
            }
        }

        private func emit(_ scrollView: UIScrollView) {
            let progress = readerProgress(
                contentOffsetY: scrollView.contentOffset.y,
                contentHeight: scrollView.contentSize.height,
                containerHeight: scrollView.bounds.height
            )
            onScrollChange(ReaderScrollState(y: -scrollView.contentOffset.y, progress: progress))
        }
    }
}

struct ScrollPositionRestorer: UIViewRepresentable {
    let progress: Double
    @Binding var didRestore: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.restore(progress: progress, didRestore: $didRestore, from: view)
    }

    final class Coordinator {
        private var attempts = 0
        private var restoring = false
        private var targetProgress: Double?

        func restore(progress: Double, didRestore: Binding<Bool>, from view: UIView) {
            guard !didRestore.wrappedValue, progress > 0.02, !restoring else { return }
            targetProgress = progress
            attempts = 0
            restoring = true
            attemptRestore(progress: targetProgress ?? progress, didRestore: didRestore, from: view, scheduled: false)
        }

        private func attemptRestore(progress: Double, didRestore: Binding<Bool>, from view: UIView, scheduled: Bool = true) {
            let work = {
                guard !didRestore.wrappedValue else {
                    self.restoring = false
                    return
                }
                guard let scrollView = view.enclosingScrollView else {
                    self.retry(progress: progress, didRestore: didRestore, from: view)
                    return
                }

                guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else {
                    self.finishWithoutRestoring(didRestore: didRestore)
                    return
                }

                scrollView.layoutIfNeeded()
                let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                guard maxOffset > 1 else {
                    self.retry(progress: progress, didRestore: didRestore, from: view)
                    return
                }

                let targetY = min(maxOffset, max(0, maxOffset * progress))
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                UIView.performWithoutAnimation {
                    scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
                    scrollView.layoutIfNeeded()
                }
                CATransaction.commit()
                didRestore.wrappedValue = true
                self.restoring = false
            }
            if scheduled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
            } else {
                work()
            }
        }

        private func retry(progress: Double, didRestore: Binding<Bool>, from view: UIView) {
            attempts += 1
            guard attempts < 18 else {
                finishWithoutRestoring(didRestore: didRestore)
                return
            }
            attemptRestore(progress: progress, didRestore: didRestore, from: view)
        }

        private func finishWithoutRestoring(didRestore: Binding<Bool>) {
            didRestore.wrappedValue = true
            restoring = false
        }
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        if let scrollView = superview as? UIScrollView {
            return scrollView
        }
        return superview?.enclosingScrollView
    }
}
#endif

struct HTMLText: View {
    let html: String
    let fallback: String?
    let articleId: String
    let theme: ReaderTheme
    let readerFont: ReaderFont
    let textSize: Double
    let lineSpacing: Double
    let highlights: [String]
    let highlightsVersion: Int
    let onAddHighlight: (String) -> Void
    let onRemoveHighlight: (String) -> Void

    private var paragraphs: [String] {
        let parsed = ArticleTextExtractor.paragraphs(from: html)
        if !parsed.isEmpty { return parsed }
        return ArticleTextExtractor.paragraphs(from: fallback ?? "")
    }

    var body: some View {
        Group {
            if paragraphs.isEmpty {
                Text("No readable text was saved for this article.")
                    .font(.system(size: textSize, weight: .regular, design: readerFont.design))
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                #if os(iOS)
                SelectableArticleText(
                    text: paragraphs.joined(separator: "\n\n"),
                    articleId: articleId,
                    theme: theme,
                    readerFont: readerFont,
                    textSize: textSize,
                    lineSpacing: lineSpacing,
                    highlights: highlights,
                    highlightsVersion: highlightsVersion,
                    onAddHighlight: onAddHighlight,
                    onRemoveHighlight: onRemoveHighlight
                )
                #else
                VStack(alignment: .leading, spacing: paragraphSpacing) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.system(size: textSize, weight: .regular, design: readerFont.design))
                            .foregroundStyle(theme.primary)
                            .lineSpacing(lineSpacing)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                #endif
            }
        }
    }

    private var paragraphSpacing: CGFloat {
        max(7, CGFloat(lineSpacing) * 0.75)
    }
}

#if os(iOS)
struct SelectableArticleText: View {
    let text: String
    let articleId: String
    let theme: ReaderTheme
    let readerFont: ReaderFont
    let textSize: Double
    let lineSpacing: Double
    let highlights: [String]
    let highlightsVersion: Int
    let onAddHighlight: (String) -> Void
    let onRemoveHighlight: (String) -> Void
    @State private var height: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            NativeSelectableTextView(
                text: text,
                articleId: articleId,
                theme: theme,
                readerFont: readerFont,
                textSize: textSize,
                lineSpacing: lineSpacing,
                highlights: highlights,
                highlightsVersion: highlightsVersion,
                onAddHighlight: onAddHighlight,
                onRemoveHighlight: onRemoveHighlight,
                availableWidth: width,
                height: $height
            )
            .frame(width: width, height: height, alignment: .leading)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NativeSelectableTextView: UIViewRepresentable {
    let text: String
    let articleId: String
    let theme: ReaderTheme
    let readerFont: ReaderFont
    let textSize: Double
    let lineSpacing: Double
    let highlights: [String]
    let highlightsVersion: Int
    let onAddHighlight: (String) -> Void
    let onRemoveHighlight: (String) -> Void
    let availableWidth: CGFloat
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.adjustsFontForContentSizeCategory = true
        textView.dataDetectorTypes = [.link]
        textView.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        let editMenuInteraction = UIEditMenuInteraction(delegate: context.coordinator)
        context.coordinator.editMenuInteraction = editMenuInteraction
        textView.addInteraction(editMenuInteraction)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let width = normalizedWidth
        textView.bounds.size.width = width
        textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        let signature = "\(text.hashValue)-\(theme.rawValue)-\(readerFont.rawValue)-\(textSize)-\(lineSpacing)-\(Int((width * 10).rounded()))-\(highlightsVersion)-\(highlights.hashValue)"
        if context.coordinator.signature != signature {
            context.coordinator.signature = signature
            UIView.performWithoutAnimation {
                textView.attributedText = attributedText
                textView.layoutIfNeeded()
            }
            recalculateHeight(textView, width: width)
        } else if height <= 1 {
            recalculateHeight(textView, width: width)
        }
        textView.textColor = UIColor(theme.primary)
    }

    private var normalizedWidth: CGFloat {
        let scale = max(1, UIScreen.main.scale)
        let width = max(1, availableWidth)
        return (width * scale).rounded(.down) / scale
    }

    private var attributedText: NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(lineSpacing)
        paragraphStyle.paragraphSpacing = max(7, CGFloat(lineSpacing) * 0.75)

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: readerFont.uiFont(size: CGFloat(textSize)),
                .foregroundColor: UIColor(theme.primary),
                .paragraphStyle: paragraphStyle,
            ]
        )
        for highlight in highlights {
            for range in ranges(of: highlight, in: text) {
                attributed.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.42), range: range)
            }
        }
        return attributed
    }

    private func ranges(of needle: String, in haystack: String) -> [NSRange] {
        let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let nsHaystack = haystack as NSString
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: nsHaystack.length)
        while searchRange.location < nsHaystack.length {
            let found = nsHaystack.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let nextLocation = found.location + max(found.length, 1)
            searchRange = NSRange(location: nextLocation, length: nsHaystack.length - nextLocation)
        }
        return ranges
    }

    private func recalculateHeight(_ textView: UITextView, width: CGFloat) {
        textView.bounds.size.width = width
        textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let usedHeight = textView.layoutManager.usedRect(for: textView.textContainer).height
        let targetHeight = ceil(max(size.height, usedHeight))
        guard targetHeight.isFinite, abs(height - targetHeight) > 0.5 else { return }
        DispatchQueue.main.async {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                height = targetHeight
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIContextMenuInteractionDelegate, UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
        var parent: NativeSelectableTextView
        var signature = ""
        weak var textView: UITextView?
        weak var editMenuInteraction: UIEditMenuInteraction?

        init(parent: NativeSelectableTextView) {
            self.parent = parent
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            selectionMenu(for: textView, ranges: [NSValue(range: range)], suggestedActions: suggestedActions)
        }

        @available(iOS 26.0, *)
        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            selectionMenu(for: textView, ranges: ranges, suggestedActions: suggestedActions)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let textView,
                  let range = highlightedRange(in: textView, at: location) else {
                return nil
            }

            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let deleteHighlight = UIAction(
                    title: "Delete Highlight",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self, weak textView] _ in
                    guard let self, let textView else { return }
                    self.deleteHighlight(in: textView, range: range)
                }
                return UIMenu(children: [deleteHighlight])
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let textView = recognizer.view as? UITextView else { return }
            let point = recognizer.location(in: textView)
            guard let range = highlightedRange(in: textView, at: point) else { return }
            textView.selectedRange = range
            textView.becomeFirstResponder()
            editMenuInteraction?.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        private func selectionMenu(for textView: UITextView, ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            let hasSelection = ranges.contains { $0.rangeValue.length > 0 } || textView.selectedRange.length > 0
            if let highlightedRange = highlightedRangeForMenu(in: textView, ranges: ranges) {
                let deleteHighlight = UIAction(
                    title: "Delete Highlight",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak textView] _ in
                    guard let textView else { return }
                    self.deleteHighlight(in: textView, range: highlightedRange)
                }
                return UIMenu(children: [deleteHighlight] + suggestedActions)
            }

            guard hasSelection else {
                if let highlightedRange = highlightedRange(in: textView, near: textView.selectedRange.location) {
                    let deleteHighlight = UIAction(
                        title: "Delete Highlight",
                        image: UIImage(systemName: "trash"),
                        attributes: .destructive
                    ) { [weak textView] _ in
                        guard let textView else { return }
                        self.deleteHighlight(in: textView, range: highlightedRange)
                    }
                    return UIMenu(children: [deleteHighlight] + suggestedActions)
                }
                return UIMenu(children: suggestedActions)
            }

            let highlight = UIAction(
                title: "Highlight",
                image: UIImage(systemName: "highlighter")
            ) { [weak textView] _ in
                guard let textView else { return }
                self.applyHighlight(to: textView, ranges: ranges)
            }

            return UIMenu(children: [highlight] + suggestedActions)
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let textView else { return UIMenu(children: suggestedActions) }
            return selectionMenu(for: textView, ranges: [NSValue(range: textView.selectedRange)], suggestedActions: suggestedActions)
        }

        func editMenuInteraction(_ interaction: UIEditMenuInteraction, targetRectFor configuration: UIEditMenuConfiguration) -> CGRect {
            guard let textView else { return .zero }
            let position = textView.position(from: textView.beginningOfDocument, offset: textView.selectedRange.location) ?? textView.beginningOfDocument
            return textView.caretRect(for: position).insetBy(dx: -6, dy: -8)
        }

        private func highlightedRangeForMenu(in textView: UITextView, ranges: [NSValue]) -> NSRange? {
            let candidates = ranges.map(\.rangeValue).filter { $0.length > 0 }
            let targetRanges = candidates.isEmpty && textView.selectedRange.length > 0 ? [textView.selectedRange] : candidates
            for range in targetRanges {
                let location = min(max(range.location, 0), max(textView.attributedText.length - 1, 0))
                if let highlighted = highlightedRange(in: textView, near: location),
                   NSIntersectionRange(highlighted, range).length > 0 {
                    return highlighted
                }
            }
            return nil
        }

        private func applyHighlight(to textView: UITextView, ranges: [NSValue]) {
            let selected = ranges.map(\.rangeValue).filter { $0.length > 0 }
            let targetRanges = selected.isEmpty && textView.selectedRange.length > 0 ? [textView.selectedRange] : selected
            guard !targetRanges.isEmpty else { return }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            for range in targetRanges where NSMaxRange(range) <= mutable.length {
                mutable.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.42), range: range)
                let selectedText = (mutable.string as NSString).substring(with: range)
                parent.onAddHighlight(selectedText)
            }
            textView.attributedText = mutable
            let lastRange = targetRanges.last ?? .init(location: 0, length: 0)
            textView.selectedRange = NSRange(location: min(NSMaxRange(lastRange), mutable.length), length: 0)
            textView.selectedTextRange = nil
            textView.resignFirstResponder()
            if #available(iOS 16.0, *) {
                editMenuInteraction?.dismissMenu()
            }
            parent.recalculateHeight(textView, width: parent.normalizedWidth)
        }

        private func deleteHighlight(in textView: UITextView, range: NSRange) {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            let fullRange = contiguousHighlightRange(in: mutable, containing: range)
            guard NSMaxRange(fullRange) <= mutable.length else { return }
            let highlightedText = (mutable.string as NSString).substring(with: fullRange)
            mutable.removeAttribute(.backgroundColor, range: fullRange)
            textView.attributedText = mutable
            textView.selectedRange = NSRange(location: fullRange.location, length: 0)
            parent.onRemoveHighlight(highlightedText)
            parent.recalculateHeight(textView, width: parent.normalizedWidth)
        }

        private func contiguousHighlightRange(in attributed: NSAttributedString, containing range: NSRange) -> NSRange {
            guard attributed.length > 0 else { return range }
            var start = min(max(range.location, 0), attributed.length - 1)
            var end = min(max(NSMaxRange(range) - 1, start), attributed.length - 1)

            while start > 0, attributed.attribute(.backgroundColor, at: start - 1, effectiveRange: nil) != nil {
                start -= 1
            }
            while end + 1 < attributed.length, attributed.attribute(.backgroundColor, at: end + 1, effectiveRange: nil) != nil {
                end += 1
            }
            return NSRange(location: start, length: end - start + 1)
        }

        private func highlightedRange(in textView: UITextView, near location: Int) -> NSRange? {
            guard textView.attributedText.length > 0 else { return nil }
            let index = min(max(location, 0), textView.attributedText.length - 1)
            var effectiveRange = NSRange(location: 0, length: 0)
            let color = textView.attributedText.attribute(.backgroundColor, at: index, effectiveRange: &effectiveRange)
            return color == nil ? nil : effectiveRange
        }

        private func highlightedRange(in textView: UITextView, at point: CGPoint) -> NSRange? {
            guard textView.attributedText.length > 0 else { return nil }
            let containerPoint = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )
            let index = textView.layoutManager.characterIndex(
                for: containerPoint,
                in: textView.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            guard index < textView.attributedText.length else { return nil }
            return highlightedRange(in: textView, near: index)
        }
    }
}
#endif

enum ArticleTextExtractor {
    static func paragraphs(from html: String) -> [String] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let source = trimmed
            .replacingOccurrences(of: "</p>", with: "</p>\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</div>", with: "</div>\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</section>", with: "</section>\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</article>", with: "</article>\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</li>", with: "</li>\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br>", with: "<br>\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "<br/>\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "<br />\n", options: .caseInsensitive)

        let text = decodeEntities(
            source
                .replacingOccurrences(of: "<script[\\s\\S]*?</script>", with: " ", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        )

        let paragraphs = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isAdvertisementLine($0) }

        if !paragraphs.isEmpty { return paragraphs }

        let stripped = decodeEntities(source.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return stripped.isEmpty || isAdvertisementLine(stripped) ? [] : [stripped]
    }

    private static func isAdvertisementLine(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalized == "advertisement"
            || normalized == "skip advertisement"
            || normalized == "story continues below advertisement"
            || normalized == "article continues below advertisement"
            || normalized == "continues below advertisement"
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

// MARK: - Highlight persistence

struct StoredHighlight: Codable, Identifiable, Hashable {
    let id: String
    let articleId: String
    let text: String
    let createdAt: Date
}

final class HighlightStore {
    static let shared = HighlightStore()

    private let queue = DispatchQueue(label: "reader.highlight.store")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func all(account: String) -> [StoredHighlight] {
        guard let data = try? Data(contentsOf: fileURL(account: account)) else { return [] }
        return (try? decoder.decode([StoredHighlight].self, from: data)) ?? []
    }

    func highlights(account: String, articleId: String) -> [StoredHighlight] {
        all(account: account).filter { $0.articleId == articleId }
    }

    @discardableResult
    func add(account: String, articleId: String, text: String) -> StoredHighlight {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let highlight = StoredHighlight(
            id: UUID().uuidString,
            articleId: articleId,
            text: trimmed,
            createdAt: Date()
        )
        write(account: account) { current in
            current.append(highlight)
        }
        return highlight
    }

    func remove(account: String, articleId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        write(account: account) { current in
            if let idx = current.firstIndex(where: { $0.articleId == articleId && $0.text == trimmed }) {
                current.remove(at: idx)
            }
        }
    }

    func replace(account: String, articleId: String, highlights newValue: [String]) {
        let unique = Array(NSOrderedSet(array: newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })) as? [String] ?? []
        write(account: account) { current in
            current.removeAll { $0.articleId == articleId }
            for text in unique {
                current.append(StoredHighlight(id: UUID().uuidString, articleId: articleId, text: text, createdAt: Date()))
            }
        }
    }

    private func write(account: String, mutate: (inout [StoredHighlight]) -> Void) {
        queue.sync {
            var current = (try? decoder.decode([StoredHighlight].self, from: (try? Data(contentsOf: fileURL(account: account))) ?? Data())) ?? []
            mutate(&current)
            let url = fileURL(account: account)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? encoder.encode(current) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func fileURL(account: String) -> URL {
        let safe = account.lowercased().replacingOccurrences(of: "[^a-z0-9._-]", with: "_", options: .regularExpression)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LibraryReader", isDirectory: true)
        return directory.appendingPathComponent("\(safe)-highlights.json")
    }
}

// MARK: - EPUB / Zip writer

enum CRC32 {
    static let table: [UInt32] = {
        (0...255).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 == 1) ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<data.count {
                let b = bytes[i]
                crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

struct MinimalZipEntry {
    let name: String
    let data: Data
}

enum MinimalZip {
    static func archive(entries: [MinimalZipEntry]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        let dosDateTime = currentDosDateTime()

        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let localHeaderOffset = UInt32(output.count)

            // Local file header
            output.append(uint32: 0x04034b50)
            output.append(uint16: 20) // version needed
            output.append(uint16: 0)  // gp flags
            output.append(uint16: 0)  // method STORED
            output.append(uint16: dosDateTime.time)
            output.append(uint16: dosDateTime.date)
            output.append(uint32: crc)
            output.append(uint32: UInt32(entry.data.count))
            output.append(uint32: UInt32(entry.data.count))
            output.append(uint16: UInt16(nameBytes.count))
            output.append(uint16: 0)
            output.append(contentsOf: nameBytes)
            output.append(entry.data)

            // Central directory entry
            centralDirectory.append(uint32: 0x02014b50)
            centralDirectory.append(uint16: 0x031E) // version made by (UNIX, ZIP 3.0)
            centralDirectory.append(uint16: 20)
            centralDirectory.append(uint16: 0)
            centralDirectory.append(uint16: 0)
            centralDirectory.append(uint16: dosDateTime.time)
            centralDirectory.append(uint16: dosDateTime.date)
            centralDirectory.append(uint32: crc)
            centralDirectory.append(uint32: UInt32(entry.data.count))
            centralDirectory.append(uint32: UInt32(entry.data.count))
            centralDirectory.append(uint16: UInt16(nameBytes.count))
            centralDirectory.append(uint16: 0)
            centralDirectory.append(uint16: 0)
            centralDirectory.append(uint16: 0)
            centralDirectory.append(uint16: 0)
            centralDirectory.append(uint32: 0)
            centralDirectory.append(uint32: localHeaderOffset)
            centralDirectory.append(contentsOf: nameBytes)
        }

        let centralDirectoryOffset = UInt32(output.count)
        let centralDirectorySize = UInt32(centralDirectory.count)
        output.append(centralDirectory)

        // End of central directory record
        output.append(uint32: 0x06054b50)
        output.append(uint16: 0)
        output.append(uint16: 0)
        output.append(uint16: UInt16(entries.count))
        output.append(uint16: UInt16(entries.count))
        output.append(uint32: centralDirectorySize)
        output.append(uint32: centralDirectoryOffset)
        output.append(uint16: 0)

        return output
    }

    private static func currentDosDateTime() -> (time: UInt16, date: UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let year = max(1980, components.year ?? 1980) - 1980
        let date = UInt16(year << 9) | UInt16((components.month ?? 1) << 5) | UInt16(components.day ?? 1)
        let time = UInt16((components.hour ?? 0) << 11) | UInt16((components.minute ?? 0) << 5) | UInt16(((components.second ?? 0) / 2))
        return (time, date)
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
    mutating func append(uint32 value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}

enum MinimalEPUB {
    static func build(title: String, articles: [Article]) -> Data {
        let bookId = "urn:uuid:\(UUID().uuidString)"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let modified = isoFormatter.string(from: Date())

        var entries: [MinimalZipEntry] = []

        // mimetype must be first, STORED, no extras
        entries.append(MinimalZipEntry(name: "mimetype", data: Data("application/epub+zip".utf8)))

        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        entries.append(MinimalZipEntry(name: "META-INF/container.xml", data: Data(container.utf8)))

        // Build chapter files
        var manifestItems: [String] = []
        var spineItems: [String] = []
        var navItems: [String] = []

        for (index, article) in articles.enumerated() {
            let chapterId = String(format: "chap%04d", index + 1)
            let chapterFile = "\(chapterId).xhtml"
            let chapterTitle = escapeXML(article.title.isEmpty ? "Untitled" : article.title)
            let chapterBody = chapterHTML(article: article, chapterNumber: index + 1)
            entries.append(MinimalZipEntry(name: "OEBPS/\(chapterFile)", data: Data(chapterBody.utf8)))
            manifestItems.append("<item id=\"\(chapterId)\" href=\"\(chapterFile)\" media-type=\"application/xhtml+xml\"/>")
            spineItems.append("<itemref idref=\"\(chapterId)\"/>")
            navItems.append("<li><a href=\"\(chapterFile)\">Chapter \(index + 1): \(chapterTitle)</a></li>")
        }

        let css = """
        body { font-family: -apple-system, Georgia, serif; line-height: 1.6; margin: 1.5em; }
        h1 { font-size: 1.6em; margin-bottom: 0.4em; }
        .byline { color: #666; font-size: 0.9em; margin-bottom: 1.4em; }
        p { margin: 0.6em 0; }
        """
        entries.append(MinimalZipEntry(name: "OEBPS/styles.css", data: Data(css.utf8)))
        manifestItems.append("<item id=\"css\" href=\"styles.css\" media-type=\"text/css\"/>")

        let navXhtml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>\(escapeXML(title))</title></head>
        <body>
        <nav epub:type="toc" id="toc"><h1>Contents</h1><ol>
        \(navItems.joined(separator: "\n"))
        </ol></nav>
        </body></html>
        """
        entries.append(MinimalZipEntry(name: "OEBPS/nav.xhtml", data: Data(navXhtml.utf8)))
        manifestItems.append("<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>")

        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="en">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">\(bookId)</dc:identifier>
            <dc:title>\(escapeXML(title))</dc:title>
            <dc:language>en</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            \(manifestItems.joined(separator: "\n    "))
          </manifest>
          <spine>
            \(spineItems.joined(separator: "\n    "))
          </spine>
        </package>
        """
        entries.append(MinimalZipEntry(name: "OEBPS/package.opf", data: Data(opf.utf8)))

        return MinimalZip.archive(entries: entries)
    }

    private static func chapterHTML(article: Article, chapterNumber: Int) -> String {
        let paragraphs = ArticleTextExtractor.paragraphs(from: article.content)
            .map { "<p>\(escapeXML($0))</p>" }
            .joined(separator: "\n")
        let title = escapeXML(article.title.isEmpty ? "Untitled" : article.title)
        let byline = [article.author, article.siteName].compactMap { $0 }.joined(separator: " · ")
        let bylineHTML = byline.isEmpty ? "" : "<p class=\"byline\">\(escapeXML(byline))</p>"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">
        <head><title>\(title)</title><link rel="stylesheet" type="text/css" href="styles.css"/></head>
        <body epub:type="chapter">
        <p class="byline">Chapter \(chapterNumber)</p>
        <h1>\(title)</h1>
        \(bylineHTML)
        \(paragraphs)
        </body></html>
        """
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
