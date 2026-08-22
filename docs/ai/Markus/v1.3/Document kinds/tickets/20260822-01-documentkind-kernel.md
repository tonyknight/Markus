---
id: 20260822-01-documentkind-kernel
title: "DocumentKind kernel"
type: feature
priority: high
status: todo
created: 2026-08-22
updated: 2026-08-22
closed:
notes: "model_tier: premium"
parent:
depends_on: []
subtasks: []
---
## Description

Stop forcing every URL to Markdown. Introduce `DocumentKind`, map UTI/extension → kind, carry kind on the session, register Wave A types in Info.plist. `MarkusDocumentController.typeForContents` / Open / importer must not hard-code `net.daringfireball.markdown` for every file. Untitled with no URL remains Markdown.

## Acceptance criteria

- [ ] Opening `.json` / `.html` / `.svg` / `.toml` / `.md` selects the matching kind (R1, R11).
- [ ] Markdown still opens as markdown (R4).
- [ ] Info.plist advertises Wave A types; same `NSDocumentClass` (R11).
- [ ] macOS Debug build succeeds; iOS/iPad builds succeed (shared types) (R12, N3).

## Context

Requirements: R1, R11, R12. `MarkdownDocument.swift` `MarkusDocumentController`. `Info.plist` `CFBundleDocumentTypes`. File importer in `ContentView`. Architecture A: one document class, kind is a field.

Do **not** build JSON folds, WebView, or kind-pin UI (tickets 03–05). A stub kind is enough if Open sets it.

NO TDD. Verify by build.

## Subtasks

- [ ] `DocumentKind` enum (markdown, json, html, svg, toml + Wave B cases as enum cases even if unused).
- [ ] Map extension/UTI → kind; default markdown.
- [ ] Session/document carries kind.
- [ ] Stop `typeForContents` forcing Markdown.
- [ ] Info.plist Wave A document types.
- [ ] Widen file importer allowed types.

## Implementation plan

Status: draft
Current task:

## Notes

Append-only running log. Each entry dated.
