import 'package:go_router/go_router.dart';

import 'routes.dart';

/// Strongly-typed navigation actions
/// Keeps navigation logic out of widgets
class NavActions {
  final GoRouter router;

  NavActions(this.router);

  void openNote(String id) => router.go('/notes/$id');
  void openPrayer(String id) => router.go('/prayers/$id');
  void openPerson(String id) => router.go(Routes.socialPerson(id));
  void openPromise(String id) => router.go('/promises/$id');
  void search() => router.push('/search');
  void back() => router.pop();
}
