//
//  HelpContent.swift
//  gridstream-ipad
//
//  What the Help screen says: one topic per screen or feature, one item
//  per control or gesture. Keep it in step with the views it describes.
//

import Foundation

struct HelpTopic: Identifiable {
    let id: String
    let systemImage: String
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    let items: [HelpItem]
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
}

extension HelpTopic {
    static let all: [HelpTopic] = [
        gettingStarted, topBar, grid, tile, playback, audio, fullscreen,
        library, tagsAndRatings, smartLists, simpleLists, timeRanges,
        annotations, presets
    ]

    static let gettingStarted = HelpTopic(
        id: "getting-started",
        systemImage: "sparkles",
        title: "Getting Started",
        summary: "Connect to your Mac or try the demo.",
        items: [
            HelpItem("desktopcomputer", "GridStream Server", "GridStream Server runs on the Mac that holds your videos and streams them to this iPad over your local network. Nothing is uploaded or copied."),
            HelpItem("chevron.down.circle", "Server menu", "The connection status at the far left of the top bar is a menu. Use it to connect to your Mac, try or leave the demo, show this help or the welcome screens again."),
            HelpItem("play.rectangle.on.rectangle", "Demo", "The demo downloads a few short open-movie clips with a ready-made library, so you can try every feature without a Mac. Reset Demo puts it back as it came; Delete Demo Videos frees the space."),
            HelpItem("lock", "PIN", "If the server asks for a PIN, enter the one shown in GridStream Server's settings on your Mac. This iPad then stays signed in."),
            HelpItem("iphone.slash", "Forget Device", "Signs this iPad out of a server that uses a PIN. You will need the PIN again to reconnect.")
        ]
    )

    static let topBar = HelpTopic(
        id: "top-bar",
        systemImage: "menubar.rectangle",
        title: "Top Bar",
        summary: "Tiles, library, presets and layout.",
        items: [
            HelpItem("hand.tap", "Showing the bar", "Tap any tile to show the bar. It hides by itself after a few seconds, and stays up while one of its menus is open."),
            HelpItem("plus.rectangle", "Add Tile", "Adds an empty tile, up to 12."),
            HelpItem("minus.rectangle", "Remove Tile", "Removes the selected tile and its video."),
            HelpItem("rectangle.stack", "Library", "Opens the library to choose a video for the selected tile."),
            HelpItem("shuffle", "Shuffle All", "Loads a random video on every tile. Each tile picks from its own list when it has one."),
            HelpItem("square.stack.3d.up", "Presets", "Recalls a saved preset: the number of tiles and what each tile plays. Reset All empties every tile."),
            HelpItem("playpause", "Pause All / Play All", "Pauses or resumes every video at once."),
            HelpItem("arrow.left.and.right", "Orientation", "Arranges the tiles in rows or in columns."),
            HelpItem("square.grid.2x2", "Layout", "Picks a grid, from 1 to 12 tiles. With 3 or 4 tiles you can also choose an uneven layout, then drag the line between tiles to resize them.")
        ]
    )

    static let grid = HelpTopic(
        id: "grid",
        systemImage: "square.grid.3x2",
        title: "Grid and Tiles",
        summary: "Selecting tiles and filling empty ones.",
        items: [
            HelpItem("hand.tap", "Selected tile", "Tap a tile to select it: it gets a coloured border and plays at full volume, while the other tiles play quieter. Top bar actions apply to the selected tile."),
            HelpItem("shuffle", "Empty tile: Random", "Loads a random video, from the tile's list if it has one, otherwise from the whole library."),
            HelpItem("film", "Empty tile: Select", "Opens the library to choose a video for this tile."),
            HelpItem("list.bullet", "Empty tile: Playlist", "Opens your smart lists to give this tile a list to play from."),
            HelpItem("trash", "Empty tile: Remove", "Removes the empty tile.")
        ]
    )

    static let tile = HelpTopic(
        id: "tile",
        systemImage: "hand.tap",
        title: "Tile Controls",
        summary: "The buttons and gestures on each video.",
        items: [
            HelpItem("hand.tap", "Tap and double-tap", "Tap a video to show its controls; they hide after a few seconds. Double-tap to hide them at once."),
            HelpItem("hand.draw", "Swipe for history", "Swipe right to go back to the video this tile played before. After going back, swipe left to go forward again."),
            HelpItem("speaker.wave.2", "Audio", "Opens the volume, mute and solo controls for this tile."),
            HelpItem("repeat", "When this video ends", "Choose what the tile does at the end: Stop, Loop, Play Next or Play Random. Next follows the tile's list, or the library order."),
            HelpItem("shuffle", "Random", "Replaces the video with a random one from the tile's list or the library."),
            HelpItem("arrow.up.left.and.arrow.down.right", "Framing", "Switches between filling the tile (cropping the edges) and fitting the whole picture."),
            HelpItem("square.arrowtriangle.4.outward", "Fullscreen", "Shows this video fullscreen, with the other tiles as floating windows."),
            HelpItem("tag", "Tags", "Adds tags to this video or removes them."),
            HelpItem("text.badge.plus", "Add to List", "Adds this video to a simple list, or creates a new list."),
            HelpItem("arrow.triangle.2.circlepath", "Change Video", "Opens the library to pick another video for this tile."),
            HelpItem("camera.aperture", "Capture Frame", "Appears while paused. Saves the current frame on your Mac."),
            HelpItem("list.bullet.rectangle", "Badges and chips", "The badge shows the list the tile plays from. The chips at the bottom show every list that contains this video, and the tags appear on the right.")
        ]
    )

    static let playback = HelpTopic(
        id: "playback",
        systemImage: "slider.horizontal.below.rectangle",
        title: "Playback and Scrubbing",
        summary: "The seek bar, precision scrubbing and the end screen.",
        items: [
            HelpItem("hand.draw", "Scrub", "Drag along the seek bar to scrub; a preview frame follows your finger. Let go to jump there."),
            HelpItem("arrow.up", "Precision scrubbing", "While scrubbing, slide your finger up: a little for fine scrubbing (1/10 speed), further for frame by frame. Slide back down to return to normal."),
            HelpItem("paintpalette", "Seek bar colours", "Orange marks the preview frames already prepared; the handle turns from red to green once they are all ready. Coloured segments are time ranges, yellow marks are captures."),
            HelpItem("pin", "Pin", "Keeps the controls on screen instead of hiding them."),
            HelpItem("forward.end", "End of video", "Unless the tile loops, the end screen offers Replay, Next and Random, and names the list the tile plays from.")
        ]
    )

    static let audio = HelpTopic(
        id: "audio",
        systemImage: "speaker.wave.3",
        title: "Audio",
        summary: "Volume, mute, solo and normalization.",
        items: [
            HelpItem("speaker.wave.2", "Volume", "Drag the bar to set this tile's volume. Settings are kept per tile, also after relaunching the app."),
            HelpItem("speaker.slash", "Mute", "Silences this tile."),
            HelpItem("headphones", "Solo", "Only this tile is heard. Only one tile can be soloed at a time."),
            HelpItem("hand.tap", "Exclusive solo", "Press and hold Solo to mute every other tile and solo this one. The other tiles stay muted afterwards."),
            HelpItem("waveform", "Normalization", "In the library's Audio tab, evens out loud and quiet videos. Choose a preset or tune it yourself.")
        ]
    )

    static let fullscreen = HelpTopic(
        id: "fullscreen",
        systemImage: "pip",
        title: "Fullscreen and Floating Windows",
        summary: "One video large, the others floating over it.",
        items: [
            HelpItem("xmark", "Leave fullscreen", "The X at the top right returns to the grid."),
            HelpItem("headphones.circle", "SuperSolo", "Silences every other video while it is on, without changing their own settings."),
            HelpItem("speaker.wave.2.circle", "Stereo panning", "Plays each floating window from the left or the right, depending on where it sits on screen."),
            HelpItem("rectangle.on.rectangle.circle", "Remember window layout", "Remembers where the floating windows were for each video shown fullscreen. Press and hold to put them back in place, for this video or for all videos."),
            HelpItem("arrow.up.left.and.arrow.down.right", "Framing for all tiles", "Tap to switch this video between fill and fit; press and hold to switch every tile."),
            HelpItem("hand.tap", "Swap a window", "Tap a floating window to show it fullscreen; the fullscreen video takes its place."),
            HelpItem("hand.draw", "Move, resize and rotate", "Drag a floating window to move it, pinch to resize it, and turn with two fingers to rotate it."),
            HelpItem("hand.point.up.left", "Window controls", "Press and hold a floating window for its own volume, mute, solo and play controls, and to reset its size and rotation. Press and hold two windows one after the other to swap them."),
            HelpItem("arrow.up.right", "Hide all windows", "Swipe diagonally with two fingers toward a corner to slide the floating windows away; do it again to bring them back.")
        ]
    )

    static let library = HelpTopic(
        id: "library",
        systemImage: "rectangle.stack",
        title: "Library",
        summary: "Finding videos, filtering and editing several at once.",
        items: [
            HelpItem("square.grid.3x3", "Tabs", "Content shows your videos. History lists what you played recently. Tags, Smart Lists, Simple Lists, Audio and Presets manage those features, and Diagnostics records playback problems."),
            HelpItem("line.3.horizontal.decrease", "Viewing", "Shows all videos or the videos of one list. With a list shown, Apply gives it to a tile, so Random and Next pick from it there."),
            HelpItem("magnifyingglass", "Search", "Filters videos by name as you type."),
            HelpItem("slider.horizontal.3", "Filters", "Filter by tags (with a rating range for rated tags), by rating, by folder, or show unrated videos only. Each filter appears as a chip you can remove."),
            HelpItem("hand.tap", "Choose a video", "Tap a thumbnail to play it on the tile and close the library."),
            HelpItem("checkmark.circle", "Select several", "Turn on selection, pick videos, then tag them, rate them or add them to a list all at once."),
            HelpItem("arrow.clockwise", "New content", "When videos are added on your Mac, a banner offers to refresh the list.")
        ]
    )

    static let tagsAndRatings = HelpTopic(
        id: "tags-ratings",
        systemImage: "heart",
        title: "Tags and Ratings",
        summary: "Organize videos and rate them.",
        items: [
            HelpItem("tag", "Tags", "Create up to 30 tags in the library's Tags tab, each with a colour and a description. Swipe a tag to edit or delete it."),
            HelpItem("checkmark", "Apply or detach", "When the library was opened from a video, Apply and Detach add or remove a tag on that video."),
            HelpItem("star", "Per-tag rating", "Turn on rating for a tag to rate each video on that tag separately, for example how good a take is."),
            HelpItem("heart", "Rating", "Tap the rating on a tile to expand it, then tap a heart to rate from 1 to 10. Tap the current heart again to clear the rating."),
            HelpItem("play", "Play count and time", "The rating panel also shows how often a video was played and for how long.")
        ]
    )

    static let smartLists = HelpTopic(
        id: "smart-lists",
        systemImage: "list.bullet.rectangle",
        title: "Smart Lists",
        summary: "Lists that fill themselves from rules.",
        items: [
            HelpItem("plus", "Create a smart list", "In the Smart Lists tab, tap + and add conditions. The list always holds the videos that match, and updates as they change."),
            HelpItem("line.3.horizontal.decrease.circle", "Conditions", "Match on tags (included or excluded, with a rating range), rating, folder, file size, file name, dates, play count, annotations, time ranges, or membership of another list. Combine them with And or Or."),
            HelpItem("eye", "Preview", "The editor shows how many videos match and a few of them as you edit."),
            HelpItem("square.on.square", "Apply to a tile", "Apply gives the list to a tile. The tile keeps its current video; Random, Next and the end action then pick from the list.")
        ]
    )

    static let simpleLists = HelpTopic(
        id: "simple-lists",
        systemImage: "rectangle.stack.badge.plus",
        title: "Simple Lists",
        summary: "Playlists you fill by hand.",
        items: [
            HelpItem("plus", "Create a simple list", "In the Simple Lists tab, tap + and give it a name and a sort order."),
            HelpItem("text.badge.plus", "Add videos", "Use Add to List on a tile, or select several videos in the library and tap Add."),
            HelpItem("square.on.square", "Apply to a tile", "Apply gives the list to a tile, so Random, Next and the end action pick from it."),
            HelpItem("hand.draw", "Edit or delete", "Swipe a list to rename it, change its order or delete it.")
        ]
    )

    static let timeRanges = HelpTopic(
        id: "time-ranges",
        systemImage: "timeline.selection",
        title: "Time Ranges",
        summary: "Mark the parts of a video that matter.",
        items: [
            HelpItem("timeline.selection", "Open the editor", "Tap the time ranges button next to the seek bar."),
            HelpItem("flag", "Set Start and Set End", "Play or scrub to the start, tap Set Start, move to the end, then tap Set End to save the range."),
            HelpItem("hand.tap", "Edit a range", "Tap a range to jump to its start and edit it, then use Update Start or Update End at the current position. The X deletes a range."),
            HelpItem("paintpalette", "On the seek bar", "Each range shows as a coloured segment on the seek bar.")
        ]
    )

    static let annotations = HelpTopic(
        id: "annotations",
        systemImage: "pencil.tip.crop.circle",
        title: "Annotations and Captures",
        summary: "Draw on frames and save stills.",
        items: [
            HelpItem("pencil.tip.crop.circle", "Annotate", "Tap the pencil next to the seek bar: the video pauses and you can draw on the frame with Apple Pencil. Drawings are saved with their frame and show only in annotation mode."),
            HelpItem("arrow.left.arrow.right","Step through frames", "In annotation mode, the arrows move one frame back or forward. Frames lists every annotated frame; tap one to jump to it."),
            HelpItem("textformat", "Text note", "Adds a written note to the video, shown while annotating."),
            HelpItem("camera.aperture", "Capture", "While paused, the capture button saves the current frame on your Mac."),
            HelpItem("photo.on.rectangle", "Captures gallery", "In fullscreen, the captures button lists the saved frames; tap one to jump to it. Captures also show as yellow marks on the seek bar.")
        ]
    )

    static let presets = HelpTopic(
        id: "presets",
        systemImage: "square.stack.3d.up",
        title: "Presets",
        summary: "Save and recall what your tiles play.",
        items: [
            HelpItem("square.and.arrow.down", "Save a preset", "In the library's Presets tab, name the current setup and tap Save. A preset keeps the number of tiles and each tile's video and list."),
            HelpItem("square.stack.3d.up", "Recall a preset", "Pick it from the Presets menu in the top bar, or tap Load in the Presets tab."),
            HelpItem("hand.draw", "Delete a preset", "Swipe it in the Presets tab.")
        ]
    )
}
