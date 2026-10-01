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
    @State private var username: String = ""
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
                    TextField("Tailscale IP / Host (e.g. 100.80.1.25)", text: $host)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    LabeledContent("Port") {
                        TextField("Port", text: $portString)
                            .labelsHidden()
                            .accessibilityLabel("Port")
                            .frame(minWidth: 80)
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
                    footer: Text("Saved in the system Keychain. Enter a new password to update or leave unchanged.")
                ) {
                    TextField("Username (Mac account, optional)", text: $username)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField(username.isEmpty ? "VNC Password" : "Mac Account Password", text: $password)
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
            .formStyle(.grouped)
            #if canImport(UIKit)
            .scrollDismissesKeyboard(.interactively)
            #endif
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
                        guard let port = UInt16(portString), port > 0 else { return }
                        var updatedDev = device
                        updatedDev.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? host : name
                        updatedDev.host = host.trimmingCharacters(in: .whitespaces)
                        updatedDev.port = port
                        updatedDev.username = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : username.trimmingCharacters(in: .whitespacesAndNewlines)
                        updatedDev.authMethod = updatedDev.username == nil ? .vncPassword : .macAccount
                        updatedDev.deviceType = deviceType
                        updatedDev.macAddress = macAddress.isEmpty ? nil : macAddress
                        
                        let newPassword = isPasswordModified ? (password.isEmpty ? nil : password) : DeviceStore.shared.getPassword(for: device)
                        
                        DeviceStore.shared.updateDevice(updatedDev, password: newPassword)
                        viewModel.reload()
                        dismiss()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || UInt16(portString) == nil || UInt16(portString) == 0)
                }
            }
            .onAppear {
                username = device.username ?? ""
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
        .frame(width: 540, height: 660)
        #endif
    }
}
