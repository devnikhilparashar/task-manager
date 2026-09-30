import Foundation
import ApplicationServices

struct MacAccessibilityExtractor: AccessibilityExtracting {
    let policy: CapturePolicy

    func extract(from context: ActiveWindowContext) async -> SemanticSnapshot {
        guard let root = context.accessibilityWindow else {
            return SemanticSnapshot(context: context, timestamp: Date(), text: [], elements: [], quality: 0)
        }
        let start = Date()
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        var lines: [String] = []
        var metadata: [ElementMetadata] = []
        var seen = Set<String>()

        while index < queue.count,
              index < policy.maximumAXNodes,
              Date().timeIntervalSince(start) < policy.maximumAXDuration {
            let (element, depth) = queue[index]
            index += 1
            let role = string(element, kAXRoleAttribute as CFString) ?? ""
            let subrole = string(element, kAXSubroleAttribute as CFString) ?? ""
            if subrole.lowercased().contains("secure") { continue }

            let hidden = bool(element, "AXHidden" as CFString) ?? false
            if hidden { continue }
            let candidates = [
                string(element, kAXTitleAttribute as CFString),
                string(element, kAXDescriptionAttribute as CFString),
                string(element, kAXValueAttribute as CFString),
                string(element, kAXDocumentAttribute as CFString),
                string(element, "AXURL" as CFString)
            ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count < 20_000 }
            for candidate in candidates where seen.insert(candidate).inserted { lines.append(candidate) }
            if !candidates.isEmpty {
                metadata.append(ElementMetadata(role: role, label: candidates.first ?? "", frame: frame(element)))
            }
            if depth < policy.maximumAXDepth {
                queue.append(contentsOf: children(element).map { ($0, depth + 1) })
            }
        }
        let characters = lines.reduce(0) { $0 + $1.count }
        let completion = min(1, Double(index) / Double(max(1, queue.count)))
        let richness = min(1, Double(characters) / 500)
        return SemanticSnapshot(context: context, timestamp: Date(), text: lines, elements: metadata, quality: max(0.05, richness * 0.8 + completion * 0.2))
    }

    private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: CFString) -> String? {
        guard let value = attribute(element, name) else { return nil }
        if let string = value as? String { return string }
        if let url = value as? URL { return url.absoluteString }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func bool(_ element: AXUIElement, _ name: CFString) -> Bool? { attribute(element, name) as? Bool }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(element, kAXPositionAttribute as CFString),
              let sizeValue = attribute(element, kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}
