Below is a **deep, depth-first expansion** of the **NOTE EDITOR SCREEN**, written as a **design + behavior + implementation-ready spec**.
This is intentionally verbose and explicit so **nothing is left to interpretation**, even at edge-case level.

You should be able to build the entire editor *purely from this description*.

---

# 3️⃣ NOTE EDITOR SCREEN — DETAILED SPECIFICATION

---

## 3.0 Intent & Philosophy

The **Note Editor Screen** is a **distraction-free, deterministic writing environment** optimized for:

* Long-form writing
* Structured thought
* Zero cognitive overhead
* Offline-first reliability
* Safe multi-device editing

There is **no concept of “Save” as an action**.
Persistence is **continuous, implicit, and atomic**.

The editor must feel:

* Immediate
* Predictable
* Forgiving
* Non-destructive

---

## 3.1 Screen Entry Conditions

### 3.1.1 Entry Sources

The screen can be entered from:

* New note creation
* Existing note selection
* Deep link (note ID)
* Search result
* Back-stack restore (process death recovery)

### 3.1.2 Initial State Resolution

On entry, the editor must resolve:

1. **Note identity**

   * Existing note → load latest local version
   * New note → create local draft immediately

2. **Data source**

   * Always load from **local database**
   * Never block UI on network

3. **Cursor state**

   * Restored from last session if available
   * Else follows default rules (see below)

---

## 3.2 Screen Layout Structure

```
┌──────────────────────────────┐
│ Title Field                  │
├──────────────────────────────┤
│ Rich Text Editor (Scrollable)│
│                              │
│                              │
│                              │
├──────────────────────────────┤
│ Formatting Toolbar (Context) │
└──────────────────────────────┘
     ↳ Metadata Panel (Overlay / Sheet)
```

---

## 3.3 Title Field

### 3.3.1 Visual Characteristics

* Single-line text input
* Larger font than body text
* No formatting options
* Fixed height
* Always visible (non-scrollable)

### 3.3.2 Functional Rules

* **Mandatory field**
* Cannot be empty when note is persisted
* Leading/trailing whitespace trimmed automatically
* Line breaks are blocked at input level

### 3.3.3 Auto-Focus Behavior

| Scenario               | Focus Behavior                |
| ---------------------- | ----------------------------- |
| New note               | Auto-focus title              |
| Existing note          | Focus restored to last cursor |
| Back navigation return | Focus unchanged               |
| App restore            | Focus restored                |

### 3.3.4 Empty Title Handling

* If user navigates away with empty title:

  * Auto-generate temporary title:

    * First non-empty content line
    * Else fallback: `"Untitled Note"`
* Title auto-updates only once unless manually edited

---

## 3.4 Rich Text Editor Area

### 3.4.1 Core Characteristics

* Scrollable vertical canvas
* Full width
* Infinite height
* Block-based document model
* Cursor-driven interaction model

---

### 3.4.2 Document Model (Conceptual)

The editor operates on **blocks**, not raw text.

Each block has:

* Type
* Content
* Optional attributes
* Stable internal ID

#### Supported Block Types

| Block Type      | Description     |
| --------------- | --------------- |
| Heading (H1–H3) | Section titles  |
| Paragraph       | Default text    |
| Bullet List     | Unordered list  |
| Numbered List   | Ordered list    |
| Checkbox List   | Task-style list |

---

### 3.4.3 Cursor & Selection Model

#### Cursor Rules

* Cursor exists **within a block**
* Each block maintains its own internal cursor index
* Cursor movement across blocks is deterministic

#### Selection Rules

* Selection may:

  * Span partial text
  * Span full blocks
  * Span multiple block types
* Selection never corrupts block boundaries

---

### 3.4.4 Keyboard Behavior

#### Enter Key

| Context         | Result                 |
| --------------- | ---------------------- |
| Paragraph       | New paragraph block    |
| Heading         | New paragraph block    |
| List item       | New list item          |
| Empty list item | Exit list              |
| Checkbox        | New unchecked checkbox |

#### Backspace at Start of Block

| Context         | Result              |
| --------------- | ------------------- |
| Non-first block | Merge with previous |
| First block     | No-op               |
| Empty block     | Remove block        |

---

### 3.4.5 Undo / Redo Stack

* Linear history
* Block-aware operations
* Includes:

  * Text changes
  * Formatting changes
  * Block creation/deletion
* Metadata changes **excluded** from undo stack

Undo must never:

* Cross notes
* Affect metadata
* Affect sync/version state

---

## 3.5 Formatting Toolbar (Contextual)

### 3.5.1 Visibility Rules

Toolbar appears when:

* Text selection is non-empty
* OR keyboard is visible and cursor is active

Toolbar hides when:

* No selection AND keyboard dismissed
* Editor loses focus

---

### 3.5.2 Toolbar Positioning

* Anchored near selection
* Avoids covering selected text
* Falls back to bottom dock if space constrained

---

### 3.5.3 Formatting Actions

#### Inline Formatting

* Bold
* Italic
* Underline
* Strikethrough

**Rules**

* Applies only to selected range
* Can be toggled on/off
* Nested formatting allowed
* No visual glitches on partial spans

---

#### Block Formatting

* Bullet list toggle
* Numbered list toggle
* Checkbox toggle

**Rules**

* Applies to entire block(s)
* Mixed selection → normalize to target type
* Preserves text content exactly

---

### 3.5.4 Formatting Side Effects

* Formatting does **not**:

  * Reset cursor
  * Collapse selection
  * Trigger scroll jumps
* Formatting is atomic per action

---

## 3.6 Metadata Panel (Collapsible)

### 3.6.1 Access Pattern

* Opened via explicit icon/action
* Appears as:

  * Bottom sheet OR
  * Side panel (tablet/landscape)

---

### 3.6.2 Metadata Fields

#### Date Picker

* Optional
* Supports clearing
* Defaults to null
* Time ignored unless explicitly enabled later

---

#### Preacher Selector

* Single selection
* Sourced from:

  * Existing preacher list
  * Inline creation allowed
* Changes propagate instantly

---

#### Tag Selector

* Multi-select
* Autocomplete input
* Supports:

  * Create
  * Remove
  * Reorder
* Tags persist globally

---

### 3.6.3 Metadata Behavior Rules

* Metadata edits:

  * Save independently
  * Do not affect undo stack
  * Do not move editor cursor
* Closing panel does not trigger re-render of editor content

---

### 3.6.4 Sync & Filtering Impact

* Metadata updates:

  * Immediately affect filters/search
  * Sync independently of note body
* Partial metadata sync must never block content edits

---

## 3.7 Auto-Save & Persistence Model

### 3.7.1 Save Triggers

* Every text mutation
* Every formatting change
* Every block change
* Every metadata change

No debounce visible to user
Persistence must feel instantaneous

---

### 3.7.2 Save Granularity

* Content saved as structured document
* Metadata saved separately
* Title saved independently

Each save updates:

* `updatedAt`
* `version`

---

## 3.8 Exit & Navigation Behavior

### 3.8.1 Back Navigation

* Immediate return
* No dialogs
* No prompts
* Save already completed

---

### 3.8.2 App Kill / Background

* Editor state persisted:

  * Cursor position
  * Scroll offset
  * Selection state (if possible)
* Restoration must feel seamless

---

## 3.9 Conflict & Version Handling

### 3.9.1 Multi-Device Conflicts

* Conflicts resolved via versioning
* Latest version wins by default
* No blocking UI

---

### 3.9.2 Conflict Visibility (Future-Safe)

* Architecture must allow:

  * Diff visualization
  * Manual resolution
* But no UI required now

---

## 3.10 Explicit Non-Goals (Editor Scope)

The editor **does not** support:

* Attachments
* Images
* Tables
* Real-time collaboration
* Comments
* Mentions
* Inline emojis
* Markdown shortcuts

---

## 3.11 Success Criteria

The Note Editor is considered **correctly implemented** when:

* User never thinks about saving
* Cursor never jumps unexpectedly
* Formatting never corrupts structure
* Metadata never interferes with writing
* App can crash, restart, sync — without data loss

---

Below is the **Flutter-aware expansion** of the **NOTE EDITOR SCREEN**, written so a Flutter engineer can build it *without guessing*.

---

# 3️⃣ NOTE EDITOR SCREEN — FLUTTER-AWARE DETAILED SPEC

---

## 3.0 Architectural Intent (Flutter Context)

The Note Editor must behave like a **local-first document engine**, not a form.

Key Flutter principles enforced:

* UI ≠ source of truth
* Widgets are disposable
* Editor state survives rebuilds
* No reliance on widget-local state for persistence
* Deterministic rendering across rebuilds, hot reloads, and app restarts

---

## 3.1 State Management Strategy (MANDATORY)

### 3.1.1 Recommended Pattern

**Unidirectional data flow** with explicit editor state.

Acceptable options:

* Riverpod (preferred)
* Bloc / Cubit
* Redux (only if already adopted)

❌ `setState` for editor logic is **explicitly forbidden**

---

### 3.1.2 Editor State Layers

Split state into **three distinct layers**:

```
┌──────────────────────────────┐
│ UI Interaction State         │ ← ephemeral (cursor, selection)
├──────────────────────────────┤
│ Editor Document State        │ ← authoritative (blocks, text)
├──────────────────────────────┤
│ Persistence / Sync State     │ ← side effects
└──────────────────────────────┘
```

---

### 3.1.3 Required State Objects

#### `NoteEditorController` (Long-Lived)

Responsible for:

* Document mutations
* Undo/redo
* Block normalization
* Versioning
* Emitting immutable snapshots

Must:

* Live above widget tree
* Survive rebuilds
* Be disposable only on screen exit

---

#### `EditorDocumentState`

Contains:

* List of blocks (ordered)
* Block IDs (stable)
* Block content
* Inline formatting spans

This is the **single source of truth** for rendering.

---

#### `EditorUIState`

Contains:

* Cursor position
* Selection range
* Scroll offset
* Keyboard visibility
* Toolbar visibility

Must be:

* Serializable
* Persisted on app background
* Restored on re-entry

---

## 3.2 Screen Entry (Flutter Lifecycle)

### 3.2.1 Entry Timing

Editor initialization must occur in:

* `initState()` **only to bind**
* Actual data loading in controller constructor or provider

❌ No async work inside `build()`

---

### 3.2.2 Rebuild Safety Rules

Editor must:

* Survive:

  * Orientation change
  * Theme change
  * Text scale change
  * Keyboard appearance
* Never:

  * Reset cursor
  * Lose selection
  * Reorder blocks accidentally

---

## 3.3 Title Field (Flutter Implementation)

### 3.3.1 Widget Choice

* `TextField`
* Single line
* Dedicated `TextEditingController`

Controller rules:

* Controller owned by editor controller, **not widget**
* Widget only binds to it

---

### 3.3.2 Focus Handling

Use:

* `FocusNode` managed by editor controller

Auto-focus rules:

| Scenario | Behavior               |
| -------- | ---------------------- |
| New note | Request focus on title |
| Existing | Restore last focus     |
| Rebuild  | Never auto-request     |

---

### 3.3.3 Input Constraints

* `maxLines: 1`
* `TextInputAction.next`
* Newline blocked at formatter level
* Emoji allowed (plain text)

---

## 3.4 Rich Text Editor Area (Flutter-Specific)

### 3.4.1 Rendering Strategy (CRITICAL)

❌ Do NOT use:

* `SelectableText.rich`
* `EditableText` directly
* HTML renderers
* Markdown widgets

✅ Use:

* Custom block renderer
* One widget per block
* Each block manages its own `TextEditingController`

---

### 3.4.2 Block Widget Contract

Each block widget must:

* Receive immutable block data
* Emit **intent events**, not mutations
* Never mutate document directly

Example events:

* `InsertText`
* `DeleteBackward`
* `SplitBlock`
* `MergeWithPrevious`
* `ToggleFormat`

---

### 3.4.3 Scroll & Keyboard Coordination

Use:

* `ScrollablePositionedList` or equivalent
* Manual scroll anchoring on cursor move

IME rules:

* Keyboard appearance must not:

  * Jump scroll
  * Hide cursor
  * Re-layout entire document

---

## 3.5 Cursor & Selection (Flutter Realities)

### 3.5.1 Cursor Model

Flutter’s `TextSelection` is **insufficient alone**.

You must maintain:

* Block ID
* Offset within block
* Selection direction

Cursor state must:

* Live outside widget
* Be restored on rebuild
* Survive IME reconnects

---

### 3.5.2 Selection Spanning Blocks

Flutter does not support this natively.

Required behavior:

* Manual selection tracking
* Manual highlight rendering
* Manual toolbar anchoring

---

## 3.6 Formatting Toolbar (Flutter Behavior)

### 3.6.1 Visibility Triggers

Driven by:

* Selection changes
* Keyboard visibility (`WidgetsBindingObserver`)
* Focus changes

Never rely on:

* `onSelectionChanged` alone (not reliable across rebuilds)

---

### 3.6.2 Action Dispatch Model

Toolbar buttons:

* Dispatch **commands**
* Never modify text directly

Example:

```
ToggleBold(
  blockId,
  startOffset,
  endOffset
)
```

Editor controller:

* Applies transformation
* Emits new document snapshot
* UI rebuilds idempotently

---

## 3.7 Metadata Panel (Flutter UX)

### 3.7.1 Presentation

* `showModalBottomSheet` (phone)
* Persistent side panel (tablet)

Must:

* Not rebuild editor
* Not steal focus unless interacting

---

### 3.7.2 State Isolation

Metadata state:

* Separate provider / cubit
* Separate persistence calls
* Independent undo domain (no undo)

Closing panel must:

* Restore previous focus
* Restore cursor
* Not trigger document re-layout

---

## 3.8 Persistence & Auto-Save (Flutter)

### 3.8.1 Write Strategy

* Write on **every mutation**
* Writes go to:

  * Local DB first
  * Sync later (background)

Use:

* Isolates for serialization
* Batched writes (but logically immediate)

---

### 3.8.2 App Lifecycle Hooks

Must handle:

* `AppLifecycleState.paused`
* `inactive`
* `detached`

On pause:

* Persist UI state
* Persist cursor
* Persist scroll offset

---

## 3.9 Undo / Redo (Flutter Safe)

Undo stack:

* Lives in controller
* Stores **operations**, not text
* Must be capped (memory safe)

Undo must not:

* Trigger keyboard flicker
* Reset focus
* Affect metadata

---

## 3.10 Exit Behavior (Flutter Navigation)

### 3.10.1 Back Handling

Use:

* `WillPopScope`

Behavior:

* Always return `true`
* Never block
* Never show dialogs

Saving already completed.

---

## 3.11 Performance Constraints (Flutter)

Must handle:

* Notes with thousands of blocks
* Zero frame drops while typing
* No rebuild of entire list on keystroke

Required optimizations:

* Block-level `const` where possible
* Keyed widgets (`ValueKey(blockId)`)
* Fine-grained listeners (Selector / Consumer)

---

## 3.12 Explicit Flutter Non-Negotiables

❌ No global mutable singletons
❌ No widget-owned document state
❌ No reliance on `build()` for logic
❌ No async logic inside render paths

✅ Controllers own logic
✅ Widgets are dumb renderers
✅ State is serializable
✅ Rebuilds are safe

---

## 3.13 Success Criteria (Flutter Edition)

The editor is correct if:

* Hot reload doesn’t break cursor
* Rotation doesn’t reset selection
* Keyboard doesn’t cause jumps
* Undo works across blocks
* App kill → restore feels invisible
* Sync never blocks typing

---


Below is a **dedicated, IME-SAFE CURSOR & SELECTION HANDLING SPEC**, written as **rules + invariants + implementation guidance**.
If you follow this, you avoid **cursor jumps, selection loss, ghost cursors, and keyboard desync** (the usual Flutter editor nightmares).

---

# 3️⃣ NOTE EDITOR — IME-SAFE CURSOR & SELECTION HANDLING (FLUTTER)

---

## 3.X Prime Rule (Non-Negotiable)

> **The IME does NOT own your cursor. Flutter does NOT own your cursor.
> Your editor controller owns the cursor.**

Flutter’s `TextSelection` is a **projection**, not the source of truth.

---

## 3.X.1 Cursor Ownership Model

### 3.X.1.1 Canonical Cursor State

Maintain a **single canonical cursor object**:

```
EditorCursor {
  blockId: String
  offset: Int
  affinity: upstream | downstream
}
```

Optional:

```
EditorSelection {
  anchor: EditorCursor
  focus: EditorCursor
}
```

Rules:

* Cursor state lives in editor controller
* Widgets receive cursor as input
* Widgets emit cursor intent events only

❌ Widgets must never store cursor as truth
❌ Never read cursor back from `TextEditingController`

---

## 3.X.2 Why Flutter Cursor Breaks (Root Cause)

Flutter IME issues arise because:

* IME can reconnect at any time
* TextEditingController may re-emit old selection
* Keyboard may send stale composing ranges
* Rebuilds reset internal EditableText state

**Therefore:**

> Any cursor coming *from Flutter* is **untrusted**.

---

## 3.X.3 IME Interaction Zones (Critical Concept)

There are **three independent systems**:

| System            | Responsibility    |
| ----------------- | ----------------- |
| IME               | Text composition  |
| Flutter           | Rendering + input |
| Editor Controller | Truth + intent    |

You must **bridge**, not merge, these systems.

---

## 3.X.4 TextEditingController Rules (MANDATORY)

### Rule 1 — Controller Lifecycle

Each block:

* Owns **one** TextEditingController
* Controller persists as long as block exists
* Never recreate controller on rebuild

Recreating controllers = **cursor loss**

---

### Rule 2 — Selection Sync Direction

**One-way synchronization only**

```
EditorController → TextEditingController
```

Never:

```
TextEditingController → EditorController
```

---

### Rule 3 — Applying Cursor to Flutter

When editor cursor changes:

```
controller.value = controller.value.copyWith(
  selection: TextSelection.collapsed(offset)
)
```

Rules:

* Apply selection only when block is focused
* Never apply during IME composing phase
* Never apply redundantly (check equality)

---

## 3.X.5 IME Composing Region Handling

### 3.X.5.1 Composing State Detection

Monitor:

```
TextEditingValue.composing
```

IME is active when:

```
composing.isValid && !composing.isCollapsed
```

---

### 3.X.5.2 Absolute Rule During Composition

> **DO NOT move the cursor during composition**

This includes:

* Formatting
* Undo
* Block splitting
* Programmatic selection changes

Allowed:

* Text insertion
* Text replacement within composing range

---

### 3.X.5.3 Composition Lock

When composing is active:

```
editorController.lockCursor()
```

Unlock only when:

* composing becomes invalid OR
* composing collapses

---

## 3.X.6 Cursor Movement Rules (IME-Safe)

### 3.X.6.1 Arrow Keys / Gestures

All cursor movement must be **intent-based**:

```
MoveCursorLeft
MoveCursorRight
MoveCursorUp
MoveCursorDown
```

Controller resolves:

* Block transitions
* Offset clamping
* Selection collapse

Never allow Flutter to auto-handle cross-block movement.

---

### 3.X.6.2 Enter Key (IME-Aware)

When Enter pressed:

If composing active:

* Let IME finish composition first

Else:

* Split block
* Create new block
* Move cursor to start of new block
* Apply cursor after frame

---

### 3.X.7 Post-Frame Cursor Application

### Rule

**All cursor applications must be post-frame**

Use:

```
WidgetsBinding.instance.addPostFrameCallback
```

Why:

* IME may override selection during frame
* Layout not stable during build

---

## 3.X.8 Preventing Cursor Jump on Rebuild

### Invariant

> Rebuilds must be *pure render operations*

Rules:

* No cursor mutation in `build`
* No controller value mutation in `build`
* Cursor only changes via explicit editor commands

---

## 3.X.9 Selection Across Blocks (IME-Safe)

Flutter cannot handle multi-block selection.

Rules:

* Disable IME selection handles for multi-block selection
* Render custom selection highlight
* Collapse to single cursor before IME input resumes

IME must only ever see:

```
collapsed selection
```

---

## 3.X.10 Toolbar Interaction Safety

Formatting actions:

1. Temporarily suspend IME
2. Apply formatting
3. Restore cursor
4. Resume IME

Never apply formatting mid-composition.

---

## 3.X.11 App Lifecycle & IME

### On Background / Pause

Persist:

* Cursor
* Selection
* Focused block

### On Resume

Restore in order:

1. Focus node
2. TextEditingController
3. Cursor (post-frame)
4. Scroll offset

---

## 3.X.12 Debugging & Instrumentation (Strongly Recommended)

Log:

* Cursor transitions
* Composing start/end
* Selection mismatches

Add assertion:

```
assert(!composingActive || !cursorMutated)
```

---

## 3.X.13 Golden Rules Summary

**DO**

* Own cursor centrally
* Respect IME composition
* Apply cursor post-frame
* Keep controllers alive
* Treat Flutter selection as output-only

**DO NOT**

* Trust Flutter cursor
* Recreate controllers
* Mutate selection in build
* Modify cursor during composition
* Let IME cross blocks

---

## 3.X.14 Success Criteria (IME Edition)

Your implementation is correct if:

✅ Cursor never jumps while typing
✅ No ghost selections
✅ Emoji & CJK input works
✅ Undo doesn’t break IME
✅ Orientation change preserves cursor
✅ Formatting doesn’t break composition

---

