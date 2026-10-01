import SwiftUI

/// Sheet for editing an existing computer's connection details, VNC password, and Wake-on-LAN settings.
public struct EditDeviceSheet: View {
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
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
                Section(header: Text(AppLocalization.string("Device Information"))) {
                    TextField(AppLocalization.string("Name"), text: $name)
                    TextField(AppLocalization.string("Tailscale IP / Host (e.g. 100.80.1.25)"), text: $host)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    LabeledContent(AppLocalization.string("Port")) {
                        TextField(AppLocalization.string("Port"), text: $portString)
                            .labelsHidden()
                            .accessibilityLabel(AppLocalization.string("Port"))
                            .frame(minWidth: 80)
                            .multilineTextAlignment(.trailing)
                            #if canImport(UIKit)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }

                Section(header: Text(AppLocalization.string("Operating System"))) {
                    Picker(AppLocalization.string("Device Type"), selection: $deviceType) {
                        ForEach(RemoteDevice.DeviceType.allCases, id: \.self) { type in
                            Label(AppLocalization.string(type.rawValue), systemImage: type.systemIcon).tag(type)
                        }
                    }
                }

                Section(
                    header: Text(AppLocalization.string("Authentication")),
                    footer: Text(AppLocalization.string("Saved in the system Keychain. Enter a new password to update or leave unchanged."))
                ) {
                    TextField(AppLocalization.string("Username (Mac account, optional)"), text: $username)
                        .autocorrectionDisabled()
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField(AppLocalization.string(username.isEmpty ? "VNC Password" : "Mac Account Password"), text: $password)
                        .onChange(of: password) { _, _ in
                            isPasswordModified = true
                        }
                }

                Section(
                    header: Text(AppLocalization.string("Wake-on-LAN (Optional)")),
                    footer: Text(AppLocalization.string("Hardware MAC address (e.g. AA:BB:CC:DD:EE:FF) to wake this Mac remotely."))
                ) {
                    TextField(AppLocalization.string("MAC Address"), text: $macAddress)
                        .autocorrectionDisabled()
                }
            }
            .formStyle(.grouped)
            #if canImport(UIKit)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .navigationTitle(AppLocalization.string("Edit Computer"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Save")) {
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
