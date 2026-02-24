/// A labeled argument for Swift code generation
struct LabeledArg {
    let label: String
    let value: String
}

extension Array where Element == LabeledArg {
    /// Format as a comma-separated, indented argument list
    func formatted(indent: String) -> String {
        self.map { arg in
            let indentedValue = arg.value
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .map { i, line in i == 0 ? String(line) : indent + String(line) }
                .joined(separator: "\n")
            return "\(indent)\(arg.label): \(indentedValue)"
        }
        .joined(separator: ",\n")
    }
}
