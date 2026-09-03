//  Clip for Mac — clipboard history that refuses to capture secrets.
//  MIT licensed. See LICENSE.

import Foundation
import CryptoKit

enum SharingSuite {
    static let suite = TestSuite(name: "Sharing", cases: [
        TestCase(name: "both sides derive the same key and code; a third party does not") { t in
            let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey(), m = Curve25519.KeyAgreement.PrivateKey()
            let ids = ["A-ID", "B-ID"]
            let sa = try a.sharedSecretFromKeyAgreement(with: b.publicKey)
            let sb = try b.sharedSecretFromKeyAgreement(with: a.publicKey)
            t.equal(ShareCrypto.code(shared: sa, ids: ids), ShareCrypto.code(shared: sb, ids: ["B-ID", "A-ID"]), "same code both sides, order-independent")
            t.equal(ShareCrypto.code(shared: sa, ids: ids).count, 6, "six digits")
            t.check(ShareCrypto.pairKey(shared: sa, ids: ids) == ShareCrypto.pairKey(shared: sb, ids: ids), "same key")
            let sm = try m.sharedSecretFromKeyAgreement(with: a.publicKey)
            t.check(ShareCrypto.code(shared: sm, ids: ids) != ShareCrypto.code(shared: sa, ids: ids), "man in the middle shows a different code")
            let sealed = try ShareCrypto.seal(Data("hello".utf8), key: ShareCrypto.pairKey(shared: sa, ids: ids))
            t.equal(try ShareCrypto.open(sealed, key: ShareCrypto.pairKey(shared: sb, ids: ids)), Data("hello".utf8), "round trip")
            t.check((try? ShareCrypto.open(sealed, key: ShareCrypto.pairKey(shared: sm, ids: ids))) == nil, "wrong key fails")
            var tampered = sealed; tampered[tampered.count - 1] ^= 1
            t.check((try? ShareCrypto.open(tampered, key: ShareCrypto.pairKey(shared: sa, ids: ids))) == nil, "tampering fails")
        },
        TestCase(name: "payload never carries secrets, images, files or excluded-app items") { t in
            let s = Store.shared
            let pin = s.insert(TestKit.capture("pinned text"))
            s.setPinned(pin.id, true, keyword: "pt")
            _ = s.insert(TestKit.capture("token sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
            _ = s.insert(TestKit.capture("", kind: .image, blob: Data([1, 2, 3]), blobType: "public.png"))
            _ = s.insert(TestKit.capture("/tmp/x", kind: .file))
            _ = s.insert(TestKit.capture("from a vault", app: "com.1password.1password"))
            _ = s.insert(TestKit.capture("plain recent"))
            _ = s.insert(TestKit.capture("https://example.com", kind: .url))
            let p = SharePayload.build(from: s, recent: 10, device: "Test Mac")
            let texts = p.entries.map(\.plain)
            t.check(texts.contains("pinned text") && texts.contains("plain recent") && texts.contains("https://example.com"), "safe items included")
            t.check(!texts.contains { $0.contains("sk-ant") }, "secret excluded")
            t.check(!texts.contains("from a vault"), "excluded app excluded")
            t.check(!p.entries.contains { $0.kind == "image" || $0.kind == "file" }, "no images or files")
            t.check(p.entries.first { $0.plain == "pinned text" }?.keyword == "pt", "keyword travels")
            let limited = SharePayload.build(from: s, recent: 1, device: "Test Mac")
            t.equal(limited.entries.filter { !$0.pinned }.count, 1, "recent count honoured")
        },
        TestCase(name: "payload merges into another store") { t in
            let a = Store(inMemory: true), b = Store(inMemory: true)
            let pin = a.insert(TestKit.capture("shared pin")); a.setPinned(pin.id, true, keyword: "sp")
            _ = a.insert(TestKit.capture("shared recent"))
            let p = SharePayload.build(from: a, recent: 5, device: "Mac A")
            let data = try JSONEncoder().encode(p)
            let back = try JSONDecoder().decode(SharePayload.self, from: data)
            t.equal(back.merge(into: b), 3, "two new items, one newly pinned")
            t.equal(b.snippet(keyword: "sp")?.plain, "shared pin", "pin arrived with keyword")
            t.equal(b.recent().first { $0.plain == "shared recent" }?.sourceName, "Mac A", "source is the other Mac")
            t.equal(back.merge(into: b), 0, "merging again changes nothing")
        },
        TestCase(name: "frames are length-prefixed and survive splitting") { t in
            let f1 = Frame(kind: .hello, id: "X", name: "Mac", pub: "AAAA")
            let f2 = Frame(kind: .data, id: "X", box: "BBBB")
            var stream = try f1.encoded() + f2.encoded()
            var partial = stream.prefix(stream.count - 3)
            let firstBatch = Frame.drain(&partial)
            t.equal(firstBatch.count, 1, "only the complete frame is parsed")
            t.equal(firstBatch.first?.kind, .hello, "first frame")
            partial.append(stream.suffix(3))
            let second = Frame.drain(&partial)
            t.equal(second.first?.box, "BBBB", "second frame after the rest arrives")
            t.check(partial.isEmpty, "buffer drained")
            var bad = Data([0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3])
            t.check(Frame.drain(&bad).isEmpty && bad.isEmpty, "absurd length drops the buffer")
            stream.removeAll()
        },
        TestCase(name: "paired device bookkeeping in memory") { t in
            ShareKeys.memoryOnly = true
            defer { ShareKeys.memoryOnly = false }
            let k1 = ShareKeys.privateKey(), k2 = ShareKeys.privateKey()
            t.check(k1.rawRepresentation == k2.rawRepresentation, "device key is stable")
            let key = SymmetricKey(size: .bits256)
            ShareKeys.setPairKey(key, for: "peer1")
            t.check(ShareKeys.pairKey(for: "peer1") == key, "pair key round trip")
            ShareKeys.setPairKey(nil, for: "peer1")
            t.check(ShareKeys.pairKey(for: "peer1") == nil, "removed")
            ShareKeys.paired = [PairedDevice(id: "peer1", name: "Other", pairedAt: Date())]
            t.equal(ShareKeys.paired.first?.name, "Other", "paired list persists in defaults")
            t.check(!ShareKeys.deviceID.isEmpty && ShareKeys.deviceID == ShareKeys.deviceID, "device id stable")
        },
    ])
}
