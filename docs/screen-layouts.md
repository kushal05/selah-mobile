--

# 📘 APPLICATION DESIGN SPECIFICATION

**(Screen-by-Screen, Depth-First, Implementation-Ready)**

---

# 0. GLOBAL DESIGN PRINCIPLES (Applies to ALL Screens)

These rules are **non-negotiable** and must be followed everywhere.

## 0.1 Interaction Philosophy

* Every screen must answer **one primary user intent**
* No screen should mix **creation + analytics + management**
* Editing is always **explicit**, never accidental
* Navigation is **predictable, reversible, and shallow**

## 0.2 Data Handling

* All data is **offline-first**
* UI never blocks on network
* Every user action:

  1. Writes locally
  2. Updates UI immediately
  3. Syncs asynchronously

## 0.3 Action Semantics

* **Tap** = Navigate or Open
* **Long press** = Secondary actions
* **Swipe** = Contextual action (never destructive without confirmation)

---

# 1️⃣ DASHBOARD SCREEN (App Entry Point)

## Purpose

This screen **does not manage data**.
It **orients the user emotionally and contextually**.

---

## 1.1 Screen Layout (Top → Bottom)

---

### 1.1.1 Header Section

**Contains**

* App title or greeting (e.g., “Good Morning”)
* Current date (human-readable)
* Sync status indicator (subtle)

**Behavior**

* Sync indicator:

  * Green → fully synced
  * Grey → offline
  * Yellow → syncing
* Tapping sync indicator opens **Sync Status Sheet** (read-only)

---

### 1.1.2 Daily Focus Card (Primary Card)

**Purpose**
Direct the user to *what matters today*.

**Content Priority (first available wins)**

1. Today’s scheduled prayers
2. Most recently updated prayer
3. Recently edited note
4. Highlighted promise (fallback)

**Elements**

* Title (dynamic)
* Context subtitle (e.g., “Scheduled for today”)
* Primary CTA button

**Action**

* CTA navigates directly to the **relevant detail screen**
* If prayer → opens Prayer Detail
* If note → opens Note Editor
* If promise → opens Promise Detail

---

### 1.1.3 Quick Actions Row

**Buttons**

* New Note
* New Prayer
* New Promise
* New Person

**Behavior**

* Tap → Opens respective **Create Screen**
* Create screens always open empty and focused
* Back navigation returns to Dashboard (state preserved)

---

### 1.1.4 Summary Cards Section

Each card is **read-only** and **navigational**.

#### Notes Summary Card

* Total notes count
* Last edited note title
* Last modified time

**Tap**
→ Notes Home (Folder Explorer)

---

#### Promises Summary Card

* Total promises
* Count of promises with conditions

**Tap**
→ Promises List

---

#### Prayers Summary Card

* Active prayers count
* Today’s prayers count

**Tap**
→ Prayer Dashboard

---

#### People Summary Card

* Total people count
* Most recently prayed-for person

**Tap**
→ People List

---

### 1.1.5 Recent Activity Feed (Condensed)

**Displays**

* Last 5–7 events:

  * Prayer logged
  * Prayer updated
  * Note edited
  * Promise updated

**Item Tap**
→ Navigates to corresponding detail

**“View All”**
→ Full Updates Feed

---

## 1.2 Empty States

* New user → Guided welcome dashboard
* No data → Encouraging CTA cards
* Offline → Banner only, no blocking

---

# 2️⃣ NOTES HOME / FOLDER EXPLORER

## Purpose

Primary navigation surface for notes.

---

## 2.1 Screen Structure

### 2.1.1 Header

* Current folder name
* Breadcrumb path (scrollable)
* Add (+) button

**Add Button**

* Tap → Bottom sheet:

  * New Folder
  * New Note

---

### 2.1.2 Folder Tree Section

**Folder Items**

* Folder icon
* Name
* Expand/collapse chevron

**Tap**

* Expands folder
* Updates note list

**Long Press**

* Rename
* Move
* Delete (soft)

---

### 2.1.3 Notes List Section

**Note Row**

* Title
* Metadata preview (date/tags if present)
* Last modified timestamp

**Tap**
→ Note Editor

**Swipe**

* Move
* Delete (soft)

---

## 2.2 Folder Actions Behavior

### Create Folder

* Prompt for name
* Validation: unique within parent
* Appears instantly

### Delete Folder

* Confirmation dialog
* Soft delete recursively
* Folder hidden immediately

---

# 3️⃣ NOTE EDITOR SCREEN

## Purpose

Focused writing environment.

---

## 3.1 Screen Composition

### 3.1.1 Title Field

* Single line
* Mandatory
* Auto-focus on new note

---

### 3.1.2 Rich Text Editor Area

**Supports**

* Heading levels
* Paragraphs
* Lists
* Checkboxes

**Behavior**

* Cursor-based editing
* Undo/redo stack
* Block-aware navigation

---

### 3.1.3 Formatting Toolbar (Contextual)

**Appears**

* On text selection
* Or keyboard open

**Actions**

* Bold
* Italic
* Underline
* Strikethrough
* List toggles

**Action Effect**

* Applies to selected range only
* Preserves block structure

---

### 3.1.4 Metadata Panel (Collapsible)

**Fields**

* Date picker
* Preacher selector
* Tag selector

**Behavior**

* Independent save
* No cursor loss
* Changes update filters instantly

---

## 3.2 Exit Behavior

* Back → auto save
* No explicit save button
* Conflict handled by versioning

---

# 4️⃣ PROMISES LIST SCREEN

## Purpose

Manage and browse promises.

---

## 4.1 Layout

### 4.1.1 Header

* “Promises”
* Add (+)

---

### 4.1.2 Promise Cards

**Card Contains**

* Verse reference
* Promise excerpt
* Tag chips

**Tap**
→ Promise Detail

---

# 5️⃣ PROMISE DETAIL SCREEN

## Purpose

Deep reflection on a promise.

---

## 5.1 Sections

### Promise Header

* Verse
* Tags

---

### Promise Content

* Full promise text
* Optional explanation

---

### Conditions Section

* List of conditions

**Condition Item**

* Description
* Status badge

**Tap**
→ Edit Condition

---

### Add Condition

* Inline or modal
* Saves immediately

---

# 6️⃣ PRAYER DASHBOARD (Module Home)

## Purpose

Prayer-focused command center.

---

## 6.1 Daily Prayers Section

**Prayer Item**

* Title
* Log Prayer button

**Log Prayer**

* Creates immutable log
* Marks as completed for today

---

## 6.2 Category Cards

Each card navigates to filtered lists:

* Current
* Answered
* Archived
* People
* Articles
* Logs
* Updates Feed

---

# 7️⃣ PRAYER DETAIL SCREEN

## Purpose

Single prayer lifecycle management.

---

## 7.1 Header

* Title
* Status badge

---

## 7.2 Description

* Rich text
* Editable

---

## 7.3 Linked People

* List of people
* Add/remove action

---

## 7.4 Updates Section

* Chronological updates
* Add Update opens editor

---

## 7.5 Log History (Read-Only)

* Timestamped entries
* Immutable

---

## 7.6 Actions

* Log Prayer
* Mark Answered
* Archive

Each action:

* Updates status
* Writes log if applicable
* Immediate UI update

---

# 8️⃣ PEOPLE LIST SCREEN

## Purpose

Centralized people database.

---

## 8.1 Person Row

* Name
* Relation
* Tags

**Tap**
→ Person Detail

---

# 9️⃣ PERSON DETAIL SCREEN

## Purpose

Single person context.

---

## 9.1 Sections

* Personal info
* Tags
* Linked prayers list

**Tap Prayer**
→ Prayer Detail

---

# 10️⃣ GLOBAL SEARCH SCREEN

## Purpose

Cross-entity discovery.

---

## 10.1 Search Behavior

* Instant results
* Grouped by entity

**Tap Result**
→ Entity detail

---

# 11️⃣ TAG MANAGEMENT SCREEN

## Purpose

Global taxonomy control.

---

## 11.1 Tag Row

* Name
* Usage count

**Actions**

* Rename
* Merge
* Tap → filtered search

---

# 12️⃣ PRAYER ARTICLES SCREENS

## Article List

* Categories
* Search

## Article Detail

* Read-only content
* Copy to Note
* Copy to Prayer

---

# 13️⃣ SYSTEM SCREENS

## Confirmation Dialogs

* Always explicit
* No destructive defaults

## Offline Banner

* Informational only