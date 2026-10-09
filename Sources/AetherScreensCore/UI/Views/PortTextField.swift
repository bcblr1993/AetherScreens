import SwiftUI
#if canImport(UIKit)
import UIKit

/// Numeric entry with a native accessory, including floating iPad keyboards.
struct PortTextField: UIViewRepresentable {
    @Binding var text: String
    var label = "Port"
    var identifier: String?

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .numberPad
        field.textAlignment = .right
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.placeholder = AppLocalization.string(label)
        field.accessibilityLabel = AppLocalization.string(label)
        field.accessibilityIdentifier = identifier
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        context.coordinator.field = field
        field.delegate = context.coordinator
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        toolbar.autoresizingMask = [.flexibleWidth]
        let done = UIBarButtonItem(title: AppLocalization.string("Done"), style: .done,
                                   target: context.coordinator, action: #selector(Coordinator.done))
        done.accessibilityIdentifier = "dismiss-port-keyboard"
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        field.inputAccessoryView = toolbar
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
        field.placeholder = AppLocalization.string(label)
        field.accessibilityLabel = AppLocalization.string(label)
        field.accessibilityIdentifier = identifier
        (field.inputAccessoryView as? UIToolbar)?.items?.last?.title = AppLocalization.string("Done")
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        weak var field: UITextField?
        init(text: Binding<String>) { self.text = text }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Run after UIKit places the touch caret. Numeric connection ports
            // are usually replaced as a whole, including with iPad's floating pad.
            DispatchQueue.main.async { [weak textField] in
                guard let textField, textField.isFirstResponder else { return }
                textField.selectedTextRange = textField.textRange(from: textField.beginningOfDocument,
                                                                 to: textField.endOfDocument)
            }
        }
        @objc func changed(_ sender: UITextField) { text.wrappedValue = sender.text ?? "" }
        @objc func done() { field?.resignFirstResponder() }
    }
}
#else
struct PortTextField: View {
    @Binding var text: String
    var label = "Port"
    var identifier: String?
    var body: some View {
        TextField(AppLocalization.string(label), text: $text)
            .labelsHidden()
            .accessibilityLabel(AppLocalization.string(label))
            .accessibilityIdentifier(identifier ?? "")
            .multilineTextAlignment(.trailing)
    }
}
#endif
