import Foundation

public enum Log {
    public static func info(_ msg: String) {
        FileHandle.standardError.write(Data("[recmeet] \(msg)\n".utf8))
    }

    public static func error(_ msg: String) {
        FileHandle.standardError.write(Data("[recmeet][error] \(msg)\n".utf8))
    }
}
