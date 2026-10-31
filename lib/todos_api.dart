/// The whole Todos API client. Every network call in the app is in this file.
///
/// Docs: https://todos.simpleapi.dev/docs
///
/// Two rules apply to every request:
///  * the developer key goes in the `apikey` QUERY parameter (never a header);
///  * a logged-in user also sends `Authorization: Bearer <token>`, where the
///    token comes from [TodosApi.register] / [TodosApi.login].
///
/// The todo calls used here are the per-user ones (`/api/users/{user_id}/...`).
/// The `{user_id}` is always the logged-in user's own id, taken from the
/// register / login answer, never typed in or guessed.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown for any non-2xx answer. [message] is the API's own text,
/// e.g. "Request failed.  API Key not found."
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class Todo {
  const Todo({required this.id, required this.description, required this.completed});

  final int id;
  final String description;
  final bool completed;

  /// `completed` is a real boolean on every route.
  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: (json['id'] as num).toInt(),
      description: '${json['description'] ?? ''}',
      completed: json['completed'] == true,
    );
  }
}

/// What login / register answer with. [token] is null only for a 2xx answer
/// that carried no token.
class AuthResult {
  const AuthResult({this.token, this.id, this.name = '', this.message = ''});

  final String? token;
  final int? id;
  final String name;
  final String message;
}

class TodosApi {
  TodosApi({
    required this.apiKey,
    this.token,
    this.userId,
    http.Client? client,
    this.host = 'todos.simpleapi.dev',
  }) : _http = client ?? http.Client();

  final String apiKey;
  final String host;

  /// Set after [login] / [register]; sent as the Bearer token.
  String? token;

  /// The logged-in user's own id; used in every `/api/users/{user_id}/...` path.
  int? userId;

  final http.Client _http;

  bool get loggedIn => token != null && userId != null;

  // ------------------------------------------------------------------ users

  /// POST /api/users/register - create a user that belongs to this key and log
  /// in as it. The API allows at most 10 users per key, passwords of 8+
  /// characters and an email with a dotted domain. A new user answers 201
  /// (older deployments answered 200; both are accepted). An email that is
  /// already registered answers 409.
  Future<AuthResult> register({required String name, required String email, required String password}) async {
    final json = await _send('POST', '/api/users/register', body: {'name': name, 'email': email, 'password': password});
    return _authResult(json);
  }

  /// POST /api/users/login - returns the user's id, name and a token. A wrong
  /// email or password answers 401 "Invalid email or password.".
  Future<AuthResult> login({required String email, required String password}) async {
    final json = await _send('POST', '/api/users/login', body: {'email': email, 'password': password});
    return _authResult(json);
  }

  /// POST /api/users/logout - invalidates the current token.
  Future<void> logout() async {
    try {
      await _send('POST', '/api/users/logout');
    } finally {
      token = null;
      userId = null;
    }
  }

  AuthResult _authResult(Map<String, dynamic> json) {
    final t = json['token'];
    final id = json['id'];
    if (t is String && t.isNotEmpty && id is num) {
      token = t;
      userId = id.toInt();
      return AuthResult(token: t, id: userId, name: '${json['name'] ?? ''}');
    }
    return AuthResult(message: '${json['message'] ?? 'No token was returned.'}');
  }

  /// POST /api/users/forgot - emails a 6-digit reset code. The answer is the
  /// same whether or not the address has an account.
  Future<String> forgotPassword(String email) async {
    final json = await _send('POST', '/api/users/forgot', body: {'email': email});
    return '${json['message'] ?? 'If an account exists for that email, a reset code has been sent.'}';
  }

  /// POST /api/users/reset - sets a new password using the emailed code.
  Future<String> resetPassword({required String email, required String code, required String password}) async {
    final json = await _send('POST', '/api/users/reset', body: {'email': email, 'code': code, 'password': password});
    return '${json['message'] ?? 'Password updated.'}';
  }

  // ------------------------------------------------------------------- keys

  /// GET /api/todos - needs only the key. Used by Settings as a one-call check
  /// that a pasted key is accepted (a bad key answers 401).
  Future<void> checkKey() async {
    await _send('GET', '/api/todos');
  }

  // ------------------------------------------------------------------ todos
  // Everything below needs a logged-in user (Bearer token).

  /// GET /api/users/{user_id}/todos - the logged-in user's todos.
  Future<List<Todo>> listTodos() async {
    final json = await _send('GET', '$_userPath/todos');
    return [for (final t in (json['_list'] as List? ?? const [])) Todo.fromJson(t as Map<String, dynamic>)];
  }

  /// POST /api/users/{user_id}/todos - add a todo (a user may have 25; the
  /// 26th is refused with 403).
  Future<Todo> createTodo(String description, {bool completed = false}) async {
    final json = await _send('POST', '$_userPath/todos', body: {'description': description, 'completed': completed});
    return Todo.fromJson(json);
  }

  /// PUT /api/users/{user_id}/todos/{id} - change the text and/or the
  /// completed flag. `description` is required on every update.
  Future<Todo> updateTodo(int id, {required String description, required bool completed}) async {
    final json = await _send('PUT', '$_userPath/todos/$id', body: {'description': description, 'completed': completed});
    return Todo.fromJson(json);
  }

  /// DELETE /api/users/{user_id}/todos/{id} - delete one of your todos.
  Future<void> deleteTodo(int id) async {
    await _send('DELETE', '$_userPath/todos/$id');
  }

  String get _userPath {
    final id = userId;
    if (id == null) throw ApiException(401, 'Please log in first.');
    return '/api/users/$id';
  }

  // ---------------------------------------------------------------- plumbing

  /// Sends one request and returns the decoded JSON. A JSON array is wrapped
  /// as `{'_list': [...]}` so every caller gets a Map; a bare boolean (the API
  /// answers `true` to logout) becomes `{}`.
  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.https(host, path, {'apikey': apiKey});
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers.addAll({if (token != null) 'Authorization': 'Bearer $token'});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } catch (e) {
      throw ApiException(0, 'Could not reach $host ($e)');
    }

    final text = response.body.trim();
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        // Every API answer is JSON. Anything else (a proxy's error page, say)
        // gets the generic message below.
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, _errorMessage(response.statusCode, decoded));
    }
    if (decoded is List) return {'_list': decoded};
    if (decoded is Map<String, dynamic>) return decoded;
    return {};
  }

  /// Every error from the API is JSON: `{"message": "..."}`.
  String _errorMessage(int status, Object? decoded) {
    if (decoded is Map) {
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return 'Request failed (HTTP $status).';
  }
}
