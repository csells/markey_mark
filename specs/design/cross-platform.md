# 08 — Cross-Platform, Accessibility & i18n

The entire point of going native (ADR-001) is **uniform behavior on all six Flutter
targets** from one codebase, adapting to each platform's input and UI conventions.

## 08.1 Platform support matrix

| Capability | iOS | Android | Web | Windows | macOS | Linux |
|------------|:---:|:-------:|:---:|:-------:|:-----:|:-----:|
| Core editor (model/layout/render/IME) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Math (`flutter_math_fork`, native) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Code highlight (`re_highlight`, native) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Editable tables (native) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Images render | ✅ | ✅ | ✅¹ | ✅ | ✅ | ✅ |
| Rich clipboard (`super_clipboard`) | ✅ | ✅ | ✅² | ✅ | ✅ | ✅ |
| Drag & drop (`super_drag_and_drop`) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Hardware shortcuts | n/a³ | n/a³ | ✅ | ✅ | ✅ | ✅ |
| Soft keyboard / IME | ✅ | ✅ | ✅ | n/a | n/a | n/a |
| Mermaid (**native Dart engine**, no JS) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

¹ Web: use bytes/network (`Image.memory`/`Image.network`); `Image.file` is unavailable.
² Web: clipboard **reads** must go through DOM paste events (can't actively read clipboard).
³ Mobile supports external keyboards; primary input is the soft keyboard/IME.
⁴ Windows/Linux WebView is third-party (`flutter_inappwebview`/CEF); hence the default never
  relies on it and the deterministic SVG/PNG provider exists.

**The headline:** the *editor itself* is ✅ everywhere. The only ⚠️ is the *optional* Mermaid
WebView provider on Windows/Linux, which always has a native fallback.

## 08.2 Per-platform concerns

- **Web.** Flutter renders text inputs in-framework (hidden `<input>`/`contenteditable` with
  CSS-hidden content), so we inherit browser quirks for IME/spellcheck/autofill. We budget
  explicit web testing for selection, composing region, and paste (paste-via-events). No
  iframe is used for the core (ADR-001), so we avoid the pointer-event-swallowing trap.
- **Desktop (Win/macOS/Linux).** Hardware-keyboard-first; macOS routes key bindings as
  `performSelector` selectors (handled in the IME client); right-click context menus; mouse
  hover affordances (block handles). Delta semantics differ (macOS vs Linux) — centralized in
  the IME layer.
- **Mobile (iOS/Android).** Soft-keyboard IME primary; floating cursor (iOS), Scribble (iOS) /
  Scribe (Android) handwriting, magnifier, platform selection toolbars; keyboard avoidance so
  the caret stays visible (resize/scroll on keyboard show).
- **Input adaptation** is isolated in L5; L0–L4 are platform-agnostic and identically tested
  everywhere.

## 08.3 Accessibility

A custom-rendered editor produces **no** semantics automatically — we build the tree
explicitly:

- Wrap blocks in `Semantics` with correct roles: headings expose heading level, list items
  expose list semantics, images expose `alt` as label, code/quote labeled, links actionable.
- Expose editable text through text-field semantics so VoiceOver/TalkBack announce content,
  caret, and selection and allow navigation.
- Honor system "reduce motion" (caret blink, animations) and high-contrast.
- **Test with real TalkBack + VoiceOver**, not just the semantics debugger.

## 08.4 Internationalization & bidi

- **RTL / bidi:** respect `Directionality.of(context)`; render per-paragraph direction;
  per-run bidi (e.g., English inside Hebrew) handled by the text engine via `TextDirection`.
  Use `*Directional` insets/alignment (`EdgeInsetsDirectional`, `start`/`end`) throughout so
  the editor mirrors correctly. Optional per-block auto-direction detection.
- **Font scaling:** honor `MediaQuery.textScalerOf(context)` (`TextScaler`); size everything
  relative to resolved styles, never hardcoded px, so OS accessibility text sizing works.
- **Localization:** all chrome strings (toolbar tooltips, slash items, menus, placeholders)
  go through a `MarkdownEditorLocalizations` delegate so hosts can translate; ship English
  defaults.

## 08.5 The cross-platform test posture

- Pure-Dart layers (model, markdown, editing) run identically everywhere → cheap unit tests
  on Linux CI.
- Input/IME quirks are covered with **platform-tagged** widget tests.
- Rendering is verified with **golden tests**, which are platform-sensitive — see
  [10-testing-ci-packaging.md](./testing-ci-packaging.md) for the per-platform golden
  strategy (`alchemist`) and the CI matrix.
