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
#elseif os(macOS)
import Cocoa
import SafariServices
typealias PlatformViewController = NSViewController
#endif

let extensionBundleIdentifier = "com.giacomodaros.library.Extension"
let appBaseURL = URL(string: "https://readitlater-theta.vercel.app")!
let appGroupIdentifier = "group.com.giacomodaros.library"

class ViewController: PlatformViewController {
    @IBOutlet var webView: WKWebView?

    #if os(iOS)
    private var hostingController: UIHostingController<ReaderRootView>?
    #elseif os(macOS)
    private var hostingView: NSHostingView<ReaderRootView>?
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        webView?.removeFromSuperview()

        let root = ReaderRootView(store: ReaderStore())

        #if os(iOS)
        let hosting = UIHostingController(rootView: root)
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
    let labels: [ReaderLabel]
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
    let labels: [ReaderLabel]
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
            return UserDefaults.standard.string(forKey: tokenKey)
        }
        set {
            defaults.set(newValue, forKey: tokenKey)
            UserDefaults.standard.set(newValue, forKey: tokenKey)
        }
    }

    var email: String? {
        get {
            if let email = defaults.string(forKey: emailKey) {
                return email
            }
            return UserDefaults.standard.string(forKey: emailKey)
        }
        set {
            defaults.set(newValue, forKey: emailKey)
            UserDefaults.standard.set(newValue, forKey: emailKey)
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
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }

            let standard = ISO8601DateFormatter()
            if let date = standard.date(from: value) { return date }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
        }
        self.decoder = decoder
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

    func articles(archived: Bool = false, search: String = "") async throws -> [ArticleSummary] {
        var items = [URLQueryItem(name: "archived", value: archived ? "true" : "false")]
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "search", value: search))
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

    var isSignedIn: Bool {
        tokenStore.token != nil
    }

    func bootstrap() {
        consumePendingShareURL()
        guard isSignedIn else { return }
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

    func loadArticles() async {
        do {
            loading = true
            errorMessage = nil
            articles = try await api.articles(archived: archived, search: search)
            loading = false
            if selectedId == nil, let first = articles.first {
                await select(first)
            } else if articles.isEmpty {
                selectedArticle = nil
                selectedId = nil
            }
        } catch {
            loading = false
            errorMessage = error.localizedDescription
        }
    }

    func select(_ article: ArticleSummary) async {
        do {
            selectedId = article.id
            selectedArticle = try await api.article(id: article.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(url: String) async {
        do {
            errorMessage = nil
            let saved = try await api.save(url: url)
            await loadArticles()
            selectedId = saved.id
            selectedArticle = saved
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleArchive() async {
        guard let article = selectedArticle else { return }
        do {
            _ = try await api.setArchived(!article.archived, articleId: article.id)
            selectedArticle = nil
            selectedId = nil
            await loadArticles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum AuthMode {
    case login
    case register
}

enum ReaderTheme: String, CaseIterable, Identifiable {
    case offWhite
    case darkGray
    case oled

    var id: String { rawValue }

    static func load() -> ReaderTheme {
        guard let raw = UserDefaults.standard.string(forKey: "reader.native.theme"),
              let theme = ReaderTheme(rawValue: raw) else {
            return .offWhite
        }
        return theme
    }

    var label: String {
        switch self {
        case .offWhite: "Paper"
        case .darkGray: "Graphite"
        case .oled: "OLED"
        }
    }

    var background: Color {
        switch self {
        case .offWhite: Color(red: 0.972, green: 0.964, blue: 0.94)
        case .darkGray: Color(red: 0.075, green: 0.075, blue: 0.08)
        case .oled: .black
        }
    }

    var panel: Color {
        switch self {
        case .offWhite: Color.white.opacity(0.72)
        case .darkGray: Color(red: 0.13, green: 0.13, blue: 0.14).opacity(0.92)
        case .oled: Color(red: 0.035, green: 0.035, blue: 0.04).opacity(0.96)
        }
    }

    var selectedPanel: Color {
        switch self {
        case .offWhite: Color.black.opacity(0.08)
        case .darkGray, .oled: Color.white.opacity(0.13)
        }
    }

    var primary: Color {
        switch self {
        case .offWhite: Color(red: 0.08, green: 0.08, blue: 0.085)
        case .darkGray, .oled: Color.white.opacity(0.95)
        }
    }

    var secondary: Color {
        switch self {
        case .offWhite: Color.black.opacity(0.56)
        case .darkGray, .oled: Color.white.opacity(0.62)
        }
    }

    var hairline: Color {
        switch self {
        case .offWhite: Color.black.opacity(0.10)
        case .darkGray, .oled: Color.white.opacity(0.12)
        }
    }

    var scheme: ColorScheme {
        switch self {
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

    var body: some View {
        NavigationStack {
            ZStack {
                store.theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.archived ? "Archive" : "Library")
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
                            store.archived.toggle()
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.articles) { article in
                                NavigationLink(value: article) {
                                    ArticleRow(article: article, selected: false, theme: store.theme)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ArticleSummary.self) { article in
                CompactReaderDestination(summary: article, store: store)
            }
        }
    }
}

struct CompactReaderDestination: View {
    let summary: ArticleSummary
    @ObservedObject var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @State private var article: Article?

    var body: some View {
        ZStack {
            store.theme.background.ignoresSafeArea()

            if let article {
                ReaderDetailView(article: article, store: store) {
                    Task { await store.toggleArchive() }
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(store.theme.primary)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(store.theme.hairline)
                    }
            }
            .buttonStyle(.plain)
            .padding(.leading, 18)
            .padding(.top, 10)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .onEnded { value in
                    guard value.startLocation.x < 32,
                          value.translation.width > 72,
                          abs(value.translation.height) < 90 else {
                        return
                    }
                    dismiss()
                }
        )
        .toolbar(.hidden, for: .navigationBar)
        .task(id: summary.id) {
            article = nil
            await store.select(summary)
            article = store.selectedArticle
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
                    store.archived.toggle()
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
                        ArticleRow(article: article, selected: store.selectedId == article.id, theme: store.theme)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(article.title)
                .font(.system(.headline, design: .default, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(theme.primary)
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? theme.selectedPanel : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ReaderDetailView: View {
    let article: Article
    @ObservedObject var store: ReaderStore
    let onArchive: () -> Void
    @State private var showPreferences = true
    @State private var lastScrollY: CGFloat?

    var body: some View {
        ZStack(alignment: .bottom) {
            TrackableScrollView(onOffsetChange: updatePreferenceVisibility) {
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
                        theme: store.theme,
                        readerFont: store.readerFont,
                        textSize: store.textSize,
                        lineSpacing: store.lineSpacing
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, 118)
                .frame(maxWidth: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if value.translation.height < -10 {
                            showPreferences = false
                        } else if value.translation.height > 10 {
                            showPreferences = true
                        }
                    }
            )

            ReaderCommandBar(store: store, article: article, onArchive: onArchive)
                .padding(.bottom, 18)
                .opacity(showPreferences ? 1 : 0)
                .offset(y: showPreferences ? 0 : 34)
                .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showPreferences)
                .allowsHitTesting(showPreferences)
        }
        .background(store.theme.background)
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

    private func updatePreferenceVisibility(_ y: CGFloat) {
        guard let lastScrollY else {
            self.lastScrollY = y
            return
        }

        if y >= -4 {
            showPreferences = true
        } else if y < lastScrollY - 4 {
            showPreferences = false
        } else if y > lastScrollY + 4 {
            showPreferences = true
        }
        self.lastScrollY = y
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
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 8) {
            ShareLink(item: articleURL) {
                Image(systemName: "square.and.arrow.up")
                    .accessibilityLabel("Share")
            }
            .buttonStyle(LiquidGlassIconButtonStyle(theme: store.theme))

            Button(action: onArchive) {
                Image(systemName: article.archived ? "tray.and.arrow.up" : "archivebox")
                    .accessibilityLabel(article.archived ? "Unarchive" : "Archive")
            }
            .buttonStyle(LiquidGlassIconButtonStyle(theme: store.theme))

            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "textformat")
                    .accessibilityLabel("Reader settings")
            }
            .buttonStyle(LiquidGlassIconButtonStyle(theme: store.theme))
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                ReaderSettingsPanel(store: store)
                    .frame(width: 340)
                    .padding(18)
                    .background(store.theme.background)
                    .preferredColorScheme(store.theme.scheme)
            }
        }
        .padding(8)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(store.theme.hairline)
                }
                .shadow(color: .black.opacity(store.theme == .offWhite ? 0.16 : 0.55), radius: 28, y: 14)
        }
        .padding(.horizontal, 20)
    }

    private var articleURL: URL {
        URL(string: article.url) ?? appBaseURL
    }
}

struct LiquidGlassIconButtonStyle: ButtonStyle {
    let theme: ReaderTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .default))
            .foregroundStyle(theme.primary)
            .frame(width: 44, height: 44)
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

struct TrackableScrollView<Content: View>: View {
    let onOffsetChange: (CGFloat) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("readerScroll")).minY)
            }
            .frame(height: 0)

            content
        }
        .coordinateSpace(name: "readerScroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self, perform: onOffsetChange)
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
    let theme: ReaderTheme
    let readerFont: ReaderFont
    let textSize: Double
    let lineSpacing: Double

    private var paragraphs: [String] {
        ArticleTextExtractor.paragraphs(from: html)
    }

    var body: some View {
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
    }

    private var paragraphSpacing: CGFloat {
        max(12, CGFloat(lineSpacing) + 8)
    }
}

enum ArticleTextExtractor {
    static func paragraphs(from html: String) -> [String] {
        let source = html
            .replacingOccurrences(of: "</p>", with: "</p>\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br>", with: "<br>\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "<br/>\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "<br />\n", options: .caseInsensitive)

        let text: String
        if let attributed = try? NSAttributedString(
            data: Data(source.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ) {
            text = attributed.string
        } else {
            text = source.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        }

        return text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
