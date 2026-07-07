import SwiftUI

/// Phase 1 stand-in for destinations that gain full split-column layouts in Phase 1.5.
struct CommandDestinationPlaceholder: View {
    let destination: CommandDestination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.systemImage)
        } description: {
            Text("Full \(destination.title.lowercased()) split view ships in Phase 1.5. Fleet command center is live now.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(destination.title)
    }
}