import Foundation

enum AssistSuite {
    static let suite = TestSuite(name: "Assist", cases: [
        TestCase(name: "context numbers items and summarizes images and files") { t in
            let s = Store.shared
            let text = s.insert(TestKit.capture("plain words", name: "Notes"))
            let img = s.insert(TestKit.capture("", kind: .image, blob: Data(repeating: 0, count: 2048), blobType: "public.png"))
            let file = s.insert(TestKit.capture("/tmp/a\n/tmp/b", kind: .file))
            let ctx = Assist.context(for: [text, img, file])
            t.check(ctx.contains("### 1.") && ctx.contains("### 2.") && ctx.contains("### 3."), "numbered")
            t.check(ctx.contains("plain words") && ctx.contains("Notes"), "text and source app")
            t.check(ctx.contains("[image, 2 KB]"), "image placeholder, not bytes")
            t.check(ctx.contains("[files] /tmp/a, /tmp/b"), "file paths")
        },
        TestCase(name: "context stops at the character budget") { t in
            let items = (0..<10).map { _ in Store.shared.insert(TestKit.capture(String(repeating: "y", count: 500) + UUID().uuidString)) }
            let ctx = Assist.context(for: items, maxChars: 1200)
            t.check(ctx.count < 1500, "bounded")
            t.check(ctx.contains("more items omitted"), "says what was left out")
        },
        TestCase(name: "cloud payload is masked and excludes excluded apps") { t in
            let s = Store.shared
            let key = s.insert(TestKit.capture("deploy with sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdef"))
            let pw = s.insert(TestKit.capture("vault entry", app: "com.1password.1password"))
            let ok = s.insert(TestKit.capture("meeting at 3"))
            let p = Assist.shared.prepareCloud("what?", items: [key, pw, ok])
            t.equal(p.itemCount, 2, "excluded-app item dropped")
            t.check(!p.maskedContext.contains("sk-ant-"), "key masked")
            t.check(!p.maskedContext.contains("vault entry"), "excluded content absent")
            t.check(p.maskedContext.contains("meeting at 3"), "ordinary content kept")
            t.equal(p.labels, ["API KEY"], "labels")
            t.equal(p.prompt, "what?", "prompt kept")
            t.check(p.chars > 0, "chars counted")
        },
        TestCase(name: "semantic search ranks meaning") { t in
            guard Capabilities.sentenceEmbeddingAvailable else { t.skip("no sentence embedding for this language"); return }
            let s = Store.shared
            let inv = s.insert(TestKit.capture("The quarterly invoice for the Woodland project is overdue"))
            let rec = s.insert(TestKit.capture("recipe: two eggs, flour, milk, whisk until smooth"))
            _ = s.insert(TestKit.capture("meeting notes: ship the clipboard app next week"))
            Assist.shared.indexPending()
            t.equal(s.allVectors(model: Assist.shared.modelTag).count, 3, "all three embedded")
            t.equal(Assist.shared.semanticSearch("unpaid bill").first?.0.id, inv.id, "bill → invoice")
            t.equal(Assist.shared.semanticSearch("pancake batter").first?.0.id, rec.id, "batter → recipe")
            t.check(Assist.shared.semanticSearch("zzqx").isEmpty || true, "nonsense doesn't crash")
            let v = Assist.shared.vector(for: "anything")!
            let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
            t.check(abs(norm - 1) < 0.001, "vectors are unit length")
        },
        TestCase(name: "provider endpoints and errors") { t in
            t.check(Assist.Provider(rawValue: "openai")?.endpoint.host == "api.openai.com", "openai endpoint")
            t.check(Assist.Provider.anthropic.endpoint.absoluteString == "https://api.anthropic.com/v1/messages", "anthropic endpoint")
            t.equal(AssistError.noKey(.anthropic).errorDescription?.contains("Anthropic") ?? false, true, "error names the provider")
        },
    ])
}
