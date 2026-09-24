import SwiftUI

struct MainView: View {
    @Bindable private var store = Store.shared

    var body: some View {
        TabView(selection: $store.mainTab) {
            TimesheetView()
                .tabItem { Label("Timesheet", systemImage: "calendar") }
                .tag(MainTab.timesheet)
            JobsView()
                .tabItem { Label("Jobs", systemImage: "folder") }
                .tag(MainTab.jobs)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .padding(.top, 8)
        .frame(minWidth: 780, minHeight: 480)
    }
}
