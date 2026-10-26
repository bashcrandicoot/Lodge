import SwiftUI

/// Settings ▸ Destinations: favorite folders you can add, rename, reorder (drag), re-point,
/// remove, and mark as the default.
struct DestinationsSettingsView: View {
    @EnvironmentObject private var destinations: DestinationStore
    @EnvironmentObject private var model: AppModel
    @State private var selection = Set<UUID>()
    @FocusState private var focusedName: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Favorite Destinations")
                    .font(.headline)
                Text("Switch between these in the Destination stage. A favorite on a drive that isn’t plugged in shows as Not Connected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                list
                Divider()
                controlBar
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))

            if let error = destinations.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Lodge starts in the default favorite. If its drive isn’t connected, it uses the one you used last.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .id(destinations.mountRevision)
    }

    @ViewBuilder
    private var list: some View {
        if destinations.favorites.isEmpty {
            ContentUnavailableView {
                Label("No Favorites", systemImage: "externaldrive")
            } description: {
                Text("Click + to add a folder you offload to often.")
            }
            .frame(maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(destinations.favorites) { favorite in
                    row(favorite)
                        .tag(favorite.id)
                        .contextMenu {
                            Button("Change Folder…") { changeFolder(favorite.id) }
                            Button("Make Default") { destinations.setDefault(favorite.id) }
                                .disabled(favorite.id == destinations.defaultFavorite?.id)
                            Divider()
                            Button("Remove") { remove([favorite.id]) }
                        }
                }
                .onMove { destinations.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .onDeleteCommand { remove(selection) }
        }
    }

    private func row(_ favorite: FavoriteDestination) -> some View {
        let connected = destinations.isConnected(favorite)
        let isDefault = favorite.id == destinations.defaultFavorite?.id
        return HStack(spacing: 8) {
            Image(systemName: favorite.symbol)
                .foregroundStyle(connected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                TextField("Name", text: Binding(
                    get: { destinations.favorite(id: favorite.id)?.name ?? "" },
                    set: { destinations.rename(favorite.id, to: $0) }),
                    prompt: Text(favorite.url.lastPathComponent))
                    .textFieldStyle(.plain)
                    .focused($focusedName, equals: favorite.id)
                    .accessibilityLabel("Favorite name")
                Text(favorite.abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !connected {
                Text("Not Connected")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if isDefault {
                Text("Default")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 3)
        .help(favorite.path)
    }

    private var singleSelection: UUID? {
        selection.count == 1 ? selection.first : nil
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            Button(action: addFavorite) {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .help("Add a favorite folder")
            .accessibilityLabel("Add favorite")
            Divider().frame(height: 16)
            Button { remove(selection) } label: {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .disabled(selection.isEmpty)
            .help("Remove the selected favorite")
            .accessibilityLabel("Remove favorite")
            Spacer()
            Button("Change Folder…") {
                if let id = singleSelection { changeFolder(id) }
            }
            .disabled(singleSelection == nil)
            .padding(.trailing, 8)
            Button("Make Default") {
                if let id = singleSelection { destinations.setDefault(id) }
            }
            .disabled(singleSelection == nil || singleSelection == destinations.defaultFavorite?.id)
            .padding(.trailing, 6)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private func addFavorite() {
        guard let url = AppSettings.pickFolder(startingAt: model.settings.destinationURL,
                                               message: "Choose a folder to add to your favorite destinations.") else { return }
        let favorite = destinations.add(path: url.path)
        selection = [favorite.id]
        focusedName = favorite.id
    }

    private func changeFolder(_ id: UUID) {
        guard let favorite = destinations.favorite(id: id),
              let url = AppSettings.pickFolder(startingAt: favorite.url,
                                               message: "Choose the new folder for “\(favorite.displayName)”.") else { return }
        let wasCurrent = model.currentFavorite?.id == id
        destinations.setPath(id, to: url.path)
        // If it was the folder in use, keep using it at its new location.
        if wasCurrent { model.useFavorite(destinations.favorite(id: id) ?? favorite) }
    }

    private func remove(_ ids: Set<UUID>) {
        destinations.delete(ids)
        selection.subtract(ids)
    }
}

#if DEBUG
#Preview("Destination settings") {
    DestinationsSettingsView().demoEnvironment(DemoData.model(state: .ready))
}
#endif
