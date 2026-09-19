#if DEBUG
import SwiftUI

/// Uses the production overlay container to compare its page frame with controls shown/hidden.
struct ReaderChromePreview: View {
    @State private var visible = !CommandLine.arguments.contains("--fullscreen-preview")
    @State private var page = 1
    var body: some View {
        ReaderChrome(title: "Chapter 21", subtitle: "The quiet adventure · Source B", visible: visible,
            preferences: {}, pages: { size in
                Image("MidokuArtwork").resizable().scaledToFit()
                    .frame(width: size.width, height: size.height).background(Color.black)
                    .onTapGesture { visible.toggle() }
            }, controls: { ReaderPageControls(index: page, count: 19) { page = $0 } })
            .environment(\.readerChapterNavigation, ReaderChapterNavigation(previous: {}, next: {}))
    }
}
#endif
