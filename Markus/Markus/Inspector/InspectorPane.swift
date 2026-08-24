import SwiftUI

/// Trailing inspector for the current document. Reads outline rows and
/// parse diagnostics from `DocumentHost` — it does not parse again.
struct InspectorPane: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                InspectorDocumentSection(host: host)
                InspectorOutlineSection(host: host)
                InspectorWarningsSection(host: host)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("inspector.pane")
    }
}

private struct InspectorSectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct InspectorDocumentSection: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionHeader(title: "Document")
            LabeledContent("Name", value: filename)
            Picker("Kind", selection: kindBinding) {
                ForEach(DocumentKind.shipped, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Kind")
            HStack {
                Button("Pin Kind") { host.pinKind() }
                    .disabled(host.session.fileURL == nil)
                Button("Unpin Kind") { host.unpinKind() }
                    .disabled(!host.session.isKindPinned)
            }
            LabeledContent("Encoding", value: "UTF-8")
            LabeledContent("Lines", value: "\(lineCount)")
        }
    }

    private var filename: String {
        host.session.fileURL?.lastPathComponent ?? "Untitled"
    }

    private var lineCount: Int {
        let text = host.session.editor.string
        if text.isEmpty { return 0 }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    private var kindBinding: Binding<DocumentKind> {
        Binding(
            get: { host.session.kind },
            set: { host.setKind($0) }
        )
    }
}

private struct InspectorOutlineSection: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionHeader(title: "Outline")
            if host.outlineItems.isEmpty {
                Text("No outline")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(host.outlineItems.enumerated()), id: \.offset) { _, item in
                    Button {
                        host.jumpToOutlineItem(item)
                    } label: {
                        Text(item.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat(max(item.level - 1, 0)) * 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct InspectorWarningsSection: View {
    @ObservedObject var host: DocumentHost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorSectionHeader(title: "Warnings")
            if host.diagnostics.isEmpty {
                Text("No warnings")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(host.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    Button {
                        host.goToLine(diagnostic.line)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(severityLabel(diagnostic.severity))
                                .font(.caption.weight(.semibold))
                            Text(diagnostic.message)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func severityLabel(_ severity: ParseDiagnostic.Severity) -> String {
        switch severity {
        case .error: "Error"
        case .warning: "Warning"
        case .info: "Info"
        }
    }
}
