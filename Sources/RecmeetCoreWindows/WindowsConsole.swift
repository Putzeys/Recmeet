#if os(Windows)
import WinSDK
import Foundation

/// Helpers for the Windows console — currently just a Ctrl-C waiter for the CLI.
public enum WindowsConsole {
    private static let semaphore = DispatchSemaphore(value: 0)
    private static var handlerInstalled = false
    private static let lock = NSLock()

    public static func waitForCtrlC() async {
        installHandlerIfNeeded()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                semaphore.wait()
                cont.resume()
            }
        }
    }

    private static func installHandlerIfNeeded() {
        lock.lock(); defer { lock.unlock() }
        guard !handlerInstalled else { return }
        handlerInstalled = true
        SetConsoleCtrlHandler({ ctrlType in
            switch Int32(ctrlType) {
            case CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT:
                WindowsConsole.semaphore.signal()
                return true
            default:
                return false
            }
        }, true)
    }
}

#endif
