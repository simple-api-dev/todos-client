import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'key_store.dart';
import 'todos_api.dart';

/// The app's only shared state: which key is in use and who is logged in.
/// Screens listen to it with [ListenableBuilder].
///
/// The key comes from the build ([buildKey]) unless the visitor saved their
/// own in this browser's localStorage, which then takes over.
class AppState extends ChangeNotifier {
  AppState({required this.store, this.buildKey = configuredKey, this._client}) {
    final own = store.read();
    _useKey(
      own != null && own.isNotEmpty ? own : buildKey,
      own: own != null && own.isNotEmpty,
    );
  }

  final KeyStore store;
  final String buildKey;
  final http.Client? _client;

  TodosApi? _api;
  bool _usingOwnKey = false;
  String? userName;

  /// Bumped whenever the key changes so screens can reload their data.
  int keyVersion = 0;

  bool get hasKey => _api != null;
  bool get hasBuildKey => buildKey.isNotEmpty;
  bool get usingOwnKey => _usingOwnKey;
  bool get loggedIn => _api?.loggedIn ?? false;

  /// The client for the current key. Only call when [hasKey] is true.
  TodosApi get api => _api!;

  void _useKey(String key, {required bool own}) {
    _api = key.isEmpty ? null : TodosApi(apiKey: key, client: _client);
    _usingOwnKey = own;
    userName = null; // users belong to a key, so a new key means logged out
    keyVersion++;
  }

  /// Checks [key] with one real call (GET /api/todos), then remembers it in
  /// localStorage and uses it instead of the build key.
  /// Throws [ApiException] if the API rejects it.
  Future<void> useOwnKey(String key) async {
    await TodosApi(apiKey: key, client: _client).checkKey();
    store.write(key);
    _useKey(key, own: true);
    notifyListeners();
  }

  /// Forgets the saved key and goes back to the build key (if there is one).
  void useBuildKey() {
    store.clear();
    _useKey(buildKey, own: false);
    notifyListeners();
  }

  void loggedInAs(String name) {
    userName = name;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on ApiException {
      // The token was already invalid: logging out locally is all that is left.
    }
    userName = null;
    notifyListeners();
  }

  /// The API said our token is no longer valid (401 while logged in): drop it.
  void sessionExpired() {
    final api = _api;
    if (api == null || !api.loggedIn) return;
    api.token = null;
    api.userId = null;
    userName = null;
    notifyListeners();
  }
}
