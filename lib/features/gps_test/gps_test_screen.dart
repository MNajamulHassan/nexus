import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location/location_models.dart';
import '../../core/location/location_providers.dart';

class GpsTestScreen extends ConsumerStatefulWidget {
  const GpsTestScreen({super.key});

  @override
  ConsumerState<GpsTestScreen> createState() => _GpsTestScreenState();
}

class _GpsTestScreenState extends ConsumerState<GpsTestScreen> {
  bool _loading = false;
  LocationResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshLocation();
    });
  }

  Future<void> _refreshLocation() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
    });

    final result = await ref.read(locationServiceProvider).getCurrentLocation();
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _result = result;
    });
  }

  Future<void> _openSettings(Future<bool> Function() open) async {
    await open();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('GPS Test')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Location is used only while this screen is open to verify GPS. Background tracking is not enabled.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(child: _buildBody(context)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _refreshLocation,
                child: Text(_loading ? 'Reading location…' : 'Refresh Location'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return switch (_result) {
      null => const Center(child: Text('No location yet.')),
      LocationFix(:final location) => _LocationDetails(location: location),
      LocationError(:final kind, :final message) => _ErrorState(
        message: message,
        actionLabel: switch (kind) {
          LocationErrorKind.servicesDisabled => 'Open Location Settings',
          LocationErrorKind.permissionDeniedForever => 'Open App Settings',
          _ => null,
        },
        onAction: switch (kind) {
          LocationErrorKind.servicesDisabled => () {
            _openSettings(ref.read(locationServiceProvider).openLocationSettings);
          },
          LocationErrorKind.permissionDeniedForever => () {
            _openSettings(ref.read(locationServiceProvider).openAppSettings);
          },
          _ => null,
        },
      ),
    };
  }
}

class _LocationDetails extends StatelessWidget {
  const _LocationDetails({required this.location});

  final AppLocation location;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _ValueRow(label: 'Latitude', value: location.latitude.toStringAsFixed(6)),
        _ValueRow(label: 'Longitude', value: location.longitude.toStringAsFixed(6)),
        _ValueRow(
          label: 'Accuracy',
          value: location.accuracyMeters == null
              ? 'Unavailable'
              : '${location.accuracyMeters!.toStringAsFixed(1)} m',
        ),
        _ValueRow(
          label: 'Altitude',
          value: location.altitudeMeters == null
              ? 'Unavailable'
              : '${location.altitudeMeters!.toStringAsFixed(1)} m',
        ),
        _ValueRow(
          label: 'Speed',
          value: location.speedMetersPerSecond == null
              ? 'Unavailable'
              : '${location.speedMetersPerSecond!.toStringAsFixed(1)} m/s',
        ),
        _ValueRow(label: 'Timestamp', value: _formatTimestamp(location.timestamp)),
        _ValueRow(label: 'Precision', value: _precisionLabel(location.precision)),
      ],
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  String _precisionLabel(LocationPrecision precision) {
    return switch (precision) {
      LocationPrecision.precise => 'Precise',
      LocationPrecision.approximate => 'Approximate',
      LocationPrecision.unknown => 'Unknown',
    };
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off, size: 48, color: colors.error),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
