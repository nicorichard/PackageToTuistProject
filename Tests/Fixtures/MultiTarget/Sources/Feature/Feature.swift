import Core

public struct Feature {
    private let core = Core()

    public init() {}

    public func featureFunction() -> String {
        "Feature using \(core.coreFunction())"
    }
}
