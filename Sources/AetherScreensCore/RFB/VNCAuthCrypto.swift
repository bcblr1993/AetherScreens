import Foundation

/// Implements VNC Security Type 2 (VNC Authentication) cryptographic challenge-response.
/// As defined in RFC 6143 Section 7.2.2:
/// - 8-byte password is padded with null bytes or truncated.
/// - Each byte has its bits reversed (LSB becomes MSB).
/// - The 16-byte random challenge from the server is encrypted with DES (ECB mode).
public enum VNCAuthCrypto {

    /// Reverses the bits of a single byte (e.g. 0b10000000 -> 0b00000001).
    public static func reverseBits(in byte: UInt8) -> UInt8 {
        var b = byte
        b = ((b & 0xF0) >> 4) | ((b & 0x0F) << 4)
        b = ((b & 0xCC) >> 2) | ((b & 0x33) << 2)
        b = ((b & 0xAA) >> 1) | ((b & 0x55) << 1)
        return b
    }

    /// Prepares the 8-byte DES key from user password by padding/truncating and reversing bits.
    public static func prepareKey(from password: String) -> [UInt8] {
        let rawBytes = Array(password.utf8.prefix(8))
        var key = [UInt8](repeating: 0, count: 8)
        for i in 0..<min(rawBytes.count, 8) {
            key[i] = reverseBits(in: rawBytes[i])
        }
        return key
    }

    /// Encrypts the 16-byte server challenge with the user password using DES-ECB.
    public static func encryptChallenge(_ challenge: Data, password: String) -> Data {
        guard challenge.count == 16 else {
            return Data()
        }
        let key = prepareKey(from: password)
        let des = DESCipher(key: key)

        let block1 = Array(challenge[0..<8])
        let block2 = Array(challenge[8..<16])

        let enc1 = des.encryptBlock(block1)
        let enc2 = des.encryptBlock(block2)

        return Data(enc1 + enc2)
    }
}

// MARK: - Pure Swift DES (Data Encryption Standard) Implementation

/// Self-contained Single-DES block cipher (FIPS PUB 46-3) in ECB mode.
public struct DESCipher {
    private let subkeys: [[UInt8]] // 16 rounds of 48-bit subkeys (6 bytes each)

    public init(key: [UInt8]) {
        assert(key.count == 8, "DES key must be exactly 8 bytes (64 bits)")
        self.subkeys = DESCipher.generateSubkeys(from: key)
    }

    public func encryptBlock(_ block: [UInt8]) -> [UInt8] {
        assert(block.count == 8, "DES block must be exactly 8 bytes")
        
        // Initial Permutation (IP)
        let permuted = DESCipher.permute(block, table: DESCipher.initialPermutationTable, bitLength: 64)
        var left = Array(permuted[0..<4])
        var right = Array(permuted[4..<8])

        // 16 Feistel rounds
        for round in 0..<16 {
            let roundSubkey = subkeys[round]
            let fResult = DESCipher.feistelFunction(right: right, subkey: roundSubkey)
            let newRight = zip(left, fResult).map { $0 ^ $1 }
            left = right
            right = newRight
        }

        // Swap 32-bit halves (Preoutput is R16 || L16)
        let preoutput = right + left

        // Final Permutation (FP / IP^-1)
        return DESCipher.permute(preoutput, table: DESCipher.finalPermutationTable, bitLength: 64)
    }

    // MARK: - Feistel Round Function

    private static func feistelFunction(right: [UInt8], subkey: [UInt8]) -> [UInt8] {
        // 1. Expansion E (32 bits -> 48 bits)
        let expanded = permute(right, table: expansionTable, bitLength: 48)

        // 2. XOR with round subkey (48 bits / 6 bytes)
        let xored = zip(expanded, subkey).map { $0 ^ $1 }

        // 3. Substitution using 8 S-Boxes (48 bits -> 32 bits)
        var sOutput = [UInt8](repeating: 0, count: 4)
        for s in 0..<8 {
            let bitOffset = s * 6
            let byteIndex = bitOffset / 8
            let bitInByte = bitOffset % 8
            
            // Extract 6 bits
            var val: UInt16 = UInt16(xored[byteIndex]) << 8
            if byteIndex + 1 < xored.count {
                val |= UInt16(xored[byteIndex + 1])
            }
            let sixBits = UInt8((val >> (10 - bitInByte)) & 0x3F)

            let row = ((sixBits & 0x20) >> 4) | (sixBits & 0x01)
            let col = (sixBits >> 1) & 0x0F
            let sVal = sBoxes[s][Int(row)][Int(col)]

            let outIndex = s / 2
            if s % 2 == 0 {
                sOutput[outIndex] |= (sVal << 4)
            } else {
                sOutput[outIndex] |= sVal
            }
        }

        // 4. Permutation P (32 bits -> 32 bits)
        return permute(sOutput, table: permutationPTable, bitLength: 32)
    }

    // MARK: - Key Schedule

    private static func generateSubkeys(from key: [UInt8]) -> [[UInt8]] {
        // Permuted Choice 1 (PC-1): 64 bits -> 56 bits (discard parity bits)
        let pc1 = permute(key, table: pc1Table, bitLength: 56)

        // Split into C0 and D0 (28 bits each)
        var c = extract28Bits(from: pc1, high: true)
        var d = extract28Bits(from: pc1, high: false)

        var subkeys: [[UInt8]] = []
        let roundShifts = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1]

        for shift in roundShifts {
            c = rotateLeft28(c, by: shift)
            d = rotateLeft28(d, by: shift)

            let combined56 = combine28Bits(c: c, d: d)
            // Permuted Choice 2 (PC-2): 56 bits -> 48 bits (6 bytes)
            let k_i = permute(combined56, table: pc2Table, bitLength: 48)
            subkeys.append(k_i)
        }

        return subkeys
    }

    private static func extract28Bits(from data: [UInt8], high: Bool) -> UInt32 {
        var num: UInt64 = 0
        for b in data {
            num = (num << 8) | UInt64(b)
        }
        if high {
            return UInt32((num >> 28) & 0x0FFF_FFFF)
        } else {
            return UInt32(num & 0x0FFF_FFFF)
        }
    }

    private static func combine28Bits(c: UInt32, d: UInt32) -> [UInt8] {
        let val: UInt64 = (UInt64(c & 0x0FFF_FFFF) << 28) | UInt64(d & 0x0FFF_FFFF)
        var bytes = [UInt8](repeating: 0, count: 7)
        for i in 0..<7 {
            bytes[6 - i] = UInt8((val >> (i * 8)) & 0xFF)
        }
        return bytes
    }

    private static func rotateLeft28(_ val: UInt32, by shift: Int) -> UInt32 {
        let masked = val & 0x0FFF_FFFF
        return ((masked << shift) | (masked >> (28 - shift))) & 0x0FFF_FFFF
    }

    // MARK: - Permutation Helper

    private static func permute(_ input: [UInt8], table: [UInt8], bitLength: Int) -> [UInt8] {
        let outByteCount = (bitLength + 7) / 8
        var output = [UInt8](repeating: 0, count: outByteCount)

        for (outBitIdx, src1BasedBitIdx) in table.enumerated() {
            let src0Based = Int(src1BasedBitIdx) - 1
            let srcByte = src0Based / 8
            let srcBit = 7 - (src0Based % 8)
            let bit = (input[srcByte] >> srcBit) & 1

            let dstByte = outBitIdx / 8
            let dstBit = 7 - (outBitIdx % 8)
            output[dstByte] |= (bit << dstBit)
        }

        return output
    }

    // MARK: - DES Tables

    private static let initialPermutationTable: [UInt8] = [
        58, 50, 42, 34, 26, 18, 10, 2,
        60, 52, 44, 36, 28, 20, 12, 4,
        62, 54, 46, 38, 30, 22, 14, 6,
        64, 56, 48, 40, 32, 24, 16, 8,
        57, 49, 41, 33, 25, 17, 9,  1,
        59, 51, 43, 35, 27, 19, 11, 3,
        61, 53, 45, 37, 29, 21, 13, 5,
        63, 55, 47, 39, 31, 23, 15, 7
    ]

    private static let finalPermutationTable: [UInt8] = [
        40, 8, 48, 16, 56, 24, 64, 32,
        39, 7, 47, 15, 55, 23, 63, 31,
        38, 6, 46, 14, 54, 22, 62, 30,
        37, 5, 45, 13, 53, 21, 61, 29,
        36, 4, 44, 12, 52, 20, 60, 28,
        35, 3, 43, 11, 51, 19, 59, 27,
        34, 2, 42, 10, 50, 18, 58, 26,
        33, 1, 41, 9,  49, 17, 57, 25
    ]

    private static let expansionTable: [UInt8] = [
        32, 1,  2,  3,  4,  5,
        4,  5,  6,  7,  8,  9,
        8,  9,  10, 11, 12, 13,
        12, 13, 14, 15, 16, 17,
        16, 17, 18, 19, 20, 21,
        20, 21, 22, 23, 24, 25,
        24, 25, 26, 27, 28, 29,
        28, 29, 30, 31, 32, 1
    ]

    private static let permutationPTable: [UInt8] = [
        16, 7, 20, 21,
        29, 12, 28, 17,
        1,  15, 23, 26,
        5,  18, 31, 10,
        2,  8,  24, 14,
        32, 27, 3,  9,
        19, 13, 30, 6,
        22, 11, 4,  25
    ]

    private static let pc1Table: [UInt8] = [
        57, 49, 41, 33, 25, 17, 9,
        1,  58, 50, 42, 34, 26, 18,
        10, 2,  59, 51, 43, 35, 27,
        19, 11, 3,  60, 52, 44, 36,
        63, 55, 47, 39, 31, 23, 15,
        7,  62, 54, 46, 38, 30, 22,
        14, 6,  61, 53, 45, 37, 29,
        21, 13, 5,  28, 20, 12, 4
    ]

    private static let pc2Table: [UInt8] = [
        14, 17, 11, 24, 1,  5,
        3,  28, 15, 6,  21, 10,
        23, 19, 12, 4,  26, 8,
        16, 7,  27, 20, 13, 2,
        41, 52, 31, 37, 47, 55,
        30, 40, 51, 45, 33, 48,
        44, 49, 39, 56, 34, 53,
        46, 42, 50, 36, 29, 32
    ]

    private static let sBoxes: [[[UInt8]]] = [
        // S1
        [
            [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
            [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
            [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
            [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13]
        ],
        // S2
        [
            [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
            [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
            [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
            [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9]
        ],
        // S3
        [
            [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
            [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
            [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
            [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12]
        ],
        // S4
        [
            [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
            [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
            [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
            [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14]
        ],
        // S5
        [
            [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
            [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
            [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
            [11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3]
        ],
        // S6
        [
            [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
            [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
            [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
            [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13]
        ],
        // S7
        [
            [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
            [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
            [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
            [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12]
        ],
        // S8
        [
            [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
            [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
            [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
            [2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11]
        ]
    ]
}
