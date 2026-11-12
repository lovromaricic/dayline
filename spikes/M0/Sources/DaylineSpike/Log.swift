import Foundation

enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func line(_ s: String) {
        print("\(formatter.string(from: Date()))  \(s)")
    }

    static func raw(_ s: String) {
        print(s)
    }
}
