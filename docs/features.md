---

# 📘 Application Feature Specification

**Domain:** Notes, Promises, Prayers
**Audience:** Product, Design, Engineering
**Purpose:** Define user-facing functionality and data expectations in detail

---

## 1. Notes Module

### 1.1 Overview

The **Notes module** is a structured, rich-text note-taking system designed to organize content hierarchically and semantically.
It supports folders, metadata, formatting, and structured content similar to a modern note editor.

---

### 1.2 Folder Hierarchy

#### Features

* Users can create **folders** to organize notes.
* Folders support **unlimited nesting depth**.
* Each folder can contain:

  * Notes
  * Sub-folders
* Folder names must be unique **within the same parent folder**.

#### Functional Requirements

* Create folder
* Rename folder
* Move folder (drag & drop or move action)
* Delete folder (soft delete)
* Restore deleted folder (optional)
* Reorder folders within the same level

#### Rules

* Deleting a folder affects all child folders and notes.
* Root folder always exists and cannot be deleted.

---

### 1.3 Notes

#### Core Properties

Each note must have:

* **Title** (mandatory, plain text)
* **Content** (rich text)
* **Folder association**
* **Last modified timestamp**

---

### 1.4 Rich Text Content Structure

#### Block Types

The note editor must support:

* Heading (multiple levels, e.g. H1, H2, H3)
* Sub-heading
* Normal paragraph text
* Bulleted list
* Numbered list
* Checkbox list (task list)

#### Inline Formatting

* Bold
* Italics
* Underline
* Strikethrough

Formatting must be:

* Applicable to partial text selections
* Preserved during editing and syncing
* Undoable / redoable

---

### 1.5 Note Metadata

Each note can optionally contain structured metadata:

| Field    | Description                                 |
| -------- | ------------------------------------------- |
| Date     | Custom date (e.g., sermon date, event date) |
| Preacher | Person associated with the note             |
| Tags     | User-defined labels for categorization      |

#### Metadata Behavior

* Metadata is editable independently of note content.
* Tags are reusable across notes.
* Notes can be filtered and searched by metadata.

---

## 2. Promises & Conditions Module

### 2.1 Overview

This module is designed to capture **biblical or spiritual promises** along with their **associated conditions and reflections**.

---

### 2.2 Promise Entity

Each promise must contain:

* **Verse / Reference**
* **Promise text**
* **Optional notes or explanation**
* **Tags**

---

### 2.3 Conditions

Each promise can have **one or more conditions**.

#### Condition Properties

* Condition description
* Notes or commentary
* Optional status (e.g., fulfilled, ongoing)

#### Relationships

* One promise → many conditions
* Conditions are not standalone; they belong to a promise

---

### 2.4 Usage Scenarios

* Study and reflection
* Tracking spiritual commitments
* Linking promises to prayers or notes (future enhancement)

---

## 3. Prayers Module

### 3.1 Overview

The **Prayers module** is a structured prayer management system with tracking, reminders, people association, and history logging.

---

### 3.2 People Database

A **separate People database** exists to avoid duplication.

#### Person Entity Fields

* Name
* Relation (family, friend, church member, etc.)
* Church (optional)
* Tags

#### Behavior

* A person can be linked to multiple prayers.
* Editing a person updates all linked prayers.

---

### 3.3 Prayer Entity

Each prayer must include the following fields:

| Field         | Description                   |
| ------------- | ----------------------------- |
| Title         | Short summary of the prayer   |
| Status        | Active, Answered, Archived    |
| Reminder      | Date/time based reminder      |
| Tags          | Reusable labels               |
| Last Updated  | Auto-updated timestamp        |
| Description   | Main prayer content           |
| Linked People | References to People database |
| Updates       | User-added updates/comments   |
| Log History   | System-generated prayer logs  |

---

### 3.4 Prayer Page (Detail View)

Each prayer page must provide actions to:

* Log Prayer

  > Marks that the user prayed for this item at a specific time
* Add Update

  > Free-text update (reflection, progress, testimony)
* Archive Prayer
* Mark Prayer as Answered
* Add / Remove linked people
* Edit prayer details

#### Log History

* Each prayer log entry contains:

  * Timestamp
  * Optional note
* Logs are immutable once created

---

### 3.5 Prayer Homepage (Dashboard)

The main prayer screen must include the following sections:

#### 1. Daily Prayers

* List of prayers scheduled for today
* Each prayer has a **“Log Prayer”** button
* Once logged, the prayer:

  * Is marked as completed for the day
  * Disappears or is visually checked off

#### 2. Prayer Categories (Card Layout)

* Current Prayers
* Answered Prayers
* Archived Prayers
* People
* Starter Prayer Content
* Prayer Log History
* All Updates (feed-style timeline)

---

### 3.6 Updates & Feed

* All prayer updates appear in a global feed
* Sorted by most recent
* Can be filtered by:

  * Prayer
  * Person
  * Tag

---

## 5. Songs Module

### 5.1 Overview

The **Songs module** is a structured system for managing **song lyrics and musical annotations (chords)**.
It is designed for **searchability, organization, and reuse**, and integrates tightly with the existing **Notes and Folder architecture**.

Songs are treated as a **specialized note type**, inheriting folder hierarchy, tags, search, and offline behavior, while introducing **song-specific content modes**.

---

### 5.2 Folder Hierarchy for Songs

#### Features

* Songs are organized using the **same folder hierarchy system** as Notes.
* Folders support **unlimited nesting depth**.
* Each folder can contain:

  * Songs
  * Sub-folders
* Folder hierarchy may be used to organize songs by:

  * Language (e.g., English, Telugu, Hindi)
  * Song books / collections (e.g., Hymns, Worship Sets)
  * Custom user-defined groupings

#### Rules

* Folder names must be unique **within the same parent folder**.
* Deleting a folder:

  * Soft-deletes all contained songs
  * Soft-deletes all child folders recursively
* Root folder always exists and cannot be deleted.

---

### 5.3 Song Entity

Each song must include the following core properties:

| Field              | Description                                  |
| ------------------ | -------------------------------------------- |
| Title              | Mandatory, plain text                        |
| Folder Association | The folder in which the song is stored       |
| Lyrics Content     | Textual song lyrics                          |
| Chords Content     | Optional chord annotations aligned to lyrics |
| Language           | Primary language of the song                 |
| Tags               | User-defined labels for categorization       |
| Last Modified      | Auto-updated timestamp                       |

---

### 5.4 Song Content Modes

Each song supports **two distinct content modes**, which are stored and managed independently.

#### 1. Lyrics Mode

* Contains **clean, plain-text lyrics**
* Preserves:

  * Line breaks
  * Verse/chorus structure
* No rich-text formatting is required
* Intended for:

  * Reading
  * Projection
  * Sharing

---

#### 2. Chords Mode

* Contains lyrics with **inline chord annotations**
* Chords are visually rendered **above the corresponding lyric text**
* Chords do **not modify the underlying lyrics**
* Intended for:

  * Practice
  * Instrumental reference
  * Musical preparation

---

### 5.5 Song Metadata

Each song supports structured metadata:

| Field      | Description                                |
| ---------- | ------------------------------------------ |
| Language   | Primary language of the song               |
| Tags       | Reusable labels (shared across the app)    |
| Book       | Optional collection or songbook identifier |
| Has Chords | Indicates presence of chord annotations    |

#### Metadata Behavior

* Metadata is editable independently of song content
* Tags are reusable across:

  * Songs
  * Notes
  * Prayers
  * Promises
* Metadata fields are indexed for search and filtering

---

### 5.6 Song List & Browsing

#### Song List Behavior

* Songs are listed within the selected folder
* Default sorting:

  * Title (A–Z)
* Each song row displays:

  * Song title
  * Language
  * Tag indicators
  * Chords availability indicator

#### Multi-Select Actions

* Move songs to another folder
* Delete songs (soft delete)
* Bulk tag assignment

---

### 5.7 Song Search & Filter

#### Search Capabilities

Search supports querying across:

* Song title
* Lyrics content
* Chord annotations (optional)
* Tags
* Language

---

#### Filter Options

Users can filter songs using:

| Filter Type     | Description                       |
| --------------- | --------------------------------- |
| Folder          | Restrict to a folder or subtree   |
| Language        | One or more languages             |
| Tags            | One or more tags                  |
| Lyrics Contains | Text match within lyrics          |
| Has Chords      | Only songs with chord annotations |

---

### 5.8 Song Viewing & Actions

#### Song Viewing Modes

* Lyrics-only view
* Lyrics + chords view
* Fullscreen / distraction-free mode

#### Actions Available

* Edit song
* Move song to another folder
* Duplicate song
* Soft delete song
* Share lyrics (text-only)

---

## 6. Cross-Cutting Features

### 6.1 Tags

* Tags are shared across:

  * Notes
  * Promises
  * Prayers
  * Songs
  * People
* Central tag management
* Ability to rename or merge tags

---

### 6.2 Search

* Global search across:

  * Notes
  * Prayers
  * People
  * Promises
  * Songs
* Supports:

  * Full-text search
  * Tag-based filtering
  * Metadata-based filtering

---

### 6.3 Audit & History

* Prayers maintain a detailed history
* Notes may maintain version history (optional future feature)
* Songs track last-modified timestamps for sync and conflict resolution

---

## 7. Non-Functional Expectations

* Offline-first usage
* Fast navigation even with large datasets
* Consistent UX patterns across modules
* Clean separation of structured data vs free text
* Song search and filtering must function offline

---

## 8. Explicit Non-Goals (For Now)

* Real-time collaboration
* Public sharing
* Attachments (images, audio, PDFs)
* Cross-user prayer or song sharing
* Audio playback or recording

---

If you want, next we can:

* Convert **Songs** into a **data schema**
* Add **navigation + screen inventory**
* Add **exact editor behavior rules (lyrics vs chords parsing)**
* Produce a **single “authoritative spec” markdown**

Just tell me the next step.


# New Features:

✝️ Faith-Centric Feature Specifications

This section defines Bible references, daily prayer flow, sharing & collaboration, social graph, and church communities in a way that is offline-first, scalable, and consistent with the existing Notes & Prayers architecture.

1️⃣ Bible References Inside Notes
1.1 Purpose

Allow users to insert Bible verses directly into notes in a structured, searchable, and reusable way—without breaking the writing flow.

The feature must:

Be fast and keyboard-first

Support multiple Bible versions

Preserve verse metadata (not just plain text)

Work fully offline after initial data availability

1.2 Trigger Mechanism
Symbol Trigger

Typing @ inside the note editor opens a contextual Bible Reference Picker

Trigger works:

At beginning of a line

After whitespace

Inside paragraphs (inline insertion)

Popup Behavior

Appears as a bottom sheet / floating modal

Does not block the editor completely

Dismissible by:

Escape

Backspace (if @ is removed)

Tapping outside

1.3 Bible Reference Selection Flow

The picker is step-wise and stateful:

Step 1: Book Selection

List all Bible books (Genesis → Revelation)

Supports:

Search by name (Gen, John, 1 Cor)

Old Testament / New Testament tabs

Selection advances automatically

Step 2: Chapter Selection

Numeric list or scroll wheel

Shows valid chapter range for the selected book

Step 3: Verse Selection

Supports:

Single verse (e.g., John 3:16)

Verse range (e.g., John 3:16–18)

Verse preview (first few words per verse)

Step 4: Version Selection

Default version is user-configured (e.g., NIV, ESV, KJV)

User can override per insertion

App remembers last used version

1.4 Insertion Behavior

Once confirmed, the editor inserts a Bible Reference Block.

Visual Representation (Editable View)
📖 John 3:16 (NIV)
“For God so loved the world…”


Reference line is bold and tappable

Verse text is read-only inside the block

Block can be:

Moved

Deleted

Copied

1.5 Data Model (Conceptual)

Bible references are not plain text.

Each inserted reference stores:

Book

Chapter

Verse start

Verse end (optional)

Bible version

Verse text snapshot

Source ID (for updates / re-fetch)

This allows:

Re-rendering with a different version

Linking references across notes

Global Bible verse search

1.6 Offline Behavior

Bible text is cached locally once used

If verse text is unavailable offline:

Insert reference metadata

Mark text as “Pending download”

Auto-fill when online

1.7 Editing & Management

Tapping the reference opens:

Change version

Expand verse range

Replace with another reference

Long-press options:

Copy verse text only

Copy reference only

Remove reference

2️⃣ “Pray Today” – Unified Daily Prayer Flow
2.1 Purpose

Create a single, uninterrupted daily prayer experience that eliminates switching between prayer items.

This feature answers:

“What exactly should I pray for today?”

2.2 Pray Today Button
Location

Prominently placed on:

Prayer home/dashboard

Today view

Always visible

Label

“Pray Today”

2.3 What Happens on Click

The system generates a Daily Prayer Page by merging:

All prayers with daily recurrence

All new prayers created today

Any prayers explicitly marked as “Include today”

This generation is:

Deterministic

Cached for the day

Immutable once started (to preserve focus)

2.4 Daily Prayer Page Structure
Header

Date (e.g., Tuesday, March 12)

Prayer count

Progress indicator (e.g., 3 / 12 completed)

Prayer List (Sequential)

Each prayer appears as a full expandable card:

Title

Description

Linked people

Tags

Previous updates (collapsed by default)

2.5 Logging Flow (Critical)

Each prayer card has a “Log Prayer” action.

When tapped:

A log entry is created with:

Timestamp

Optional short note

The prayer is visually marked as completed

The UI automatically scrolls to the next unprayed item

No confirmation dialogs.
No interruptions.

2.6 Completion Behavior

When all prayers are logged:

Show a gentle completion screen:

“You’ve completed today’s prayers”

Option to:

Review logs

Add a reflection

Exit

2.7 Edge Cases

If no prayers qualify:

Show an empty-state with encouragement

If app closes mid-session:

Resume exactly where the user left off

3️⃣ Shareable & Collaborative Prayers
3.1 Purpose

Enable shared prayer life without losing personal ownership.

3.2 Sharing Model

A prayer can be marked as:

Private (default)

Shared

Shared prayers generate a shareable reference, not a copy.

3.3 Permissions

Each shared prayer supports roles:

Owner

Collaborator

Viewer

Permissions control:

Editing prayer text

Logging prayers

Adding updates

3.4 Collaboration Behavior

All collaborators see:

Prayer content

Updates

Logs (with author attribution)

Logs are per-user

Updates are shared

3.5 Offline & Conflict Handling

Changes sync using last-write-wins

Logs are append-only (never conflicted)

If conflict occurs:

Preserve both updates

Flag for review

4️⃣ Friends Feature (Username-Based)
4.1 Purpose

Create a lightweight social graph without contacts or phone numbers.

4.2 Usernames

Each user has a unique, permanent username

Case-insensitive

Used for:

Search

Mentions

Sharing

4.3 Adding Friends
Methods

Search by username

Accept / reject friend requests

4.4 Friend Capabilities

Friends can:

Share prayers

Invite to groups

Mention in prayer updates

Friends cannot see private notes or prayers.

4.5 Privacy

Users can:

Disable friend requests

Block users

Remove friends silently

5️⃣ Church Community Groups
5.1 Purpose

Support church-level spiritual collaboration while keeping personal data safe.

5.2 Group Types

Church groups

Ministry groups

Small groups / cell groups

5.3 Group Structure

Each group contains:

Name

Description

Admins

Members

Shared prayers

Announcements (optional)

5.4 Membership

Invite-only or open join

Roles:

Admin

Member

5.5 Group Prayers

Group prayers behave like shared prayers

Each member logs prayer independently

Aggregate completion stats (optional)

5.6 Notes & Content Scope

Group content is isolated

Leaving a group removes access

No retroactive data access