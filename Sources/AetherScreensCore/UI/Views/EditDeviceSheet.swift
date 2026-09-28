import SwiftUI

/// Sheet for editing an existing computer's connection details, VNC password, and Wake-on-LAN settings.
public struct EditDeviceSheet: View {
    public let device: RemoteDevice
    @ObservedObject public var viewModel: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portString: String = "5900"
    @State private var deviceType: RemoteDevice.DeviceType = .mac
    @State private var password: String = ""
    @State private var macAddress: String = ""
    @State private var isPasswordModified: Bool = false

    public init(device: RemoteDevice, viewModel: DeviceListViewModel) {
        self.device = device
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Device Information")) {
                    TextField("Name", text: $name)
                    TextField("Host / Tailscale IP", text: $host)
                        .autocorrectionDisabled()
                    TextField("Port", text: $portString)
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
                    footer: Text("Saved in macOS Keychain. Enter a new password to update or leave unchanged.")
                ) {
                    SecureField("VNC Password", text: $password)
                        .onChange(of: password) { _, _ in
                            isPasswordModified = true
                        }
                }

                Section(
                    header: Text("Wake-on-LAN (Optional)"),
                    footer: Text("Hardware MAC address (e.g. AA:BB:CC:DD:EE:FF) to wake this Mac remotely.")
                ) {
                    TextField("MAC Address", text: $macAddress)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit Computer")
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
                        let port = UInt16(portString) ?? device.port
                        var updatedDev = device
                        updatedDev.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? host : name
                        updatedDev.host = host.trimmingCharacters(in: .whitespaces)
                        updatedDev.port = port
                        updatedDev.deviceType = deviceType
                        updatedDev.macAddress = macAddress.isEmpty ? nil : macAddress
                        
                        let newPassword = isPasswordModified ? (password.isEmpty ? nil : password) : DeviceStore.shared.getPassword(for: device)
                        
                        DeviceStore.shared.updateDevice(updatedDev, password: newPassword)
                        viewModel.reload()
                        dismiss()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = device.name
                host = device.host
                portString = "\(device.port)"
                deviceType = device.deviceType
                macAddress = device.macAddress ?? ""
                if let savedPwd = DeviceStore.shared.getPassword(for: device) {
                    password = savedPwd
                }
                isPasswordModified = false
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 400)
        #endif
    }
}
