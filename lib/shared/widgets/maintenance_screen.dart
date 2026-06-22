import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Full-screen, non-dismissable maintenance notice shown when the backend sets
/// the `app.maintenanceMode` remote-config flag. Because that flag defaults to
/// false in code, only an explicit server `true` can ever surface this.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldGray,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.build_circle_outlined,
                  size: 72, color: AppTheme.brandBlue),
              const SizedBox(height: 24),
              Text(
                'Under maintenance',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                "We're making things better and will be back shortly. "
                'Please check again in a little while.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
