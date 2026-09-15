import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Shorthand for the generated localisations.
///
/// `l10n(context).actionCancel` rather than
/// `AppLocalizations.of(context).actionCancel` — short enough that reaching
/// for a raw string literal is no longer the path of least resistance, which
/// is what kept 1,088 of them in the code while the localisation
/// infrastructure sat unused.
AppLocalizations l10n(BuildContext context) => AppLocalizations.of(context);
