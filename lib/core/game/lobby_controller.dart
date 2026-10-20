import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/game.dart';
import 'game_providers.dart';
import 'lobby_realtime.dart';

final lobbyControllerProvider = AsyncNotifierProvider.autoDispose
    .family<LobbyController, LobbyView, String>(LobbyController.new);

class LobbyController extends AsyncNotifier<LobbyView> {
  LobbyController(this.gameId);

  final String gameId;

  LobbyRealtimeSubscription? _subscription;
  Timer? _debounce;
  Timer? _safety;
  LobbyRealtimeStatus _realtime = LobbyRealtimeStatus.connecting;
  bool _disposed = false;
  int _reloadEpoch = 0;

  @override
  Future<LobbyView> build() async {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _safety?.cancel();
      final subscription = _subscription;
      _subscription = null;
      unawaited(subscription?.dispose());
    });

    final snapshot = await ref.read(lobbyServiceProvider).loadLobby(gameId);
    _ensureSubscribed();
    return LobbyView(snapshot: snapshot, realtime: _realtime);
  }

  void _ensureSubscribed() {
    if (_subscription != null) {
      return;
    }

    _subscription = ref
        .read(gameRepositoryProvider)
        .subscribeLobby(
          gameId: gameId,
          onChange: _scheduleReload,
          onGameDeleted: _markCancelled,
          onStatus: _setRealtime,
        );

    _safety ??= Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_reload());
    });
  }

  void _setRealtime(LobbyRealtimeStatus status) {
    _realtime = status;
    // Must check _disposed before touching `state` at all — unsubscribing
    // the realtime channel during teardown can re-enter this callback
    // synchronously, and Riverpod asserts against any `state` access
    // (read or write) from inside that disposal call stack.
    if (_disposed) {
      return;
    }
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(realtime: status));
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    final epoch = ++_reloadEpoch;
    try {
      final snapshot = await ref.read(lobbyServiceProvider).loadLobby(gameId);
      if (_disposed || epoch != _reloadEpoch) {
        return;
      }
      state = AsyncData(
        LobbyView(snapshot: snapshot, realtime: _realtime),
      );
    } on LobbyException catch (error) {
      if (error.kind == LobbyErrorKind.cancel) {
        _markCancelled();
        return;
      }
      if (_disposed) {
        return;
      }
      state = AsyncError(error, StackTrace.current);
    }
  }

  void _markCancelled() {
    if (_disposed) {
      return;
    }
    final current = state.asData?.value;
    if (current != null) {
      state = AsyncData(current.copyWith(cancelled: true));
      return;
    }
    state = AsyncError(
      const LobbyException(
        kind: LobbyErrorKind.cancel,
        message: 'This lobby was cancelled.',
      ),
      StackTrace.current,
    );
  }

  Future<void> refresh() => _reload();

  Future<void> leave() {
    return ref.read(lobbyServiceProvider).leaveLobby(gameId);
  }

  Future<void> cancel() {
    return ref.read(lobbyServiceProvider).cancelLobby(gameId);
  }
}
