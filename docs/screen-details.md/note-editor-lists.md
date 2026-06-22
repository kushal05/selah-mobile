Here’s a **practical, implementation-friendly rule set** you can treat as your “constitution” for lists, checkboxes, cursor behavior, and indentation. This is editor-agnostic (works whether you’re DOM-based, Slate/ProseMirror-style, or custom).

---

## 1. Core Model Rules (Foundational)

**Rule 1: Lists are blocks, items are blocks**

* A list (`ul`, `ol`, `checklist`) is a block container.
* Each list item is its own block node.
* Never mix inline content directly under a list.

**Rule 2: One paragraph per list item**

* Each list item contains **exactly one primary paragraph**.
* Nested blocks (like sublists) are allowed *after* the paragraph.

```
List
 ├─ ListItem
 │   ├─ Paragraph
 │   └─ NestedList (optional)
```

This prevents cursor bugs and weird Enter behavior.

---

## 2. Numbered Lists (Ordered Lists)

### Numbering behavior

* Numbers are **derived**, never stored.
* Recalculate on:

  * Insert
  * Delete
  * Indent / Outdent
  * Type change

### Enter key rules

* **Enter in middle of item** → split item into two
* **Enter at end of non-empty item** → new item below
* **Enter on empty item** → exit list (convert to paragraph)

### Backspace rules

* **Backspace at start of item**:

  * If nested → outdent
  * If top-level → convert to paragraph
* **Backspace in empty item** → same as above

---

## 3. Unordered Lists (Bullets)

Same behavior as ordered lists, except:

* No numbering recalculation
* Bullet style can be cosmetic (`•`, `–`, `◦`)

**Important:**
Switching between ordered ↔ unordered:

* Preserve list items
* Only change list container type
* Cursor position stays in same item

---

## 4. Checklists (Task Lists)

### Checkbox rules

* Checkbox is **not text**
* Checkbox state is metadata (`checked: true/false`)
* Cursor never enters the checkbox

### Enter behavior

* **Enter at end** → new unchecked item
* **Enter on empty item** → exit checklist
* **Enter in middle** → split, both unchecked

### Backspace behavior

* **Backspace at start**:

  * Never deletes checkbox
  * Outdent or exit list instead

### Toggle behavior

* Toggling checkbox:

  * Should not move cursor
  * Should not affect selection
  * Should not create undo noise (1 toggle = 1 undo step)

---

## 5. Cursor & Selection Rules (This is where editors usually break)

### Cursor positions

* Cursor is allowed:

  * Inside text
  * At start/end of list item text
* Cursor is NOT allowed:

  * Between list and list item
  * Between checkbox and text
  * Between bullet/number and text

### Arrow key behavior

* **Up/Down**:

  * Move between list items
  * If at top/bottom → move outside list
* **Left at start**:

  * Move to parent block or outdent
* **Right at start**:

  * Indent (if allowed)

---

## 6. Indentation Rules (Tab / Shift+Tab)

### Indent (Tab)

* Only allowed if:

  * There is a previous sibling item
* Result:

  * Becomes child of previous item
  * Keeps same list type

### Outdent (Shift+Tab)

* Moves item up one level
* If already top-level → converts to paragraph

### Mixed list types

Allowed:

```
1.
   - sub bullet
   - sub bullet
2.
```

Not allowed:

```
- bullet
   1. number (without explicit nesting)
```

(Always enforce explicit nesting)

---

## 7. Deleting & Merging Rules

### Delete at end of item

* Merge with next item
* Preserve formatting
* Never delete list container implicitly

### Delete a list container

* If last item removed:

  * Replace list with paragraph
  * Keep cursor stable

---

## 8. Copy / Paste Rules

### Pasting into a list item

* Plain text → stays in item
* Multiple lines → split into multiple items
* List content → merge intelligently:

  * Same type → flatten
  * Different type → nest or convert

### Copying partial selections

* Preserve list semantics when possible
* Fall back to plain text if structure breaks

---

## 9. Undo / Redo Rules

* One **intentional action** = one undo step
* Examples:

  * Enter → split item (1 step)
  * Tab → indent (1 step)
  * Checkbox toggle (1 step)
* Auto-reflows (renumbering) are **not** undo steps

---

## 10. Visual & UX Rules (Subtle but Critical)

* Bullets/numbers align vertically, not with text baseline
* Indentation uses consistent spacing (e.g. 24px per level)
* Checkbox hit area is larger than the checkbox icon
* Empty list items still have height (cursor visibility)

---

## 11. Absolute “Do Not Break These” Rules

❌ Never allow:

* Empty list containers
* Cursor between structural nodes
* Text nodes directly under list
* Implicit nesting
* Multiple paragraphs as first child of list item

If you enforce these invariants, **90% of editor bugs disappear**.

---

If you want next steps, I can:

* Map this to **DOM contenteditable**
* Map it to **Slate / ProseMirror**
* Give **Enter / Backspace pseudocode**
* Share a **test matrix** (key combos × states)

Just tell me how deep you want to go 👀
