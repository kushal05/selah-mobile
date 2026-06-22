
Below is a **depth-first, pixel-level, interaction-level specification** for the **Notes List Page**, aligned with your **offline-first + folder hierarchy + rich notes model**  .

I’ll structure this as:

1. **Recommended Layout (Why this layout wins)**
2. **Top-Level Screen Anatomy**
3. **FIRST HALF — Folder Section (Deep dive)**
4. **SECOND HALF — Notes List Section (Deep dive)**
5. **Cross-Section Interactions**
6. **Drill-Down & Dependent Screens (Folder → Notes → Note)**
7. **Edge Cases, States, and Performance Rules**

---

## 1️⃣ Recommended Layout (Best-in-class choice)

### ✅ **Vertical Split Layout (Scrollable + Scrollable)**

```
┌─────────────────────────────┐
│ Top App Bar                 │
├─────────────────────────────┤
│ Folder List (Scrollable)    │  ← ~45–50% height
├─────────────────────────────┤
│ Notes List (Scrollable)     │  ← ~50–55% height
└─────────────────────────────┘
```

### Why this is optimal

* **Matches mental model**: “Where am I?” (folder) → “What’s inside?” (notes)
* **One-hand usability** (mobile)
* **No horizontal gestures** → fewer gesture conflicts
* **Scales to tablets** (can later become side-by-side)

> ⚠️ Do **NOT** use tabs or a drawer here — folders are *content*, not navigation.

---

## 2️⃣ Top-Level Screen Anatomy

![Image](https://thesweetsetup.com/wp-content/uploads/2023/10/Smart-Folders-Apple-Notes-5.png)

![Image](https://notedaisy.com/wp-content/uploads/2025/06/column-layout-1024x819.png)

![Image](https://media.idownloadblog.com/wp-content/uploads/2022/09/Create-new-folder-in-iPhone-Notes-app.png)

![Image](https://cdsassets.apple.com/live/7WUAS350/images/ios/ios-16-iphone-14-pro-notes-create-smart-folder.png)

### A. Top App Bar (Persistent)

**Height:** 56dp
**Elevation:** 0–2dp (flat, content-first)

**Elements (left → right):**

1. **App Title**

   * Text: `Notes`
   * Dynamically changes to selected folder name when drilled in
   * Truncated with ellipsis if long

2. **Search Icon**

   * Opens full-screen global search
   * Scope defaults to:

     * Current folder + subfolders

3. **Overflow Menu**

   * Sort notes
   * Change view density (Compact / Comfortable)
   * Select mode (bulk actions)

---

## 3️⃣ FIRST HALF — Folder Section (EXTREMELY DETAILED)

### 3.1 Folder Section Container

* **Height:** 45–50% of screen
* **Scroll behavior:** Independent vertical scroll
* **Background:** Slightly elevated surface (distinguish from notes)
* **Sticky header inside section**

---

### 3.2 Folder Section Header (Sticky)

**Always visible while scrolling folders**

**Elements:**

* **Title:** `Folders`
* **Count badge:** `(12)`
* **“+ Folder” icon button**

  * Opens *Create Folder* bottom sheet
  * Disabled during multi-select mode

---

### 3.3 Folder List Item (Atomic Unit)

Each folder row is a **stateful, hierarchical cell**.

**Height:** 48–56dp
**Padding:** 12dp horizontal

#### Left cluster

* Folder icon

  * Closed folder (default)
  * Open folder (if selected)
* Nesting indentation

  * 12–16dp per depth level
  * Visual hierarchy without tree lines (clean)

#### Center

* Folder name (single line)
* Subtext (optional, smaller text):

  * `8 notes`
  * Or `3 folders • 12 notes`

#### Right cluster

* Expand / collapse chevron (only if has children)
* More actions (⋮) — appears on long-press or hover

---

### 3.4 Folder Interactions

#### Tap

* Selects folder
* Updates **Notes List** below
* Highlights folder row
* Expands children inline (if collapsed)

#### Long-press

* Enters **Folder Selection Mode**
* Enables:

  * Rename
  * Move
  * Delete (soft)
* Multi-select allowed

#### Drag & Drop

* Reorder within same parent
* Drag into another folder to change parent
* Auto-expand folder on hover (600ms delay)

---

### 3.5 Folder Empty & Edge States

| State           | Behavior                    |
| --------------- | --------------------------- |
| No folders      | Show Root only              |
| Folder deleted  | Instantly hidden            |
| Sync conflict   | Show ⚠️ icon (tap for info) |
| Large hierarchy | Lazy render children        |

---

## 4️⃣ SECOND HALF — Notes List Section (EXTREMELY DETAILED)

### 4.1 Notes Section Header (Sticky)

**Elements:**

* Title:

  * `All Notes` (root)
  * or `Notes in “Sermons”`
* Notes count
* Sort control:

  * Last edited (default)
  * Title (A–Z)
  * Created date

---

### 4.2 Notes List Behavior

* **Data source:** Realm query filtered by:

  * `folderId == selectedFolder OR descendant`
* **Pagination:** Implicit (lazy list)
* **Recomposition-safe**

---

### 4.3 Note List Item (Atomic Unit)

**Height:** 72–88dp
**Shape:** Slight rounded rectangle
**Clickable surface:** Entire card

#### Top row

* Note title (bold)
* Last modified timestamp (right-aligned)

#### Middle row

* Content preview (1–2 lines)
* Rich text rendered as plain preview
* Truncated with fade

#### Bottom row (optional)

* Tags (chips)
* Metadata icons (date, preacher, etc.)

---

### 4.4 Note Interactions

#### Tap

* Opens **Note Editor Screen**
* Passes:

  * `noteId`
  * `folderContext`
* Navigation preserves scroll position

#### Long-press

* Multi-select mode
* Bulk actions:

  * Move
  * Delete
  * Add tags

#### Swipe (optional)

* Swipe right → quick archive
* Swipe left → quick delete (confirm)

---

### 4.5 Notes Empty States

| Scenario            | UI                             |
| ------------------- | ------------------------------ |
| No notes in folder  | “No notes yet” + Create button |
| Folder just created | Auto-focus CTA                 |
| Syncing             | Skeleton loaders               |
| Deleted note        | Removed instantly              |

---

## 5️⃣ Cross-Section Interactions

### Folder → Notes coupling rules

* Folder selection **never navigates**
* It only updates the lower half
* Notes scroll resets to top on folder change
* Notes scroll position preserved per folder (in memory)

---

## 6️⃣ Drill-Down & Dependent Screens

### 6.1 Create / Edit Folder (Bottom Sheet)

**Triggered from:**

* * Folder
* Folder overflow → Rename

**Fields:**

* Folder name
* Parent folder selector

**Actions:**

* Save → Realm write → UI updates immediately
* Cancel → No-op

---

### 6.2 Notes List → Note Editor Screen

**Navigation:**

* Full screen
* Back returns to same folder + scroll

**Receives:**

* `noteId`
* `isNew`
* `folderId`

---

### 6.3 Folder Drill-Down (Optional Deep Mode)

If user taps folder title in App Bar:

* Navigates to **Folder Detail Screen**
* Shows:

  * Folder metadata
  * Subfolders full screen
  * Notes list full screen

(Used mainly on tablets or power users)

---

## 7️⃣ Performance, State & Offline Rules

### Must-follow rules

* UI **never waits for network**
* Folder + Notes queries are **local Realm only**
* Deletions are **soft + instant**
* Sync conflicts never block UI

### Scroll & Memory

* Independent LazyLists
* No nested LazyColumn inside LazyColumn
* Stable keys everywhere

---
