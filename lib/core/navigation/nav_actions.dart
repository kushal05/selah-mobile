import 'package:go_router/go_router.dart';

/// Strongly-typed navigation actions
/// Keeps navigation logic out of widgets
class NavActions {
  final GoRouter router;

  NavActions(this.router);

  void openNote(String id) => router.go('/notes/$id');
  void openPrayer(String id) => router.go('/prayers/$id');
  void openPerson(String id) => router.go('/people/$id');
  void openPromise(String id) => router.go('/promises/$id');
  void search() => router.push('/search');
  void back() => router.pop();
}
