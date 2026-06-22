import 'package:flutter/material.dart';
import 'routes.dart';

/// Represents a bottom navigation bar item
class BottomNavItem {
  final String route;
  final String label;
  final IconData icon;

  const BottomNavItem(this.route, this.label, this.icon);
}

/// Bottom navigation items configuration
const bottomNavItems = [
  BottomNavItem(Routes.home, 'Home', Icons.home),
  BottomNavItem(Routes.notesHome, 'Notes', Icons.description),
  BottomNavItem(Routes.prayers, 'Prayers', Icons.favorite),
  BottomNavItem(Routes.promises, 'Promises', Icons.bookmark),
  BottomNavItem(Routes.people, 'People', Icons.people),
];
