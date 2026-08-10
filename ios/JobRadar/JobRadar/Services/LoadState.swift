import Foundation

/// A generic, honest representation of an integration's state. Screens render
/// distinct UI for each case — never a silent blank.
enum LoadState<Value>: Equatable where Value: Equatable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case disconnected
    case failed(String)

    var value: Value? {
        if case let .loaded(v) = self { return v }
        return nil
    }
}
