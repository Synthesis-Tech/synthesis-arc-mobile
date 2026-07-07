import SwiftUI

struct CreateChannelSheet: View {
    var onCreated: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var channelService: ChannelService

    @State private var name = ""
    @State private var description = ""
    @State private var visibility: ChannelVisibility = .public
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Channel") {
                    TextField("Name", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        Text("Public").tag(ChannelVisibility.public)
                        Text("Private").tag(ChannelVisibility.private)
                    }
                    .pickerStyle(.segmented)

                    Text(visibility == .private
                         ? "Private channels require an explicit join before reading history."
                         : "Public channels are readable by any fleet peer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Channel")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createChannel() }
                    }
                    .disabled(isCreating || sanitizedName.isEmpty)
                }
            }
        }
    }

    private var sanitizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createChannel() async {
        isCreating = true
        error = nil
        defer { isCreating = false }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await channelService.createChannel(
                name: sanitizedName,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                visibility: visibility
            )
            onCreated(sanitizedName)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}