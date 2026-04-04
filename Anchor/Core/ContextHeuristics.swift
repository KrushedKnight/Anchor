import Foundation

enum ContextHeuristics {
    static let likelyDistractingApps: Set<String> = [
        "Messages", "FaceTime", "Discord", "Telegram", "WhatsApp",
        "Twitter", "TweetDeck", "Facebook", "Instagram",
        "Spotify", "Music", "Apple Music", "TV", "Apple TV",
        "Netflix", "Steam", "Epic Games Launcher",
        "News", "Stocks", "Photos", "App Store",
        "Chess", "Minecraft"
    ]

    static let likelyDistractingDomains: Set<String> = [
        "twitter.com", "x.com", "facebook.com", "instagram.com",
        "reddit.com", "tiktok.com", "youtube.com", "twitch.tv",
        "netflix.com", "hulu.com", "disneyplus.com", "primevideo.com",
        "spotify.com", "soundcloud.com",
        "amazon.com", "ebay.com", "etsy.com",
        "discord.com", "messenger.com", "web.whatsapp.com",
        "9gag.com", "imgur.com", "buzzfeed.com",
        "store.steampowered.com", "epicgames.com",
        "news.ycombinator.com"
    ]

    static let alwaysProductiveApps: Set<String> = [
        "Xcode", "Visual Studio Code", "Terminal", "iTerm2",
        "Sublime Text", "TextEdit", "Nova", "BBEdit",
        "Finder", "Preview", "Calculator", "Activity Monitor",
        "System Preferences", "System Settings"
    ]

    static func heuristicForApp(_ app: String) -> ContextFitLevel? {
        if alwaysProductiveApps.contains(app) { return .onTask }
        if likelyDistractingApps.contains(app) { return .offTask }
        return nil
    }

    static func heuristicForDomain(_ domain: String) -> ContextFitLevel? {
        let clean = domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        if likelyDistractingDomains.contains(clean) { return .offTask }
        for known in likelyDistractingDomains {
            if clean.hasSuffix("." + known) { return .offTask }
        }
        return nil
    }
}
