import CoreAudio
import CoreMediaIO
import Foundation

/// Mic: CoreAudio kAudioDevicePropertyDeviceIsRunningSomewhere on input devices.
/// Camera: the CoreMediaIO equivalent on video devices. Neither needs a
/// permission prompt; both are listener-driven, no polling.
final class CallDetector {
    private var lastSummary: String?

    func start() {
        var devices = audioAddress(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, .main) { [weak self] _, _ in
            self?.watchAudioDevices()
            self?.evaluate(reason: "audio devices changed")
        }
        var cmioDevices = cmioAddress(kCMIOHardwarePropertyDevices)
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &cmioDevices, .main) { [weak self] _, _ in
            self?.watchVideoDevices()
            self?.evaluate(reason: "video devices changed")
        }
        if #available(macOS 14.2, *) {
            var procs = audioAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &procs, .main) { [weak self] _, _ in
                self?.evaluate(reason: "audio process list changed")
            }
        }
        watchAudioDevices()
        watchVideoDevices()
        logInventory()
        evaluate(reason: "start")
    }

    // MARK: - Listeners

    private var watchedAudio = Set<AudioObjectID>()
    private var watchedVideo = Set<CMIOObjectID>()

    private func watchAudioDevices() {
        for id in inputDevices() where !watchedAudio.contains(id) {
            var addr = audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectAddPropertyListenerBlock(id, &addr, .main) { [weak self] _, _ in self?.evaluate(reason: "mic running changed") }
            watchedAudio.insert(id)
        }
    }

    private func watchVideoDevices() {
        for id in videoDevices() where !watchedVideo.contains(id) {
            var addr = cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectAddPropertyListenerBlock(id, &addr, .main) { [weak self] _, _ in self?.evaluate(reason: "camera running changed") }
            watchedVideo.insert(id)
        }
    }

    // MARK: - State

    private func evaluate(reason: String) {
        let mics = inputDevices().filter { audioUInt32($0, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1 }.map(audioName)
        let cams = videoDevices().filter { cmioUInt32($0, kCMIODevicePropertyDeviceIsRunningSomewhere) == 1 }.map(cmioName)
        var users: [String] = []
        if #available(macOS 14.2, *) { users = processesUsingMic() }

        let inCall = !mics.isEmpty || !cams.isEmpty
        let summary = "CALL \(inCall ? "ON " : "off")  mic=\(mics.isEmpty ? "-" : mics.joined(separator: ", "))  cam=\(cams.isEmpty ? "-" : cams.joined(separator: ", "))  micUsers=\(users.isEmpty ? "-" : users.joined(separator: ", "))"
        guard summary != lastSummary else { return }
        lastSummary = summary
        Log.line("\(summary)  (\(reason))")
    }

    private func logInventory() {
        for id in inputDevices() {
            Log.line("  input device: \(audioName(id)) [\(fourCC(audioUInt32(id, kAudioDevicePropertyTransportType) ?? 0))]")
        }
        for id in videoDevices() {
            Log.line("  video device: \(cmioName(id))")
        }
    }

    /// macOS 14.2+: per-process audio objects say which app is capturing.
    @available(macOS 14.2, *)
    private func processesUsingMic() -> [String] {
        audioObjects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            .filter { audioUInt32($0, kAudioProcessPropertyIsRunningInput) == 1 }
            .map { audioString($0, kAudioProcessPropertyBundleID) ?? "pid \(audioInt32($0, kAudioProcessPropertyPID) ?? -1)" }
    }

    // MARK: - CoreAudio helpers

    private func audioAddress(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func audioObjects(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = audioAddress(sel)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func inputDevices() -> [AudioObjectID] {
        audioObjects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).filter { id in
            var addr = audioAddress(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            var size: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
        }
    }

    private func audioUInt32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32? {
        var addr = audioAddress(sel)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func audioInt32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> Int32? {
        audioUInt32(id, sel).map { Int32(bitPattern: $0) }
    }

    private func audioString(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = audioAddress(sel)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        let s = value.takeRetainedValue() as String
        return s.isEmpty ? nil : s
    }

    private func audioName(_ id: AudioObjectID) -> String {
        audioString(id, kAudioObjectPropertyName) ?? "device \(id)"
    }

    private func fourCC(_ v: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((v >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? "\(v)"
    }

    // MARK: - CoreMediaIO helpers

    private func cmioAddress(_ sel: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(sel),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private func videoDevices() -> [CMIOObjectID] {
        var addr = cmioAddress(kCMIOHardwarePropertyDevices)
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(sys, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private func cmioUInt32(_ id: CMIOObjectID, _ sel: Int) -> UInt32? {
        var addr = cmioAddress(sel)
        var value: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr ? value : nil
    }

    private func cmioName(_ id: CMIOObjectID) -> String {
        var addr = cmioAddress(kCMIOObjectPropertyName)
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Unmanaged<CFString>?>.size), &used, &value) == noErr,
              let value else { return "camera \(id)" }
        return value.takeRetainedValue() as String
    }
}
