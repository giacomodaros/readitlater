//
//  ViewController.swift
//  Shared (App)
//
//  Native reader app and Safari-extension container.
//

import SwiftUI
import Combine
import WebKit

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
                .shadow(color: .black.opacity(theme == .offWhite ? 0.08 : 0.28), radius: 18, y: 8)
        } else {
            self.readerGlassBarBackground(theme: theme)
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
        hostingController
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

    func save(url: String) async throws -> Article {
        try await send(path: "api/articles", method: "POST", body: ["url": url])
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

    func loadArticles() async {
        do {
            loadGeneration &+= 1
            let generation = loadGeneration
            let queryArchived = archived
            let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedSearch.isEmpty {
                withAnimation(.none) {
                    articles = queryArchived ? archiveArticles : inboxArticles
                }
            } else {
                loadCachedArticles()
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
            loading = false
            errorMessage = error.localizedDescription
        }
    }

    func select(_ article: ArticleSummary) async {
        selectedId = article.id
        if let cached = articleDetails[article.id] {
            selectedArticle = cached
            return
        } else {
            selectedArticle = Article(summary: article)
        }

        do {
            let fetched = try await api.article(id: article.id)
            articleDetails[article.id] = fetched
            selectedArticle = fetched
            saveCache()
        } catch {
            errorMessage = error.localizedDescription
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
            await loadArticles()
            selectedId = saved.id
            selectedArticle = saved
            saveCache()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        readingProgress[articleId] ?? 0
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

    func setProgress(_ value: Double, articleId: String) {
        let progress = max(0, min(1, value))
        let previous = readingProgress[articleId] ?? 0
        guard abs(previous - progress) >= 0.05 || progress >= 0.995 || progress <= 0.002 else { return }
        readingProgress[articleId] = progress
        if abs((persistedProgress[articleId] ?? 0) - progress) >= 0.20 || progress >= 0.995 {
            persistedProgress[articleId] = progress
            saveCache()
        }
        if progress >= 0.995,
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
            if horizontalSizeClass == .compact {
                CompactLibraryView(store: store, showingAdd: $showingAdd)
            } else {
                PadLibraryView(store: store, showingAdd: $showingAdd)
            }
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
    @FocusState private var searchFocused: Bool
    @Namespace private var selectionLoupeNamespace

    private var listSwipeArchiveEdge: HorizontalEdge { .leading }
    private var listSwipeDeleteEdge: HorizontalEdge { .trailing }

    private var isSearching: Bool {
        !store.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                store.theme.background.ignoresSafeArea()

                paneContent(pane)
                    .background(store.theme.background.ignoresSafeArea())

                if !store.selectionMode {
                    libraryToolbar
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if store.selectionMode && pane != .settings {
                    selectionToolbar
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.selectionMode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: store.search) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    guard !Task.isCancelled else { return }
                    await store.loadArticles()
                }
            }
            .navigationDestination(for: ArticleSummary.self) { article in
                CompactReaderDestination(summary: article, store: store)
            }
            .sheet(item: Binding(get: {
                exportShareURL.map { ShareableURL(url: $0) }
            }, set: { newValue in
                exportShareURL = newValue?.url
            })) { wrapper in
                ActivityShareSheet(activityItems: [wrapper.url])
            }
        }
    }

    @ViewBuilder
    private func paneContent(_ contentPane: CompactLibraryPane) -> some View {
        VStack(spacing: 0) {
            headerBar(for: contentPane)
            if contentPane == .settings {
                LibrarySettingsPane(store: store, exportShareURL: $exportShareURL)
            } else {
                articleSearchBar()
                articleList
            }
        }
        .background(store.theme.background.ignoresSafeArea())
        .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
        .safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: store.selectionMode ? 112 : 136)
        }
    }

    private func selectPane(_ newPane: CompactLibraryPane) {
        guard pane != newPane else { return }
        pane = newPane
        switch newPane {
        case .inbox:
            store.setArchiveMode(false)
            Task { await store.refreshAll() }
        case .archive:
            store.setArchiveMode(true)
            Task { await store.refreshAll() }
        case .settings:
            store.selectionMode = false
            store.selectedIds.removeAll()
        }
    }

    @ViewBuilder
    private var libraryToolbar: some View {
        Picker("Library", selection: Binding(get: { pane }, set: { selectPane($0) })) {
            Label("Inbox", systemImage: "tray").tag(CompactLibraryPane.inbox)
            Label("Archive", systemImage: "archivebox").tag(CompactLibraryPane.archive)
            Label("Settings", systemImage: "gearshape").tag(CompactLibraryPane.settings)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .tint(store.theme.primary)
        .preferredColorScheme(store.themePreference.scheme)
        .padding(.horizontal, 46)
    }

    @ViewBuilder
    private func articleSearchBar() -> some View {
        HStack(spacing: 8) {
            NativeSearchField(text: $store.search, theme: store.theme, isFirstResponder: $searchFocused)
                .frame(height: 46)
                .frame(maxWidth: 328)
                .preferredColorScheme(store.themePreference.scheme)
                .background(store.theme.glassBase, in: Capsule(style: .continuous))
                .nativeGlassCapsule(theme: store.theme)
                .transaction { transaction in
                    transaction.animation = nil
                }

            if isSearching {
                Button {
                    searchFocused = false
                    store.search = ""
                    Task { await store.loadArticles() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                        .accessibilityLabel("Clear search")
                }
                .foregroundStyle(store.theme.primary)
                .readerGlassIconButton(theme: store.theme)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: isSearching)
    }

    @ViewBuilder
    private func headerBar(for contentPane: CompactLibraryPane) -> some View {
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
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundStyle(store.theme.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .preferredColorScheme(store.themePreference.scheme)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private func headerTitle(for contentPane: CompactLibraryPane) -> String {
        if store.selectionMode {
            return "\(store.selectedIds.count) selected"
        }
        if contentPane == .settings {
            return "Settings"
        }
        return isSearching ? "Search" : (store.archived ? "Archive" : "Inbox")
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
    private var articleList: some View {
        List {
            ForEach(store.articles) { article in
                articleRow(for: article)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.defaultMinListRowHeight, 126)
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
            } else if let onArticleTap {
                row
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onArticleTap(article)
                    }
            } else {
                NavigationLink(value: article) {
                    row
                }
                .buttonStyle(.plain)
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .transaction { transaction in
            transaction.animation = nil
        }
        .contextMenu {
            articleMenu(article)
        }
        .preferredColorScheme(store.themePreference.scheme)
        .swipeActions(edge: listSwipeArchiveEdge, allowsFullSwipe: true) {
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
        .swipeActions(edge: listSwipeDeleteEdge, allowsFullSwipe: true) {
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

struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.modalPresentationStyle = .popover
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct LibrarySettingsPane: View {
    @ObservedObject var store: ReaderStore
    @Binding var exportShareURL: URL?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: Binding(get: { store.themePreference }, set: { store.setTheme($0) })) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                Picker("Font", selection: Binding(get: { store.readerFont }, set: { store.setReaderFont($0) })) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.label).tag(font)
                    }
                }
            }
            .listRowBackground(store.theme.panel)

            Section("Reader") {
                HStack {
                    Text("Font size")
                    Spacer()
                    Text("\(Int(store.textSize))")
                        .foregroundStyle(store.theme.secondary)
                }
                Slider(value: Binding(get: { store.textSize }, set: { store.setTextSize($0) }), in: 15...30, step: 1)

                HStack {
                    Text("Line spacing")
                    Spacer()
                    Text("\(Int(store.lineSpacing))")
                        .foregroundStyle(store.theme.secondary)
                }
                Slider(value: Binding(get: { store.lineSpacing }, set: { store.setLineSpacing($0) }), in: 2...18, step: 1)
            }
            .listRowBackground(store.theme.panel)

            Section("Highlights") {
                Button {
                    if let url = store.exportHighlightsCSV() {
                        exportShareURL = url
                    }
                } label: {
                    Label("Export highlights CSV", systemImage: "square.and.arrow.up")
                }
            }
            .listRowBackground(store.theme.panel)

            Section("Library") {
                Button {
                    Task {
                        if let url = await store.exportLibraryCSV() {
                            exportShareURL = url
                        }
                    }
                } label: {
                    Label("Export library CSV", systemImage: "tablecells")
                }
            }
            .listRowBackground(store.theme.panel)

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
            .listRowBackground(store.theme.panel)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(store.theme.background)
        .foregroundStyle(store.theme.primary)
    }
}

struct NativeSearchField: UIViewRepresentable {
    @Binding var text: String
    let theme: ReaderTheme
    @FocusState.Binding var isFirstResponder: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, isFirstResponder: $isFirstResponder) }

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
        searchBar.setShowsCancelButton(false, animated: false)
        applyTheme(to: searchBar)
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        if searchBar.text != text {
            searchBar.text = text
        }
        applyTheme(to: searchBar)
        let shouldShowCancel = isFirstResponder || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if searchBar.showsCancelButton != shouldShowCancel {
            searchBar.setShowsCancelButton(shouldShowCancel, animated: true)
        }
    }

    private func applyTheme(to searchBar: UISearchBar) {
        let dark = theme.isDark
        let textColor = dark ? UIColor.white.withAlphaComponent(0.95) : UIColor.label
        let placeholderColor = dark ? UIColor.white.withAlphaComponent(0.52) : UIColor.secondaryLabel
        let baseColor = UIColor(theme.glassBase)

        UIView.performWithoutAnimation {
            searchBar.overrideUserInterfaceStyle = dark ? .dark : .light
            searchBar.barTintColor = .clear
            searchBar.backgroundColor = .clear
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
            searchBar.searchTextField.clipsToBounds = true
            searchBar.searchTextField.backgroundColor = baseColor
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
        var isFirstResponder: FocusState<Bool>.Binding

        init(text: Binding<String>, isFirstResponder: FocusState<Bool>.Binding) {
            self.text = text
            self.isFirstResponder = isFirstResponder
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text.wrappedValue = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            isFirstResponder.wrappedValue = false
            searchBar.resignFirstResponder()
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
            searchBar.setShowsCancelButton(true, animated: true)
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            isFirstResponder.wrappedValue = false
            searchBar.setShowsCancelButton(!text.wrappedValue.isEmpty, animated: true)
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
                        ForEach(ReaderTheme.allCases) { theme in
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

    var body: some View {
        ZStack {
            store.theme.background.ignoresSafeArea()

            if let article {
                ReaderDetailView(article: article, store: store, onChromeVisibilityChange: { visible in
                    chromeVisible = visible
                }) {
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
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .foregroundStyle(store.theme.primary)
            .readerGlassIconButton(theme: store.theme)
            .padding(.leading, 18)
            .padding(.top, 10)
            .opacity(chromeVisible ? 1 : 0)
            .offset(y: chromeVisible ? 0 : -18)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: chromeVisible)
            .allowsHitTesting(chromeVisible)
        }
        .contentShape(Rectangle())
        .toolbar(.hidden, for: .navigationBar)
        .readerSystemChromeHidden(!chromeVisible)
        .background(NavigationGestureConfigurator().frame(width: 0, height: 0))
        .simultaneousGesture(edgeBackGesture)
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
            article = store.selectedArticle?.id == summary.id ? store.selectedArticle : Article(summary: summary)
            await store.select(summary)
            if store.selectedArticle?.id == summary.id {
                article = store.selectedArticle
            }
        }
    }

    private func postChromeVisibility(_ visible: Bool) {
        NotificationCenter.default.post(name: .readerChromeVisibilityChanged, object: visible)
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard value.startLocation.x <= 28 else { return }
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
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
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
                searchTask = Task {
                    guard !Task.isCancelled else { return }
                    await store.loadArticles()
                }
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
        HStack(alignment: .top, spacing: 12) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(selected ? Color.accentColor : theme.secondary.opacity(0.55))
                    .padding(.top, 6)
            }
            VStack(spacing: 6) {
                ArticleFavicon(article: article, theme: theme)
                if article.readAt == nil {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .padding(.top, -2)
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(article.title)
                    .font(.system(.headline, design: .default, weight: article.readAt == nil ? .semibold : .regular))
                    .lineLimit(2)
                    .foregroundStyle(theme.primary)
                if let description = article.description, !description.isEmpty {
                    Text(description)
                        .font(.system(.subheadline))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
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
                            .font(.caption)
                            .foregroundStyle(theme.secondary.opacity(0.78))
                    }
                    if let ttr = article.ttr {
                        Text("\(ttr) min")
                            .font(.caption)
                            .foregroundStyle(theme.secondary.opacity(0.78))
                    }
                    if progress > 0.01 {
                        Spacer(minLength: 0)
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(minHeight: 100, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(selected ? theme.selectedPanel : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    let onArchive: () -> Void
    let onDelete: () -> Void
    @State private var showPreferences = true
    @State private var lastScrollY: CGFloat?
    @State private var didRestoreScrollPosition = false

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
                }
                #if os(iOS)
                .background(
                    ScrollPositionRestorer(
                        progress: store.progress(for: article.id),
                        didRestore: $didRestoreScrollPosition
                    )
                )
                #endif
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
            setChromeVisible(true)
        }
        .onDisappear {
            setChromeVisible(true)
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
        74
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
        guard let lastScrollY else {
            self.lastScrollY = y
            setChromeVisible(y > -72)
            store.setProgress(state.progress, articleId: article.id)
            return
        }

        if y >= -8 {
            setChromeVisible(true)
        } else if y < -72 || y < lastScrollY - 3 {
            setChromeVisible(false)
        } else if y > lastScrollY + 16 {
            setChromeVisible(true)
        }
        store.setProgress(state.progress, articleId: article.id)
        self.lastScrollY = y
    }

    private func setChromeVisible(_ visible: Bool) {
        guard showPreferences != visible else { return }
        showPreferences = visible
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.clear)
                    .presentationDetents([.height(318), .medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.clear)
                    .preferredColorScheme(store.themePreference.scheme)
            }
            #else
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                ReaderSettingsPanel(store: store)
                    .frame(width: 340)
                    .padding(18)
                    .background(store.theme.background)
                    .preferredColorScheme(store.themePreference.scheme)
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
            .preferredColorScheme(store.themePreference.scheme)
        }
        .font(.system(size: 16, weight: .semibold, design: .default))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .readerGlassBarBackground(theme: store.theme)
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
        VStack(alignment: .leading, spacing: 8) {
            SettingsSection(title: "Theme", theme: store.theme) {
                Picker("Theme", selection: Binding(get: { store.themePreference }, set: { store.setTheme($0) })) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            SettingsSection(title: "Font", theme: store.theme) {
                Picker("Font", selection: Binding(get: { store.readerFont }, set: { store.setReaderFont($0) })) {
                    ForEach(ReaderFont.allCases) { font in
                        Text(font.label).tag(font)
                    }
                }
                .pickerStyle(.segmented)
            }

            SettingsSection(title: "Font Size", value: "\(Int(store.textSize))", theme: store.theme) {
                Slider(value: Binding(get: { store.textSize }, set: { store.setTextSize($0) }), in: 15...30, step: 1)
            }

            SettingsSection(title: "Line Spacing", value: "\(Int(store.lineSpacing))", theme: store.theme) {
                Slider(value: Binding(get: { store.lineSpacing }, set: { store.setLineSpacing($0) }), in: 2...18, step: 1)
            }
        }
        .padding(14)
        .readerGlassBarBackground(theme: store.theme)
        .tint(store.theme.primary)
        .environment(\.colorScheme, store.theme.isDark ? .dark : .light)
        .foregroundStyle(store.theme.primary)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                if let value {
                    Text(value)
                        .foregroundStyle(theme.secondary)
                }
            }
            .font(.system(.footnote, design: .default, weight: .medium))
            .foregroundStyle(theme.primary)

            content
        }
        .padding(.vertical, 1)
    }
}

struct ReaderScrollState: Equatable {
    let y: CGFloat
    let progress: Double
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

        if #available(iOS 18.0, macOS 15.0, *) {
            scrollView
                .onScrollGeometryChange(for: ReaderScrollState.self) { geometry in
                    let scrollableHeight = max(1, geometry.contentSize.height - geometry.containerSize.height)
                    let bottomOffset = geometry.contentOffset.y + geometry.containerSize.height
                    let remaining = geometry.contentSize.height - bottomOffset
                    let progress = remaining <= 28 ? 1 : min(1, max(0, geometry.contentOffset.y / scrollableHeight))
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
struct ScrollPositionRestorer: UIViewRepresentable {
    let progress: Double
    @Binding var didRestore: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard !didRestore, progress > 0.02 else { return }
        DispatchQueue.main.async {
            guard !didRestore,
                  let scrollView = view.enclosingScrollView else {
                return
            }
            let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            guard maxOffset > 1 else { return }
            let targetY = min(maxOffset, max(0, maxOffset * progress))
            scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
            didRestore = true
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
        let signature = "\(text.hashValue)-\(theme.rawValue)-\(readerFont.rawValue)-\(textSize)-\(lineSpacing)-\(availableWidth)-\(highlightsVersion)-\(highlights.hashValue)"
        if context.coordinator.signature != signature {
            context.coordinator.signature = signature
            textView.attributedText = attributedText
        }
        textView.textColor = UIColor(theme.primary)
        textView.textContainer.size = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        recalculateHeight(textView)
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

    private func recalculateHeight(_ textView: UITextView) {
        let width = max(1, availableWidth)
        let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        guard size.height.isFinite, abs(height - size.height) > 1 else { return }
        DispatchQueue.main.async {
            height = size.height
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
            parent.recalculateHeight(textView)
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
            textView.selectedRange = targetRanges.last ?? .init(location: 0, length: 0)
            parent.recalculateHeight(textView)
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
            parent.recalculateHeight(textView)
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
