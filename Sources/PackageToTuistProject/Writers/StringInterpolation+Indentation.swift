import Foundation

public extension DefaultStringInterpolation {
    mutating func appendInterpolation(indented string: String) {
        let reversedIndent = String(stringInterpolation: self).reversed().prefix { " \t".contains($0) }
        if reversedIndent.isEmpty {
            appendInterpolation(string)
        } else {
            let indent = String(reversedIndent.reversed())
            appendLiteral(string.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n" + indent))
        }
    }
}
