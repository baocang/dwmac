import Carbon.HIToolbox
import Foundation

/// Virtual key codes used by dwmac.
enum VKey {
    static let j: UInt32      = UInt32(kVK_ANSI_J)
    static let k: UInt32      = UInt32(kVK_ANSI_K)
    static let h: UInt32      = UInt32(kVK_ANSI_H)
    static let l: UInt32      = UInt32(kVK_ANSI_L)
    static let r: UInt32      = UInt32(kVK_ANSI_R)
    static let t: UInt32      = UInt32(kVK_ANSI_T)
    static let f: UInt32      = UInt32(kVK_ANSI_F)
    static let c: UInt32      = UInt32(kVK_ANSI_C)
    static let q: UInt32      = UInt32(kVK_ANSI_Q)
    static let b: UInt32      = UInt32(kVK_ANSI_B)
    static let leftBracket: UInt32  = UInt32(kVK_ANSI_LeftBracket)
    static let rightBracket: UInt32 = UInt32(kVK_ANSI_RightBracket)
    static let backslash: UInt32    = UInt32(kVK_ANSI_Backslash)
    static let `return`: UInt32 = UInt32(kVK_Return)
    static let comma: UInt32  = UInt32(kVK_ANSI_Comma)
    static let period: UInt32 = UInt32(kVK_ANSI_Period)
    static let one: UInt32    = UInt32(kVK_ANSI_1)
    static let two: UInt32    = UInt32(kVK_ANSI_2)
    static let three: UInt32  = UInt32(kVK_ANSI_3)
    static let four: UInt32   = UInt32(kVK_ANSI_4)
    static let five: UInt32   = UInt32(kVK_ANSI_5)
    static let six: UInt32    = UInt32(kVK_ANSI_6)
    static let seven: UInt32  = UInt32(kVK_ANSI_7)
    static let eight: UInt32  = UInt32(kVK_ANSI_8)
    static let nine: UInt32   = UInt32(kVK_ANSI_9)

    static let numbers: [UInt32] = [one, two, three, four, five, six, seven, eight, nine]
}

enum CarbonModifier {
    static let command: UInt32 = UInt32(cmdKey)
    static let shift:   UInt32 = UInt32(shiftKey)
    static let option:  UInt32 = UInt32(optionKey)
    static let control: UInt32 = UInt32(controlKey)
}

extension ModifierToken {
    var carbonMask: UInt32 {
        switch self {
        case .control: return CarbonModifier.control
        case .command: return CarbonModifier.command
        case .option:  return CarbonModifier.option
        case .shift:   return CarbonModifier.shift
        }
    }
}

/// Compute the Carbon modifier mask from a list of tokens (order-independent).
func carbonMask(from tokens: [ModifierToken]) -> UInt32 {
    tokens.reduce(0) { $0 | $1.carbonMask }
}

/// Carbon event signature constant for dwmac hotkeys.
let kDwmacHotKeySignature: OSType = 0x44574D43  // 'DWMC'
