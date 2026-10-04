import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/constants/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MapboxOptions.setAccessToken(AppEnv.mapboxAccessToken);

  if (!AppEnv.hasSupabaseConfig) {
    throw StateError(
      'Missing Supabase dart-defines. Run with '
      '--dart-define-from-file=env/dev.json '
      'and set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.',
    );
  }

  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    publishableKey: AppEnv.supabasePublishableKey,
  );

  runApp(const ProviderScope(child: NexusApp()));
}
