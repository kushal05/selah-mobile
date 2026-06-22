/// Offline-First Sync Layer
///
/// This module implements the complete offline-first sync architecture
/// as specified in docs/data-sync.md.
///
/// Architecture Overview:
/// ```
/// Flutter UI
///   ↓
/// ViewModel / State
///   ↓
/// Repository
///   ↓
/// Drift (SQLite)  ←── Source of Truth
///   ↓
/// Oplog (Local)
///   ↓
/// Sync Engine
///   ↓
/// MongoDB Atlas
///   ↑
/// Remote Change Stream
/// ```
///
/// Key Principles:
/// 1. Local database is the single source of truth
/// 2. UI never waits for the network
/// 3. Every mutation is durable locally before syncing
/// 4. Sync is eventual, deterministic, and replayable
/// 5. No "magic" sync – everything is observable & debuggable
library;

// Models
export 'models/sync_entity.dart';
export 'models/oplog_entry.dart';
export 'models/folder_model.dart';
export 'models/note_model.dart';
export 'models/note_block_model.dart';

// Repositories
export 'repositories/base_sync_repository.dart';
export 'repositories/folder_repository.dart';
export 'repositories/note_repository.dart';
export 'repositories/note_block_repository.dart';

// Sync Engine
export 'engine/sync_state_machine.dart';
export 'engine/sync_engine.dart';
export 'engine/conflict_resolver.dart';

// Services
export 'services/sync_api_client.dart';
export 'services/device_service.dart';

// Server Specs (for documentation)
export 'server/mongodb_schema.dart';
export 'server/sync_endpoints.dart';
