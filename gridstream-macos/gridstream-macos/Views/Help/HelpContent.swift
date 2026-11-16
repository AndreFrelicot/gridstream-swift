//
//  HelpContent.swift
//  gridstream-macos
//
//  What the Help window says: one topic per settings pane or feature, one
//  item per control. Keep it in step with the views it describes.
//

import Foundation

struct HelpTopic: Identifiable, Hashable {
    let id: String
    let systemImage: String
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let items: [HelpItem]

    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct HelpItem: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    init(_ systemImage: String, _ title: LocalizedStringResource, _ detail: LocalizedStringResource) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
    }

    func matches(_ query: String) -> Bool {
        String(localized: title).localizedStandardContains(query)
            || String(localized: detail).localizedStandardContains(query)
    }
}

extension HelpTopic {
    static let all: [HelpTopic] = [
        gettingStarted, server, activity, folders, storage, web, security, menuBar, troubleshooting
    ]

    static func topic(id: String) -> HelpTopic? {
        all.first { $0.id == id }
    }

    static let gettingStarted = HelpTopic(
        id: "getting-started",
        systemImage: "sparkles",
        title: "Getting Started",
        summary: "Serve the videos on this Mac to your iPad.",
        items: [
            HelpItem("desktopcomputer", "What GridStream Server does", "GridStream Server catalogs the videos in the folders you choose and streams them to the GridStream iPad app and to browsers on your local network. Nothing is uploaded to the internet and your files are never moved or copied."),
            HelpItem("folder.badge.plus", "1. Add your folders", "Open Settings > Folders and click Add Folder… to choose a folder that contains videos. GridStream scans it and its subfolders."),
            HelpItem("play.circle", "2. Keep the server running", "The server starts by itself when GridStream opens. Its status is shown at the top of the sidebar and in the menu bar menu."),
            HelpItem("ipad.landscape", "3. Connect the iPad", "Open GridStream on an iPad connected to the same network. It finds this Mac automatically. If a PIN is required, enter the one shown in Settings > Server."),
            HelpItem("menubar.arrow.up.rectangle", "Menu bar", "GridStream lives in the menu bar as well as in the Dock. Closing the Settings window keeps the server running; choose Quit GridStream to stop it.")
        ]
    )

    static let server = HelpTopic(
        id: "server",
        systemImage: "server.rack",
        title: "Server",
        summary: "Status, address, PIN and port.",
        items: [
            HelpItem("playpause", "Start and stop", "Start Server and Stop Server control streaming. While the server is stopped, iPads and browsers cannot connect. It cannot be started or stopped during a scan."),
            HelpItem("number", "Statistics", "Videos is the number of videos in the catalog, Folders the number of folders turned on, and PIN tells whether clients need a PIN to connect."),
            HelpItem("link", "Address", "The address other devices on your network use to reach this Mac, made of its local network name and the server port. Click the copy button to put it on the clipboard."),
            HelpItem("lock", "PIN", "The PIN to enter on the iPad or in the browser. When GridStream generated it, it is shown here; if you set your own PIN, it is not shown."),
            HelpItem("network", "Port", "The TCP port the server listens on, 8080 by default. Stop the server, type a port between 1024 and 65535, press Return, then start the server again.")
        ]
    )

    static let activity = HelpTopic(
        id: "activity",
        systemImage: "dot.radiowaves.left.and.right",
        title: "Activity",
        summary: "Connected devices, what they play and the connection log.",
        items: [
            HelpItem("number", "Statistics", "Devices is the number of connected devices, Playing the videos being streamed right now, Throughput the data the server sends per second, and Videos Served the videos started since the server started."),
            HelpItem("ipad.landscape", "Connected devices", "Each iPad or browser that has used the server in the last two minutes, with the address it connects from, the data sent to it and its current throughput. The videos it is playing are listed under it."),
            HelpItem("list.bullet.rectangle", "Log", "Sign-ins, wrong PINs, connections and the videos each device plays, newest first. The log keeps the last 500 entries and is cleared when GridStream quits. Copy puts it on the clipboard and Clear empties it."),
            HelpItem("menubar.arrow.up.rectangle", "In the menu bar", "While the server runs, the menu bar menu shows how many devices are connected and what they are playing; choose that line to open this pane. The menu bar icon changes while a video is playing.")
        ]
    )

    static let folders = HelpTopic(
        id: "folders",
        systemImage: "folder.fill",
        title: "Folders",
        summary: "Choosing which videos are served.",
        items: [
            HelpItem("plus", "Add Folder…", "Adds a folder and its subfolders. GridStream serves .mp4, .m4v and .mov files. Adding a folder that is inside, or contains, a folder already in the list is refused."),
            HelpItem("switch.2", "Turning a folder off", "The switch on the right of a folder hides its videos from clients without deleting anything. Turn it back on to find its videos again with their tags, ratings and other data."),
            HelpItem("cursorarrow.click.2", "Right-click menu", "Right-click a folder to Show in Finder, Copy Path, turn it on or off, or remove it."),
            HelpItem("minus.circle", "Removing a folder", "Hover a folder and click the minus button, or choose Remove… from its right-click menu. This permanently deletes its videos from the GridStream library with their tags, ratings, annotations, lists and captures. The video files themselves are not touched."),
            HelpItem("arrow.clockwise", "Scan for Changes", "Looks for videos that were added, changed or deleted since the last scan. GridStream also scans when it starts."),
            HelpItem("externaldrive.badge.exclamationmark", "Unavailable folders", "A folder on a disconnected drive is marked unavailable. Its videos are kept and come back when the drive is connected again and the folder is scanned."),
            HelpItem("questionmark.folder", "Missing videos", "Videos whose files are no longer found on disk are kept, in case the file comes back. Purge… deletes them and all their data for good.")
        ]
    )

    static let storage = HelpTopic(
        id: "storage",
        systemImage: "internaldrive.fill",
        title: "Storage",
        summary: "The database and scrub previews.",
        items: [
            HelpItem("folder", "Data directory", "Where GridStream keeps its database, by default in Application Support. Show in Finder reveals the database file."),
            HelpItem("arrow.right.doc.on.clipboard", "Change… and Reset", "Choose another folder for the database, for example on a larger drive. GridStream can move the current database there or start empty. The change takes effect the next time GridStream opens."),
            HelpItem("photo.stack", "Scrub previews", "Small frames the iPad shows while you drag along a video's timeline. They are made the first time they are needed and kept in the database."),
            HelpItem("gearshape.2", "Background generation", "Prepares scrub previews ahead of time while no iPad or browser is connected. Workers sets how many videos are processed at once; more workers finish sooner but use more of the Mac."),
            HelpItem("trash", "Delete All Scrub Data…", "Frees the space used by scrub previews. They are generated again when needed.")
        ]
    )

    static let web = HelpTopic(
        id: "web",
        systemImage: "globe",
        title: "Web Interface",
        summary: "Using GridStream from a browser.",
        items: [
            HelpItem("switch.2", "Serve the web interface", "When on, opening the server address in a browser shows the GridStream web app. It uses the same port as the iPad app, and the change applies immediately."),
            HelpItem("safari", "Open in Browser", "Opens the web interface on this Mac. On another computer, type the address shown in this pane."),
            HelpItem("lock", "Signing in", "When a PIN is required, the browser asks for it once and remembers it for the session duration set in Security.")
        ]
    )

    static let security = HelpTopic(
        id: "security",
        systemImage: "lock.fill",
        title: "Security",
        summary: "Who can reach your library.",
        items: [
            HelpItem("lock.shield", "Require a PIN", "With a PIN, only iPads and browsers that know it can browse, stream or change your library. Without one, anyone on your network can. Leave it on unless your network is entirely yours."),
            HelpItem("wand.and.stars", "Generated PIN", "On first launch GridStream creates a 6-digit PIN. Setting your own PIN replaces it."),
            HelpItem("key", "Set or change the PIN", "Type a PIN of 6 to 12 digits twice and click Save PIN. Changing the PIN signs out every device, which then asks for the new PIN."),
            HelpItem("clock", "Stay signed in for", "How many days a device stays signed in before it asks for the PIN again. Type a number and press Return."),
            HelpItem("person.badge.minus", "Revoke All Sessions", "Signs out every iPad and browser at once, for example after lending a device.")
        ]
    )

    static let menuBar = HelpTopic(
        id: "menu-bar",
        systemImage: "menubar.rectangle",
        title: "Menu Bar Menu",
        summary: "Quick controls from the menu bar.",
        items: [
            HelpItem("info.circle", "Status", "The top of the menu shows whether the server is running and on which port, how many videos are in the catalog, and the PIN when GridStream generated it."),
            HelpItem("globe", "Open Web Interface", "Shown while the server is running with the web interface on."),
            HelpItem("arrow.clockwise", "Scan for New Videos", "Same as Scan for Changes in Settings."),
            HelpItem("arrow.triangle.2.circlepath", "Rescan All Videos", "Reads every video again and regenerates its thumbnail. Slower; use it if thumbnails or durations look wrong."),
            HelpItem("trash", "Clear All Data…", "Empties the GridStream database: videos, tags, ratings, lists, annotations, captures and scrub previews. The video files on disk are not touched. This cannot be undone.")
        ]
    )

    static let troubleshooting = HelpTopic(
        id: "troubleshooting",
        systemImage: "wrench.and.screwdriver.fill",
        title: "Troubleshooting",
        summary: "When something doesn't connect or show up.",
        items: [
            HelpItem("wifi.exclamationmark", "The iPad doesn't find this Mac", "Check that both are on the same network and that the server is running. On the iPad, GridStream needs Local Network access (Settings > Privacy & Security > Local Network). If the macOS firewall is on, allow incoming connections for GridStream."),
            HelpItem("exclamationmark.triangle", "The server doesn't start", "Another app may be using the port. Choose another port in Settings > Server."),
            HelpItem("film", "A video is missing", "Check that its folder is in the list and turned on, that the file is .mp4, .m4v or .mov, then click Scan for Changes."),
            HelpItem("lock.trianglebadge.exclamationmark", "The iPad keeps asking for the PIN", "The PIN may have changed or all sessions may have been revoked. Enter the PIN shown in Settings > Server, or set a new one in Security.")
        ]
    )
}
