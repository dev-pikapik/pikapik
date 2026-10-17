import AppKit
import AVFoundation
import CoreAudio
import os

struct AppVolumeError: Error {
    let step: String
    let status: OSStatus
}

func appVolumeCheck(_ status: OSStatus, _ step: String) throws {
    if status != noErr { throw AppVolumeError(step: step, status: status) }
}

@available(macOS 14.2, *)
enum AppVolumeHAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? value : nil
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? value as String? : nil
    }

    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &list) == noErr else { return [] }
        return Array(list.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func processObject(pid: pid_t) -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        (read(process, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0) != 0
    }
}

@available(macOS 14.2, *)
struct AppVolumeOutput: Equatable {
    let device: AudioObjectID
    let uid: String
    let rate: Double

    init?(device: AudioObjectID) {
        guard device != kAudioObjectUnknown,
              (AppVolumeHAL.read(device, kAudioDevicePropertyDeviceIsAlive, UInt32(1)) ?? 1) != 0,
              let uid = AppVolumeHAL.string(device, kAudioDevicePropertyDeviceUID)
        else { return nil }
        self.device = device
        self.uid = uid
        rate = AppVolumeHAL.read(device, kAudioDevicePropertyNominalSampleRate, Float64(48000)) ?? 48000
    }

    static func current() -> AppVolumeOutput? {
        AppVolumeHAL.read(AppVolumeHAL.system, kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(kAudioObjectUnknown))
            .flatMap { AppVolumeOutput(device: $0) }
    }
}

@available(macOS 14.2, *)
final class AppVolumeChain {
    let output: AppVolumeOutput?
    let gain: AppVolumeGain
    private let ring: AppVolumeRing
    private let description: CATapDescription
    private let tap: AudioObjectID
    private let aggregate: AudioObjectID
    private let procID: AudioDeviceIOProcID
    private let unit: AUAudioUnit?
    private(set) var running = false

    private init(output: AppVolumeOutput?, gain: AppVolumeGain, ring: AppVolumeRing, description: CATapDescription, tap: AudioObjectID, aggregate: AudioObjectID, procID: AudioDeviceIOProcID, unit: AUAudioUnit?) {
        self.output = output
        self.gain = gain
        self.ring = ring
        self.description = description
        self.tap = tap
        self.aggregate = aggregate
        self.procID = procID
        self.unit = unit
    }

    static func make(process: AudioObjectID, name: String, output: AppVolumeOutput?, mute: CATapMuteBehavior, target: Float) throws -> AppVolumeChain {
        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.name = name
        description.isPrivate = true
        description.muteBehavior = mute
        var tap = AudioObjectID(kAudioObjectUnknown)
        try appVolumeCheck(AudioHardwareCreateProcessTap(description, &tap), "tap")
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        var procID: AudioDeviceIOProcID?
        do {
            guard let format = AppVolumeHAL.read(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription()), format.mSampleRate > 0 else {
                throw AppVolumeError(step: "format", status: kAudioHardwareBadPropertySizeError)
            }
            let gain = AppVolumeGain(target: target, sampleRate: format.mSampleRate)
            let ring = AppVolumeRing()
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: name,
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: false]],
            ]
            try appVolumeCheck(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate), "aggregate")
            let capture: AudioDeviceIOBlock = { _, input, _, _, _ in
                AppVolumeMath.capture(tap: input, ring: ring, state: gain)
            }
            try appVolumeCheck(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, nil, capture), "ioproc")
            guard let procID else { throw AppVolumeError(step: "ioproc", status: kAudioHardwareUnspecifiedError) }
            let unit = try output.map { device in
                try playback(on: device, format: format) { _, _, frames, _, data in
                    AppVolumeMath.render(tap: ring.pull(frames: Int(frames)), output: data, state: gain)
                    return noErr
                }
            }
            return AppVolumeChain(output: output, gain: gain, ring: ring, description: description, tap: tap, aggregate: aggregate, procID: procID, unit: unit)
        } catch {
            if let procID { AudioDeviceDestroyIOProcID(aggregate, procID) }
            if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
            AudioHardwareDestroyProcessTap(tap)
            throw error
        }
    }

    static func playback(on output: AppVolumeOutput, format: AudioStreamBasicDescription, provider: @escaping AURenderPullInputBlock) throws -> AUAudioUnit {
        var format = format
        guard let client = AVAudioFormat(streamDescription: &format) else {
            throw AppVolumeError(step: "format", status: OSStatus(kAudioUnitErr_FormatNotSupported))
        }
        let unit = try AUAudioUnit(componentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: OSType(kAudioUnitManufacturer_Apple), componentFlags: 0, componentFlagsMask: 0
        ))
        unit.isInputEnabled = false
        unit.isOutputEnabled = true
        try unit.setDeviceID(output.device)
        try unit.inputBusses[0].setFormat(client)
        unit.outputProvider = provider
        try unit.allocateRenderResources()
        return unit
    }

    func start() throws {
        guard !running else { return }
        ring.reset()
        try unit?.startHardware()
        let status = AudioDeviceStart(aggregate, procID)
        guard status == noErr else {
            unit?.stopHardware()
            throw AppVolumeError(step: "start", status: status)
        }
        running = true
    }

    func mute(_ on: Bool) throws {
        description.muteBehavior = on ? .muted : .unmuted
        var address = AppVolumeHAL.address(kAudioTapPropertyDescription)
        let status = withUnsafePointer(to: description) {
            AudioObjectSetPropertyData(tap, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
        try appVolumeCheck(status, "mute")
    }

    func stop() {
        guard running else { return }
        AudioDeviceStop(aggregate, procID)
        unit?.stopHardware()
        running = false
    }

    func destroy() {
        stop()
        unit?.deallocateRenderResources()
        AudioDeviceDestroyIOProcID(aggregate, procID)
        AudioHardwareDestroyAggregateDevice(aggregate)
        AudioHardwareDestroyProcessTap(tap)
    }
}
