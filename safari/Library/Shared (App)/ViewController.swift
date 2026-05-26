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
        self
            .font(.system(size: 16, weight: .semibold, design: .default))
            .buttonStyle(.plain)
            .readerGlassPressAnimation()
    }

    @ViewBuilder
    func readerGlassBarBackground(theme: ReaderTheme) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(theme == .offWhite ? 0.12 : 0.42), radius: 24, y: 12)
            }
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
    @Published var theme: ReaderTheme = ReaderTheme.load()
    @Published var textSize: Double = {
        let stored = UserDefaults.standard.double(forKey: "reader.native.textSize")
        return stored == 0 ? 19 : stored
    }()
    @Published var lineSpacing: Double = {
        let stored = UserDefaults.standard.double(forKey: "reader.native.lineSpacing")
        return stored == 0 ? 8 : stored
    }()
    @Published var readerFont: ReaderFont = ReaderFont.load()

    let api = ReaderAPI()
    let tokenStore = TokenStore.shared
    private let cache = ArticleCache.shared
    private var articleDetails: [String: Article] = [:]
    private var readingProgress: [String: Double] = [:]
    private var persistedProgress: [String: Double] = [:]
    private var prefetchingArticleIds = Set<String>()
    private var cacheSaveWorkItem: DispatchWorkItem?
    private var markingReadArticleIds = Set<String>()

    var isSignedIn: Bool {
        tokenStore.token != nil
    }

    func bootstrap() {
        consumePendingShareURL()
        guard isSignedIn else { return }
        loadCachedArticles()
        Task { await loadArticles() }
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
        theme = value
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
        articles = []
        selectedArticle = nil
        selectedId = nil
        loadCachedArticles()
    }

    func loadArticles() async {
        do {
            loadCachedArticles()
            loading = true
            errorMessage = nil
            let fetched = try await api.articles(archived: archived, search: search)
            articles = fetched
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
            errorMessage = error.localizedDescription
        }
        if !targetArchived {
            seedOppositeArchiveCache(with: updatedSummary)
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
        readingProgress[articleId] = progress
        if abs((persistedProgress[articleId] ?? 0) - progress) >= 0.12 || progress >= 0.98 {
            persistedProgress[articleId] = progress
            saveCache()
        }
        if progress >= 0.985,
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

    private func seedOppositeArchiveCache(with summary: ArticleSummary) {
        guard let account = tokenStore.email,
              let inboxCache = cache.load(account: account, archived: false, search: "") else {
            return
        }
        let merged = mergeSummaries(existing: inboxCache.articles, incoming: [summary])
        cache.save(
            account: account,
            archived: false,
            articles: merged,
            details: articleDetails,
            progress: readingProgress
        )
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

    var body: some View {
        Group {
            if store.isSignedIn {
                LibraryView(store: store)
            } else {
                AuthView(store: store)
            }
        }
        .task {
            store.bootstrap()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .sharedArticleURLReceived)) { notification in
            guard let url = notification.object as? URL else { return }
            Task { await store.add(url: url.absoluteString) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            store.consumePendingShareURL()
            guard store.isSignedIn else { return }
            Task { await store.loadArticles() }
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
                splitLayout
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
        .preferredColorScheme(store.theme.scheme)
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
struct CompactLibraryView: View {
    @ObservedObject var store: ReaderStore
    @Binding var showingAdd: Bool
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                store.theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.archived ? "Archive" : "Inbox")
                                .font(.system(.largeTitle, design: .default, weight: .bold))
                                .foregroundStyle(store.theme.primary)
                            Text("\(store.articles.count) articles")
                                .font(.title3)
                                .foregroundStyle(store.theme.secondary)
                        }

                        Spacer()

                        Button { showingAdd = true } label: {
                            Image(systemName: "plus")
                        }
                        .font(.title2)

                        Button {
                            store.setArchiveMode(!store.archived)
                            Task { await store.loadArticles() }
                        } label: {
                            Image(systemName: store.archived ? "tray" : "archivebox")
                        }
                        .font(.title2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(store.theme.secondary)
                        TextField("Search", text: $store.search)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .submitLabel(.search)
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(searchMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(store.theme.hairline)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)

                    List {
                        ForEach(store.articles) { article in
                            NavigationLink(value: article) {
                                ArticleRow(article: article, selected: false, theme: store.theme, progress: store.progress(for: article.id))
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                articleMenu(article)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await store.delete(article) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    Task {
                                        if store.archived {
                                            await store.unarchive(article)
                                        } else {
                                            await store.archive(article)
                                        }
                                    }
                                } label: {
                                    Label(store.archived ? "Unarchive" : "Archive", systemImage: store.archived ? "tray.and.arrow.up" : "archivebox")
                                }
                                .tint(.blue)

                                Button {
                                    Task { await store.toggleRead(article) }
                                } label: {
                                    Label(article.readAt == nil ? "Read" : "Unread", systemImage: article.readAt == nil ? "checkmark.circle" : "circle")
                                }
                                .tint(.green)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: store.search) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    guard !Task.isCancelled else { return }
                    await store.loadArticles()
                }
            }
            .navigationDestination(for: ArticleSummary.self) { article in
                CompactReaderDestination(summary: article, store: store)
            }
        }
    }

    private var searchMaterial: AnyShapeStyle {
        store.theme.scheme == .dark ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.white.opacity(0.72))
    }

    @ViewBuilder
    private func articleMenu(_ article: ArticleSummary) -> some View {
        Button {
            Task { await store.toggleRead(article) }
        } label: {
            Label(article.readAt == nil ? "Mark as Read" : "Mark as Unread", systemImage: article.readAt == nil ? "checkmark.circle" : "circle")
        }
        Button {
            Task {
                if store.archived {
                    await store.unarchive(article)
                } else {
                    await store.archive(article)
                }
            }
        } label: {
            Label(store.archived ? "Unarchive" : "Archive", systemImage: store.archived ? "tray.and.arrow.up" : "archivebox")
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
                    Task { await store.toggleArchive() }
                    dismiss()
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
                    Task { await store.loadArticles() }
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.articles) { article in
                        ArticleRow(article: article, selected: store.selectedId == article.id, theme: store.theme, progress: store.progress(for: article.id))
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onTapGesture {
                                Task { await store.select(article) }
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
    }
}

struct ArticleRow: View {
    let article: ArticleSummary
    let selected: Bool
    let theme: ReaderTheme
    let progress: Double

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ArticleFavicon(article: article, theme: theme)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(article.readAt == nil ? Color.accentColor : theme.secondary.opacity(0.22))
                        .frame(width: 8, height: 8)
                    Text(article.title)
                        .font(.system(.headline, design: .default, weight: article.readAt == nil ? .semibold : .regular))
                        .lineLimit(2)
                        .foregroundStyle(theme.primary)
                }
                if let description = article.description, !description.isEmpty {
                    Text(description)
                        .font(.system(.subheadline))
                        .foregroundStyle(theme.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let siteName = article.siteName { Text(siteName) }
                    if let ttr = article.ttr { Text("\(ttr) min") }
                }
                .font(.caption)
                .foregroundStyle(theme.secondary.opacity(0.75))
                if progress > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor.opacity(0.78))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? theme.selectedPanel : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ArticleFavicon: View {
    let article: ArticleSummary
    let theme: ReaderTheme

    var body: some View {
        Group {
            if let faviconURL {
                AsyncImage(url: faviconURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
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

struct ReaderDetailView: View {
    let article: Article
    @ObservedObject var store: ReaderStore
    var onChromeVisibilityChange: ((Bool) -> Void)?
    let onArchive: () -> Void
    let onDelete: () -> Void
    @State private var showPreferences = true
    @State private var lastScrollY: CGFloat?

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                let outerWidth = min(proxy.size.width, contentWidth)
                let readableWidth = max(1, outerWidth - horizontalPadding * 2)
                TrackableScrollView(onScrollChange: updatePreferenceVisibility) {
                    VStack(alignment: .leading, spacing: 24) {
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
                            theme: store.theme,
                            readerFont: store.readerFont,
                            textSize: store.textSize,
                            lineSpacing: store.lineSpacing
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
    @ObservedObject var store: ReaderStore
    let article: Article
    let onArchive: () -> Void
    let onDelete: () -> Void
    @State private var showingSettings = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            ShareLink(item: articleURL) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .accessibilityLabel("Share")
            }
            .foregroundStyle(store.theme.primary)
            .readerGlassBarButton(theme: store.theme)

            Button(action: onArchive) {
                Image(systemName: currentArticle.archived ? "tray.and.arrow.up" : "archivebox")
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .accessibilityLabel(currentArticle.archived ? "Unarchive" : "Archive")
            }
            .foregroundStyle(store.theme.primary)
            .readerGlassBarButton(theme: store.theme)

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
            #if os(iOS)
            .sheet(isPresented: $showingSettings) {
                ReaderSettingsPanel(store: store)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                    .background(.clear)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
                    .preferredColorScheme(store.theme.scheme)
            }
            #else
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                ReaderSettingsPanel(store: store)
                    .frame(width: 340)
                    .padding(18)
                    .background(store.theme.background)
                    .preferredColorScheme(store.theme.scheme)
            }
            #endif

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
            Text("Reader")
                .font(.system(.title3, design: .default, weight: .semibold))
                .foregroundStyle(store.theme.primary)

            SettingsSection(title: "Theme", theme: store.theme) {
                Picker("Theme", selection: Binding(get: { store.theme }, set: { store.setTheme($0) })) {
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
        VStack(alignment: .leading, spacing: 8) {
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
                    let progress = min(1, max(0, geometry.contentOffset.y / scrollableHeight))
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

struct HTMLText: View {
    let html: String
    let fallback: String?
    let theme: ReaderTheme
    let readerFont: ReaderFont
    let textSize: Double
    let lineSpacing: Double

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
                    theme: theme,
                    readerFont: readerFont,
                    textSize: textSize,
                    lineSpacing: lineSpacing
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
        max(12, CGFloat(lineSpacing) + 8)
    }
}

#if os(iOS)
struct SelectableArticleText: View {
    let text: String
    let theme: ReaderTheme
    let readerFont: ReaderFont
    let textSize: Double
    let lineSpacing: Double
    @State private var height: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            NativeSelectableTextView(
                text: text,
                theme: theme,
                readerFont: readerFont,
                textSize: textSize,
                lineSpacing: lineSpacing,
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
    let theme: ReaderTheme
    let readerFont: ReaderFont
    let textSize: Double
    let lineSpacing: Double
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
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let signature = "\(text.hashValue)-\(theme.rawValue)-\(readerFont.rawValue)-\(textSize)-\(lineSpacing)-\(availableWidth)"
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
        paragraphStyle.paragraphSpacing = max(12, CGFloat(lineSpacing) + 8)

        return NSAttributedString(
            string: text,
            attributes: [
                .font: readerFont.uiFont(size: CGFloat(textSize)),
                .foregroundColor: UIColor(theme.primary),
                .paragraphStyle: paragraphStyle,
            ]
        )
    }

    private func recalculateHeight(_ textView: UITextView) {
        let width = max(1, availableWidth)
        let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        guard size.height.isFinite, abs(height - size.height) > 1 else { return }
        DispatchQueue.main.async {
            height = size.height
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIContextMenuInteractionDelegate {
        var parent: NativeSelectableTextView
        var signature = ""
        weak var textView: UITextView?

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

        private func selectionMenu(for textView: UITextView, ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            let hasSelection = ranges.contains { $0.rangeValue.length > 0 } || textView.selectedRange.length > 0
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

        private func applyHighlight(to textView: UITextView, ranges: [NSValue]) {
            let selected = ranges.map(\.rangeValue).filter { $0.length > 0 }
            let targetRanges = selected.isEmpty && textView.selectedRange.length > 0 ? [textView.selectedRange] : selected
            guard !targetRanges.isEmpty else { return }

            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            for range in targetRanges where NSMaxRange(range) <= mutable.length {
                mutable.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.42), range: range)
            }
            textView.attributedText = mutable
            textView.selectedRange = targetRanges.last ?? .init(location: 0, length: 0)
            parent.recalculateHeight(textView)
        }

        private func deleteHighlight(in textView: UITextView, range: NSRange) {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
            guard NSMaxRange(range) <= mutable.length else { return }
            mutable.removeAttribute(.backgroundColor, range: range)
            textView.attributedText = mutable
            textView.selectedRange = NSRange(location: range.location, length: 0)
            parent.recalculateHeight(textView)
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
            .filter { !$0.isEmpty }

        if !paragraphs.isEmpty { return paragraphs }

        let stripped = decodeEntities(source.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return stripped.isEmpty ? [] : [stripped]
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
