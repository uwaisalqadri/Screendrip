import AppKit
import AVFoundation
import SwiftUI

struct LivestreamMenuView: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared
    @State private var camera = CameraRecordingManager.shared
    @State private var cameras = RecordingDeviceCatalog.cameras()
    @AppStorage(ScreendropPreferences.recordingCameraDeviceIDKey) private var cameraID = ""
    @AppStorage(ScreendropPreferences.recordingCameraShapeKey) private var cameraShape = RecordingCameraLayout.Shape.circle

    var body: some View {
        Group {
            Button {
                Task {
                    if camera.isShownOnItsOwn {
                        await camera.hideOnItsOwn()
                    } else {
                        await camera.showOnItsOwn()
                    }
                }
            } label: {
                Label(camera.isShownOnItsOwn ? "Hide Camera" : "Show Camera", systemImage: "video")
            }

            Menu {
                if cameras.isEmpty {
                    Text("No cameras available")
                }
                ForEach(cameras, id: \.uniqueID) { device in
                    Toggle(device.localizedName, isOn: Binding(
                        get: { activeCameraID == device.uniqueID },
                        set: { _ in select(device.uniqueID) }
                    ))
                }
            } label: {
                Label("Camera", systemImage: "web.camera")
            }

            Menu {
                ForEach(RecordingCameraLayout.Shape.allCases, id: \.self) { shape in
                    Toggle(shape.title, isOn: Binding(
                        get: { cameraShape == shape },
                        set: { _ in
                            cameraShape = shape
                            camera.updatePreviewShape()
                        }
                    ))
                }
            } label: {
                Label("Shape", systemImage: cameraShape.systemImage)
            }

            Menu {
                Button("Add Image…") { FloatingOverlays.shared.addImage() }
                Button("Add Running Text…") { FloatingOverlays.shared.addText() }
            } label: {
                Label("Overlays", systemImage: "rectangle.on.rectangle")
            }

            Divider()

            Button {
                updaterManager.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle")
            }
            .disabled(!updaterManager.canCheckForUpdates)

            Button("Quit Screendrop") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .task {
            cameras = RecordingDeviceCatalog.cameras()
        }
    }

    private var activeCameraID: String {
        cameraID.isEmpty ? cameras.first?.uniqueID ?? "" : cameraID
    }

    private func select(_ deviceID: String) {
        cameraID = deviceID
        guard camera.isShownOnItsOwn else { return }
        Task { await camera.showOnItsOwn() }
    }
}
