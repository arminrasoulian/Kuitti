import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Text("Dashboard")
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
            Text("Transactions")
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle.fill") }
            Text("Scan")
                .tabItem { Label("Scan", systemImage: "doc.viewfinder.fill") }
            Text("Products")
                .tabItem { Label("Products", systemImage: "basket.fill") }
            Text("Settings")
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    RootTabView()
}
