Perfect choice 👍
This combo (**Drift + MongoDB Atlas + custom sync**) is *exactly* what teams building serious offline-first products end up with.

Below is a **production-grade, extremely detailed implementation document** you can **directly use for development**, schema design, and sync logic.
Think of this as your **authoritative engineering spec**.

You can save this as:

```
OFFLINE_FIRST_SYNC_SPEC.md
```

---

# 📘 OFFLINE-FIRST NOTES APP

## Drift (Local) + MongoDB Atlas (Cloud)

### Custom Sync Architecture – Full Implementation Spec

---

## 0. PRIME DIRECTIVES (READ FIRST)

These are **non-negotiable** rules that guide every decision.

1. **Local database is the single source of truth**
2. **UI never waits for the network**
3. **Every mutation is durable locally before syncing**
4. **Sync is eventual, deterministic, and replayable**
5. **No “magic” sync – everything is observable & debuggable**

If any implementation violates these → it’s wrong.

---

## 1. SYSTEM OVERVIEW

![Image](https://www.couchbase.com/blog/wp-content/uploads/2023/09/image_2023-09-18_174009809-1024x986.png)

![Image](https://i.sstatic.net/6BYBr.png)

![Image](https://stack.convex.dev/_next/image?q=75\&url=https%3A%2F%2Fcdn.sanity.io%2Fimages%2Fts10onj4%2Fproduction%2F9ed5f597d3cae3ad3e6b75d0886a9d3c2e573e45-624x330.png\&w=3840)

### High-Level Flow

```
Flutter UI
  ↓
ViewModel / State
  ↓
Repository
  ↓
Drift (SQLite)  ←── Source of Truth
  ↓
Oplog (Local)
  ↓
Sync Engine
  ↓
MongoDB Atlas
  ↑
Remote Change Stream
```

---

## 2. DATA OWNERSHIP MODEL

### Ownership Rules

| Layer      | Owns Data? | Notes                         |
| ---------- | ---------- | ----------------------------- |
| UI         | ❌          | Never                         |
| ViewModel  | ❌          | Observes only                 |
| Repository | ❌          | Orchestrates                  |
| Drift DB   | ✅          | Absolute authority            |
| MongoDB    | ❌          | Eventually consistent replica |

MongoDB is **not authoritative**.
If cloud data disagrees with local → local logic decides.

---

## 3. LOCAL DATABASE DESIGN (DRIFT)

### 3.1 Core Design Rules

1. **Every table has:**

   * `id` (stable UUID)
   * `updatedAt`
   * `version`
   * `deleted` (soft delete only)
2. **No cascading deletes**
3. **No hard deletes**
4. **All writes are transactional**

---

### 3.2 Tables Overview

| Table       | Purpose               |
| ----------- | --------------------- |
| folders     | Folder hierarchy      |
| notes       | Note metadata         |
| note_blocks | Rich content blocks   |
| oplog       | Sync intent log       |
| devices     | Device identity       |
| sync_state  | Sync cursors & status |

---

### 3.3 FOLDERS TABLE

```sql
CREATE TABLE folders (
  id TEXT PRIMARY KEY,
  parent_id TEXT NULL,
  name TEXT NOT NULL,
  user_id TEXT NOT NULL,

  updated_at INTEGER NOT NULL,
  version INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
);
```

#### Rules

* `parent_id = NULL` → root folder
* Folder name uniqueness enforced **per parent**
* Deleting a folder:

  * Sets `deleted = 1`
  * Triggers recursive soft-delete in app logic

---

### 3.4 NOTES TABLE

```sql
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  folder_id TEXT NOT NULL,
  user_id TEXT NOT NULL,

  title TEXT NOT NULL,

  updated_at INTEGER NOT NULL,
  version INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
);
```

#### Notes

* **No content stored here**
* Keeps note list fast
* Prevents massive row updates during typing

---

### 3.5 NOTE_BLOCKS TABLE (CRITICAL)

```sql
CREATE TABLE note_blocks (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,

  block_type TEXT NOT NULL,
  content_json TEXT NOT NULL,

  order_index INTEGER NOT NULL,

  updated_at INTEGER NOT NULL,
  version INTEGER NOT NULL,
  deleted INTEGER NOT NULL DEFAULT 0
);
```

#### Why block-based?

* Partial updates
* Smaller sync payloads
* Better conflict isolation

---

### 3.6 OPLOG TABLE (THE HEART)

```sql
CREATE TABLE oplog (
  op_id TEXT PRIMARY KEY,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,

  operation TEXT NOT NULL, -- INSERT | UPDATE | DELETE
  payload_json TEXT NOT NULL,

  timestamp INTEGER NOT NULL,
  device_id TEXT NOT NULL,
  synced INTEGER NOT NULL DEFAULT 0
);
```

#### Non-negotiable rules

* **Every mutation creates exactly one oplog entry**
* Oplog entries are immutable
* Never delete oplog rows (only mark synced)

---

### 3.7 SYNC_STATE TABLE

```sql
CREATE TABLE sync_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),

  last_push_ts INTEGER,
  last_pull_ts INTEGER,

  last_remote_cursor TEXT,
  sync_status TEXT
);
```

---

## 4. WRITE PATH (LOCAL FIRST)

### 4.1 Example: Editing a Note Block

```
User types
 → Editor batches input (300–500ms)
 → Drift transaction
    ├─ Update note_blocks
    ├─ Increment version
    ├─ Update updated_at
    └─ Insert oplog entry
 → UI updates immediately
```

### 4.2 Drift Transaction Example (Pseudo)

```dart
await db.transaction(() async {
  await update(noteBlocks).replace(block);
  await into(oplog).insert(opEntry);
});
```

If this fails → UI must not update.

---

## 5. SYNC ENGINE (CLIENT)

### 5.1 Sync Engine Responsibilities

1. Push unsynced oplog entries
2. Pull remote operations
3. Apply remote ops locally
4. Resolve conflicts deterministically
5. Recover from crashes safely

---

### 5.2 PUSH PHASE

#### Algorithm

```
SELECT * FROM oplog WHERE synced = 0 ORDER BY timestamp ASC
FOR EACH op:
  send to server
  on success:
    mark synced = 1
```

#### Important

* Push order **must be preserved**
* Never batch ops that affect different entities blindly

---

### 5.3 PULL PHASE

Server returns:

```json
{
  "cursor": "abc123",
  "operations": [ ... ]
}
```

Client:

* Applies ops in order
* Updates `last_remote_cursor`

---

## 6. CLOUD DATA MODEL (MONGODB)

### 6.1 Collections

| Collection   | Purpose            |
| ------------ | ------------------ |
| folders      | Folder state       |
| notes        | Note state         |
| note_blocks  | Block state        |
| operations   | Optional audit log |
| sync_cursors | Per-device cursor  |

---

### 6.2 Document Shape (Example: note_blocks)

```json
{
  "_id": "block_123",
  "noteId": "note_1",
  "blockType": "paragraph",
  "content": {...},

  "updatedAt": 1700000000,
  "version": 12,
  "deleted": false
}
```

MongoDB mirrors local schema **almost 1:1**.

---

## 7. CONFLICT RESOLUTION (MANDATORY RULES)

### 7.1 Conflict Detection

Conflict exists if:

* Same `entity_id`
* Incoming `version` ≤ local `version`

---

### 7.2 Resolution Matrix

| Scenario         | Resolution          |
| ---------------- | ------------------- |
| Update vs Update | Higher `updatedAt`  |
| Same timestamp   | Higher `version`    |
| Delete vs Update | Delete wins         |
| Folder deleted   | All children hidden |
| Block conflict   | Last writer wins    |

⚠️ **Never auto-merge rich text**

---

## 8. REAL-TIME UPDATES

### Recommended

**WebSocket + MongoDB Change Streams**

Flow:

```
MongoDB change
 → Backend emits event
 → WebSocket push to clients
 → Client triggers pull
```

Client **never trusts payload directly** – it always re-applies via sync engine.

---

## 9. BACKGROUND SYNC (FLUTTER)

### Triggers

* Connectivity restored
* App resumed
* Periodic timer (15–30 min)
* WebSocket event

### Rules

* Sync must be idempotent
* Sync must survive app kill
* Sync must not block UI

---

## 10. FAILURE & RECOVERY

### App Crash Mid-Sync

* Oplog still intact
* Resume safely

### Partial Push

* Server idempotency via `op_id`

### Schema Migration

* Local migration first
* Remote ops versioned

---

## 11. OBSERVABILITY (DO NOT SKIP)

You **must log**:

* Oplog creation
* Push success/failure
* Pull batches
* Conflict resolutions

This is what saves you in production.

---

## 12. WHAT THIS ARCHITECTURE ENABLES LATER

* CRDTs (optional)
* Web client
* Multi-user sharing
* Version history
* Attachments

No rewrite required.

---

## 13. TL;DR (EXEC SUMMARY)

✔ Drift = authoritative local store
✔ Oplog = sync intent
✔ MongoDB = eventual replica
✔ Deterministic rules > magic sync
✔ Offline works *perfectly*

---

