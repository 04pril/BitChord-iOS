import BitChordCore
import InnerTube
import PlaybackQueue
import SwiftUI

/// Home (ports ui/screens/HomeScreen.kt and how MainActivity.kt places it on the Home tab).
///
/// Top to bottom, as on Android: the page title ("Listen Now", here the navigation bar's large
/// title — the iOS form of a big in-list heading that hands over to the bar as it scrolls away),
/// the sign-in banner when signed out, then YouTube Music's shelves. "Recents" leads when signed
/// in, as a sideways row of four-track columns or big cards (toggled in its heading); otherwise the first
/// shelf is the big-card hero; every other shelf is a row of square cards. More shelves load as
/// the end nears, and pulling down refreshes in place.
///
/// Tapping a song card plays it as a one-off (MainActivity's `playRadio`: it plays, the listener's
/// queue follows, AutoPlay carries on); tapping any other card opens its page. Holding a card opens
/// the song or album/playlist menu (none for artists). There is no toolbar of its own: the shared
/// top bar is the only chrome.
struct HomeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var feed = HomeFeedModel()
    /// The shelves on screen (by `feedKey`), so paging only runs while the tail is in view.
    @State private var onScreen: Set<String> = []
    @State private var openingProxy = false

    var body: some View {
        let state = feed.state
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !model.accounts.isSignedIn {
                        SignInBanner(
                            onSignIn: { model.router.present(.googleSignIn) },
                            onProxy: { openingProxy = true }
                        )
                            .frame(width: proxy.size.width, alignment: .leading)
                            .padding(.bottom, 8)
                    }
                    // Each state gets a container of its own. The shell's version switched states
                    // inside one LazyVStack, skeletons as `ForEach(0..<4, id: \.self)` and shelves as
                    // `ForEach(…, id: \.offset)`: the same ids, so the lazy stack kept the skeleton
                    // rows it already had and Home stayed on its skeleton over a loaded feed.
                    switch state {
                    case .loading:
                        VStack(alignment: .leading, spacing: 0) {
                            if feed.recentlyPlayedLoading {
                                RecentsSkeleton(listLayout: settings.homeRecentsViewType == .list, width: proxy.size.width)
                                // Recents owns the leading layout while it loads, so the feed
                                // behind it starts with ordinary shelves rather than a hero.
                                FeedSkeleton(firstIsHero: false, width: proxy.size.width)
                            } else {
                                FeedSkeleton(width: proxy.size.width)
                            }
                        }
                        .transition(.opacity)
                    case .error(let message):
                        BrowseMessage(message: message, actionTitle: L10n.retry) { reload() }
                        // The feed needs a connection; what's already on the device doesn't.
                        Button(DownloadsText.offlineBackup) { model.router.open(.offlineBackup) }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("home.offlineBackup")
                    case .success(let shelves):
                        shelfList(shelves, width: proxy.size.width)
                    }
                }
                .frame(width: proxy.size.width, alignment: .leading)
                .padding(.bottom, 16)
            }
            .refreshable {
                await feed.refresh(model.repository, listener: model.accounts.listenerKey, signedIn: model.accounts.isSignedIn)
            }
        }
        .navigationTitle(L10n.listenNow)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $openingProxy) { ProxySettingsScreen() }
        .task {
            #if DEBUG
            if BrowseDebugLaunch.take("explore") != nil || BrowseDebugLaunch.target == "moodGenre" {
                model.router.select(.explore)
            } else if let query = BrowseDebugLaunch.take("search:") {
                model.router.select(.search)
                model.router.pendingSearch = AppRouter.PendingSearch(query: query, play: false)
            } else if BrowseDebugLaunch.target?.hasPrefix("typing:") == true {
                model.router.select(.search)
            } else if BrowseDebugLaunch.take("recents") != nil {
                for song in BrowseDebugLaunch.sampleRecents { model.searchHistory.record(SearchHistoryEntity(song: song)) }
                model.searchHistory.record(SearchHistoryEntity(item: BrowseItem(
                    browseId: "UC_kRDKYrUlrbtrSiyu5Tflg", title: "Daft Punk", subtitle: "", thumbnailUrl: nil, type: .artist)))
                model.router.select(.search)
            }
            #endif
        }
        .task(id: model.accounts.listenerKey) {
            // A different listener (sign-in, profile switch, sign-out) gets their own feed.
            guard !feed.isLoaded(for: model.accounts.listenerKey) else { return }
            reload()
        }
        // A container: without this the screen identifier lands on every child and hides theirs.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.home")
    }

    private func shelfList(_ shelves: [HomeShelf], width: CGFloat) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if feed.recentlyPlayedLoading {
                RecentsSkeleton(listLayout: settings.homeRecentsViewType == .list, width: width)
            }
            // Keyed by position and title, like HomeScreen.kt's `shelf.title + index`.
            ForEach(Array(shelves.enumerated()), id: \.element.feedKey) { index, shelf in
                shelfView(index: index, shelf: shelf, width: width)
                    .onAppear {
                        onScreen.insert(shelf.feedKey)
                        // Re-checked for every shelf that comes into view rather than on the edge
                        // of "the tail is visible": a page that appends a shelf or two leaves the
                        // list still near its end, and must ask again (HomeScreen.kt).
                        loadMoreIfNearEnd()
                    }
                    .onDisappear { onScreen.remove(shelf.feedKey) }
                    .prefetchingShelfCovers(after: index, in: shelves)
            }
            if feed.loadingMore {
                ShelfCardsSkeleton()
            }
        }
        .onChange(of: feed.loadingMore) { _, busy in
            // A page that settled with the tail still on screen asks for the next one straight
            // away (HomeScreen.kt restarts its check on `loadingMore`). Only with the tail in view:
            // asking whenever a page settled would walk the whole feed with the reader at the top.
            if !busy { loadMoreIfNearEnd() }
        }
    }

    @ViewBuilder
    private func shelfView(index: Int, shelf: HomeShelf, width: CGFloat) -> some View {
        let open: (ShelfItem) -> Void = { item in openItem(item, shelfTitle: shelf.title) }
        if index == 0 && shelf.title.caseInsensitiveCompare(Self.recentsTitle) == .orderedSame {
            RecentShelf(shelf: shelf, width: width, onOpen: open, onMenu: openMenu)
        } else if index == 0 && !feed.recentlyPlayedLoading {
            // The loading skeleton already owns the hero slot until Recents lands.
            HeroShelf(shelf: shelf, width: width, onOpen: open, onMenu: openMenu)
        } else {
            HomeShelfRow(shelf: shelf, onOpen: open, onMenu: openMenu)
        }
    }

    /// The Recents shelf's title as the repository names it (HomeScreen.kt's `RECENTS_TITLE`).
    static let recentsTitle = "Recents"

    private func reload() {
        let catalog = model.repository
        let listener = model.accounts.listenerKey
        let signedIn = model.accounts.isSignedIn
        onScreen.removeAll()
        // Unstructured, like Android's viewModelScope: leaving the tab mid-load must not cancel
        // the requests and strand the page on its skeleton.
        Task { await feed.load(catalog, listener: listener, signedIn: signedIn) }
    }

    /// HomeScreen.kt's paging check: nothing in flight (a continuation page or a first-page
    /// request), a page left to ask for, and one of the last three shelves on screen.
    private func loadMoreIfNearEnd() {
        guard !feed.loadingMore, feed.continuation != nil, let shelves = feed.state.value else { return }
        guard shelves.suffix(3).contains(where: { onScreen.contains($0.feedKey) }) else { return }
        let catalog = model.repository
        Task { await feed.loadMore(catalog) }
    }

    /// MainActivity's Home `onItemClick`: a song card starts a one-off from itself; any other card
    /// opens its page.
    private func openItem(_ item: ShelfItem, shelfTitle: String) {
        BrowseNavigator(app: model).openCard(item, source: QueueSource(title: shelfTitle, type: .home))
    }

    /// MainActivity's `onShelfLongPress`.
    private func openMenu(_ item: ShelfItem) {
        BrowseNavigator(app: model).openCardMenu(item)
    }
}

extension HomeShelf {
    /// A shelf's identity in a feed: titles are unique there (the feed de-duplicates by title).
    var feedKey: String { title.lowercased() }
}

/// Common.kt's `SignInBanner`: a rounded panel inviting the guest to sign in.
struct SignInBanner: View {
    let onSignIn: () -> Void
    let onProxy: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Keep both actions reachable before opening the login browser. Accessibility text
        // sizes stack the buttons instead of squeezing their labels off screen.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.signInYoutubeMusic)
                    .font(BrowseFont.title)
                    .foregroundStyle(.primary)
                Text(L10n.personalizedRecommendations)
                    .font(BrowseFont.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            layout {
                Button(L10n.signIn, action: onSignIn)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("home.signIn")
                Button(action: onProxy) {
                    Label(L10n.tr("login_proxy_settings"), systemImage: "network")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("home.proxySettings")
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.tr("login_proxy_first"), systemImage: "exclamationmark.circle")
                    .font(.footnote.weight(.semibold))
                Text(L10n.tr("login_proxy_restart_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, BrowseMetrics.gutter)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.signInBanner")
    }
}

/// Common.kt's `MessageState`: a centred line of text and, optionally, one action under it.
struct BrowseMessage: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BrowseMetrics.gutter + 12)
        .padding(.vertical, 48)
        .accessibilityIdentifier("browse.message")
    }
}
