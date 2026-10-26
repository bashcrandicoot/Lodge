import SwiftUI

/// Settings ▸ Cameras: a list you can add to, rename, reorder (drag) and delete from.
struct CamerasSettingsView: View {
    @EnvironmentObject private var cameras: CameraStore
    @State private var selection = Set<UUID>()
    @FocusState private var focusedName: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cameras")
                    .font(.headline)
                Text("Pick one in the Media stage for each card. The short code (or the name) fills the {camera} token.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                header
                Divider()
                list
                Divider()
                controlBar
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))

            if let error = cameras.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Lodge remembers the camera you pick for each card and selects it the next time that card is inserted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 30)
            Text("Short Code").frame(width: 110, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var list: some View {
        if cameras.cameras.isEmpty {
            ContentUnavailableView {
                Label("No Cameras", systemImage: "camera")
            } description: {
                Text("Click + to add the cameras you shoot with.")
            }
            .frame(maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                ForEach(cameras.cameras) { camera in
                    row(camera)
                        .tag(camera.id)
                }
                .onMove { cameras.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .onDeleteCommand { deleteSelected() }
        }
    }

    private func row(_ camera: Camera) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .foregroundStyle(.tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            TextField("Name", text: Binding(
                get: { cameras.camera(id: camera.id)?.name ?? "" },
                set: { cameras.rename(camera.id, to: $0) }),
                prompt: Text("Camera name"))
                .textFieldStyle(.plain)
                .focused($focusedName, equals: camera.id)
                .accessibilityLabel("Camera name")
            TextField("Short Code", text: Binding(
                get: { cameras.camera(id: camera.id)?.code ?? "" },
                set: { cameras.setCode(camera.id, to: $0) }),
                prompt: Text("Optional"))
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .frame(width: 110)
                .accessibilityLabel("Short code")
        }
        .padding(.vertical, 2)
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            Button {
                let camera = cameras.add()
                selection = [camera.id]
                focusedName = camera.id
            } label: {
                Image(systemName: "plus").frame(width: 24, height: 20)
            }
            .help("Add a camera")
            .accessibilityLabel("Add camera")
            Divider().frame(height: 16)
            Button(action: deleteSelected) {
                Image(systemName: "minus").frame(width: 24, height: 20)
            }
            .disabled(selection.isEmpty)
            .help("Remove the selected camera")
            .accessibilityLabel("Remove camera")
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func deleteSelected() {
        cameras.delete(selection)
        selection = []
    }
}

#if DEBUG
#Preview("Camera settings") {
    CamerasSettingsView().demoEnvironment(DemoData.model(state: .ready))
}
#endif
