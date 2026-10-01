import SwiftUI

/// Sheet for adding a new remote computer manually.
public struct AddDeviceSheet: View {
    @ObservedObject public var viewModel: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portString: String = "5900"
    @State private var deviceType: RemoteDevice.DeviceType = .mac
    @State private var password: String = ""
    @State private var username: String = ""
    @State private var macAddress: String = ""

    public init(viewModel: DeviceListViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Device Information")) {
                    TextField("Name (e.g. Studio Mac)", text: $name)
                    TextField("Tailscale IP / Host (e.g. 100.80.1.25)", text: $host)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .keyboardType(.URL)
                        #endif
                    LabeledContent("Port") {
                        TextField("Port", text: $portString)
                            .accessibilityLabel("Port")
                            .multilineTextAlignment(.trailing)
                            #if canImport(UIKit)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }

                Section(header: Text("Operating System")) {
                    Picker("Device Type", selection: $deviceType) {
                        ForEach(RemoteDevice.DeviceType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.systemIcon).tag(type)
                        }
                    }
                }

                Section(
                    header: Text("Authentication"),
                    footer: Text("Enter your Mac account username and password. Leave Username empty to use a VNC password.")
                ) {
                    TextField("Username (Mac account, optional)", text: $username)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField(username.isEmpty ? "VNC Password (Optional)" : "Mac Account Password", text: $password)
                }

                Section(
                    header: Text("Wake-on-LAN (Optional)"),
                    footer: Text("Enter the remote Mac's hardware MAC address (e.g. AA:BB:CC:DD:EE:FF) to wake it when sleeping.")
                ) {
                    TextField("MAC Address (Optional)", text: $macAddress)
                        .autocorrectionDisabled()
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Computer")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let port = UInt16(portString), port > 0 else { return }
                        let finalName = name.isEmpty ? host : name
                        viewModel.addDevice(
                            name: finalName,
                            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                            port: port,
                            type: deviceType,
                            password: password.isEmpty ? nil : password,
                            macAddress: macAddress.isEmpty ? nil : macAddress,
                            username: username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : username.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || UInt16(portString) == nil || UInt16(portString) == 0)
                }
            }
        }
        #if os(macOS)
        .frame(width: 540, height: 660)
        #endif
    }
}
