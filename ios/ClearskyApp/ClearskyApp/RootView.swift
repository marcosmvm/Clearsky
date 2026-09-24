import SwiftUI

/// The two-screen shell for this task: Today and Triage. Root README "Screens": "The
/// two screens that carry the product's logic are Today and Triage." The other 17
/// screens in the design references are out of scope for this app-shell task.
struct RootView: View {
    var body: some View {
        TabView {
            TodayView(items: SampleData.triageItems)
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }

            TriageView(items: SampleData.triageItems)
                .tabItem {
                    Label("Triage", systemImage: "tray.full")
                }
        }
        .tint(ClearskyColor.inkNavy)
    }
}

#Preview {
    RootView()
}
