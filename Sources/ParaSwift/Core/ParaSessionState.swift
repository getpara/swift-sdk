import Foundation

public enum ParaSessionState: Int {
    case unknown = 0
    case inactive = 1
    case restoring = 2
    case active = 3
    case activeLoggedIn = 4
}
