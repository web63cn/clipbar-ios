import SwiftUI

@main
struct ClipBarApp: App {
    @StateObject private var store = ClipStore.shared
    @StateObject private var cloud = CloudSync(store: ClipStore.shared)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(cloud)
                .onAppear {
                    // 切回前台时：取走键盘扩展归档的内容 + 同步一次
                    let captured = store.drainCaptures()
                    if !captured.isEmpty {
                        for item in captured { store.add(item) }
                    }
                    store.publish()
                    if cloud.enabled { cloud.syncNow() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: ClipStore
    @EnvironmentObject private var cloud: CloudSync

    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
                .tag(0)

            TextToolsView()
                .tabItem { Label("文本工具", systemImage: "wand.and.stars") }
                .tag(1)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(2)
        }
    }
}
