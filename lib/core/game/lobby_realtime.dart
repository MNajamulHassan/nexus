typedef LobbyRealtimeDispose = Future<void> Function();

class LobbyRealtimeSubscription {
  LobbyRealtimeSubscription(this._dispose);

  final LobbyRealtimeDispose _dispose;
  bool _closed = false;

  Future<void> dispose() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _dispose();
  }
}
