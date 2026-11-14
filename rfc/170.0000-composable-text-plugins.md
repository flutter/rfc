---
type: rfc
rfc: '170.0000'
title: Composable Text Plugins in Flutter
description: Introduces TextPluginScope, TextPlugin, and TextDelegate for composable cross-cutting text inspection and decoration across RenderParagraph and RenderEditable, as the first of three stages.
status: draft
created: 2026-10-14T00:00:00Z
updated: 2026-11-11T00:00:00Z
tags:
  - 170-text-editing-and-selection
  - 120-rendering
  - 130-widgets
  - 160-semantics-and-accessibility
authors:
  - https://github.com/hannah-hyj
---

# RFC 170.0000: Composable Text Plugins in Flutter

## Overview

This RFC proposes a composable text plugin system in `package:flutter/rendering.dart` and `package:flutter/widgets.dart` centered on `TextPluginScope`, `TextPlugin`, and `TextDelegate`.

By attaching plugins through an `InheritedWidget` (`TextPluginScope`) directly to `RenderParagraph` and `RenderEditable`, applications and third-party packages can inspect rendered text, paint background and foreground decorations, scroll character ranges into view, and request offscreen sliver rendering (`OffscreenContentRenderingStrategy`) across standard `Text`, `RichText`, and `EditableText` (`TextField`) subtrees without modifying existing widget code.

Text plugins are planned in three stages. **This RFC asks to land stage 1 only.** Stages 2 and 3 are described so that reviewers can see where the design is going, and each was prototyped on top of stage 1 to check that it can be added later without changing the stage 1 public API.

| Stage | What a plugin can do | Branch | Status in this RFC |
| :--- | :--- | :--- | :--- |
| 1. Painter only (MVP) | Paint behind or in front of text with a `CustomPainter`. No pointer events, no semantics | [`text-plugin-mvp`](https://github.com/hannah-hyj/flutter/tree/text-plugin-mvp) | **The proposal** ([Sections 3 to 7](#3-stage-1-architecture-and-component-design)) |
| 2. Annotations | Gestures, hover, semantics and focus for a text range, through `TextAnnotation` | [`text-plugin-annotations`](https://github.com/hannah-hyj/flutter/tree/text-plugin-annotations) | Future stage, shown to work by experiment ([Section 8](#8-stage-2-annotations)) |
| 3. Widgets | Build real widgets behind, in front of, or floating over text | [`text-plugin-with-widget`](https://github.com/hannah-hyj/flutter/tree/text-plugin-with-widget) | Future stage, shown to work by experiment ([Section 9](#9-stage-3-widgets)) |

Find-in-page (`Ctrl+F`) is the urgent use case, and it only needs stage 1. Stages 2 and 3 must not block it.

Moving text selection into a plugin was also tried. It is not one of the three stages and not part of this proposal. [Section 5.2](#52-should-selection-highlighting-be-a-textplugin) reports what was learned.

## Table of contents

- [Overview](#overview)
- [1. Problem statement and motivation](#1-problem-statement-and-motivation)
  - [1.1 Why custom `Text` subclasses fail](#11-why-custom-text-subclasses-fail)
  - [1.2 Historical context, prior art, and acknowledgments](#12-historical-context-prior-art-and-acknowledgments)
  - [1.3 A note on the name](#13-a-note-on-the-name)
- [2. Design goals and package boundaries](#2-design-goals-and-package-boundaries)
  - [2.1 Goals and non-goals](#21-goals-and-non-goals)
  - [2.2 Built-in framework plugins versus community packages](#22-built-in-framework-plugins-versus-community-packages)
  - [2.3 The three stages](#23-the-three-stages)
- [3. Stage 1: architecture and component design](#3-stage-1-architecture-and-component-design)
  - [3.1 Layering and file organization](#31-layering-and-file-organization)
  - [3.2 `TextPlugin` lifecycle contract](#32-textplugin-lifecycle-contract)
  - [3.3 `TextDelegate` proxy for text render objects](#33-textdelegate-proxy-for-text-render-objects)
  - [3.4 `TextPluginScope` and hierarchical merging](#34-textpluginscope-and-hierarchical-merging)
  - [3.5 `RenderParagraph` and `RenderEditable` painting and Z-order pipeline](#35-renderparagraph-and-rendereditable-painting-and-z-order-pipeline)
  - [3.6 First-party `SearchInPagePlugin` implementation](#36-first-party-searchinpageplugin-implementation)
  - [3.7 Who owns a plugin](#37-who-owns-a-plugin)
  - [3.8 Performance](#38-performance)
    - [3.8.1 First measurements](#381-first-measurements)
  - [3.9 What stage 1 cannot do](#39-what-stage-1-cannot-do)
- [4. Community package use cases](#4-community-package-use-cases)
  - [4.1 Use cases implemented in the demo app](#41-use-cases-implemented-in-the-demo-app)
  - [4.2 Additional community package ideas](#42-additional-community-package-ideas)
- [5. Feature deep dives](#5-feature-deep-dives)
  - [5.1 Scrolling, document ordering, and offscreen content rendering](#51-scrolling-document-ordering-and-offscreen-content-rendering)
  - [5.2 Should selection highlighting be a `TextPlugin`?](#52-should-selection-highlighting-be-a-textplugin)
- [6. Future directions and forward compatibility](#6-future-directions-and-forward-compatibility)
  - [6.1 Custom `TextPainter` render objects and non-text widgets with searchable labels](#61-custom-textpainter-render-objects-and-non-text-widgets-with-searchable-labels)
  - [6.2 Native text fields and platform views](#62-native-text-fields-and-platform-views)
- [7. Corner cases and architectural analysis](#7-corner-cases-and-architectural-analysis)
  - [7.1 `ChangeNotifier` and `setState` re-entrancy during build, layout, and dispose](#71-changenotifier-and-setstate-re-entrancy-during-build-layout-and-dispose)
  - [7.2 Why `didAddText`, `didUpdateText`, and `didLayoutText` are flushed post-layout](#72-why-didaddtext-didupdatetext-and-didlayouttext-are-flushed-post-layout)
  - [7.3 Embedded `WidgetSpan`s and UTF-16 offset alignment](#73-embedded-widgetspans-and-utf-16-offset-alignment)
  - [7.4 Text truncation and overflow clipping](#74-text-truncation-and-overflow-clipping)
  - [7.5 Multi-line wrapping, bidirectional text, and surrogate pairs](#75-multi-line-wrapping-bidirectional-text-and-surrogate-pairs)
  - [7.6 Plugin list reconciliation and stateful delegate preservation](#76-plugin-list-reconciliation-and-stateful-delegate-preservation)
  - [7.7 Deduplicating plugins by `Type` and instance across nested scopes](#77-deduplicating-plugins-by-type-and-instance-across-nested-scopes)
  - [7.8 Pointer events: none in stage 1](#78-pointer-events-none-in-stage-1)
  - [7.9 `SelectionArea` and `SelectableRegion` coexistence](#79-selectionarea-and-selectableregion-coexistence)
  - [7.10 Unintended capture of UI chrome and `TextPluginScope.none`](#710-unintended-capture-of-ui-chrome-and-textpluginscopenone)
  - [7.11 Lazy slivers and offscreen viewport recycling](#711-lazy-slivers-and-offscreen-viewport-recycling)
  - [7.12 Canvas state corruption in plugin painters](#712-canvas-state-corruption-in-plugin-painters)
  - [7.13 Obscured text fields are never given to a plugin](#713-obscured-text-fields-are-never-given-to-a-plugin)
  - [7.14 Text that is mounted but not visible](#714-text-that-is-mounted-but-not-visible)
  - [7.15 A match inside a scrolled text field](#715-a-match-inside-a-scrolled-text-field)
  - [7.16 What a plugin may do in a lifecycle callback](#716-what-a-plugin-may-do-in-a-lifecycle-callback)
- [8. Stage 2: annotations](#8-stage-2-annotations)
  - [8.1 What it adds](#81-what-it-adds)
  - [8.2 How it answers the review comments on pointer events](#82-how-it-answers-the-review-comments-on-pointer-events)
  - [8.3 Why it does not change the stage 1 API](#83-why-it-does-not-change-the-stage-1-api)
  - [8.4 Use cases that move here](#84-use-cases-that-move-here)
  - [8.5 What is still open](#85-what-is-still-open)
- [9. Stage 3: widgets](#9-stage-3-widgets)
  - [9.1 What it adds](#91-what-it-adds)
  - [9.2 Why it does not change the stage 1 API](#92-why-it-does-not-change-the-stage-1-api)
  - [9.3 What the experiment showed](#93-what-the-experiment-showed)
  - [9.4 Known defects and open problems](#94-known-defects-and-open-problems)
- [10. The same feature, written three ways](#10-the-same-feature-written-three-ways)
- [11. Open questions](#11-open-questions)
- [Appendix A: What was verified](#appendix-a-what-was-verified)

---

## 1. Problem statement and motivation

Flutter applications often need cross-cutting text features that inspect, decorate, or attach interactions to text across a page or widget subtree.

1. Find-in-page search locates all matches across separate [Text](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/text.dart) and [RichText](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/basic.dart) widgets. It also paints active and passive highlights and scrolls the active match into view.

2. Entity and pattern decoration highlights stock tickers (`GOOG`, `AAPL`), hashtags, mentions, or citations without mutating the source string. Callers do not need to pre-tokenize `TextSpan` trees.

3. Automatic linkification detects URLs (`https://...`, `www....`) in plain `Text` widgets, paints link underlines, and handles tap gestures.

4. Live content and SEO extraction indexes visible text across a subtree to generate Schema.org JSON-LD metadata, reading-time analytics, or crawler snapshots.

Items 1, 2 and 4 only need to read text and paint over it, so stage 1 covers them. Item 3 needs a tap, and a link also has to be a link for a screen reader, so it is a stage 2 use case ([Section 8](#8-stage-2-annotations)).

### 1.1 Why custom `Text` subclasses fail

Historically, package authors solved these problems by creating custom replacement widgets such as `LinkifyText`, `SearchableText`, and `ParsedText`. That approach fails in production apps for three reasons.

First, custom widgets do not compose. A developer cannot combine `LinkifyText` from one package with `StockTickerText` from another package on the same paragraph.

Second, replacing widgets requires invasive refactoring. Developers must replace every `Text` widget in the app, including those inside third-party packages or Material and Cupertino components (`ListTile`, `Card`, `DataTable`).

Third, individual text widgets lack document-level coordination unless paired with custom ancestor state management.

Cross-cutting text features therefore belong in an ambient, composable plugin pipeline attached via `InheritedWidget` (`TextPluginScope`). [RenderParagraph](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/paragraph.dart) and [RenderEditable](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/editable.dart) execute this pipeline directly, leaving standard `Text`, `RichText`, and `EditableText` widgets unchanged.

### 1.2 Historical context, prior art, and acknowledgments

This design builds on years of prototyping and architectural discussions across the Flutter team. We want to thank **Michael Goderbauer (`@goderbauer`)**, **Renzo Olivares (`@Renzo-Olivares`)**, and **Kevin Moore (`@kevmoo`)** for their work in this area.

#### 1. Michael Goderbauer's original Text Plugins proposal (November 2023)

In late 2023, **Michael Goderbauer** authored the original [Text Plugins One-Pager](https://docs.google.com/document/d/1doToFSPGJO29_FJ-VE7mD6XiNgF-s2xVaIi-UC495m8/edit?tab=t.0) after building an early [Find-in-Page web demo](https://goderbauer.github.io/demos/find-in-page/) with a custom `SearchableText` widget.

Goderbauer recognized that `SearchableText` could not compose with SEO text extraction, auto-linkification, or stock ticker highlighting. It also could not reach `Text` widgets inside third-party packages. He proposed the three core abstractions used in this design: `TextPluginScope`, `TextPlugin` (`didAddText`, `didUpdateText`, `didRemoveText`), and `TextDelegate` (`text`, `foregroundPainter`, `backgroundPainter`, `getBoxesForSelection`, `handleEvent`).

#### 2. Renzo Olivares's `Ctrl+F` and `TextPluginScope` prototype

**Renzo Olivares** turned the one-pager into a working framework prototype on his [text-plugins-alt](https://github.com/Renzo-Olivares/flutter/tree/text-plugins-alt) branch. His branch demonstrated end-to-end `Ctrl+F` (`SearchInPagePlugin`) alongside selection highlighting (`_SelectionHighlightTextPlugin`).

Renzo's prototype solved several rendering-layer problems that we carry forward here. He made `TextDelegate` implement `Listenable` (notifying plugins after `RenderParagraph.performLayout`) and `Comparable<TextDelegate>` (sorting delegates in visual document order via a Lowest Common Ancestor walk of the `RenderObject` tree).

He also exposed `placeholderRanges` (`includePlaceholders: false`) so regex and substring queries do not match across `WidgetSpan` `0xFFFC` boundaries, and added `ensureVisible()` to scroll active matches into view. Finally, he prototyped `_SelectionHighlightTextPlugin` inside `SelectableRegion` to test whether selection highlighting could use the `TextPlugin` paint pipeline.

#### 3. Kevin Moore's Find-in-Page experiment

**Kevin Moore** built an end-to-end `Ctrl+F` and `Cmd+F` prototype ([PR #193186](https://github.com/flutter/flutter/pull/193186), [RFC #25](https://github.com/flutter/rfc/pull/25)) that implemented Find-in-Page on top of `SelectableRegion`, `SelectionRegistrar`, and `RenderParagraph`'s internal `_SelectableFragment`.

This experiment validated developer demand and surfaced key edge cases, including offscreen lazy sliver discovery and `Semantics` label search. It also showed why `SelectableRegion` could not be the underlying foundation.

Adding search-specific properties (`searchHighlightColor`, `setSearchHighlights`) directly onto `Text`, `RenderParagraph`, and `Selectable` solved `Ctrl+F` in isolation. However, it could not generalize to linkification, spellcheck, or custom highlights, and could not support `EditableText` (`TextField`), which does not register with an ancestor `SelectableRegion`.

In addition, `_SelectableFragment` requires a `SelectionRegistrar`. Searching non-selectable pages required wrapping the subtree in a hidden "find-only" `SelectableRegion` (`_enableSelection: false`). That wrapper still added extra `SelectionContainer` elements per `Text` widget and required special logic to suppress selection cursors, focus changes, and gesture recognizers. These findings motivated unifying our work around `TextPluginScope`.

### 1.3 A note on the name

A **text plugin** in this document is a Dart object that observes and decorates text inside a Flutter app. It has no native code and it is not a package.

It is unrelated to a **Flutter plugin**, which is a package that contains platform-specific code. The name is kept because it follows the earlier text plugin proposals listed above. Where the two could be confused, this document always says "text plugin".

---

## 2. Design goals and package boundaries

### 2.1 Goals and non-goals

#### Goals

- Existing `Text('...')`, `Text.rich(...)`, and `EditableText` (`TextField`) widgets automatically participate when placed inside a `TextPluginScope`.

- Static text (`RenderParagraph`) and editable text (`RenderEditable`) both support plugins and update decorations live during text editing.

- Multiple plugins can inspect and paint behind or in front of the same `RenderParagraph` or `RenderEditable`, ordered by `TextPlugin.paintOrder` (with root-to-leaf scope installation order as a stable tie-breaker).

- Plugins interact with a capability-scoped `TextDelegate` wrapping `RenderParagraph` or `RenderEditable`, rather than mutating RenderObject internals directly.

- Subtrees such as toolbars, search inputs, or decorative chrome can opt out of ancestor plugins via `TextPluginScope.none` or filter specific plugin types via `TextPluginScope.exclude`.

- Rendering primitives live in `package:flutter/rendering.dart` (`packages/flutter/lib/src/rendering/text_plugin.dart`), and widget scoping lives in `package:flutter/widgets.dart` (`packages/flutter/lib/src/widgets/text_plugin.dart`). Neither layer depends on Material or Cupertino.

- While the initial implementation targets `RenderParagraph` and `RenderEditable`, `TextDelegate` and `TextPluginScope` are shaped so custom `TextPainter` render objects, non-text widgets, and native platform-view text fields can be integrated without breaking existing plugins (see [Section 6](#6-future-directions-and-forward-compatibility)).

#### Non-goals (current scope)

- We do not aim to build every plugin in the framework. We define the extensible architecture and provide core plugins (`SearchInPagePlugin` and `_SelectionHighlightTextPlugin`), while community packages provide domain-specific plugins.

- Non-text widgets (`Image`, `Icon`, custom `RenderBox` subclasses) are not the focus of the initial scope. Section [6.1](#61-custom-textpainter-render-objects-and-non-text-widgets-with-searchable-labels) shows with concrete code how custom `TextPainter` render objects and non-text widgets can participate via `TextDelegateHostMixin`, which the prototype already includes.

- Text rendered by native OS or browser DOM views inside a Platform View (`HtmlElementView`, `UITextView`, `EditText`) is out of the initial scope. Section [6.2](#62-native-text-fields-and-platform-views) shows how `TextDelegate` can connect to the W3C `Range` and CSS Custom Highlight APIs (`CSS.highlights`) in a future phase.

- `TextPlugin` is not a security or PII redaction mechanism. Drawing an opaque bar in `foregroundPainter` only hides glyphs on screen, while the plain text remains accessible to `Ctrl+F`, `SelectionArea` copy-paste, the `Semantics` tree, and DevTools. Apps must scrub sensitive strings at the data layer before passing them to `Text` widgets. The one protection the framework does give is for password fields: an `EditableText` with `obscureText` set is never given to a plugin (see [Section 7.13](#713-obscured-text-fields-are-never-given-to-a-plugin)).

- Plugins do not mutate the input `InlineSpan` tree or alter text layout metrics. They decorate and observe laid-out text via [CustomPainter](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/custom_paint.dart) hooks (`backgroundPainter` and `foregroundPainter`).

- Stage 1 plugins do not receive pointer events, do not change semantics or focus, and do not build widgets. Those belong to stages 2 and 3 (see [Section 2.3](#23-the-three-stages) and [Section 3.9](#39-what-stage-1-cannot-do)).

---

### 2.2 Built-in framework plugins versus community packages

We separate what belongs in the core Flutter framework (`package:flutter`) from what belongs in community packages on `pub.dev`.

#### 2.2.1 Framework-builtin plugins (`package:flutter`)

Only plugins that implement platform-standard features with zero external dependencies belong inside `package:flutter`:

1. `SearchInPagePlugin` provides desktop and web `Ctrl+F` search highlighting, sequential match navigation, and viewport offscreen rendering management.

2. `_SelectionHighlightTextPlugin` is a candidate internal plugin for migrating `SelectionArea` and `SelectableRegion` selection highlighting onto the `TextPlugin` pipeline (evaluated in [Section 5.2](#52-should-selection-highlighting-be-a-textplugin)).

3. Spell check is assumed to become a first-party text plugin later, because it is a default feature of the framework today. This proposal does not move it: spell check keeps decorating the `InlineSpan` until the plugin framework has landed. Whether it would live in `flutter/flutter` or `flutter/packages` is open ([Section 11](#11-open-questions)).

`SearchInPagePlugin` is first-party because find-in-page is expected on web and desktop and is the reason for this work. To keep the maintenance cost small, the first-party part is a controller without UI (see [Section 3.6](#36-first-party-searchinpageplugin-implementation)).

A rule of thumb for "plugin or `InlineSpan`": a feature that changes how text is laid out has to stay in the span. A feature that only paints over text that is already laid out can be a text plugin.

#### 2.2.2 Community package plugins (`pub.dev`)

Domain-specific or third-party-dependent features belong in standalone community packages:

1. `LinkifyPlugin` (`package:flutter_linkify_plugin`) parses URLs with regular expressions, applies custom link styles, shows hover preview popups, and launches URLs via `url_launcher`. This needs stage 2.

2. `StockTickerPlugin` decorates financial symbols (`GOOG`, `AAPL`), detects crypto addresses, and formats currency conversions.

3. `SpoilerMaskPlugin` (`package:flutter_spoiler_mask`) renders interactive tap-to-reveal spoiler bars (`||...||`) and flashcard cloze-deletion study masks (`{{...}}`). Tap-to-reveal needs stage 2 or 3.

4. `ReadAloudPlugin` (`package:flutter_read_aloud`) synchronizes word-by-word TTS karaoke highlights with `flutter_tts` or cloud speech APIs.

5. `SeoExtractorPlugin` (`package:flutter_seo_text`) extracts plain text for Schema.org JSON-LD web crawlers.

6. `AiGroundingPlugin` renders LLM citation grounding popups and interactive source attribution spans. The popups need stage 3.

#### 2.2.3 Principles for a general-purpose API

The `TextPlugin` API follows four design rules so it can support both core selection and community packages:

1. `TextDelegate` exposes an opinionated plain-text getter (`text`) and low-level geometry and painting primitives (`getBoxesForSelection`, `getPositionForOffset`, `getWordBoundary`, `getOffsetForCaret`, `backgroundPainter`, and `foregroundPainter`) rather than feature-specific methods.

2. `TextPluginScope` stacks plugins across the widget tree, deduplicating by plugin `Type` (so inner scopes can override outer scopes of the same `Type`, matching `Actions` and `Shortcuts`) and sorting by `TextPlugin.paintOrder`. `TextPluginScope.exclude(types: {...})` lets app developers filter out specific plugin types on UI chrome without disabling core plugins like `_SelectionHighlightTextPlugin`.

3. `bool get needsOffscreenContent` on `TextPlugin` and the standalone `OffscreenContentRenderingStrategy` widget (`OffscreenRenderingPolicy.lazy()` versus `OffscreenRenderingPolicy.eager({ScrollCacheExtent cacheExtent})`) let document-wide plugins request eager offscreen sliver rendering in `ListView.builder` viewports while allowing subtrees to customize or bound the offscreen `ScrollCacheExtent`. This keeps `Viewport` decoupled from `TextPluginScope`.

4. Stage 1 does not change semantics. Mapping decorated ranges (links, tickers, spoiler masks) to focusable `SemanticsNode`s for screen readers is the job of `TextAnnotation` in stage 2 (see [Section 8](#8-stage-2-annotations)).

### 2.3 The three stages

| | Stage 1: painter only | Stage 2: annotations | Stage 3: widgets |
| :--- | :--- | :--- | :--- |
| A plugin gives the text | A `CustomPainter` behind and one in front | Data about a range: tap, long-press, cursor, hover, label, link | Widgets positioned on a range |
| Pointer events | None | Through the gesture arena | Whatever the widgets do |
| Semantics and focus | Unchanged | A range can be a link or a button, and can take focus | Whatever the widgets do |
| Changes text layout | No | No | No |
| Enough for | Find-in-page, highlights, underlines, read-aloud, text extraction | Links, tap-to-reveal, hover cards anchored by the app | Menus, chips, blur, animation with widget state |
| In this RFC | The proposal | Future, prototyped | Future, prototyped |

The rules for staging are:

1. Stage 1 is useful alone. Find-in-page needs nothing from stages 2 and 3.
2. A later stage adds API. It does not change the stage 1 public API. A plugin written for stage 1 keeps working.
3. A plugin uses the smallest stage that fits. A highlight stays a painter even when widgets are available, because a painter costs the least.

Both experiments are built directly on top of the stage 1 branch. Sections [8](#8-stage-2-annotations) and [9](#9-stage-3-widgets) list exactly what each one touches in the stage 1 code, since "no change to the public API" is not the same as "no change to the files".

[Section 10](#10-the-same-feature-written-three-ways) shows one feature written in each stage.

---

## 3. Stage 1: architecture and component design

Sections 3 to 7 describe stage 1, which is what this RFC proposes. Everything in them matches the prototype on the [`text-plugin-mvp`](https://github.com/hannah-hyj/flutter/tree/text-plugin-mvp) branch unless a sentence says otherwise. A live demo of the stage 1 example app, with its five paint-only plugins, is at [text-plugin-mvp-demo.web.app](https://text-plugin-mvp-demo.web.app/). [Appendix A](#appendix-a-what-was-verified) lists what was verified by running and what was only read.

At the widget level, developers wrap any subtree in `TextPluginScope`:

```dart
class _ArticlePageState extends State<ArticlePage> {
  // A plugin with state is created once and disposed by its creator (Section 3.7).
  final SearchInPagePlugin _search = SearchInPagePlugin()..query = 'Flutter';
  final StockTickerPlugin _tickers = StockTickerPlugin(); // e.g., paints pills behind GOOG, AAPL

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextPluginScope.multiple(
      plugins: [_search, _tickers],
      child: Column(
        children: [
          // Standard widgets automatically participate in the plugin pipeline!
          Text('Welcome to Flutter! Buy GOOG today'), // Automatically highlighted & decorated
          TextField(),                                // Text input also automatically inspected

          // Developers can easily firewall UI chrome from being affected:
          TextPluginScope.none(
            child: Text('Search query: Flutter'), // Safely isolated from plugins
          ),
        ],
      ),
    );
  }
}
```

### 3.1 Layering and file organization

| Layer | File | Public Symbols | Responsibility |
| :--- | :--- | :--- | :--- |
| **Rendering** | `packages/flutter/lib/src/rendering/text_plugin.dart` | `TextPlugin`, `TextDelegate` | Defines the plugin lifecycle interface (`needsOffscreenContent`, `paintOrder`, post-layout callbacks) and the per-plugin `TextDelegate` proxy wrapping `RenderParagraph` or `RenderEditable`. |
| **Rendering** | [packages/flutter/lib/src/rendering/object.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/object.dart) | `PipelineOwner.schedulePostLayoutCallback` (new, `@internal`) | Flushes post-layout callbacks at the end of `PipelineOwner.flushLayout()` after all dirty `RenderObject`s have completed layout and before `flushPaint()`. |
| **Rendering** | [packages/flutter/lib/src/rendering/paragraph.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/paragraph.dart) | `RenderParagraph.textPlugins` | Reconciles delegates, schedules post-layout lifecycle callbacks, and executes painters for static text. |
| **Rendering** | [packages/flutter/lib/src/rendering/editable.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/editable.dart) | `RenderEditable.textPlugins` | Reconciles delegates, schedules post-layout lifecycle callbacks during typing and layout, and executes painters for editable text fields. |
| **Widgets** | `packages/flutter/lib/src/widgets/text_plugin.dart` | `TextPluginScope`, `TextPluginSuspension` (new, `@internal`) | Scopes, deduplicates by `Type`, and sorts `TextPlugin`s by `paintOrder` down the widget tree, and configures `OffscreenContentRenderingStrategy` when any active plugin has `needsOffscreenContent == true`. `TextPluginSuspension` withholds plugins from text that is mounted but covered ([Section 7.14](#714-text-that-is-mounted-but-not-visible)). |
| **Widgets** | [packages/flutter/lib/src/widgets/overlay.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/overlay.dart) | None | Suspends plugins for an `OverlayEntry` that is below an opaque entry, so that text in a covered route is not given to plugins. |
| **Widgets** | [packages/flutter/lib/src/widgets/viewport.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/viewport.dart) | `OffscreenRenderingPolicy`, `OffscreenContentRenderingStrategy` | Inherited strategy controlling whether descendant `Viewport` and `ShrinkWrappingViewport` widgets render offscreen sliver content lazily or eagerly with a configurable `ScrollCacheExtent`. |
| **Widgets** | [packages/flutter/lib/src/widgets/basic.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/basic.dart) | `RichText.textPlugins` | Resolves `textPlugins ?? TextPluginScope.maybeOf(context)` and forwards to `RenderParagraph`. |
| **Widgets** | [packages/flutter/lib/src/widgets/editable_text.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/editable_text.dart) | `EditableText.textPlugins` | Resolves `textPlugins ?? TextPluginScope.maybeOf(context)` and forwards to `_Editable` and `RenderEditable`. Passes no plugins when `obscureText` is set. |

**Why the render objects know about plugins.** It would be cleaner if text rendering and plugin painting were separate. In stage 1 they are not, because a plugin painter has to run between the paragraph's own paint steps, after its background and before its glyphs, with the same offset and the same clip. Only the render object can do that today. Stage 3 goes the other way: its widgets live in a host that wraps the text from outside, and the render object only hands out the delegate ([Section 9](#9-stage-3-widgets)).

### 3.2 `TextPlugin` lifecycle contract

Defined in `packages/flutter/lib/src/rendering/text_plugin.dart`, `TextPlugin` exposes declarative `needsOffscreenContent` and `paintOrder` getters and four lifecycle hooks:

```dart
abstract class TextPlugin {
  const TextPlugin();

  bool get needsOffscreenContent => false; // Eagerly build offscreen slivers when true
  int get paintOrder => 0;                 // Smaller values paint further behind

  void didAddText(TextDelegate delegate) {}
  void didUpdateText(TextDelegate delegate) {}
  void didLayoutText(TextDelegate delegate) {}
  void didRemoveText(TextDelegate delegate) {}
}
```

There is no pointer hook. An earlier version of this proposal had `TextPlugin.handlePointerEvent`, which delivered raw pointer events outside the gesture arena. It is removed. Interaction comes back in stage 2 as recognizers that take part in the arena ([Section 8](#8-stage-2-annotations)).

#### Post-layout lifecycle guarantee (`didAddText`, `didUpdateText`, `didLayoutText`)

Plugins often need to query word boxes (`getBoxesForSelection`) or screen positions (`localToGlobal`) and attach a painter as soon as text appears or changes:

- **Before or during layout is too early:** Sizes and parent offsets are not finalized yet, so geometry queries crash or return stale coordinates.
- **After the frame (`addPostFrameCallback`) is too late:** The frame has already painted, causing a 1-frame flash of unhighlighted (or unmasked) text.

To hit the exact sweet spot **after layout finishes and before paint starts**, `RenderParagraph` and `RenderEditable` schedule these callbacks at the end of `PipelineOwner.flushLayout()` via `PipelineOwner.schedulePostLayoutCallback` (see [Section 7.2](#72-why-didaddtext-didupdatetext-and-didlayouttext-are-flushed-post-layout) for pipeline details). Every glyph box and screen coordinate is ready (`delegate.hasLayout == true`), and any `backgroundPainter` or `foregroundPainter` set in the callback paints in the **same frame**:

1. **`didAddText(delegate)`**: Fires once after a new `(RenderObject, TextPlugin)` pair finishes its first layout.
2. **`didUpdateText(delegate)`**: Fires post-layout when the text or span styles changed.
3. **`didLayoutText(delegate)`**: Fires post-layout every time the text has a new layout. That includes the frames in which `didAddText` or `didUpdateText` fire: it is called right after them.
4. **`didRemoveText(delegate)`**: Fires synchronously when a plugin is removed from scope or the render object detaches. *(Skipped if layout never ran, so `didAddText` and `didRemoveText` are always paired.)*

So the three content callbacks say **what changed**, and `didLayoutText` says **the geometry is valid again**:

| What happened to the text | Callbacks, in order |
| :--- | :--- |
| It appeared | `didAddText`, then `didLayoutText` |
| Its text changed | `didUpdateText`, then `didLayoutText` |
| It was laid out again with the same text (for example, the window was resized) | `didLayoutText` |
| It was removed, or the plugin left the scope | `didRemoveText` |

The callbacks are kept apart on purpose. A plugin that scans text does it in `didAddText` and `didUpdateText`. A plugin that only depends on geometry does its work in `didLayoutText`. `SearchInPagePlugin` rescans a text when its content changes, and only repaints it when it is laid out again. With one merged callback, every plugin would rescan on every resize.

### 3.3 `TextDelegate` proxy for text render objects

Passing `RenderParagraph` directly to plugins would allow plugins to corrupt layout state, mutate constraints, or overwrite each other's painters. Instead, **each `(RenderObject, TextPlugin)` pair gets its own dedicated `TextDelegate` instance** (a strict 1-to-1 cardinality per `(RenderObject, TextPlugin)` pair):

- If a `RenderParagraph` is inside a scope with 3 active `TextPlugin`s (`SearchInPagePlugin`, `StockTickerPlugin`, and `ReadAloudPlugin`), `RenderParagraph` creates 3 distinct `TextDelegate` instances.
- Each `TextDelegate` owns isolated `backgroundPainter` and `foregroundPainter` slots for its specific `TextPlugin`. When `SearchInPagePlugin` sets `delegate.backgroundPainter = null`, it only clears its own delegate's painter slot and never affects `StockTickerPlugin` or `ReadAloudPlugin`. Setting or replacing a painter checks `shouldRepaint`, attaches or detaches the painter's `Listenable` (`addListener(_paragraph.markNeedsPaint)`), and calls `markNeedsPaint()` only when needed.

```dart
class TextDelegate extends ChangeNotifier implements Comparable<TextDelegate> {
  final RenderBox renderObject;
  final TextPlugin plugin;

  // Text & layout state
  String get text;
  InlineSpan get textSpan;
  bool get hasLayout;
  Size get size;

  // Isolated per-plugin painter slots
  CustomPainter? backgroundPainter;
  CustomPainter? foregroundPainter;

  // Geometry & scrolling
  List<ui.TextBox> getBoxesForSelection(TextSelection selection, { ... });
  ui.TextPosition getPositionForOffset(Offset offset);
  void ensureVisible(ui.TextRange range, { ... });
}
```

#### Opinionated plain-text and geometry contract

To prevent subtle offset alignment bugs across plugins, `TextDelegate` is deliberately opinionated about how text and glyph boxes are exposed:

1. **`delegate.text`**: Always returns `_paragraph.text.toPlainText(includeSemanticsLabels: false)` (keeping `includePlaceholders: true`, so each inline `WidgetSpan` is represented by a single `\uFFFC` character matching `ui.Paragraph`'s internal UTF-16 buffer). Plugin authors never call `InlineSpan.toPlainText` themselves and never have to worry about `TextSpan.semanticsLabel` shifting character offsets or plugins accidentally matching accessibility label overrides. `delegate.textSpan` remains available as a read-only inspection getter for plugins that explicitly inspect font styles.
2. **`delegate.getBoxesForSelection`**: Defaults to `bool includePlaceholders = false` (`List<ui.TextBox> getBoxesForSelection(TextSelection selection, {ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight, ui.BoxWidthStyle boxWidthStyle = ui.BoxWidthStyle.tight, bool includePlaceholders = false})`), automatically splitting selection ranges around `delegate.placeholderRanges` so text highlights and underlines do not paint across inline `WidgetSpan` children unless explicitly requested.
3. **`delegate.hasLayout`**: Tracks `renderObject.hasSize && _hasValidLayout` (where `_hasValidLayout` is set to `false` in `markNeedsLayout()` and `true` at the end of `performLayout()`). Unlike `RenderObject.debugNeedsLayout` (which always returns `false` in release builds), `delegate.hasLayout` is accurate in both debug and release modes, and is guaranteed to be `true` inside `didAddText`, `didUpdateText`, `didLayoutText`, and `CustomPainter.paint`.

Finally, `TextDelegate` provides coordinate conversion and scrolling helpers: `localToGlobal`, `globalToLocal`, `getTransformTo`, `showOnScreen`, and `ensureVisible`. These helpers allow find-in-page plugins to scroll the active match into the viewport.

#### What a plugin can read and what it can write

`TextDelegate` is read-only except for four things, all of which only affect painting or scrolling:

| A plugin can | Through |
| :--- | :--- |
| Set its own painter behind the text | `backgroundPainter` |
| Set its own painter in front of the text | `foregroundPainter` |
| Ask for a repaint | `markNeedsPaint()` |
| Ask to scroll a rectangle or a range into view | `showOnScreen()`, `ensureVisible()` |

Everything else is a getter or a geometry query. Because each plugin has its own delegate for a text, a plugin cannot reach the painters of another plugin.

Two limits of the prototype, both listed in [Section 11](#11-open-questions):

- `TextDelegate.renderObject` is public. A plugin could cast it and change the text through it, which defeats the read-only intent.
- `TextDelegate.text` leaves `TextSpan.semanticsLabel` out so that offsets match what is painted. A plugin that wants the labels reads `delegate.textSpan` and calls `getSemanticsInformation()`. None of the stage 1 plugins need this.

A plugin never gets a delegate for a password field ([Section 7.13](#713-obscured-text-fields-are-never-given-to-a-plugin)).

### 3.4 `TextPluginScope` and hierarchical merging

`TextPluginScope` uses an internal `InheritedWidget` (`_InheritedTextPluginScope`) that resolves, deduplicates, and orders active plugins down the widget tree during `build`:

```dart
class TextPluginScope extends StatefulWidget {
  const TextPluginScope({required TextPlugin plugin, required Widget child, Key? key});
  const TextPluginScope.multiple({required List<TextPlugin> plugins, required Widget child, Key? key});
  const TextPluginScope.exclude({required Set<Type> types, required Widget child, Key? key});
  const TextPluginScope.none({required Widget child, Key? key});

  static List<TextPlugin>? maybeOf(BuildContext context);
  static List<TextPlugin> of(BuildContext context);
}
```

1. **`Type`-based deduplication and inner-scope override**: Like Flutter's `Actions` and `Shortcuts` widgets, `TextPluginScope` deduplicates plugins by their concrete `runtimeType` (`Map<Type, TextPlugin>`). When an inner `TextPluginScope` provides a plugin of type `T`, it overrides any ancestor plugin of the same type `T` for its descendant subtree. This matches `TextPluginScope.exclude(types: {T})` and guarantees that at most one instance of any given `TextPlugin` subclass is active on a `RenderParagraph` or `RenderEditable`.

2. **Ordering via `TextPlugin.paintOrder`**: After merging ancestor and local plugins into the `Map<Type, TextPlugin>`, `TextPluginScope` stably sorts the active plugins in ascending order of `plugin.paintOrder` (default `0`), using root-to-leaf scope installation order as a tie-breaker when two plugins have the same `paintOrder`. This decouples visual Z-order from widget-tree nesting depth when needed (for example, allowing a plugin from an outer scope with `paintOrder: 100` to paint above a background badge plugin from an inner scope with `paintOrder: 0`).

3. **Filtering and opt-out (`exclude` and `none`)**: `TextPluginScope.exclude(types: {...})` filters out ancestor plugins whose `runtimeType` is in `types`, while `TextPluginScope.none` installs an empty scope (`plugins: const <TextPlugin>[]`), disabling all ancestor plugins for its `child` subtree.

**Choosing a `paintOrder`.** It is an `int` and defaults to `0`. Most plugins should leave it at `0` and let the order of the scopes decide. A plugin sets it only when it has to sit above or below other plugins wherever it is installed. Two packages can still choose values that clash, and an app resolves that with scope order. Whether the framework should publish a few reference values is open ([Section 11](#11-open-questions)). The selection highlight does not use a number at all ([Section 3.5](#35-renderparagraph-and-rendereditable-painting-and-z-order-pipeline)).

**The list is only the input.** `TextPluginScope.multiple` takes a list, and the scope turns it into the `Map<Type, TextPlugin>` described above. Why the scope takes plugin instances and not factories is explained in [Section 3.7](#37-who-owns-a-plugin).

### 3.5 `RenderParagraph` and `RenderEditable` painting and Z-order pipeline

`RichText` and `EditableText` forward `textPlugins ?? TextPluginScope.maybeOf(context)` to `RenderParagraph` and `RenderEditable`, which reconcile `TextDelegate`s, schedule post-layout callbacks, and paint in three steps from back to front:

```dart
class RenderParagraph extends RenderBox { // Same host contract on RenderEditable
  List<TextPlugin>? textPlugins; // Reconciles 1-to-1 TextDelegate instances

  @override
  void performLayout() {
    _layoutTextWithConstraints(constraints);
    owner?.schedulePostLayoutCallback(_flushTextPluginNotifications);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final d in _delegates) d.backgroundPainter?.paint(...); // 1. Backgrounds
    _textPainter.paint(context.canvas, offset);                  // 2. Glyphs & spans
    for (final d in _delegates) d.foregroundPainter?.paint(...); // 3. Foregrounds
  }
}
```

1. Plugin `backgroundPainter`s run in ascending `paintOrder` (with root-to-leaf `TextPluginScope` installation order breaking ties), clipped to the bounds of the text in exactly the cases in which the text itself is clipped: the text overflows its box and `overflow` is not `TextOverflow.visible`.

2. Paragraph glyphs and inline children (`_textPainter.paint` and `paintInlineChildren`) paint with any applicable overflow shader or clipping.

3. Plugin `foregroundPainter`s run in ascending `paintOrder` (with root-to-leaf `TextPluginScope` installation order breaking ties), clipped under the same rule.

In our current prototype, existing `SelectionArea` and `EditableText` selection layers remain in place around step 2 (`_SelectableFragment.paintSelection` before `_textPainter.paint` and `_SelectableFragment.paintHandles` after `foregroundPainter`s in `RenderParagraph`; `_backgroundRenderObject` and `_foregroundRenderObject` in `RenderEditable`). Inside a `SelectableRegion`, the prototype already paints the highlight of static text through `_SelectionHighlightTextPlugin` (see [Section 5.2](#52-should-selection-highlighting-be-a-textplugin)). Its `backgroundPainter` runs in step 1 after every other plugin background, directly behind the glyphs, whatever its `paintOrder`. Where that plugin is not installed, `_SelectableFragment.paintSelection` paints the highlight as before.

### 3.6 First-party `SearchInPagePlugin` implementation

`SearchInPagePlugin` is the primary first-party `TextPlugin` motivating this proposal, providing drop-in `Ctrl+F` / `Cmd+F` Find-in-Page across any subtree of `Text`, `RichText`, and `EditableText` widgets.

**What is first-party, and what is not.** The framework part is a controller: the query, the list of matches, the active match, next and previous, and the highlight painters. It builds no widgets. A search bar is ordinary widgets written by the app, or later by Material and Cupertino, that listen to the plugin. So the search UI can be replaced completely, and the plugin does not depend on a design system. The highlight colors are constructor parameters.

In the prototype the class still lives in the example app (`examples/text_plugins/lib/plugins/search_in_page_plugin.dart`). Where it lands in the framework is decided in the implementation PR.

#### 3.6.1 Public API and `ChangeNotifier` integration

`SearchInPagePlugin` extends `TextPlugin` and mixes in `ChangeNotifier` for two reasons. First, search bar UIs can wrap `ListenableBuilder(listenable: searchPlugin, ...)` to display `"${activeMatchIndex + 1} of ${matches.length}"` and enable or disable next/previous buttons. Second, `TextPluginScope` detects `plugin is Listenable` and subscribes to `needsOffscreenContent` transitions automatically when `eagerLoadOffscreenText` is toggled.

```dart
@immutable
class SearchMatch {
  const SearchMatch({required this.delegate, required this.range});
  final TextDelegate delegate;
  final TextRange range;
  List<ui.TextBox> getBoxes();
}

class SearchInPagePlugin extends TextPlugin with ChangeNotifier {
  SearchInPagePlugin({bool eagerLoadOffscreenText = false, /* highlight colors */ ...});

  String query;
  bool caseSensitive;
  bool eagerLoadOffscreenText;

  List<SearchMatch> get matches;
  int get activeMatchIndex;
  SearchMatch? get activeMatch;

  void nextMatch();
  void previousMatch();
  void scrollToActiveMatch({Duration duration, Curve curve}); // 250 ms, easeInOut by default

  @override
  bool get needsOffscreenContent => eagerLoadOffscreenText;

  @override
  void didAddText(TextDelegate delegate) { ... }

  @override
  void didUpdateText(TextDelegate delegate) { ... }

  @override
  void didLayoutText(TextDelegate delegate) { ... } // Repaints only. No rescan.

  @override
  void didRemoveText(TextDelegate delegate) { ... }
}
```

#### 3.6.2 Incremental per-delegate match indexing and active match preservation

`SearchInPagePlugin` caches matches per delegate (`Map<TextDelegate, List<SearchMatch>> _matchesByDelegate`) and keeps only the $K$ delegates that currently have matches in a document-ordered list (`List<TextDelegate> _orderedMatchingDelegates`), so a change to one text widget never costs work proportional to the $N$ mounted widgets on the page (abridged):

```dart
@override
void didUpdateText(TextDelegate delegate) {
  _updateDelegateMatches(delegate, _computeMatchesForDelegate(delegate)); // Scans only this delegate.
}

void _updateDelegateMatches(TextDelegate delegate, List<SearchMatch> newMatches) {
  final List<SearchMatch> oldMatches = _matchesByDelegate[delegate] ?? const <SearchMatch>[];
  if (listEquals(oldMatches, newMatches)) return; // Unrelated edit: zero work.

  // Splice only this delegate's slice in `_orderedMatchingDelegates` and `_matches`
  // (binary-insert if newly matching, remove if empty, or replaceRange in place).
  _spliceDelegateMatches(delegate, oldMatches, newMatches);
  _reconcileActiveMatch();             // Preserve active match by (delegate, range) value.
  _updatePainterForDelegate(delegate); // Update only affected delegate painters.
  _notifyListenersSafely();
}
```

1. **Single-delegate updates**: `didAddText`, `didUpdateText`, and `didRemoveText` scan and splice only the affected delegate. A full scan (`_rescanAllDelegates()`) runs only when `query` or `caseSensitive` changes, and even then sorts only the $K$ matching delegates.

2. **No full re-sorts**: because `_orderedMatchingDelegates` stays sorted by `TextDelegate.compareTo`, an update checks at most its two neighbors (`_isDelegateOutOfOrder`, in case keyed children were reordered) and falls back to a sort only in that rare case.

3. **Active match preservation**: `_reconcileActiveMatch` finds `previousActive` in the spliced `_matches` by `SearchMatch` value equality on `(delegate, range)`, so `activeMatchIndex` shifts with the content instead of resetting to `0` while items mount, unmount, or edit above the focused match.

#### 3.6.3 Two-layer custom painting (`backgroundPainter` and `foregroundPainter`)

Instead of looping over all mounted `_delegates` on every update or match navigation, `_updatePainterForDelegate(delegate)` updates painters only on the changed `delegate` (plus `oldActive.delegate` and `newActive.delegate` whenever `activeMatch` moves between delegates):

1. If a delegate has no matches, both `delegate.backgroundPainter` and `delegate.foregroundPainter` are set to `null`. Because each `(RenderObject, TextPlugin)` pair has its own dedicated `TextDelegate` instance (see [Section 3.3](#33-textdelegate-proxy-for-text-render-objects)), setting `delegate.backgroundPainter = null` only clears `SearchInPagePlugin`'s painter on that paragraph and never affects painters attached by other plugins in the scope.

2. Every delegate with one or more matches receives a `_SearchBackgroundPainter` on `delegate.backgroundPainter`. During step 1 of `RenderParagraph.paint` (behind the text glyphs), it queries `delegate.getBoxesForSelection(...)` and fills rounded rectangles (`Radius.circular(3.0)`) using `matchHighlightColor` for passive matches and `activeMatchBackgroundColor` for the active match.

3. Only the delegate containing `activeMatch` receives a `_SearchForegroundPainter` on `delegate.foregroundPainter`. During step 3 of `RenderParagraph.paint` (in front of the text glyphs), it strokes a `1.75px` rounded border (`activeMatchBorderColor`, inflated by `2.0px`) around the active match boxes so the focused match stands out clearly against dense text.

#### 3.6.4 Post-layout scrolling and safe notification coalescing

Because `didAddText`, `didUpdateText`, and `didLayoutText` run at the end of `PipelineOwner.flushLayout()`, `delegate.hasLayout` is already `true` whenever a delegate is added or updated:

1. Calling `scrollToActiveMatch()` from `nextMatch()` or `previousMatch()` can immediately invoke `current.delegate.ensureVisible(current.range, duration: duration, curve: curve)` because every delegate in `_matches` has already completed layout. The scroll is animated: `scrollToActiveMatch` defaults to 250 ms with `Curves.easeInOut` and passes both to `ensureVisible`. A match that is scrolled out of view inside a multi-line text field is a known gap (see [Section 7.15](#715-a-match-inside-a-scrolled-text-field)).

2. As detailed in [Section 7.1](#71-changenotifier-and-setstate-re-entrancy-during-build-layout-and-dispose), `_notifyListenersSafely()` checks `SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks`. Because `flushLayout()` runs inside `SchedulerPhase.persistentCallbacks`, `_notifyListenersSafely()` sets `_notificationScheduled = true` and coalesces all delegate mutations in that frame into a single `addPostFrameCallback` call to `notifyListeners()`.

### 3.7 Who owns a plugin

`TextPluginScope` takes plugin **instances**. It does not create them and it does not dispose them. The rule is the one Flutter already has for `ScrollController`, `TextEditingController` and `FocusNode`: whoever creates the object disposes it.

```dart
class _PageState extends State<Page> {
  final SearchInPagePlugin _search = SearchInPagePlugin();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SearchBar(onChanged: (String value) => _search.query = value), // Outside the scope.
        Expanded(child: TextPluginScope(plugin: _search, child: widget.body)),
      ],
    );
  }
}
```

Two rules follow:

1. **A plugin with state is created in a `State`, not in `build`.** Delegates are keyed by plugin instance. A new instance on every rebuild means every text in the scope is removed from the old plugin and added to the new one.
2. **A plugin without state can be `const`**, and is then safe to write inline.

#### Alternative considered: the scope takes factories

Reviewers suggested `Map<Type, TextPlugin Function()>`, so that the scope creates and disposes plugins and a developer cannot leak one.

| | Instances (proposed) | Factories |
| :--- | :--- | :--- |
| Who creates and disposes | The app | The scope |
| Driving the plugin (query, next match) | The app already holds it | Needs a lookup, which only works below the scope. A search bar usually sits beside or above the scope |
| Changing configuration | Set a property on the instance | The scope has to know when to create the plugin again, although the factory is the same object |
| Main risk | A stateful plugin created in `build` | More machinery in the scope, and `TextPlugin` needs a `dispose` |
| A plugin that an inner scope replaces | Still serves the texts outside the inner scope | Is not created for that subtree |

Instances are proposed because a stateful plugin is a controller. The app has to hold it to drive it, and then the app can also dispose it. Deduplication by `Type`, which is the useful part of the map, is already what the scope does ([Section 3.4](#34-textpluginscope-and-hierarchical-merging)).

### 3.8 Performance

Flutter is already slow with very large amounts of text, and this design must not make that worse. This section states where the cost is. The first measurements are in [Section 3.8.1](#381-first-measurements). The rest of the benchmarks at the end are owed before the implementation PR.

| Situation | Cost |
| :--- | :--- |
| A text with no plugin in scope | A null check in layout and in paint |
| A text with plugins, in a frame in which it does nothing | Nothing. No callback is scheduled |
| A text that was laid out, changed, or got a new plugin | One post-layout callback for that text, which makes one or two calls per plugin on it |
| Painting a text | One call per painter that is set, each wrapped in a save and restore |
| Building a scope | Merging the plugin map of the ancestor and sorting it. This is per scope, not per text |
| Comparing two delegates for document order | Both ancestor chains to the root, then the siblings between the two branches under the common parent. Ordering many delegates at once uses one walk of the tree instead ([Section 5.1.2](#512-document-order-sorting-textdelegate-implements-comparabletextdelegate)) |

So the cost follows the amount of text that **changed** in a frame, not the amount of text on the page. What a plugin does inside its callbacks is the plugin's own cost. `SearchInPagePlugin` keeps matches per text for that reason ([Section 3.6.2](#362-incremental-per-delegate-match-indexing-and-active-match-preservation)).

#### 3.8.1 First measurements

These numbers are from one machine: macOS desktop, profile mode, `examples/text_plugins/lib/benchmark.dart`. The benchmark was run several times while two problems were found and fixed. The tables are from the last run. A single number at the larger page size varies by a few milliseconds from run to run, so they show the shape of the cost, not exact values.

The page is a column of N paragraphs that are all mounted and laid out, each in its own repaint boundary. It is measured four ways: with no `TextPluginScope`, with a scope that installs no plugin, with a plugin that does nothing, and with `SearchInPagePlugin` and an active query that matches one paragraph in ten. A frame time is the time in `drawFrame` (build, layout, plugin callbacks, paint), averaged over 20 frames. The benchmark runs the frames itself and does not wait for vsync. Raster time is not included.

**Two problems were found and fixed.**

1. *The first search took 1.0 s on 10,000 paragraphs.* The cause was sorting the matches into document order: each comparison visited every child of the column. `TextDelegate.sortInDocumentOrder` now orders many delegates with one walk of the tree, and `compareTo` walks only the siblings between the two texts ([Section 5.1.2](#512-document-order-sorting-textdelegate-implements-comparabletextdelegate)).
2. *A frame that rebuilds every text was several milliseconds slower with a plugin installed.* When a `Text` is rebuilt, `RenderParagraph` gets its span again. With a plugin on the text, the setter built the old plain text first and only then checked whether the span had changed. On a rebuild of 10,000 unchanged texts that was 10,000 strings that were thrown away. The setter now checks first. A scope that installs no plugin never had this cost, which is how the cause was found.

In milliseconds, at 10,000 paragraphs:

| | Before | After |
| :--- | ---: | ---: |
| First search, 1,000 matches | 1,023 | 10 to 15 |
| Frame in which 100 matching paragraphs change, search plugin against a plugin that does nothing | 45.0 against 12.8 | 10.0 against 9.3 |
| Frame that rebuilds every paragraph, plugin that does nothing against no scope | 35.4 against 27.6 | 27.3 against 25.7 |
| Frame that appends one paragraph, plugin that does nothing against no scope | 45.4 against 36.7 | 34.3 against 32.6 |

Each pair is from one run. The runs before and after used different ways to drive the frames, so compare the gap inside a pair, not the numbers across the two columns.

With 10,000 paragraphs, in milliseconds:

| | No scope | Scope without plugins | Plugin that does nothing | Search plugin |
| :--- | ---: | ---: | ---: | ---: |
| Idle frame | < 0.01 | < 0.01 | < 0.01 | < 0.01 |
| Frame in which 1 paragraph changes | 2.7 | 2.8 | 2.7 | 2.8 |
| Frame in which 10 paragraphs change | 3.4 | 3.4 | 3.3 | 3.6 |
| Frame in which 100 paragraphs change | 9.1 | 9.7 | 9.3 | 10.0 |
| Frame that rebuilds every paragraph | 25.7 | 28.5 | 27.3 | 25.2 |
| Frame that appends one paragraph | 32.6 | 39.6 | 34.3 | 33.0 |
| First search, 1,000 matches | | | | 14.0 |

With 1,000 paragraphs, in milliseconds:

| | No scope | Scope without plugins | Plugin that does nothing | Search plugin |
| :--- | ---: | ---: | ---: | ---: |
| Idle frame | < 0.01 | < 0.01 | < 0.01 | < 0.01 |
| Frame in which 1 paragraph changes | 0.4 | 0.3 | 0.3 | 0.3 |
| Frame in which 10 paragraphs change | 0.8 | 0.9 | 1.0 | 0.9 |
| Frame in which 100 paragraphs change | 5.8 | 5.4 | 6.2 | 5.8 |
| Frame that rebuilds every paragraph | 1.4 | 1.3 | 1.7 | 1.3 |
| Frame that appends one paragraph | 1.9 | 2.0 | 2.2 | 1.8 |
| First search, 100 matches | | | | 1.0 |

What they show:

- **The lifecycle is not visible.** With a plugin installed, a frame in which text changes costs about the same as with no scope. The differences are under 1 ms and go both ways.
- **An idle frame costs nothing** in all four.
- **The page itself grows with N.** A frame costs more on the larger page also with no scope, because the column has N children. Appending a paragraph rebuilds the whole column, which is why it is the most expensive frame in every column. That is not a plugin cost.
- **Appending does not rescan the page.** With the search active, the append costs about the same as with a plugin that does nothing.
- **The first search grows with the page.** Ten times the text takes about ten times as long.
- **A changed text that has matches is cheap.** In these runs every changed paragraph had a match, which is the worst case for the search plugin. 100 of them cost under 1 ms more than with a plugin that does nothing.
- **One number stands out and is probably noise.** The append under a scope without plugins is 39.6 ms. In the run before, the same case was 37.4 ms against 36.7 ms with no scope.

So the cost model holds: the cost follows the text that changed.

Benchmarks owed:

1. **Noise.** Repeat each measurement over several runs, so that a difference of a few milliseconds can be told from noise.
2. **Idle cost while scrolling.** The same page scrolling with a scope and no plugin activity, against the page with no scope.
3. **Eager offscreen content.** The frame in which eager rendering is turned on, for several cache extents.
4. **Other shapes and devices.** A lazy list instead of a column, and a mobile device.

### 3.9 What stage 1 cannot do

A stage 1 plugin paints. These are the consequences, stated plainly so that the trade-off is visible:

| A stage 1 plugin cannot | Why | Where it is addressed |
| :--- | :--- | :--- |
| React to a tap, a long-press or hover | It receives no pointer events | Stage 2 |
| Change the mouse cursor | It has no hit-test target | Stage 2 |
| Be a link or a button for a screen reader, or take keyboard focus | It does not change semantics or focus | Stage 2 |
| Show a widget: a menu, a chip, a tooltip, a blur | A `CustomPainter` only has a canvas | Stage 3 |
| Keep widget state such as an animation or a text field | Same reason. A painter can still repaint from a `Listenable` | Stage 3 |
| Hide text from a screen reader, copy or search | Painting over glyphs does not remove the text | Not a goal ([Section 2.1](#21-goals-and-non-goals)) |
| Change the text or its layout | Plugins are non-destructive in every stage | Not a goal |

For that reason the stage 1 example app has no plugin that needs a tap. Links and tap-to-reveal spoilers are stage 2 or stage 3 use cases.

---

## 4. Community package use cases

`TextPlugin` combines text inspection (`text`, `placeholderRanges`), sub-span geometry (`getBoxesForSelection`, `getPositionForOffset`, `getWordBoundary`), custom painting (`backgroundPainter`, `foregroundPainter`), and viewport control (`ensureVisible`, `compareTo`, `needsOffscreenContent`, `paintOrder`). Together, these primitives support drop-in packages across any `Text`, `RichText`, or `EditableText` subtree.

### 4.1 Use cases implemented in the demo app

Alongside `SearchInPagePlugin` (covered in [Section 3.6](#36-first-party-searchinpageplugin-implementation) and [Section 5.1](#51-scrolling-document-ordering-and-offscreen-content-rendering)), our demo app (`examples/text_plugins`) implements four more paint-only plugins to validate the API. `LinkifyPlugin` and `SpoilerMaskPlugin`, which earlier versions of this document listed here, need a tap to be useful. They moved to stage 2 ([Section 8](#8-stage-2-annotations)):

#### 1. TTS read-aloud karaoke synchronizer (`ReadAloudPlugin`)

`ReadAloudPlugin` sorts mounted `TextDelegate`s in visual reading order via `delegates.sort()` (`TextDelegate.compareTo`) and tokenizes words while skipping `0xFFFC` `WidgetSpan` placeholders. It tints the active paragraph in `backgroundPainter`, paints a pill highlight over the spoken word in `foregroundPainter`, and calls `delegate.ensureVisible(wordRange)` when narration crosses a paragraph boundary. Updating word highlights via `CustomPainter` and `TextDelegate.markNeedsPaint()` avoids rebuilding or re-laying out `RenderParagraph` on every word boundary.

#### 2. Read-only spellcheck and style-guide linter (`SpellcheckLinterPlugin`)

`SpellcheckLinterPlugin` inspects rendered text for common misspellings (`recieve`, `seperate`, `occured`, `teh`) and terminology rules. In `foregroundPainter`, it draws wavy red or amber underlines along `box.toRect().bottom` using `Path`. Showing replacement suggestions when a word is tapped is a stage 3 use case ([Section 9](#9-stage-3-widgets)).

#### 3. Financial ticker badges (`StockTickerPlugin`)

`StockTickerPlugin` matches financial ticker symbols (`GOOG`, `AAPL`, `MSFT`, `NVDA`) in `delegate.text`, paints green or red pill backgrounds in `backgroundPainter`, and draws underline accents in `foregroundPainter`. Opening a live quote card on tap needs stage 2.

#### 4. Live content and SEO metadata extraction (`SeoExtractorPlugin`)

`SeoExtractorPlugin` is a headless inspection plugin that attaches no painters. As `TextDelegate`s mount, update, and unmount, it indexes visible text in document order (`compareTo`) to compute live word counts, reading-time estimates, and structured Schema.org JSON-LD metadata. It is here to show that a plugin can collect all text of a subtree in document order. It is not offered as an SEO solution: the semantics tree carries more of what a search engine needs (headings, links), and SEO is not a goal of this RFC.

### 4.2 Additional community package ideas

Beyond the plugins implemented in the demo app, the same `TextPlugin` primitives can support other community packages. Ideas that only paint work in stage 1. Ideas that react to hover, a tap or a long-press, or that show a popup, need stage 2 or 3:

- Inline dictionary, translation, and furigana popovers triggered by hover or long-press via `getPositionForOffset` and `getWordBoundary`, or focus reading rulers that dim surrounding lines in `foregroundPainter`.
- Staging-build QA detectors that highlight untranslated l10n keys (`auth.login.button_title`), broken interpolation placeholders (`{userName}`), or typography widows and orphans.
- Collaborative document annotations, persistent user highlights, and multiplayer presence carets positioned via `getOffsetForCaret`.
- AI source-attribution citations, 120fps shader shimmer effects driven by an `AnimationController` on `foregroundPainter` without text relayout, and smart entity links for log viewers (UUIDs, Git SHAs, `file.dart:123:45` stack traces, and timestamps).

---

## 5. Feature deep dives

### 5.1 Scrolling, document ordering, and offscreen content rendering

Supporting browser-style Find-in-Page (`Ctrl+F`) across scrollable Flutter views requires solving three problems at the rendering and widget layers:

1. Scrolling to a matched character range (`TextDelegate.ensureVisible`).

2. Sorting matches in visual document order regardless of lazy mount order (`TextDelegate.compareTo`).

3. Eagerly rendering offscreen content in `ListView.builder`, `SliverList.builder`, and `CustomScrollView` when `Ctrl+F` is active so offscreen items are built, laid out, and searchable (`TextPlugin.needsOffscreenContent` and `OffscreenContentRenderingStrategy`).

The third item is **off by default**. It is about content that the app already has but the framework has not built yet, such as the items of a `ListView.builder` outside the cache extent. A browser finds that kind of content, so an app can ask for the same. Content that the app has not loaded yet, such as the next page of a feed, is never found, as on the web.

---

#### 5.1.1 Scrolling to a specific character range (`TextDelegate.ensureVisible`)

Scrolling to an entire `RenderParagraph` (`showOnScreen(rect: null)`) is not enough when a paragraph spans multiple screens or when a nested scroll view clips part of a line.

`TextDelegate.ensureVisible` computes the glyph bounding rectangle for any `TextRange` and reveals it across all enclosing viewports:

```dart
void ensureVisible(ui.TextRange range, {Duration duration = Duration.zero, Curve curve = Curves.ease}) {
  assert(hasLayout);
  final List<ui.TextBox> boxes = getBoxesForSelection(
    TextSelection(baseOffset: range.start, extentOffset: range.end),
    boxHeightStyle: ui.BoxHeightStyle.max,
  );
  // Union glyph boxes (or fall back to the caret rect at `range.start` if empty):
  final Rect targetRect = boxes.isNotEmpty
      ? boxes.map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b))
      : _caretRectAt(range.start);
  showOnScreen(rect: targetRect, duration: duration, curve: curve);
}
```

When `showOnScreen` runs, `_paragraph.showOnScreen(descendant: _paragraph, rect: targetRect, duration: duration, curve: curve)` walks up the `RenderObject.parent` chain.

Each enclosing [RenderViewportBase](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/viewport.dart) invokes `RenderViewportBase.showInViewport`. It queries `viewport.getOffsetToReveal(descendant, 0.0, rect: rect)` for the leading edge and `viewport.getOffsetToReveal(descendant, 1.0, rect: rect)` for the trailing edge.

If `targetRect` is already visible between the leading and trailing edges of the viewport, `RevealedOffset.clampOffset` returns `null` and no scroll occurs. Otherwise, `offset.moveTo(targetOffset.offset, duration: duration, curve: curve)` scrolls the minimal distance needed to bring `targetRect` onscreen, then continues walking up `super.showOnScreen` so nested scroll views scroll both axes into view.

`duration` and `curve` are passed through, so the scroll can be animated. `Duration.zero` jumps.

One case is not covered: a range inside a multi-line text field that is scrolled out of view *inside the field*. See [Section 7.15](#715-a-match-inside-a-scrolled-text-field).

---

#### 5.1.2 Document-order sorting (`TextDelegate implements Comparable<TextDelegate>`)

When a user starts in the middle of a `ListView.builder` (such as `Item 10`) and scrolls upward, `RenderSliverList` mounts `Item 9`, then `Item 8`, then `Item 7`. As a result, `didAddText` fires in the order `[Item 10, Item 9, Item 8, Item 7]`. If `SearchInPagePlugin` iterates over `_delegates` in registration order, pressing "Next Match" jumps backward up the document.

Comparing global screen coordinates (`localToGlobal(Offset.zero).dy`) also fails for general layouts. Two side-by-side columns or wrapped flex items can have overlapping vertical coordinates even though they have a well-defined reading order in the widget tree.

We solve this with Lowest Common Ancestor (LCA) render-tree traversal:

1. `RenderParagraph` registers its `TextDelegate`s once attached to the `PipelineOwner` (when `RenderParagraph.parent` and the ancestor chain up to the root are linked) and unregisters them in `detach()`.

2. `TextDelegate.compareTo` walks up `RenderObject.parent` from both `this.renderObject` and `other.renderObject` to find their lowest common ancestor (`commonParent`) and the two diverging child branches (`thisBranch` and `otherBranch`).

3. It calls `commonParent.visitChildren(...)` to check which branch comes first. Because `ContainerRenderObjectMixin.visitChildren` (used by `RenderFlex`, `RenderWrap`, `RenderViewport`, and `RenderSliverList`) visits children from `firstChild` to `lastChild` in ascending logical index order, `delegates.sort()` produces top-to-bottom document order even when children are prepended during upward scrolling.

#### Performance characteristics of LCA sorting

One `compareTo` call walks both ancestor chains to the root. What it does next depends on the common parent:

- If the parent keeps a sibling list, as `RenderFlex` and `RenderSliverList` do, it walks that list forward from both branches at once and stops when one reaches the other. The cost is the distance between the two siblings.
- For any other parent it calls `visitChildren` on the common parent. The cost is the number of its children.

Sorting many delegates by comparing pairs is slow when they share one long parent. In the first measurement, sorting 1,000 matching texts among 10,000 siblings took 1.0 s, because every comparison visited all 10,000 children.

`TextDelegate.sortInDocumentOrder(List<TextDelegate>)` (new) avoids this. It marks the ancestors of every delegate, then walks the tree once from the root and visits only the marked nodes, in the order of `visitChildren`. Its cost is the number of children of the marked nodes, however many delegates there are. With it the same search takes about 10 ms ([Section 3.8.1](#381-first-measurements)).

`SearchInPagePlugin` uses `sortInDocumentOrder` for a new query and whenever it has to sort again. It uses `compareTo` only for small jobs: to check a changed text against its two neighbors, and to insert a newly matching text by binary search ([Section 3.6.2](#362-incremental-per-delegate-match-indexing-and-active-match-preservation)). It keeps order only for the texts that have matches.

A test checks that `sortInDocumentOrder` and `compareTo` give the same order, for parents with and without a sibling list.

`SelectableRegion` has the same ordering problem and orders its selectables by position today. The comparison above only needs two render objects, so it could be shared. That is a follow-up outside this proposal.

---

#### 5.1.3 Declarative offscreen content rendering (`needsOffscreenContent` and `OffscreenContentRenderingStrategy`)

In Flutter's sliver protocol ([RenderViewport._attemptLayout](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/viewport.dart) and [RenderSliverList.performLayout](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/sliver_list.dart)), `RenderViewport` computes `_calculatedCacheExtent` from `scrollCacheExtent` (defaulting to `250.0` logical pixels before and after the visible viewport).

`RenderSliverList` only builds and lays out children whose layout offsets fall within `[scrollOffset + cacheOrigin, scrollOffset + cacheOrigin + remainingCacheExtent]`. It calls `collectGarbage(leadingGarbage, trailingGarbage)` to destroy children outside that window. In a `ListView.builder` with 50 items, items #10 through #50 do not exist in the Element or RenderObject trees until scrolled near the viewport.

Rather than coupling `Viewport` to `TextPluginScope`, we split the design into two clean abstractions: `bool get needsOffscreenContent` on `TextPlugin` (defaulting to `false`, returning `true` when document-wide scanning is active) and `OffscreenContentRenderingStrategy` (`OffscreenRenderingPolicy`) on `Viewport`.

When multiple plugins are composed in a `TextPluginScope`, the scope requests eager offscreen rendering if any active plugin has `needsOffscreenContent == true`. `SearchInPagePlugin.eagerLoadOffscreenText` is `false` by default. An app that wants offscreen items to be searched sets it to `true` when its search bar opens (`needsOffscreenContent => true`), and the plugin calls `notifyListeners()`.

At the widget layer, `OffscreenRenderingPolicy` holds a configurable `ScrollCacheExtent?`, and `OffscreenContentRenderingStrategy` is a standalone `InheritedWidget` in `package:flutter/widgets.dart`:

```dart
@immutable
class OffscreenRenderingPolicy {
  const OffscreenRenderingPolicy.lazy() : isEager = false, cacheExtent = null;
  const OffscreenRenderingPolicy.eager({
    ScrollCacheExtent this.cacheExtent = const ScrollCacheExtent.pixels(1e6),
  }) : isEager = true;

  final bool isEager;
  final ScrollCacheExtent? cacheExtent;
}

class OffscreenContentRenderingStrategy extends InheritedWidget {
  const OffscreenContentRenderingStrategy({required this.policy, required super.child, super.key});
  final OffscreenRenderingPolicy policy;
  static OffscreenRenderingPolicy of(BuildContext context) { ... }
}
```

`Viewport` and `ShrinkWrappingViewport` in [packages/flutter/lib/src/widgets/viewport.dart](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/viewport.dart) do not import `text_plugin.dart`; they only query `OffscreenContentRenderingStrategy.of(context)`.

`TextPluginScope` separates `_InheritedTextPluginScope` (which provides `List<TextPlugin>` to `RichText` and `EditableText`) from `OffscreenContentRenderingStrategy` (which provides `OffscreenRenderingPolicy` to `Viewport`). When a plugin's `needsOffscreenContent` flips between `false` and `true`, only `Viewport` and `ShrinkWrappingViewport` rebuild; existing onscreen `RichText` widgets do not rebuild.

When `policy.isEager` is `true`, `Viewport` and `ShrinkWrappingViewport` apply `policy.cacheExtent` (defaulting to `const ScrollCacheExtent.pixels(1e6)`).

We use `1e6` (`1,000,000.0` logical pixels, ~1,200–1,500 screens of scroll) as the default eager cache extent instead of `double.maxFinite` or `double.infinity`. In `RenderViewport._attemptLayout`, `fullCacheExtent = mainAxisExtent + 2 * _calculatedCacheExtent` and `centerCacheOffset = centerOffset + _calculatedCacheExtent`. Using `double.maxFinite` (`1.79e308`) overflows `2 * _calculatedCacheExtent` to `double.infinity` (producing `NaN` in `fullCacheExtent - centerCacheOffset`) and loses floating-point mantissa precision when adding `centerOffset`. By contrast, `1e6` pixels stays well within IEEE-754 float64 exact precision while remaining overridable via `OffscreenContentRenderingStrategy`.

When the user closes `Ctrl+F` (`eagerLoadOffscreenText = false`), `OffscreenContentRenderingStrategy` switches back to `const OffscreenRenderingPolicy.lazy()` and restores the normal `250.0` pixel `cacheExtent`. On the next layout pass, `RenderSliverList.collectGarbage` unmounts offscreen items and triggers `didRemoveText` for each one.

#### Performance trade-offs and bounding `cacheExtent`

Because Flutter's `Widget`, `Element`, and `RenderObject` trees (`RenderSliverList`, `RenderParagraph`) are single-threaded on the UI isolate, offscreen widgets cannot be inflated or laid out on a background isolate. Eagerly building and laying out offscreen children in a single frame has a main-thread cost proportional to the number of items within `cacheExtent`.

Because `OffscreenRenderingPolicy` carries a configurable `ScrollCacheExtent?`, developers can bound or disable eager offscreen rendering for any expensive or infinite scroll view using `OffscreenContentRenderingStrategy`:
- **Bounding `cacheExtent` per scroll view**: Wrap a large `ListView` or `CustomScrollView` in `OffscreenContentRenderingStrategy(policy: const OffscreenRenderingPolicy.eager(cacheExtent: ScrollCacheExtent.pixels(5000.0)), child: ...)` (or `ScrollCacheExtent.viewport(5.0)`) to cap how far ahead of the viewport offscreen items are eagerly built.
- **Opting out a scroll view (`OffscreenRenderingPolicy.lazy()`)**: Wrap an expensive or infinite list (`itemCount == null`) in `OffscreenContentRenderingStrategy(policy: const OffscreenRenderingPolicy.lazy(), child: ...)` so it remains strictly lazy even when an ancestor `TextPluginScope` has `needsOffscreenContent == true`.

A cheaper variant was suggested in review: build the offscreen widgets without laying them out, and lay a text out only when a plugin needs its geometry, for example to scroll to a match. Layout is the larger part of the cost. Plugins hear about a text after its layout today, so this needs a different lifecycle. It is future work.

---

### 5.2 Should selection highlighting be a `TextPlugin`?

When a user drags to select text inside a [SelectionArea](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/material/selection_area.dart) or [SelectableRegion](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/selectable_region.dart), Flutter draws a colored rectangle behind the selected characters. A natural architectural question is what parts of text selection can be implemented as a `TextPlugin`, and what parts cannot.

#### 5.2.1 What `TextPlugin` can do: painting selection highlights

In `RenderParagraph` today, selection highlight painting (`_SelectableFragment.paintSelection`) queries `getBoxesForSelection` and draws rectangles on the canvas before the text glyphs paint:

```dart
for (final TextBox textBox in paragraph.getBoxesForSelection(selection)) {
  context.canvas.drawRect(textBox.toRect().shift(offset), selectionPaint);
}
```

Because this is the same operation performed by a plugin `backgroundPainter`, `SelectableRegion` can install a `_SelectionHighlightTextPlugin` via `TextPluginScope` that reads the paragraph's active selection from `TextDelegate` and paints the highlight boxes.

Moving selection highlight painting into a `TextPlugin` simplifies `RenderParagraph.paint` and allows apps to customize how selection highlights look (such as rounded selection corners or collaborative cursors) using the standard plugin pipeline.

---

#### 5.2.2 Trade-offs and what `TextPlugin` cannot do alone

Evaluating selection as a `TextPlugin` highlights four architectural trade-offs and boundaries:

##### 1. Paint order between `SelectionArea` and inner feature plugins (solved by painting the selection highlight last)

`SelectionArea` is typically mounted near the root of an app or page, while feature plugins (such as `StockTickerPlugin`, which paints an opaque green pill behind `"GOOG"`) are mounted deeper inside the page body:

```dart
SelectionArea( // Outer scope: _SelectionHighlightTextPlugin (painted last)
  child: Scaffold(
    body: TextPluginScope(
      plugin: stockTickerPlugin, // Inner scope: opaque green pill (paintOrder: 0)
      child: const Text('Buy GOOG today'),
    ),
  ),
)
```

If plugin paint order were locked strictly to root-to-leaf widget tree nesting, the inner opaque `"GOOG"` pill would paint over the outer `SelectionArea` highlight, making `"GOOG"` look unselected. The prototype solves this without a number: `RenderParagraph` paints the background of `_SelectionHighlightTextPlugin` after the backgrounds of all other plugins, whatever their `paintOrder` (see [Section 3.5](#35-renderparagraph-and-rendereditable-painting-and-z-order-pipeline)), so selection highlights always paint above opaque background badges from inner `TextPluginScope`s while still painting behind the paragraph's text glyphs.

##### 2. Per-widget `Text(selectionColor: ...)` and inline `WidgetSpan`s

A single `_SelectionHighlightTextPlugin` installed at the root `SelectableRegion` only knows the default selection color from `DefaultSelectionStyle`. If a descendant `Text('Warning', selectionColor: Colors.red)` overrides its selection color, or if a `Text.rich` contains inline `WidgetSpan`s that split the paragraph into multiple selectable ranges, the plugin cannot render accurately unless `TextDelegate` exposes per-paragraph `selectionColor` and `selections` (where `getBoxesForSelection` defaults to `includePlaceholders: false` so inline widgets are not highlighted).

##### 3. Plugin opt-out (`TextPluginScope.none` versus `TextPluginScope.exclude`)

If a developer wraps a sidebar in `TextPluginScope.none` so `SeoExtractorPlugin` ignores the sidebar text, `TextPluginScope.none` removes all ancestor plugins, including `_SelectionHighlightTextPlugin`. In the prototype the highlight does not disappear, because `RenderParagraph` falls back to its built-in highlight painting when the plugin is not installed. A custom selection style that an app installed through a plugin would still be lost there. Using `TextPluginScope.exclude(types: {SeoExtractorPlugin})` lets developers disable specific feature plugins without stripping selection highlighting.

##### 4. Mobile drag handles and cross-widget selection

While `CustomPainter` can draw selection rectangles on a `Canvas`, it cannot replace the rest of `_SelectableFragment` inside `RenderParagraph`:

1. Mobile selection drag handles (the teardrop handles on Android and iOS) require pushing composited `LeaderLayer`s (`context.pushLayer(LeaderLayer(...))`) into the `PaintingContext` during `RenderParagraph.paint`. A `CustomPainter` only receives a `Canvas` and cannot push composited layers.

2. `SelectionArea` coordinates selection gestures across both text (`RenderParagraph`) and non-text widgets (such as selectable images), so `RenderParagraph` must still register its selectable fragments with `SelectionRegistrar`.

---

#### 5.2.3 Summary: what can and cannot move to `TextPlugin`

| Selection Responsibility | Can be a `TextPlugin`? | Architectural Reason |
| :--- | :--- | :--- |
| **Drawing selection highlight boxes** | **Yes** | Maps directly to `TextDelegate.backgroundPainter` + `getBoxesForSelection(...)`, provided `TextDelegate` exposes `selections` and `selectionColor`. |
| **Custom selection styles (rounded rects, animations)** | **Yes** | Custom `TextPlugin` painters can draw any `Canvas` decoration behind or in front of selected glyphs. |
| **Mobile drag handle positioning (`LeaderLayer`)** | **No (not via `CustomPainter`)** | Requires `PaintingContext.pushLayer(LeaderLayer(...))` and `alwaysNeedsCompositing` on `RenderParagraph`. |
| **Gesture dispatch and cross-widget selection** | **No** | Handled by `SelectableRegion` and `SelectionRegistrar` across both text and non-text `Selectable` render objects. |

#### 5.2.4 Follow-up roadmap: what it would take to migrate `SelectionArea` to `TextPlugin`

Moving all of `SelectionArea`'s text responsibilities into a `TextPlugin` involves a core trade-off: it removes roughly 2,100 lines of `_SelectableFragment` code from `RenderParagraph`, but it requires expanding `TextDelegate` beyond canvas painting into composited layer management and `SelectionRegistrar` plumbing.

Because of that trade-off, this initial proposal keeps the rest of Flutter's built-in selection code unchanged while landing the core `TextPlugin` pipeline first. Only the painting of the highlight for static text goes through a plugin (see 5.2.5). If we choose to migrate `SelectionArea` to `TextPlugin` in a follow-up, it would require four steps, of which the first two already exist in the prototype:

1. Expose per-paragraph `selections` (`List<TextSelection>`) and `selectionColor` (`Color?`) on `TextDelegate`, and have `SelectionContainer` and `SelectableRegion` install `_SelectionHighlightTextPlugin` to draw selection boxes via `delegate.backgroundPainter`.

2. Paint the background of `_SelectionHighlightTextPlugin` after every other plugin background, so outer `SelectionArea` highlights paint over opaque background badges from inner feature plugins.

3. Extend `TextDelegate` with `delegate.registerHandleLayers(startLink, endLink)` so a selection plugin can push composited `LeaderLayer`s for mobile drag handles during `RenderParagraph.paint` and `RenderEditable._paintContents`.

4. Use `TextPluginScope.exclude(types: {...})` on UI chrome so disabling feature plugins never strips `_SelectionHighlightTextPlugin`, and then remove the legacy selection highlight painting code from `RenderParagraph` and `RenderEditable`.

#### 5.2.5 What has been done, and what an experiment showed

**In the stage 1 prototype.** Steps 1 and 2 of the roadmap above exist. `TextDelegate` exposes `selections` and `selectionColor`. `SelectableRegion` installs an internal `_SelectionHighlightTextPlugin`, which paints the highlight of static text. `TextPluginScope.exclude` keeps it. Everything else about selection is unchanged and stays in `RenderParagraph`.

**In a separate experiment.** The [`text-plugin-selection`](https://github.com/hannah-hyj/flutter/tree/text-plugin-selection) branch goes further and moves the text half of selection (`_SelectableFragment`, the highlight and the handle layers) out of `RenderParagraph` into a `TextSelectionPlugin`.

> This experiment is background. It is **not one of the three stages and not part of this proposal.** It was built before stage 1 became paint-only, on a branch that still has the old stage 2 code under it. It has not been rebased, so it does not run on the current stage 1 branch. The numbers below are from the experiment's own report and were not measured again.

| Question | What the experiment found |
| :--- | :--- |
| Is it doable? | Yes for static text (`Text` and `RichText` in a `SelectionArea`), with one changed test expectation. Not as an ordinary plugin |
| What did the plugin API need? | Seven new `TextDelegate` members, and one new type, `TextAnchor`, to position the handles |
| What did the host need? | Three special rules: selectable text always has exactly one selection plugin, which the paragraph installs itself; the text is re-added to the plugin when the registrar changes; and the selection delegate is kept through `detach()` |
| How much moved? | About 95% of the selection lines left `RenderParagraph`. Most of the new plugin is code that moved unchanged |
| What could it not do? | Be written by a package, move `SelectableRegion` itself, or cover `TextField` |
| Hardest part | Lifecycle, not geometry or painting. "A delegate dies when the text detaches" does not fit a plugin that holds state |

What this means for the plan:

- A general anchor (`TextAnchor`) costs about the same as the selection-only `registerHandleLayers` sketched in step 3 above, and is also useful for link previews and comment bubbles. It belongs with stage 3, or with a later stage.
- Selection needs host rules that no other plugin needs. If it moves, it moves as a special first-party plugin.
- Stage 1 does not depend on any of this.

Two related ideas from review belong to that follow-up as well: a plugin that overrides the selection style for a subtree, for `Text(selectionColor: ...)`, and sharing the document-order comparison with `SelectableRegion` ([Section 5.1.2](#512-document-order-sorting-textdelegate-implements-comparabletextdelegate)).

---

## 6. Future directions and forward compatibility

Although the initial scope targets `RenderParagraph` and `RenderEditable`, we shaped `TextDelegate`, `TextPlugin`, and `TextPluginScope` so the architecture can expand to custom `TextPainter` render objects, non-text widgets, and native platform-view text fields without breaking existing plugins.

Of the items below, only `TextDelegateHostMixin` (examples 1 and 2 of [Section 6.1](#61-custom-textpainter-render-objects-and-non-text-widgets-with-searchable-labels)) exists in the prototype and is covered by a test. The rest is future work.

---

### 6.1 Custom `TextPainter` render objects and non-text widgets with searchable labels

Users searching a page (`Ctrl+F` via `SearchInPagePlugin`) or listening to an article (`ReadAloudPlugin`) often expect custom widgets that paint text directly with `TextPainter` (such as custom chips, table cells, or canvas badges) as well as labeled non-text widgets (`Image(semanticLabel: '...')`, `Icon(semanticLabel: '...')`, or custom charts like `BarChart` and `Sparkline`) to be discoverable, highlighted, scrolled into view, and narrated in document order alongside standard `Text` paragraphs.

#### 1. Concrete example: custom widget and `RenderBox` using `TextPainter` directly

Because `TextDelegate.renderObject` is typed as `RenderBox`, `TextDelegateHostMixin` on `RenderBox` provides the `textPlugins` setter, post-layout `TextDelegate` flush scheduling (`markNeedsTextDelegateUpdate()`, `didLayoutTextDelegates()`), and painter hooks (`paintTextPluginBackgrounds`, `paintTextPluginForegrounds`). Any custom `RenderBox` that paints text directly with `TextPainter` can mix in `TextDelegateHostMixin` to participate in `TextPluginScope`:

```dart
mixin TextDelegateHostMixin on RenderBox {
  String get plainText;
  InlineSpan get textSpan => TextSpan(text: plainText);
  ui.TextDirection get textDirection;
  List<ui.TextBox> getBoxesForSelection(TextSelection selection, { ... });

  List<TextPlugin>? textPlugins;

  @protected void markNeedsTextDelegateUpdate();
  @protected void didLayoutTextDelegates();
  @protected void paintTextPluginBackgrounds(PaintingContext context, Offset offset);
  @protected void paintTextPluginForegrounds(PaintingContext context, Offset offset);
}

class RenderCustomBadgeText extends RenderBox with TextDelegateHostMixin {
  // Widget forwards `textPlugins ?? TextPluginScope.maybeOf(context)`.
  // Label setter updates `_textPainter.text` and calls `markNeedsTextDelegateUpdate()`.
  final TextPainter _textPainter;

  @override
  String get plainText => _textPainter.plainText;

  @override
  List<ui.TextBox> getBoxesForSelection(TextSelection selection, { ... }) =>
      _textPainter.getBoxesForSelection(selection, ...);

  @override
  void performLayout() {
    _textPainter.layout(maxWidth: constraints.maxWidth);
    size = constraints.constrain(_textPainter.size);
    didLayoutTextDelegates();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    paintTextPluginBackgrounds(context, offset);
    _textPainter.paint(context.canvas, offset);
    paintTextPluginForegrounds(context, offset);
  }
}
```

#### 2. Concrete example: simple non-text widget (`LabeledColorBox` / `Image` / `Icon`)

Unlike a `TextPainter`-backed widget where substrings map to individual glyph boxes, a simple non-text `RenderBox` (such as an image, icon, or colored thumbnail) exposing a searchable `label` maps any non-empty `TextSelection` within `0..label.length` to the widget's full bounding box:

```dart
class RenderLabeledColorBox extends RenderBox with TextDelegateHostMixin {
  // Constructor, LeafRenderObjectWidget, and property setters omitted for brevity.
  String _label;
  Color _color;
  Size _boxSize;

  @override
  String get plainText => _label; // Setter calls markNeedsTextDelegateUpdate()

  @override
  List<ui.TextBox> getBoxesForSelection(TextSelection selection, { ... }) {
    if (!selection.isValid || selection.isCollapsed) return const <ui.TextBox>[];
    // Map any matched range within 0.._label.length to the widget's full bounds:
    return <ui.TextBox>[
      ui.TextBox.fromLTRBD(0, 0, size.width, size.height, textDirection),
    ];
  }

  @override
  void performLayout() {
    size = constraints.constrain(_boxSize);
    didLayoutTextDelegates();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    paintTextPluginBackgrounds(context, offset);
    context.canvas.drawRect(offset & size, Paint()..color = _color);
    paintTextPluginForegrounds(context, offset);
  }
}
```

While whole-widget highlighting works well for Search, TTS, and SEO, character-level typographic plugins like `SpellCheckPlugin` (which draws wavy underlines under words) should not underline an entire `Image`. Exposing `bool get hasCharacterBoxes` on `TextDelegate` lets character-specific plugins skip non-text delegates. Because an `Image` or opaque box paints across its bounds, non-text delegates can render highlight borders or tints in `foregroundPainter`.


#### 3. Complex non-text widgets (`BarChart`, `Sparkline`): widget-owned highlight rendering

A complex widget such as a `BarChart` or `Sparkline` may want to control how matched content is highlighted. A rectangular `CustomPainter` overlay does not know how to highlight a specific bar, pie slice, or sparkline vertex.

In `Ctrl+F` (`SearchInPagePlugin`) or TTS (`ReadAloudPlugin`), the plugin owns the document-wide coordinator state (the active search query, the `"3 of 12"` match count, and Next/Previous navigation). Meanwhile, the `BarChart` widget owns the domain-specific rendering of its data series.

We can separate match discovery (owned by the plugin) from highlight rendering (owned by the widget or host) by passing structured highlight ranges to `TextDelegate`, with the plugin's `CustomPainter` acting as the default fallback when a widget does not override highlight rendering:

```dart
class TextPluginHighlight {
  const TextPluginHighlight({
    required this.range,
    required this.role, // e.g., searchMatch, activeSearchMatch, spokenWord
    this.fallbackStyle, // Default color/decoration if host uses default painter
  });

  final ui.TextRange range;
  final Object role;
  final TextHighlightStyle? fallbackStyle;
}
```

First, a `BarChart` exposes its data labels to `TextDelegate` (for example, `"Q1: $10M\nQ2: $15M\nQ3: $22M\nQ4: $18M"`).

Second, when `SearchInPagePlugin` queries `delegate.getBoxesForSelection(rangeForQ3)` for `ensureVisible`, the `BarChart` returns the bounding `Rect` of the Q3 bar so `Ctrl+F` scrolls directly to that bar.

Third, instead of painting a flat yellow rectangle over the chart, the `BarChart` receives the active `List<TextPluginHighlight>`, maps range `18..26` (`"Q3: $22M"`) back to `barIndex = 2`, and highlights that bar or sparkline vertex using its own graphics.

#### Summary across target widgets

| Target Widget | How `TextDelegate.text` Is Provided | How `getBoxesForSelection(range)` Works | Who Renders the Highlight? |
| :--- | :--- | :--- | :--- |
| **Standard `Text` / `EditableText`** | `InlineSpan.toPlainText(includeSemanticsLabels: false)` | `TextPainter` glyph boxes | **Plugin's default painter** (`CustomPainter` on `RenderParagraph`) |
| **Custom `TextPainter` `RenderBox`** | `TextPainter.plainText` via `TextDelegateHostMixin` | `TextPainter.getBoxesForSelection` | **Plugin's default painter** (`paintTextPluginBackgrounds` / `Foregrounds`) |
| **Simple `Image` / `Icon`** | `semanticLabel` | Whole widget bounding box (`0..w, 0..h`) | **Plugin's default painter** (or foreground border/tint) |
| **Complex Graphic (`BarChart`, `Sparkline`)** | Concatenated series / datum labels | Bounding box of the matched bar / datum | **The Chart Widget itself** (glows bar, pulses sparkline point, elevates slice) |
| **Native Platform View (`HtmlElementView`, `UITextView`)** | DOM `textContent` / native text | W3C `Range.getClientRects()` / `UITextInput` | **The Platform View itself** (via W3C `CSS.highlights` / `::highlight()` or `NSLayoutManager`) |

---

### 6.2 Native text fields and platform views

On Web and mobile platforms, apps may embed platform-rendered text fields or HTML views via Platform Views (`HtmlElementView`, `UiKitView`, `AndroidView`), where text shaping and painting happen inside the browser DOM or native OS toolkit rather than Flutter's `TextPainter`.

On Web (`HtmlElementView`), the W3C `Range` API and W3C CSS Custom Highlight API (`CSS.highlights` and `::highlight()`) use the same non-destructive decoration model as `TextPlugin`:

| `TextDelegate` Capability | Flutter (`RenderParagraph` / `RenderEditable`) | Web Platform View (W3C DOM APIs) | iOS / Android Native Text Views |
| :--- | :--- | :--- | :--- |
| **`text`** | `InlineSpan.toPlainText(includeSemanticsLabels: false)` | `element.textContent` | `UITextView.text` / `EditText.getText()` |
| **`getBoxesForSelection(range)`** | `ui.Paragraph.getBoxesForRange` | `Range.getClientRects()` (mapped to local `RenderBox` coordinates) | `UITextInput.selectionRects(for:)` / `Layout.getSelectionPath` |
| **`getPositionForOffset(point)`** | `TextPainter.getPositionForOffset` | `document.caretPositionFromPoint(x, y)` | `UITextInput.closestPosition(to:)` / `Layout.getOffsetForHorizontal` |
| **`ensureVisible(range)`** | `RenderObject.showOnScreen(rect)` | `Range.getBoundingClientRect()` + `scrollIntoView` / `showOnScreen` | `UITextView.scrollRangeToVisible` |
| **Range Decoration** | `CustomPainter` (`backgroundPainter` / `foregroundPainter`) | **`CSS.highlights.set(id, new Highlight(range))`** + `::highlight(id)` | `NSLayoutManager` temporary attributes / `Spannable` `CharacterStyle` |

To support platform views without breaking existing plugins:

1. `TextDelegate` can delegate text, geometry, and painting hooks to a `TextDelegateHost` interface that Platform View render objects can also implement.

2. A Flutter `CustomPainter` cannot paint between a native platform view's background and its text glyphs, and a canvas overlay cannot stay frame-synchronized with internal DOM compositor scrolling. Adding a declarative highlight method on `TextDelegate` (`setHighlights(Object pluginKey, List<TextHighlight> highlights)`) alongside `CustomPainter` lets `RenderParagraph` and `RenderEditable` paint ranges with an internal `CustomPainter`, while Web Platform Views translate those ranges into W3C `Range` instances registered in `CSS.highlights` (`::highlight()`).

3. In browsers, W3C `Range` and `CSS.highlights` operate on DOM `Text` nodes. Because HTML `<input>` and `<textarea>` store their text inside a closed User-Agent shadow root (`.value`), native web text fields using `CSS.highlights` need a DOM node that keeps its text in `Text` nodes, such as a synchronized mirror node, so character offsets map to DOM `Text` nodes. A `<div contenteditable="plaintext-only">` would also do that, but it does not support autofill, so it cannot replace `<input>`.

---

## 7. Corner cases and architectural analysis

Below are the corner cases identified during design, prototyping and review, along with how the architecture handles each one.

### 7.1 `ChangeNotifier` and `setState` re-entrancy during build, layout, and dispose

Suppose a search bar widget at the top of the screen listens to `SearchInPagePlugin` (`ChangeNotifier`) via `ListenableBuilder` to display a match counter such as `"1 of 5 matches"`.

When the user scrolls a `ListView` and a new `Text` item mounts on screen, `PipelineOwner.flushLayout()` invokes `searchPlugin.didAddText(delegate)` while Flutter is in the middle of laying out the frame (`SchedulerPhase.persistentCallbacks`). Inside `didAddText`, `SearchInPagePlugin` scans the new paragraph and finds a sixth match (`"1 of 6 matches"`).

If `SearchInPagePlugin` calls `notifyListeners()` synchronously inside `didAddText` (or inside `didUpdateText`, `didLayoutText`, or `didRemoveText`), the search bar widget will call `setState()` while Flutter is still building or laying out the widget tree. Flutter then throws a `setState() or markNeedsBuild() called during build` assertion error.

To avoid this crash, plugins separate canvas repaints from external widget notifications:

- Updating `delegate.backgroundPainter = ...` inside `didAddText` or `didUpdateText` only calls `RenderParagraph.markNeedsPaint()`, which is always safe during build and layout because painting (`flushPaint()`) happens later in the same frame.
- When notifying external UI widgets (such as the `"1 of 6 matches"` counter in `SearchInPagePlugin._notifyListenersSafely`), if `SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks`, the plugin defers `notifyListeners()` to the end of the frame via `SchedulerBinding.instance.addPostFrameCallback`. When the user types in the search box between frames (`SchedulerPhase.idle`), `notifyListeners()` runs immediately.

---

### 7.2 Why `didAddText`, `didUpdateText`, and `didLayoutText` are flushed post-layout

In an early iteration of the prototype, `didAddText` ran synchronously inside `attach()` / `updateRenderObject()` (during `buildScope`), `didUpdateText` ran synchronously inside `RenderParagraph.text = ...` (immediately after `markNeedsLayout()`), and `didLayoutText` ran at the end of `RenderParagraph.performLayout()`. Empirical testing uncovered four subtle bugs with that timing:

1. **`_needsLayout` is still `true` inside `performLayout()`**: `RenderObject.layout()` sets `_needsLayout = false` *after* `performLayout()` returns. Calling `didLayoutText` inside `performLayout()` meant `debugNeedsLayout` was still `true`, so `delegate.hasLayout` returned `false` and `delegate.getBoxesForSelection(...)` crashed with `Assertion failed: !debugNeedsLayout is not true`.
2. **Release-mode false positives on `debugNeedsLayout`**: `RenderObject.debugNeedsLayout` unconditionally returns `false` in release builds (`if (!kDebugMode) return false;`). Checking `!renderObject.debugNeedsLayout` in `TextDelegate.hasLayout` falsely returned `true` in release mode when `RenderParagraph` had a dirty layout, causing `getBoxesForSelection` to return boxes computed under stale constraints or stale text.
3. **`RenderObject.debugActiveLayout` assertions**: While any `RenderObject` is inside `performLayout()`, `RenderObject.debugActiveLayout` is non-null, causing `otherDelegate.size` to fail an assertion in `RenderBox.size`.
4. **Unpositioned parent offsets**: Inside `RenderParagraph.performLayout()`, parent containers (`RenderFlex`, `RenderSliverList`) have not yet set `childParentData.offset` on the child, so `delegate.localToGlobal(Offset.zero)` returned unpositioned coordinates.

To solve all four issues:

1. `TextDelegate` tracks a dedicated `_hasValidLayout` boolean (set to `false` in `markNeedsLayout()` and `true` at the end of `performLayout()`), so `delegate.hasLayout` is accurate in both debug and release builds.
2. `RenderParagraph` and `RenderEditable` schedule `didAddText`, `didUpdateText`, and `didLayoutText` via `PipelineOwner.schedulePostLayoutCallback`, which flushes at the end of `PipelineOwner.flushLayout()` after all dirty `RenderObject`s have exited `layout()` and finalized parent offsets, and right before `PipelineOwner.flushPaint()`. A pipeline owner flushes these callbacks after its child pipeline owners have flushed their layout, so the layout of that owner and of everything below it is final (see [Section 7.16](#716-what-a-plugin-may-do-in-a-lifecycle-callback)).
3. As a result, `delegate.hasLayout` is guaranteed to be `true` in all three callbacks (`didAddText`, `didUpdateText`, and `didLayoutText`), all geometry and coordinate queries (`getBoxesForSelection`, `size`, `localToGlobal`) succeed immediately, and painters set in those callbacks paint in the same frame.

---

### 7.3 Embedded `WidgetSpan`s and UTF-16 offset alignment

A `Text.rich` widget can contain inline `WidgetSpan` children:

```dart
Text.rich(
  TextSpan(
    children: [
      TextSpan(text: 'Buy '),
      WidgetSpan(child: Icon(Icons.trending_up)),
      TextSpan(text: ' GOOG today'),
    ],
  ),
)
```

Inside `TextPainter` and `ui.Paragraph`, every `PlaceholderSpan` occupies 1 UTF-16 code unit represented by the Unicode Object Replacement Character `\uFFFC` (`0xFFFC`).

If `delegate.text` omitted placeholders (`includePlaceholders: false`), `' GOOG today'` would start at index `4` in `delegate.text`, but at offset `5` in `TextPainter`. Passing `TextSelection(baseOffset: 4, extentOffset: 8)` to `getBoxesForSelection` would highlight `'GOO'` instead of `'GOOG'`. Conversely, if `delegate.text` used `includeSemanticsLabels: true` (the default of `InlineSpan.toPlainText()`), a `TextSpan(text: 'GOOG', semanticsLabel: 'Alphabet Inc.')` would return `'Alphabet Inc.'` in `delegate.text`, desynchronizing string indices from `TextPainter` glyph offsets and causing plugins to process accessibility label overrides instead of visible text.

To make this impossible to get wrong, `TextDelegate` enforces an opinionated contract:

1. `TextDelegate.text` always calls `_paragraph.text.toPlainText(includeSemanticsLabels: false)` internally (preserving `\uFFFC` placeholder code units and ignoring `semanticsLabel`). Plugin authors simply read `delegate.text` and never call `InlineSpan.toPlainText` directly.
2. Because `\uFFFC` is not a word character (`\w`) or whitespace (`\s`), regex patterns like `\bGOOG\b` naturally treat adjacent `WidgetSpan`s as word boundaries without shifting character indices.
3. `TextDelegate.getBoxesForSelection` defaults to `includePlaceholders: false`, automatically splitting any selection range around `delegate.placeholderRanges` so multi-word matches never highlight across an inline `WidgetSpan`.

---

### 7.4 Text truncation and overflow clipping

Suppose a `Text` widget has `maxLines: 1, overflow: TextOverflow.ellipsis` and a 500-character string where `'GOOG'` appears at character 400 (truncated behind `'...'`).

`delegate.text` returns the full 500-character string from `InlineSpan.toPlainText`, so a regex in `SearchInPagePlugin` or `StockTickerPlugin` still matches `'GOOG'` at offset `400..404`. For characters past the ellipsis cutoff, `ui.Paragraph.getBoxesForRange` returns an empty list `[]` or a collapsed zero-width box at the ellipsis end. For a match that straddles the ellipsis cutoff (`'https://flut...'`), `getBoxesForSelection` returns the box for the visible prefix (`'https://flut'`).

In `RenderParagraph.paint`, when the text overflows and is clipped (`TextOverflow.clip`, `TextOverflow.ellipsis`, `TextOverflow.fade`), both `backgroundPainter` and `foregroundPainter` passes are clipped to `offset & size` via `context.canvas.clipRect(offset & size)` so badges cannot bleed outside the paragraph bounds. In the future, exposing `bool didExceedMaxLines` or `TextRange getVisibleTextRange()` on `TextDelegate` can let search plugins filter out truncated matches when desired.

---

### 7.5 Multi-line wrapping, bidirectional text, and surrogate pairs

A single logical substring (such as a long URL wrapping across two lines, or an English phrase inside an Arabic or Hebrew RTL paragraph) does not map to a single `Rect`. `getBoxesForSelection` returns multiple `ui.TextBox` instances, one per line fragment and bidirectional run.

In addition, Dart `String` indices and `TextSelection` offsets are UTF-16 code units. Characters outside the Basic Multilingual Plane (such as emoji characters like U+1F680 or regional indicator flag pairs) occupy 2 or more UTF-16 code units.

Plugins should iterate over every `ui.TextBox` returned by `delegate.getBoxesForSelection(...)` when painting. When scrolling a multi-line match into view (`SearchInPagePlugin.scrollToActiveMatch`), `TextDelegate.ensureVisible` computes the bounding union of all boxes (`boxes.map((b) => b.toRect()).reduce((a, b) => a.expandToInclude(b))`) and passes it to `showOnScreen(rect: bounds)`.

---

### 7.6 Plugin list reconciliation and stateful delegate preservation

Suppose a user toggles a single plugin on or off in `TextPluginScope.multiple(plugins: _activePlugins, ...)`, changing the active plugin list from `[stockPlugin, readAloudPlugin, searchPlugin]` to `[stockPlugin, readAloudPlugin]`.

If `RenderParagraph` disposed all delegates and recreated them whenever `textPlugins` changed, `stockPlugin` and `readAloudPlugin` would receive unnecessary `didRemoveText` and `didAddText` calls on every toggle, losing any per-delegate state cached by `stockPlugin`.

In `RenderParagraph._syncTextPluginDelegates`, we diff the existing `_textPluginDelegates` keys against `newPlugins`:

1. Only plugins removed from `newPlugins` have their `TextDelegate` detached, notified via `plugin.didRemoveText(delegate)`, and disposed.

2. Plugins present in both the old and new lists keep their existing `TextDelegate` instance and attached painters, re-ordered to match the new `paintOrder` and installation order.

3. Only newly added plugins receive a new `TextDelegate` and schedule a post-layout `didAddText(delegate)`.

---

### 7.7 Deduplicating plugins by `Type` and instance across nested scopes

A widget tree might mount two scopes with the same plugin `Type` (for example, an outer `TextPluginScope(plugin: SearchInPagePlugin(matchHighlightColor: Colors.yellow))` and an inner `TextPluginScope(plugin: SearchInPagePlugin(matchHighlightColor: Colors.green))`), or pass the same `TextPlugin` instance twice in `TextPluginScope.multiple(plugins: [pluginA, pluginA])`.

If `RenderParagraph` active plugins were not deduplicated by `Type`, both `SearchInPagePlugin` instances would run on the same paragraph and paint every match twice.

We deduplicate at both layers:

1. **`Type`-based deduplication in `TextPluginScope`**: `TextPluginScope.build` merges ancestor and local plugins into a `Map<Type, TextPlugin>` keyed by `plugin.runtimeType`. An inner `TextPluginScope` providing a plugin of type `T` overrides any outer plugin of the same `Type` `T` for its subtree (matching `Actions`, `Shortcuts`, and `TextPluginScope.exclude(types: {T})`).
2. **Instance deduplication in `RenderParagraph` and `RenderEditable`**: `_syncTextPluginDelegates` also checks `if (orderedDelegates.containsKey(plugin)) continue;` in case duplicate plugin instances are passed directly to `RichText(textPlugins: [...])`.

---

### 7.8 Pointer events: none in stage 1

An earlier version of this proposal forwarded raw `PointerEvent`s to every plugin through `TextPlugin.handlePointerEvent`, and each plugin detected taps by hand. Review showed that this cannot work in general. Nothing arbitrated between two plugins on the same range, an authored `TextSpan.recognizer`, `SelectableRegion` and `TextField`. A double-click to select a word inside a link also opened the link twice.

`handlePointerEvent` is removed. A stage 1 plugin receives no pointer events, so `RenderParagraph` and `RenderEditable` hit-test and handle events exactly as they do without plugins. Interaction is designed in stage 2, where a plugin's tap is a recognizer in the gesture arena ([Section 8](#8-stage-2-annotations)).

---

### 7.9 `SelectionArea` and `SelectableRegion` coexistence

When a `Text` widget is inside both a `SelectionArea` and a `TextPluginScope`, both `RenderParagraph`'s `_SelectableFragment`s and `TextDelegate` painters are active on the same `RenderParagraph`.

If a plugin's `backgroundPainter` painted on top of the user's text selection highlight, an opaque plugin badge would hide the user's selection rectangle. If a plugin's `foregroundPainter` painted on top of selection drag handles, the handles could be covered.

In `RenderParagraph.paint`, plugin `backgroundPainter`s paint behind `_SelectableFragment.paintSelection` (or before `_SelectionHighlightTextPlugin`, which always paints last among the backgrounds) so user text selection remains visible over plugin background tints. Plugin `foregroundPainter`s paint in front of glyphs (for underlines and overlays) but behind `_SelectableFragment.paintHandles`.

---

### 7.10 Unintended capture of UI chrome and `TextPluginScope.none`

In Flutter, many UI controls use `Text` and `RichText` internally, including `AppBar` titles, `FilledButton` labels, `FilterChip` labels, `Tooltip` popups, `SnackBar` messages, and `TextField` hint or counter text.

If a developer wraps their entire `MaterialApp` or `Scaffold` in a `TextPluginScope(plugin: searchPlugin, ...)`, searching for `'Add'` highlights the `'Add Text'` button label. Worse, if the search bar itself is inside the `TextPluginScope` and displays `'1 / 4'`, typing `'1'` matches the search bar's own match counter.

`TextPluginScope.none` strips all ancestor `TextPlugin`s for its `child` subtree (and `TextPluginScope.exclude(types: {SearchInPagePlugin})` strips specific plugin types while preserving selection). Developers should either place `TextPluginScope` around the content body rather than the outer `Scaffold` chrome, or wrap embedded toolbars and search bars in `TextPluginScope.none`.

---

### 7.11 Lazy slivers and offscreen viewport recycling

In a `ListView.builder` or `CustomScrollView` with 1,000 paragraphs, Flutter by default only builds and mounts `RenderParagraph` instances for items inside the viewport plus `cacheExtent` (`250.0` logical pixels).

As the user scrolls down, top paragraphs are deactivated (`detach()` fires `didRemoveText`) and bottom paragraphs are mounted (post-layout flush fires `didAddText`). Visual decoration plugins (`StockTickerPlugin`, `SpellcheckLinterPlugin`) keep `needsOffscreenContent => false` and work with $O(\text{visible items})$ memory overhead.

Document-wide plugins (`SearchInPagePlugin`, `SeoExtractorPlugin`) handle upward scroll mount order via `TextDelegate.compareTo`, character-range scrolling via `TextDelegate.ensureVisible`, and configurable offscreen item discovery via `TextPlugin.needsOffscreenContent` and `OffscreenContentRenderingStrategy` (`OffscreenRenderingPolicy.eager(cacheExtent: ...)`; see [Section 5.1.3](#513-declarative-offscreen-content-rendering-needsoffscreencontent-and-offscreencontentrenderingstrategy)).

---

### 7.12 Canvas state corruption in plugin painters

All plugin `backgroundPainter`s and `foregroundPainter`s share `PaintingContext.canvas` with `RenderParagraph`. A buggy plugin painter that calls `canvas.save()` without `canvas.restore()`, or mutates the canvas transform without restoring, could corrupt the rendering of subsequent plugins, the paragraph text itself, or sibling widgets in the same repaint boundary.

`RenderParagraph._paintWithCustomPainter` wraps each individual plugin painter call in its own `canvas.save()`, `canvas.translate(offset.dx, offset.dy)`, and `canvas.restore()` pair. In debug mode, it records `canvas.getSaveCount()` before and after `painter.paint(canvas, size)` and throws a `FlutterError` naming the offending `CustomPainter` if its `save()` and `restore()` calls are unbalanced. The check exists in `RenderParagraph` and `RenderEditable`. `TextDelegateHostMixin` saves and restores around each painter but does not check the count yet.

---

### 7.13 Obscured text fields are never given to a plugin

A third-party plugin that logs or indexes text must not see a password. Obscuring characters alone do not guarantee that: on mobile, the most recently typed character can be shown briefly.

So the rule has no flag. An `EditableText` with `obscureText` set is not registered with any text plugin, neither the plugins of the enclosing `TextPluginScope` nor the ones passed in `EditableText.textPlugins`. A plugin gets no delegate for the field, so it cannot read it, paint on it or find matches in it. Find-in-page skips password fields, as browsers do.

When `obscureText` changes while the field is mounted, the plugins get `didRemoveText` or `didAddText` for it.

---

### 7.14 Text that is mounted but not visible

**Covered routes.** A route that is covered by an opaque route stays mounted. Its text is not given to any plugin while it is covered. A search scope placed above a `Navigator` therefore counts only the matches in the routes that can be seen.

The `Overlay` does this. It keeps an `OverlayEntry` below an opaque entry mounted, but does not lay it out or paint it. It now also wraps every entry in a `TextPluginSuspension` (new, `@internal`), which withholds plugins while the entry is covered.

- When a route becomes covered, the plugins get `didRemoveText` for its texts. When it is uncovered, they get `didAddText` again. The route keeps its state.
- During the transition both routes are on stage, and both are given to plugins.
- A route below a non-opaque route, such as a dialog, can still be seen and stays with its plugins.
- A `TextPluginScope` inside the covered route does not install its plugins either. The result does not depend on where the scope is.
- Plugins passed directly in `RichText.textPlugins` or `EditableText.textPlugins` are not affected.

The cost is two small widgets per overlay entry, also in an app that uses no plugins.

This is tested in `text_plugin_test.dart` and in the example app (the "Stacked Pages" card).

**Other text that is mounted but not visible.** An inactive tab that is kept alive, a hidden child of `IndexedStack` and a child of `Offstage` are not handled. Their text is still given to plugins. For these the answer is still placement: put the scope inside the tab body. Whether they should be left out in the same way is open ([Section 11](#11-open-questions)). This part was read from the code and has not been tested.

---

### 7.15 A match inside a scrolled text field

`TextDelegate.ensureVisible` asks the render object to show a rectangle. That scrolls the scroll views around the text. A multi-line text field also scrolls its own content, and that scrolling is done by `EditableText`, not by an enclosing viewport. Nothing in the `ensureVisible` path moves it.

So when the active match is inside a text field and scrolled out of view inside the field, the page scrolls to the field but the field does not scroll to the match.

This is a known gap of the prototype. A test in the example app confirms it (the "Multi-line Text Field" card): after moving to the match, the scroll offset of the field has not changed and the match is still below the last visible line.

The fix belongs in the delegate, as review suggested: for an editable text, first bring the range into view inside the field, then scroll the ancestors.

---

### 7.16 What a plugin may do in a lifecycle callback

The callbacks run after layout and before paint. In a callback, a plugin may:

- read text and geometry from the delegate,
- set or clear its painters,
- ask for a repaint.

A plugin must not mark anything as needing layout, and must not call `setState` or notify widgets synchronously. A plugin that has to tell widgets about a change postpones that to after the frame, as `SearchInPagePlugin` does ([Section 7.1](#71-changenotifier-and-setstate-re-entrancy-during-build-layout-and-dispose)).

The prototype does not enforce this yet. Whether to add an assertion is open ([Section 11](#11-open-questions)).

**Timing with several pipeline owners.** A `PipelineOwner` runs its post-layout callbacks at the end of its own `flushLayout`, which is after its child owners have flushed theirs. Inside a callback, the layout of that owner and of everything below it is final. A child owner runs its own callbacks at the end of its own flush.

**Alternative considered.** A binding-level `RendererBinding.addPostLayoutCallback`, called once per frame after the root pipeline owner has flushed layout, was suggested in review. It is simpler and runs once per frame instead of once per render tree. The per-owner version is used in the prototype because a text schedules the callback on the owner it is attached to and needs no binding. This choice is open.

---

## 8. Stage 2: annotations

> Stage 2 is a future stage. It is **not** part of what this RFC asks to land. It is here to show that interaction can be added on top of stage 1.
> Branch: [`text-plugin-annotations`](https://github.com/hannah-hyj/flutter/tree/text-plugin-annotations). Live demo: [text-plugin-annotations-demo.web.app](https://text-plugin-annotations-demo.web.app/). The statements in this section come from the design notes and the tests on that branch. They will be checked again after the branch is rebased onto the current stage 1 branch.

### 8.1 What it adds

A plugin attaches a `TextAnnotation` to a range of a text. An annotation is data, not code that handles events:

```dart
@override
void didUpdateText(TextDelegate delegate) {
  delegate.annotations = [
    for (final TextRange range in _findUrls(delegate.text))
      TextAnnotation(range: range, cursor: SystemMouseCursors.click, onTap: () => _open(range)),
  ];
}
```

| An annotation can give a range | Through |
| :--- | :--- |
| A tap or a long-press | `onTap`, `onLongPress`, or a recognizer owned by the plugin |
| A mouse cursor and hover callbacks | `cursor`, `onEnter`, `onHover`, `onExit` |
| A place in the semantics tree | `linkUrl` makes it a link, an action makes it a button, `semanticsLabel` replaces what is spoken |
| Keyboard focus | An annotation with an action is reached with Tab and activated with Enter |

### 8.2 How it answers the review comments on pointer events

| Concern | Stage 2 answer |
| :--- | :--- |
| Raw pointer events bypass the gesture arena | There is no raw hook. A tap is a recognizer in the arena. A drag that starts on a link scrolls and opens nothing |
| Two plugins on the same characters | Both join the arena. The topmost plugin wins, exactly once |
| A spoiler over a link | The spoiler is on top, so the first tap reveals. It then has no annotation on that range, so the next tap is meant to go to the link. The first tap is tested, the second is not |
| A link inside selectable or editable text | The arena cannot decide this, because a tap fires before a second click is known. The delegate tells the plugin whether the text is editable, read-only or selectable. The link plugin of the experiment opens on a plain click only in static text, and needs a modifier key elsewhere, so a click still places the caret and a double-click still selects |
| A link for a screen reader | A range with a URL becomes its own link node, the same shape a `TextSpan` with a recognizer produces today. A plugin that only paints leaves the text as one node |
| Tab and Enter | Tab reaches annotations in reading order, Enter activates, and a focus ring is painted. Not inside editable text, where Tab has to leave the field |

### 8.3 Why it does not change the stage 1 API

`TextAnnotation` and `TextDelegate.annotations` are additions. `TextPlugin` keeps its four callbacks, and a stage 1 plugin runs unchanged.

It does change stage 1 **code**, and the list is given here so that this is not a surprise later:

| What stage 2 touches | Effect on a stage 1 plugin |
| :--- | :--- |
| Hit testing and semantics assembly inside `RenderParagraph` and `RenderEditable` | None when no annotation is set |
| `TextPluginScope` adds an internal plugin that manages focus | The list of plugins on a text is one longer. Two expectations in the stage 1 test file had to change for that reason |
| `TextDelegateHostMixin` implements a new `TextPluginHost` interface | None for a plugin. A custom host gets new members with defaults |

### 8.4 Use cases that move here

**Automatic URL linkification (`LinkifyPlugin`).** It detects URLs (`https://...`, `www....`) inside plain `Text` and `EditableText` widgets and underlines them, without requiring callers to split strings into `TextSpan`s with `TapGestureRecognizer`s. In stage 2 each URL is an annotation with a `linkUrl`, a click cursor and an `onTap`. Hover previews use the hover callbacks, with the popup anchored by `delegate.localToGlobal`.

**Interactive spoiler and study-cloze masking (`SpoilerMaskPlugin`).** It scans `delegate.text` for spoiler tags (`||...||`, `[spoiler]...[/spoiler]`) or flashcard cloze-deletion markers (`{{...}}`) and draws an opaque rounded cover over the hidden glyphs in `foregroundPainter`. In stage 2 the cover is still painted, and an annotation makes it tappable and gives it a spoken label.

Because `TextPlugin` is non-destructive and does not mutate the input `InlineSpan` string or alter glyph layout metrics, the delimiter characters (`||` or `{{`) remain part of the laid-out paragraph run when revealed. Depending on the desired UX, the plugin can either leave the syntax delimiters visible around the revealed text or paint an opaque background-colored mask over the delimiter `ui.TextBox`es (`range.start..range.start + 2` and `range.end - 2..range.end`) in `foregroundPainter` so the `||` markers remain visually hidden after reveal without triggering text relayout.

**Stock ticker quote cards and spell-check suggestions on tap** are the interactive halves of two stage 1 plugins.

### 8.5 What is still open

- Whether one ordering rule (the topmost plugin wins) is right for hit testing, cursor, semantics and focus alike.
- The shape of the semantics tree on each platform. The experiment only splits read-only editable text into nodes, and never an editable field.
- Whether the modifier-key convention for links in editable text should live in the framework or in each plugin.

---

## 9. Stage 3: widgets

> Stage 3 is a future stage. It is **not** part of what this RFC asks to land.
> Branch: [`text-plugin-with-widget`](https://github.com/hannah-hyj/flutter/tree/text-plugin-with-widget). Live demo: [text-plugin-widget-demo.web.app](https://text-plugin-widget-demo.web.app/). Its framework tests were run for this document. The findings about the two example plugins come from the experiment's own report.

### 9.1 What it adds

A plugin can build real widgets and place them on a range of text, in one of three layers: behind the text, in front of it, or in the overlay, where they float over everything else in the route.

```dart
class MentionPlugin extends TextPlugin with TextWidgetPlugin {
  @override
  Iterable<Widget> buildTextWidgets(BuildContext context, TextDelegate delegate, TextWidgetLayer layer) {
    if (layer != TextWidgetLayer.foreground) {
      return const <Widget>[];
    }
    return [
      for (final TextRange range in _find(delegate.text))
        TextPositioned.fill(delegate: delegate, range: range, child: MentionChip(onTap: () => _open(range))),
    ];
  }
}
```

| Component | What it is |
| :--- | :--- |
| `TextWidgetPlugin` | A mixin on `TextPlugin`. The host asks it for widgets with `buildTextWidgets` |
| `TextWidgetLayer` | Which layer is being built: background, foreground or overlay |
| `TextPositioned` | Places a child on a range of the text, using the same geometry a painter would use |
| `TextPluginWidgetHost` | Wraps a text and holds the layers. `Text` and `EditableText` add it only when a widget plugin is in scope |

Because the children are ordinary widgets, gestures, focus, semantics, mouse regions, animation and state work the way they do everywhere else.

### 9.2 Why it does not change the stage 1 API

`TextWidgetPlugin` is a mixin that a plugin opts into. A plugin without it is a stage 1 plugin and is treated as one. The stage 1 test file is unchanged on the branch and passes.

What it touches in stage 1 code:

| What stage 3 touches | Effect on a stage 1 plugin |
| :--- | :--- |
| `Text` wraps its `RichText` in `TextPluginWidgetHost`, and `EditableText` has a matching change | None when no widget plugin is in scope: the text is returned unwrapped |
| An internal hook on `TextDelegate` that tells the host when the layout of the text becomes invalid | None |
| An internal `textDelegateFor(plugin)` on the render objects | None |

### 9.3 What the experiment showed

Two plugins were built on it: a spell-check suggestion menu that extends the stage 1 linter, and a frosted-glass spoiler that blurs the text behind it, which a painter cannot do.

| Claim | Result |
| :--- | :--- |
| Widgets can be added to a painter-only plugin | The menu plugin extends the stage 1 linter. The linter and the framework did not change |
| Widgets sit on the text in the same frame | After a re-wrap, after typing in a field, and after a text change during an animation |
| Foreground widgets move with the text | When a list scrolls, the widgets move without being built again |
| Overlay widgets follow the text but are not clipped with it | A menu floats over later siblings and receives their taps |
| The host does not change the text | Size, intrinsic size and baseline of the text are the same with and without it |
| Ordinary widgets work | Focus traversal, semantics, `MouseRegion` and cursor |
| It coexists with selection and editing | In a `SelectionArea` and in a `TextField` |

### 9.4 Known defects and open problems

These are open in the experiment and are stated here so that nobody is surprised by them later.

Defects:

1. **A plugin that notifies rebuilds the widgets of every text in its scope.** Opening one menu rebuilt the widgets of all texts, for every widget plugin. Painters have `delegate.markNeedsPaint()` for one text. Widgets have no counterpart yet.
2. **A second notification in the same frame can be lost.**
3. **A plugin that notifies from inside `buildTextWidgets` makes the texts rebuild each other every frame, and nothing reports it.**

Limits found while building the two plugins:

- Widgets built from data that the lifecycle callbacks collect are one frame late, because `buildTextWidgets` runs during layout and the callbacks run after it. A widget plugin has to build from the delegate.
- The overlay layer only places a widget. Everything else that makes a menu a menu (dismissal, focus, keyboard) is left to the plugin.
- A widget cannot change what the text itself is. It cannot hide words from a screen reader. A complete spoiler needs stage 2 for that and stage 3 for the blur, so annotations and widgets are two halves, not alternatives.
- Adding the first widget plugin to a scope, or removing the last one, re-creates every text in it, because the host is inserted or removed.

None of these affect stage 1.

---

## 10. The same feature, written three ways

"Do something with every `@mention`." `_find` returns the ranges.

**Stage 1, painter only.** The plugin reacts to a callback and stores a painter:

```dart
@override
void didUpdateText(TextDelegate delegate) {
  delegate.backgroundPainter = _MentionPainter(delegate, _find(delegate.text));
}
```

**Stage 2, annotations.** Same moment, and the plugin stores data next to the painter:

```dart
@override
void didUpdateText(TextDelegate delegate) {
  delegate.annotations = [
    for (final TextRange range in _find(delegate.text))
      TextAnnotation(range: range, cursor: SystemMouseCursors.click, onTap: () => open(range)),
  ];
}
```

**Stage 3, widgets.** No callback. The host asks, and the plugin answers:

```dart
@override
Iterable<Widget> buildTextWidgets(BuildContext context, TextDelegate delegate, TextWidgetLayer layer) {
  return [
    for (final TextRange range in _find(delegate.text))
      TextPositioned.fill(delegate: delegate, range: range, child: MentionChip(onTap: () => open(range))),
  ];
}
```

| | Stage 1 | Stage 2 | Stage 3 |
| :--- | :--- | :--- | :--- |
| The mention looks different | Yes | Yes, with the stage 1 painter | Yes |
| A tap opens the profile | No | Yes | Yes |
| The cursor changes on hover | No | Yes | Yes |
| A screen reader announces a link or button | No | Yes | Yes, as a separate widget |
| It shows an avatar, a menu or an animation with state | No | No | Yes |
| What the plugin hands over | A painter | Data | Widgets |
| When | After layout, in a callback | After layout, in a callback | During layout, when the host asks |
| Cost for a text without mentions | Nothing | Nothing | A host around every text in scope |

The three are layers, not replacements. The stage 1 line stays in the stage 2 plugin, and a stage 3 plugin can still paint.

---

## 11. Open questions

For stage 1:

| # | Question | Where |
| :--- | :--- | :--- |
| 1 | Should `TextDelegate.renderObject` be hidden, so that the delegate is read-only in fact and not only by convention? | [3.3](#33-textdelegate-proxy-for-text-render-objects) |
| 2 | Should the framework publish reference values for `paintOrder`? | [3.4](#34-textpluginscope-and-hierarchical-merging) |
| 3 | Should the post-layout callback assert that a plugin does not dirty layout? | [7.16](#716-what-a-plugin-may-do-in-a-lifecycle-callback) |
| 4 | Per-owner `schedulePostLayoutCallback`, or a binding-level callback once per frame? | [7.16](#716-what-a-plugin-may-do-in-a-lifecycle-callback) |
| 5 | Covered routes are left out. Should a kept-alive tab, a hidden `IndexedStack` child and an `Offstage` child be left out too? | [7.14](#714-text-that-is-mounted-but-not-visible) |
| 6 | `ensureVisible` for a range inside a scrolled text field | [7.15](#715-a-match-inside-a-scrolled-text-field) |
| 7 | The benchmarks that are owed | [3.8](#38-performance) |
| 8 | Where `SearchInPagePlugin` lives in the framework | [3.6](#36-first-party-searchinpageplugin-implementation) |
| 9 | Spell check as a first-party text plugin: `flutter/flutter` or `flutter/packages`? | [2.2](#22-built-in-framework-plugins-versus-community-packages) |

For the later stages, see [Section 8.5](#85-what-is-still-open), [Section 9.4](#94-known-defects-and-open-problems) and [Section 5.2.5](#525-what-has-been-done-and-what-an-experiment-showed).

---

## Appendix A: What was verified

"Ran" means a test was run for this document. "Read" means the code was read on the branch and no test was run for the claim.

| Claim | Branch | How |
| :--- | :--- | :--- |
| The stage 1 framework tests pass (21 tests in `text_plugin_test.dart`) | `text-plugin-mvp` | Ran |
| An obscured `EditableText` is not registered with any plugin | `text-plugin-mvp` | Ran |
| The order of the lifecycle callbacks ([Section 3.2](#32-textplugin-lifecycle-contract)) | `text-plugin-mvp` | Read, in all three hosts. The lifecycle tests ran |
| Painting order and clipping ([Section 3.5](#35-renderparagraph-and-rendereditable-painting-and-z-order-pipeline)) | `text-plugin-mvp` | Read. The paint-order tests ran |
| `SearchInPagePlugin` defaults, and that it builds no widgets | `text-plugin-mvp` | Read |
| The example app has five paint-only plugins | `text-plugin-mvp` | Read. Its tests ran (4 tests) |
| The cost model ([Section 3.8](#38-performance)) | `text-plugin-mvp` | Read. Measured on macOS in profile mode, several runs ([Section 3.8.1](#381-first-measurements)) |
| Text in a covered route is not given to plugins ([Section 7.14](#714-text-that-is-mounted-but-not-visible)) | `text-plugin-mvp` | Ran, and checked by hand in the example app |
| Kept-alive tabs, `IndexedStack` and `Offstage` are still given to plugins ([Section 7.14](#714-text-that-is-mounted-but-not-visible)) | `text-plugin-mvp` | Read. Not tested |
| A match inside a scrolled text field is not scrolled into view ([Section 7.15](#715-a-match-inside-a-scrolled-text-field)) | `text-plugin-mvp` | Ran, and checked by hand in the example app |
| Stage 2 behavior ([Section 8](#8-stage-2-annotations)) | `text-plugin-annotations` | From the design notes and test names on the branch. Tests not run |
| What stages 2 and 3 touch in stage 1 code | Both | Read from the diff against stage 1 |
| The stage 3 framework tests pass, together with the unchanged stage 1 tests (50 tests) | `text-plugin-with-widget` | Ran, before the last stage 1 commit |
| Stage 3 findings and defects ([Section 9](#9-stage-3-widgets)) | `text-plugin-with-widget` | From the experiment's report |
| Selection experiment ([Section 5.2.5](#525-what-has-been-done-and-what-an-experiment-showed)) | `text-plugin-selection` | From the experiment's report. Not run again, and not rebased |
