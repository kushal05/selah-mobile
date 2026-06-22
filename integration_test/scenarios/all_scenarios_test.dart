import 'offline_sync_test.dart' as offline_sync;
import 'conflict_resolution_test.dart' as conflict;
import 'restart_recovery_test.dart' as restart;

/// Single entry point for all scenario integration tests.
///
/// Build once, run all 23 tests in sequence:
///   flutter test -d [device] integration_test/scenarios/all_scenarios_test.dart --flavor qa --reporter expanded
void main() {
  offline_sync.offlineSyncTests();
  conflict.conflictResolutionTests();
  restart.restartRecoveryTests();
}
