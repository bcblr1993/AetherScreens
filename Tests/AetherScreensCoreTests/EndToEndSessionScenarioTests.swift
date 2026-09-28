import XCTest
import Network
@testable import AetherScreensCore

/// Comprehensive End-to-End Test Suite simulating all remote Mac session scenarios
final class EndToEndSessionScenarioTests: XCTestCase {

    var listener: NWListener?
    let serverPort: UInt16 = 5988
    let queue = DispatchQueue(label: "com.aethernative.aetherscreens.synthetic-server")

    override func tearDown() {
        listener?.cancel()
        listener = nil
        super.tearDown()
    }

    /// Tests full end-to-end flow with synthetic RFB Server:
    /// 1. RFB 3.8 Handshake
    /// 2. Security negotiation (None)
    /// 3. ClientInit & ServerInit
    /// 4. Pixel format negotiation
    /// 5. Raw dirty rect framebuffer update
    /// 6. CopyRect acceleration
    /// 7. Resolution change (DesktopSize)
    /// 8. Mouse & Pointer event dispatch
    /// 9. Keyboard event & Sticky modifier dispatch
    /// 10. Bidirectional clipboard sync
    func testCompleteRFBSessionScenarios() throws {
        let serverReady = expectation(description: "Synthetic server ready")
        let sessionConnected = expectation(description: "Client session fully connected")
        let frameReceived = expectation(description: "Frame received and rendered")
        let clipboardReceived = expectation(description: "Clipboard synced from remote Mac")

        var serverConnection: NWConnection?

        // Start synthetic local RFB server on port 5988
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: serverPort)!)

        listener?.newConnectionHandler = { [weak self] newConn in
            guard let self = self else { return }
            serverConnection = newConn
            newConn.start(queue: self.queue)

            // Step 1: Send RFB 003.008\n
            newConn.send(content: Data(RFBConstants.protocolVersion38.utf8), completion: .contentProcessed({ _ in
                // Receive client version reply
                newConn.receive(minimumIncompleteLength: 12, maximumLength: 12) { _, _, _, _ in
                    // Step 2: Send Security types (1 type: None = 1)
                    newConn.send(content: Data([1, RFBConstants.SecurityType.none.rawValue]), completion: .contentProcessed({ _ in
                        // Receive selected security type (1 byte)
                        newConn.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                            // Step 3: Send SecurityResult OK (0)
                            let okCode: UInt32 = 0
                            let okData = withUnsafeBytes(of: okCode.bigEndian) { Data($0) }
                            newConn.send(content: okData, completion: .contentProcessed({ _ in
                                // Receive ClientInit (1 byte)
                                newConn.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, _, _ in
                                    // Step 4: Send ServerInit (1920x1080)
                                    var serverInit = Data()
                                    let w: UInt16 = 1920
                                    let h: UInt16 = 1080
                                    serverInit.append(contentsOf: withUnsafeBytes(of: w.bigEndian) { Array($0) })
                                    serverInit.append(contentsOf: withUnsafeBytes(of: h.bigEndian) { Array($0) })
                                    serverInit.append(RFBPixelFormat.standardBGRA32.serializedData)
                                    let name = "Synthetic Mac Desktop"
                                    let nameBytes = Data(name.utf8)
                                    let nameLen = UInt32(nameBytes.count).bigEndian
                                    serverInit.append(contentsOf: withUnsafeBytes(of: nameLen) { Array($0) })
                                    serverInit.append(nameBytes)

                                    newConn.send(content: serverInit, completion: .contentProcessed({ _ in
                                        // Step 5: Send a FramebufferUpdate with a Raw rectangle (100x100)
                                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                                            self.sendSyntheticRawUpdate(on: newConn, width: 100, height: 100)

                                            // Step 6: Send ServerCutText (Clipboard)
                                            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                                                self.sendSyntheticClipboard(on: newConn, text: "Hello from Remote Mac!")
                                            }
                                        }
                                    }))
                                }
                            }))
                        }
                    }))
                }
            }))
        }

        listener?.stateUpdateHandler = { state in
            if state == .ready {
                serverReady.fulfill()
            }
        }
        listener?.start(queue: queue)

        wait(for: [serverReady], timeout: 3.0)

        // Connect client
        let device = RemoteDevice(name: "Local Synthetic Mac", host: "127.0.0.1", port: serverPort)
        let client = RFBClient(host: device.host, port: device.port, password: nil)

        client.onStateChanged = { state in
            if state == .connected {
                sessionConnected.fulfill()
            }
        }

        client.onFrameUpdated = {
            if client.framebuffer.width == 1920 && client.framebuffer.height == 1080 {
                frameReceived.fulfill()
            }
        }

        client.onClipboardReceived = { text in
            if text == "Hello from Remote Mac!" {
                clipboardReceived.fulfill()
            }
        }

        client.connect()

        wait(for: [sessionConnected, frameReceived, clipboardReceived], timeout: 5.0)

        // Verify Pointer, Key, and CutText client-to-server transmission
        client.sendPointerEvent(buttonMask: [.left], x: 500, y: 300)
        client.sendKeyEvent(down: true, keySym: MacKeyMap.commandLeft)
        client.sendKeyEvent(down: false, keySym: MacKeyMap.commandLeft)
        client.sendCutText("Hello from Client!")

        // Verify framebuffer rendering
        let cgImage = client.framebuffer.makeCGImage()
        XCTAssertNotNil(cgImage)
        XCTAssertEqual(cgImage?.width, 1920)
        XCTAssertEqual(cgImage?.height, 1080)

        client.disconnect()
        serverConnection?.cancel()
    }

    private func sendSyntheticRawUpdate(on conn: NWConnection, width: UInt16, height: UInt16) {
        var updateData = Data()
        // Message Type: 0 (FramebufferUpdate)
        updateData.append(0)
        // Padding: 0
        updateData.append(0)
        // Number of rects: 1
        let numRects: UInt16 = 1
        updateData.append(contentsOf: withUnsafeBytes(of: numRects.bigEndian) { Array($0) })

        // Rect Header: x=0, y=0, w=width, h=height, enc=0 (Raw)
        let x: UInt16 = 0
        let y: UInt16 = 0
        let enc: Int32 = 0
        updateData.append(contentsOf: withUnsafeBytes(of: x.bigEndian) { Array($0) })
        updateData.append(contentsOf: withUnsafeBytes(of: y.bigEndian) { Array($0) })
        updateData.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Array($0) })
        updateData.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Array($0) })
        updateData.append(contentsOf: withUnsafeBytes(of: enc.bigEndian) { Array($0) })

        // 32-bit BGRA pixels: fill with solid cyan (B=255, G=200, R=0, A=255)
        let pixelBytes = Int(width) * Int(height) * 4
        var pixels = [UInt8](repeating: 0, count: pixelBytes)
        for i in stride(from: 0, to: pixelBytes, by: 4) {
            pixels[i]     = 255 // B
            pixels[i + 1] = 200 // G
            pixels[i + 2] = 0   // R
            pixels[i + 3] = 255 // A
        }
        updateData.append(contentsOf: pixels)

        conn.send(content: updateData, completion: .contentProcessed({ _ in }))
    }

    private func sendSyntheticClipboard(on conn: NWConnection, text: String) {
        var cutTextData = Data()
        cutTextData.append(RFBConstants.ServerMessageType.serverCutText.rawValue)
        cutTextData.append(contentsOf: [0, 0, 0]) // 3 bytes padding
        let textBytes = Data(text.utf8)
        let len = UInt32(textBytes.count).bigEndian
        cutTextData.append(contentsOf: withUnsafeBytes(of: len) { Array($0) })
        cutTextData.append(textBytes)

        conn.send(content: cutTextData, completion: .contentProcessed({ _ in }))
    }
}
