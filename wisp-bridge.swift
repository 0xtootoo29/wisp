import Foundation

// Wisp Bridge — Chrome Native Messaging host ↔ Wisp.app 中继
// Chrome 在扩展 connectNative 时拉起本进程；生命周期跟随扩展端口（stdin EOF 即退出）。
// 协议：stdin/stdout 走 NM 帧（4 字节小端长度 + JSON）；与 App 之间走分布式通知。

let cmdNote = Notification.Name("local.tootoo.wisp.cmd")     // App → 扩展
let stateNote = Notification.Name("local.tootoo.wisp.state") // 扩展 → App

let outQ = DispatchQueue(label: "wisp.bridge.out")

func send(_ obj: [String: String]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    var len = UInt32(data.count).littleEndian
    var frame = Data(bytes: &len, count: 4)
    frame.append(data)
    outQ.sync { FileHandle.standardOutput.write(frame) }
}

final class Relay: NSObject {
    @objc func onCmd(_ note: Notification) {
        send(["cmd": (note.object as? String) ?? ""])
    }
}
let relay = Relay()
DistributedNotificationCenter.default().addObserver(
    relay, selector: #selector(Relay.onCmd(_:)), name: cmdNote, object: nil)

// SW 保活心跳：host→扩展 的消息会重置 service worker 空闲计时
// ponytail: Chrome 116+ NM 端口本身即保活，心跳是双保险
let ping = Timer(timeInterval: 25, repeats: true) { _ in send(["cmd": "ping"]) }
RunLoop.main.add(ping, forMode: .common)

// 扩展 → App：读 stdin 帧，状态转发为分布式通知
DispatchQueue.global().async {
    let stdin = FileHandle.standardInput
    while true {
        let header = stdin.readData(ofLength: 4)
        if header.count < 4 { exit(0) } // 端口关闭
        let len = header.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        if len == 0 || len > 1_000_000 { exit(1) }
        let payload = stdin.readData(ofLength: Int(len))
        if payload.count < Int(len) { exit(0) }
        guard let msg = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let state = msg["state"] as? String else { continue }
        DistributedNotificationCenter.default().postNotificationName(
            stateNote, object: state, userInfo: nil, deliverImmediately: true)
    }
}

RunLoop.main.run()
