import DefaultBackend
import SwiftCrossUI

#if canImport(SwiftBundlerRuntime)
    import SwiftBundlerRuntime
#endif

@main
struct RecmeetCrossApp: App {
    var body: some Scene {
        WindowGroup("recmeet") {
            ContentView()
        }
        .defaultSize(width: 460, height: 520)
    }
}
