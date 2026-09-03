//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.
//
//  Sharing between your own Macs on the local network. No server, no account: Bonjour finds the
//  other Mac, both sides show the same six-digit code derived from an ECDH key exchange, you confirm
//  on both, and from then on pins and the last N text items travel end-to-end encrypted with
//  ChaChaPoly. Items that look like secrets, images, files and anything from an excluded app never
//  leave the machine. Off by default.

import Foundation
import Network
import CryptoKit
import AppKit

// MARK: - Pure parts (tested)

enum ShareCrypto {
    static let serviceType = "_clipmac._tcp"

    /// Symmetric key for a pair: HKDF over the ECDH secret, bound to both device ids in a fixed order.
    static func pairKey(shared: SharedSecret, ids: [String]) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("clipmac-pair-v1".utf8), sharedInfo: Data(ids.sorted().joined(separator: "|").utf8), outputByteCount: 32)
    }

    /// The six digits both screens show. Anyone in the middle would produce a different code on each side.
    static func code(shared: SharedSecret, ids: [String]) -> String {
        let k = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("clipmac-sas-v1".utf8), sharedInfo: Data(ids.sorted().joined(separator: "|").utf8), outputByteCount: 8)
        let n = k.withUnsafeBytes { $0.load(as: UInt64.self) }
        return String(format: "%06llu", n % 1_000_000)
    }

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        try ChaChaPoly.seal(plaintext, using: key).combined
    }

    static func open(_ combined: Data, key: SymmetricKey) throws -> Data {
        try ChaChaPoly.open(try ChaChaPoly.SealedBox(combined: combined), using: key)
    }
}

/// What is sent: pins, and recent text that is safe to share.
struct SharePayload: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var kind: String
        var plain: String
        var keyword: String?
        var pinned: Bool
        var blobType: String?
        var blob: String?
    }
    var device: String
    var sentAt = Date()
    var entries: [Entry]

    /// Only pins and recent text-like items that are not secret-shaped and not from excluded apps.
    static func build(from store: Store, recent: Int, device: String, excluded: [String] = Prefs.excludedBundleIDs) -> SharePayload {
        func ok(_ it: Item) -> Bool {
            !it.looksSensitive && (it.kind == .text || it.kind == .url || it.kind == .rtf || it.kind == .html)
                && !(it.sourceBundleID.map { excluded.contains($0) } ?? false)
        }
        var entries: [Entry] = []
        var seen = Set<String>()
        for it in store.pinned().filter(ok) + store.recent(limit: recent * 2).filter({ ok($0) && !$0.pinned }).prefix(recent) {
            guard !seen.contains(it.contentHash) else { continue }
            seen.insert(it.contentHash)
            entries.append(Entry(kind: it.kind.rawValue, plain: it.plain, keyword: it.keyword, pinned: it.pinned, blobType: it.blobType,
                                 blob: it.blobHash.flatMap { store.blob($0)?.base64EncodedString() }))
        }
        return SharePayload(device: device, entries: entries)
    }

    /// Merges into the store. Returns how many items were new or newly pinned.
    @discardableResult
    func merge(into store: Store) -> Int {
        var changed = 0
        for e in entries {
            let kind = ItemKind(rawValue: e.kind) ?? .text
            let blob = e.blob.flatMap { Data(base64Encoded: $0) }
            let before = store.count()
            let item = store.insert(Capture(kind: kind, plain: e.plain, blobData: blob, blobType: e.blobType, sourceBundleID: "com.keithadler.clipmac.shared",
                                            sourceName: device, size: (blob?.count ?? 0) + e.plain.utf8.count))
            if store.count() != before { changed += 1 }
            if e.pinned && !(item.pinned && item.keyword == e.keyword) { store.setPinned(item.id, true, keyword: e.keyword ?? item.keyword); changed += 1 }
        }
        return changed
    }
}

/// Wire format: one JSON object per frame, length-prefixed (4 bytes big-endian).
struct Frame: Codable {
    enum Kind: String, Codable { case hello, confirm, data, bye }
    var kind: Kind
    var id: String?          // device id
    var name: String?        // device name
    var pub: String?         // base64 Curve25519 public key (hello)
    var box: String?         // base64 sealed payload (data)

    func encoded() throws -> Data {
        let body = try JSONEncoder().encode(self)
        var len = UInt32(body.count).bigEndian
        return Data(bytes: &len, count: 4) + body
    }

    /// Parses complete frames from a buffer, leaving any partial frame in place.
    static func drain(_ buffer: inout Data) -> [Frame] {
        var out: [Frame] = []
        while buffer.count >= 4 {
            let len = Int(buffer.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            guard len <= 64 << 20 else { buffer.removeAll(); break }   // absurd frame: drop the connection's buffer
            guard buffer.count >= 4 + len else { break }
            let body = buffer.subdata(in: 4..<(4 + len))
            buffer.removeSubrange(0..<(4 + len))
            if let f = try? JSONDecoder().decode(Frame.self, from: body) { out.append(f) }
        }
        return out
    }
}

struct PairedDevice: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var pairedAt: Date
}

// MARK: - Keys and paired devices

enum ShareKeys {
    private static let service = "com.keithadler.clipmac.sharing"

    static var deviceID: String {
        if let id = Prefs.defaults.string(forKey: "shareDeviceID") { return id }
        let id = UUID().uuidString
        Prefs.defaults.set(id, forKey: "shareDeviceID")
        return id
    }

    static var deviceName: String {
        get { Prefs.defaults.string(forKey: "shareDeviceName") ?? (Host.current().localizedName ?? "Mac") }
        set { Prefs.defaults.set(newValue, forKey: "shareDeviceName") }
    }

    /// Long-term key-agreement key, created on first use and kept in the login Keychain.
    static func privateKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let raw = read("device-key"), let k = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) { return k }
        let k = Curve25519.KeyAgreement.PrivateKey()
        write("device-key", k.rawRepresentation)
        return k
    }

    static func pairKey(for peer: String) -> SymmetricKey? { read("peer-" + peer).map { SymmetricKey(data: $0) } }
    static func setPairKey(_ key: SymmetricKey?, for peer: String) {
        if let key { write("peer-" + peer, key.withUnsafeBytes { Data($0) }) } else { delete("peer-" + peer) }
    }

    static var paired: [PairedDevice] {
        get { (Prefs.defaults.data(forKey: "sharePaired")).flatMap { try? JSONDecoder().decode([PairedDevice].self, from: $0) } ?? [] }
        set { Prefs.defaults.set(try? JSONEncoder().encode(newValue), forKey: "sharePaired") }
    }

    /// In-memory keys for tests and for the screenshots process, so nothing touches the Keychain there.
    nonisolated(unsafe) static var memoryOnly = false
    nonisolated(unsafe) private static var memory: [String: Data] = [:]

    private static func read(_ account: String) -> Data? {
        if memoryOnly { return memory[account] }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
    private static func write(_ account: String, _ data: Data) {
        if memoryOnly { memory[account] = data; return }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecAttrLabel as String] = "Clip for Mac sharing"
        SecItemAdd(add as CFDictionary, nil)
    }
    private static func delete(_ account: String) {
        if memoryOnly { memory[account] = nil; return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}

// MARK: - Live sharing

@MainActor
final class Sharing: ObservableObject {
    static let shared = Sharing()

    struct Nearby: Identifiable, Equatable {
        let id: String            // device id from the TXT record
        let name: String
        let endpoint: NWEndpoint
        static func == (a: Nearby, b: Nearby) -> Bool { a.id == b.id }
    }

    struct Pairing {
        let peerID: String
        let peerName: String
        let code: String
        let key: SymmetricKey
        let connection: NWConnection
        var confirmedHere = false
        var confirmedThere = false
    }

    @Published private(set) var running = false
    @Published private(set) var nearby: [Nearby] = []
    @Published var paired: [PairedDevice] = ShareKeys.paired
    @Published var pairing: Pairing?
    @Published private(set) var lastSync: Date?
    @Published private(set) var lastError: String?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [NWConnection] = []
    private var buffers: [ObjectIdentifier: Data] = [:]
    private var pushTimer: Timer?
    private let queue = DispatchQueue(label: "com.keithadler.clipmac.sharing")

    var enabled: Bool { Prefs.sharingEnabled }

    func start() {
        guard enabled, !running else { return }
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let l = try NWListener(using: params)
            l.service = NWListener.Service(name: ShareKeys.deviceName, type: ShareCrypto.serviceType, txtRecord: NWTXTRecord(["id": ShareKeys.deviceID]))
            l.newConnectionHandler = { [weak self] c in Task { @MainActor in self?.accept(c) } }
            l.stateUpdateHandler = { [weak self] st in
                if case .failed(let e) = st { Task { @MainActor in self?.lastError = e.localizedDescription } }
            }
            l.start(queue: queue)
            listener = l
        } catch { lastError = error.localizedDescription; return }

        let b = NWBrowser(for: .bonjourWithTXTRecord(type: ShareCrypto.serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found: [Nearby] = results.compactMap { r in
                guard case .bonjour(let txt) = r.metadata, let id = txt["id"], id != ShareKeys.deviceID,
                      case .service(let name, _, _, _) = r.endpoint else { return nil }
                return Nearby(id: id, name: name, endpoint: r.endpoint)
            }
            Task { @MainActor in self?.nearby = found.sorted { $0.name < $1.name } }
        }
        b.start(queue: queue)
        browser = b
        running = true

        pushTimer?.invalidate()
        pushTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in Task { @MainActor in self.pushToPaired() } }
        NotificationCenter.default.addObserver(forName: .clipPinsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pushSoon() }
        }
        pushSoon()
    }

    func stop() {
        listener?.cancel(); browser?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll(); buffers.removeAll()
        listener = nil; browser = nil; nearby = []; running = false
        pushTimer?.invalidate(); pushTimer = nil
    }

    func setEnabled(_ on: Bool) {
        Prefs.defaults.set(on, forKey: "sharingEnabled")
        on ? start() : stop()
    }

    // MARK: Pairing

    /// Initiator: connect to a nearby Mac and start the key exchange.
    func pair(with peer: Nearby) {
        let c = NWConnection(to: peer.endpoint, using: .tcp)
        attach(c)
        c.start(queue: queue)
        sendHello(on: c)
    }

    private func accept(_ c: NWConnection) {
        attach(c)
        c.start(queue: queue)
    }

    private func attach(_ c: NWConnection) {
        connections.append(c)
        buffers[ObjectIdentifier(c)] = Data()
        c.stateUpdateHandler = { [weak self] st in
            Task { @MainActor in
                guard let self else { return }
                switch st {
                case .ready: self.receive(on: c)
                case .failed, .cancelled: self.detach(c)
                default: break
                }
            }
        }
    }

    private func detach(_ c: NWConnection) {
        connections.removeAll { $0 === c }
        buffers[ObjectIdentifier(c)] = nil
        if pairing?.connection === c && !(pairing?.confirmedHere == true && pairing?.confirmedThere == true) { pairing = nil }
    }

    private func sendHello(on c: NWConnection) {
        let pub = ShareKeys.privateKey().publicKey.rawRepresentation.base64EncodedString()
        send(Frame(kind: .hello, id: ShareKeys.deviceID, name: ShareKeys.deviceName, pub: pub), on: c)
    }

    private func send(_ frame: Frame, on c: NWConnection) {
        guard let data = try? frame.encoded() else { return }
        c.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receive(on c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.buffers[ObjectIdentifier(c), default: Data()].append(data) }
                var buf = self.buffers[ObjectIdentifier(c)] ?? Data()
                for f in Frame.drain(&buf) { self.handle(f, on: c) }
                self.buffers[ObjectIdentifier(c)] = buf
                if done || error != nil { c.cancel() } else { self.receive(on: c) }
            }
        }
    }

    private func handle(_ f: Frame, on c: NWConnection) {
        switch f.kind {
        case .hello:
            guard let id = f.id, let name = f.name, let pubB64 = f.pub, let pubData = Data(base64Encoded: pubB64),
                  let pub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubData),
                  let shared = try? ShareKeys.privateKey().sharedSecretFromKeyAgreement(with: pub) else { return }
            let ids = [ShareKeys.deviceID, id]
            let key = ShareCrypto.pairKey(shared: shared, ids: ids)
            if paired.contains(where: { $0.id == id }), let known = ShareKeys.pairKey(for: id) {
                // Already paired: this is a data session. Reply hello so the initiator can send, then expect data.
                _ = known
                if pairing == nil { sendHello(on: c) }
                return
            }
            // New peer: show the code and wait for both confirmations.
            if pairing == nil { sendHello(on: c) }   // responder answers with its own hello
            pairing = Pairing(peerID: id, peerName: name, code: ShareCrypto.code(shared: shared, ids: ids), key: key, connection: c)
        case .confirm:
            guard var p = pairing, p.connection === c else { return }
            p.confirmedThere = true
            pairing = p
            finishPairingIfReady()
        case .data:
            guard let id = f.id, let key = ShareKeys.pairKey(for: id), let b64 = f.box, let box = Data(base64Encoded: b64),
                  let plain = try? ShareCrypto.open(box, key: key),
                  let payload = try? decoder.decode(SharePayload.self, from: plain) else { return }
            let n = payload.merge(into: Store.shared)
            lastSync = Date()
            if n > 0 {
                Assist.shared.indexSoon()
                NotificationCenter.default.post(name: .clipHistoryChanged, object: nil)
                Toast.show(String(format: String(localized: "%lld items from %@"), n, payload.device), symbol: "laptopcomputer.and.arrow.down")
            }
        case .bye:
            c.cancel()
        }
    }

    /// The user pressed "Pair" after comparing codes.
    func confirmPairing() {
        guard var p = pairing else { return }
        p.confirmedHere = true
        pairing = p
        send(Frame(kind: .confirm, id: ShareKeys.deviceID), on: p.connection)
        finishPairingIfReady()
    }

    func cancelPairing() {
        if let p = pairing { send(Frame(kind: .bye), on: p.connection); p.connection.cancel() }
        pairing = nil
    }

    private func finishPairingIfReady() {
        guard let p = pairing, p.confirmedHere, p.confirmedThere else { return }
        ShareKeys.setPairKey(p.key, for: p.peerID)
        var list = ShareKeys.paired.filter { $0.id != p.peerID }
        list.append(PairedDevice(id: p.peerID, name: p.peerName, pairedAt: Date()))
        ShareKeys.paired = list
        paired = list
        pairing = nil
        pushSoon()
    }

    func unpair(_ device: PairedDevice) {
        ShareKeys.setPairKey(nil, for: device.id)
        ShareKeys.paired.removeAll { $0.id == device.id }
        paired = ShareKeys.paired
    }

    // MARK: Data

    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private var pushWork: DispatchWorkItem?

    func pushSoon() {
        pushWork?.cancel()
        let w = DispatchWorkItem { [weak self] in Task { @MainActor in self?.pushToPaired() } }
        pushWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }

    /// Sends the current payload to every paired Mac that is on the network right now.
    func pushToPaired() {
        guard running, !paired.isEmpty else { return }
        let payload = SharePayload.build(from: Store.shared, recent: Prefs.shareRecentCount, device: ShareKeys.deviceName)
        guard let plain = try? encoder.encode(payload) else { return }
        for device in paired {
            guard let peer = nearby.first(where: { $0.id == device.id }), let key = ShareKeys.pairKey(for: device.id),
                  let box = try? ShareCrypto.seal(plain, key: key) else { continue }
            let c = NWConnection(to: peer.endpoint, using: .tcp)
            attach(c)
            c.stateUpdateHandler = { [weak self] st in
                Task { @MainActor in
                    guard let self else { return }
                    switch st {
                    case .ready:
                        self.send(Frame(kind: .data, id: ShareKeys.deviceID, box: box.base64EncodedString()), on: c)
                        self.send(Frame(kind: .bye), on: c)
                        self.lastSync = Date()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { c.cancel() }
                    case .failed(let e): self.lastError = e.localizedDescription; self.detach(c)
                    case .cancelled: self.detach(c)
                    default: break
                    }
                }
            }
            c.start(queue: queue)
        }
    }
}
