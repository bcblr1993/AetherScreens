import Foundation
import Darwin

enum AppleFileCopySourceAttributes {
    enum Failure: Error { case attributes, exceedsLimit }
    static func collect(descriptor: Int32) throws -> [AppleFileCopyAttributeBlock.Entry] {
        let length = flistxattr(descriptor, nil, 0, 0)
        guard length >= 0 else { throw Failure.attributes }
        guard length <= 65_517 else { throw Failure.exceedsLimit }
        guard length > 0 else { return [] }
        var names = [CChar](repeating: 0, count: length)
        let actual = names.withUnsafeMutableBufferPointer { flistxattr(descriptor, $0.baseAddress, length, 0) }
        guard actual == length, names.last == 0 else { throw Failure.attributes }
        var result: [AppleFileCopyAttributeBlock.Entry] = []
        var remaining = 65_535 - 18
        for rawName in names.split(separator: 0) {
            let name = Data(rawName.map { UInt8(bitPattern: $0) })
            if name == Data("com.apple.ResourceFork".utf8) { continue }
            guard name.count + 9 <= remaining else { throw Failure.exceedsLimit }
            remaining -= name.count + 9
            let terminated = Array(rawName) + [0]
            let value: Data = try terminated.withUnsafeBufferPointer { pointer in
                let size = fgetxattr(descriptor, pointer.baseAddress!, nil, 0, 0, 0)
                guard size >= 0 else { throw Failure.attributes }
                guard size <= remaining else { throw Failure.exceedsLimit }
                var data = Data(count: size)
                let count = data.withUnsafeMutableBytes { fgetxattr(descriptor, pointer.baseAddress!, $0.baseAddress, size, 0, 0) }
                guard count == size else { throw Failure.attributes }
                return data
            }
            remaining -= value.count
            result.append(.init(name: name, value: value))
        }
        return result
    }
}
