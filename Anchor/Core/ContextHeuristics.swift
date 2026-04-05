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

    static let likelyProductiveDomains: Set<String> = [
        // Development
        "github.com", "gitlab.com", "bitbucket.org",
        "stackoverflow.com",
        "developer.apple.com", "docs.swift.org",
        "npmjs.com", "pypi.org", "crates.io",
        "readthedocs.io",
        // Google Workspace
        "docs.google.com", "sheets.google.com", "slides.google.com",
        "drive.google.com", "meet.google.com", "calendar.google.com",
        // Project Management
        "linear.app", "jira.atlassian.com", "confluence.atlassian.com",
        "trello.com", "asana.com", "notion.so",
        "basecamp.com", "monday.com",
        // Design
        "figma.com",
        // Cloud & DevOps
        "console.aws.amazon.com", "cloud.google.com", "portal.azure.com",
        "vercel.com", "netlify.com", "render.com", "heroku.com",
        // Learning
        "coursera.org", "udemy.com", "egghead.io",
        "frontendmasters.com", "pluralsight.com",
        "leetcode.com", "hackerrank.com"
    ]

    static let alwaysProductiveApps: Set<String> = [
        // Core Development
        "Xcode", "Visual Studio Code", "Terminal", "iTerm2",
        "Sublime Text", "TextEdit", "Nova", "BBEdit",
        // Design Tools
        "Figma", "Sketch", "Photoshop", "Illustrator",
        "Adobe XD", "Affinity Designer", "Affinity Photo",
        "Pixelmator Pro", "Vectornator",
        // Writing & Documentation
        "Microsoft Word", "Pages", "Notion", "Bear", "Obsidian",
        "Ulysses", "Scrivener", "iA Writer", "Typora",
        // Dev Adjacent
        "GitHub Desktop", "SourceTree", "Tower",
        "Docker", "Postman", "Insomnia",
        "TablePlus", "Sequel Pro", "DBngin",
        "Instruments", "Simulator",
        // Productivity & Reference
        "Numbers", "Excel", "Keynote", "PowerPoint",
        "Airtable", "Things 3", "OmniFocus",
        // Research & Reading
        "Papers", "Mendeley", "Zotero", "Reeder",
        "NetNewsWire", "PDF Expert", "Skim",
        // Communication (work context)
        "Slack", "Microsoft Teams", "Zoom", "Google Meet",
        // System & Navigation
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

        // Check distracting domains first
        if likelyDistractingDomains.contains(clean) { return .offTask }
        for known in likelyDistractingDomains {
            if clean.hasSuffix("." + known) { return .offTask }
        }

        // Check productive domains
        if likelyProductiveDomains.contains(clean) { return .onTask }
        for known in likelyProductiveDomains {
            if clean.hasSuffix("." + known) { return .onTask }
        }

        return nil
    }
}
