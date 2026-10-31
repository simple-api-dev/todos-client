/// Live check of the Todos API, using the same client the app uses.
///
///     SIMPLEAPI_KEY=<a throwaway demo key> dart run tool/live_check/live_check.dart
///
/// The key is read only from the environment and is never printed or written.
/// Test users are created with random emails and passwords, and everything
/// created (todos and users) is deleted again at the end, even after a failure.
/// Requests go out about one per second; a 429 is retried with back-off.
///
/// The results are printed as a markdown table (and written to
/// tool/live_check/results.md). This shows what was tried, not that the API is
/// free of bugs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:todos_client/todos_api.dart';

const host = 'todos.simpleapi.dev';

/// Sends every request at most once per [gap], retries 429s with back-off and
/// remembers the last answer so checks can look at the real status and body.
class PacedClient extends http.BaseClient {
  PacedClient({this.gap = const Duration(milliseconds: 1100)});

  final Duration gap;
  final http.Client _inner = http.Client();
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  int lastStatus = 0;
  String lastBody = '';
  int requests = 0;
  int throttled = 0;

  /// Non-2xx answers whose body is not JSON of the shape {"message": "..."}.
  final badErrorBodies = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final original = request as http.Request;
    for (var attempt = 0;; attempt++) {
      final wait = gap - DateTime.now().difference(_lastSent);
      if (!wait.isNegative) await Future<void>.delayed(wait);
      _lastSent = DateTime.now();
      requests++;

      final copy = http.Request(original.method, original.url)
        ..headers.addAll(original.headers)
        ..bodyBytes = original.bodyBytes;
      final response = await http.Response.fromStream(await _inner.send(copy));
      lastStatus = response.statusCode;
      lastBody = response.body;
      if (response.statusCode >= 400 && !(response.statusCode == 429 && attempt < 4)) {
        Object? j;
        try {
          j = jsonDecode(response.body);
        } on FormatException {
          j = null;
        }
        if (!(j is Map && j['message'] is String && (j['message'] as String).isNotEmpty)) {
          badErrorBodies.add('${request.method} ${request.url.path} -> ${response.statusCode}');
        }
      }

      if (response.statusCode == 429 && attempt < 4) {
        throttled++;
        final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
        final seconds = retryAfter ?? 5 * (1 << attempt);
        stdout.writeln('  (429, backing off ${seconds}s)');
        await Future<void>.delayed(Duration(seconds: seconds));
        continue;
      }
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        request: request,
        reasonPhrase: response.reasonPhrase,
      );
    }
  }
}

class Row {
  Row(this.id, this.what, this.expected, this.actual, this.pass, {this.pending = false});
  final String id, what, expected, actual;
  final bool pass;

  /// A check for a change that is merged but not deployed yet (todos PR #2):
  /// a failure is reported as PENDING and does not fail the run.
  final bool pending;
  String get result => pass ? 'PASS' : (pending ? 'PENDING' : 'FAIL');
}

final rows = <Row>[];
final random = Random.secure();
late final PacedClient client;
late final String apiKey;

String randomString(int n) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(n, (_) => chars[random.nextInt(chars.length)]).join();
}

/// Keeps emails, tokens and long ids out of the report.
String redact(String s) {
  var out = s.replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.\w+'), '<email>');
  out = out.replaceAll(RegExp(r'"token"\s*:\s*"[^"]*"'), '"token":"<token>"');
  out = out.replaceAll(RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}'), '<uuid>');
  return out.length > 170 ? '${out.substring(0, 170)}...' : out;
}

/// A short description of the last answer: status plus the (redacted) body.
String last() => 'HTTP ${client.lastStatus} ${redact(client.lastBody.trim())}'.trim();

bool is2xx() => client.lastStatus >= 200 && client.lastStatus < 300;
bool is4xx() => client.lastStatus >= 400 && client.lastStatus < 500;

Future<void> attempt(Future<Object?> Function() f) async {
  try {
    await f();
  } on ApiException {
    // the status and body are in the client's "last" fields
  }
}

/// Records one row. [expected] is what the docs say (or why they are silent);
/// [ok] decides PASS/FAIL from the last answer.
void record(String id, String what, String expected, bool Function() ok, {String? note, bool pending = false}) {
  final row = Row(id, what, expected, note ?? last(), ok(), pending: pending);
  rows.add(row);
  stdout.writeln('${row.result}  ${row.id}  ${row.what}  ->  ${row.actual}');
}

Future<http.Response> raw(
  String method,
  String path, {
  String? key,
  bool sendKey = true,
  String? token,
  String? body,
  Map<String, String>? query,
}) async {
  final uri = Uri.https(host, path, {if (sendKey) 'apikey': key ?? apiKey, ...?query});
  final r = http.Request(method, uri)..headers['Accept'] = 'application/json';
  if (token != null) r.headers['Authorization'] = 'Bearer $token';
  if (body != null) {
    r.headers['Content-Type'] = 'application/json';
    r.body = body;
  }
  return http.Response.fromStream(await client.send(r));
}

Future<void> main() async {
  final key = Platform.environment['SIMPLEAPI_KEY'] ?? '';
  if (key.isEmpty) {
    stderr.writeln('Set SIMPLEAPI_KEY to a throwaway demo key first.');
    exit(2);
  }
  apiKey = key;
  client = PacedClient();

  final api = TodosApi(apiKey: apiKey, client: client); // user A
  final apiB = TodosApi(apiKey: apiKey, client: client); // user B
  final tag = randomString(10);
  final emailA = 'simpleapi-sample-apps+a$tag@agentmail.to';
  final emailB = 'simpleapi-sample-apps+b$tag@agentmail.to';
  final passA = 'Pw-${randomString(14)}';
  final passB = 'Pw-${randomString(14)}';
  final passNew = 'Pw-${randomString(14)}';
  final createdTodos = <(TodosApi, int)>[];
  final extraUsers = <(int, String)>[]; // (id, token) of users made by a check that should have been refused
  String? oldToken;
  int keyTodosBefore = -1;

  try {
    // ---------------------------------------------------------- keys
    await attempt(() => raw('GET', '/api/todos', sendKey: false));
    record('K1', 'GET /api/todos with no apikey', '401 (key required)', () => client.lastStatus == 401);

    await attempt(() => raw('GET', '/api/todos', key: 'not-a-real-key'));
    record('K2', 'GET /api/todos with a bad apikey', '401 (key required)', () => client.lastStatus == 401);

    await attempt(() => raw('POST', '/api/users/login', sendKey: false, body: '{"email":"x@example.com","password":"abcdefgh1"}'));
    record('K3', 'POST /api/users/login with no apikey', '401 (key required)', () => client.lastStatus == 401);

    await attempt(api.checkKey);
    record('K4', 'checkKey: GET /api/todos with the demo key (Settings)', '200', () => client.lastStatus == 200);
    final before = jsonDecode(client.lastBody);
    keyTodosBefore = before is List ? before.length : -1;

    // ------------------------------------------------------- register
    await attempt(() => api.register(name: 'T', email: 'not-an-email', password: passA));
    record('R1', 'register with a malformed email', '422 (validation)', () => client.lastStatus == 422);

    await attempt(() => api.register(name: 'T', email: emailA, password: 'short'));
    record('R2', 'register with a 5-character password', '422 (validation)', () => client.lastStatus == 422);

    await attempt(() => raw('POST', '/api/users/register', body: jsonEncode({'email': emailA, 'password': passA})));
    record('R3', 'register without the required name', '422 (validation)', () => client.lastStatus == 422);

    await attempt(() => raw('POST', '/api/users/register', body: '{not json'));
    record('R4', 'register with a malformed JSON body', '400', () => client.lastStatus == 400);

    await attempt(() => raw('POST', '/api/users/register', body: jsonEncode({'name': 'T', 'email': 'nodot$tag@localhost', 'password': passA})));
    final noDot = jsonDecode(client.lastBody);
    if (is2xx() && noDot is Map && noDot['id'] is int && noDot['token'] is String) {
      extraUsers.add((noDot['id'] as int, noDot['token'] as String)); // deleted at the end
    }
    record('R7', 'register with an email without a dotted domain (name@host)', '422 (todos PR #2)', () => client.lastStatus == 422,
        pending: true);

    await attempt(() => api.register(name: 'Check A', email: emailA, password: passA));
    record('R5', 'register user A', '200 or 201 with token and id', () => (client.lastStatus == 200 || client.lastStatus == 201) && api.loggedIn);
    record('R5b', 'a successful register answers 201', '201 (todos PR #2)', () => client.lastStatus == 201, pending: true);
    final aId = api.userId;

    await attempt(() => TodosApi(apiKey: apiKey, client: client).register(name: 'Dup', email: emailA, password: passA));
    record('R6', 'register the same email again', '409', () => client.lastStatus == 409);

    // ---------------------------------------------------------- login
    await attempt(() => TodosApi(apiKey: apiKey, client: client).login(email: emailA, password: 'Wrong-${randomString(8)}'));
    record('L1', 'login with the wrong password', '401 "Invalid email or password."',
        () => client.lastStatus == 401 && jsonDecode(client.lastBody)['message'] == 'Invalid email or password.');
    final wrongPasswordBody = client.lastBody;

    await attempt(() => TodosApi(apiKey: apiKey, client: client).login(email: 'nobody-${randomString(8)}@example.com', password: passA));
    record('L2', 'login with an unknown email', '401, the same body as a wrong password (no account leak)',
        () => client.lastStatus == 401 && client.lastBody == wrongPasswordBody);

    await attempt(() => TodosApi(apiKey: apiKey, client: client).login(email: emailA, password: 'short'));
    record('L3', 'login with a 5-character password', '401 (not a 422)', () => client.lastStatus == 401);

    await attempt(() => raw('POST', '/api/users/login', body: '{}'));
    record('L4', 'login with an empty body', '422 (validation)', () => client.lastStatus == 422);

    await attempt(() => api.login(email: emailA, password: passA));
    record('L5', 'login as user A (right credentials)', '200 with token, id, name, email', () {
      final j = jsonDecode(client.lastBody);
      return client.lastStatus == 200 && j is Map && j['token'] is String && j['id'] == aId;
    });
    final loginJson = jsonDecode(client.lastBody) as Map;
    record(
      'L6',
      'login field types match the docs (enabled/admin are booleans)',
      'enabled: boolean, admin: boolean',
      () => loginJson['enabled'] is bool && loginJson['admin'] is bool,
      note: 'enabled=${loginJson['enabled'].runtimeType}, admin=${loginJson['admin'].runtimeType}',
    );

    // ---------------------------------------------------------- todos
    await attempt(api.listTodos);
    record('T1', 'listTodos for a new user', '200, empty array', () => client.lastStatus == 200 && client.lastBody.trim() == '[]');

    Todo? todo;
    await attempt(() async => todo = await api.createTodo('first todo'));
    record('T2', 'createTodo', '200 with id, description, completed (boolean)',
        () => client.lastStatus == 200 && todo != null && jsonDecode(client.lastBody)['completed'] == false);
    if (todo != null) createdTodos.add((api, todo!.id));
    final tid = todo?.id ?? -1;

    await attempt(() => api.createTodo(''));
    record('T3', 'createTodo with an empty description', '422 (description required)', () => client.lastStatus == 422);

    await attempt(() => raw('POST', '/api/users/$aId/todos', token: api.token, body: '{}'));
    record('T4', 'createTodo with no description field', '422 (description required)', () => client.lastStatus == 422);

    await attempt(() => raw('POST', '/api/users/$aId/todos', token: api.token, body: jsonEncode({'description': '   '})));
    record('T5', 'createTodo with a whitespace-only description', 'a 4xx would be sensible, docs silent', is4xx);
    final blank = jsonDecode(client.lastBody);
    if (is2xx() && blank is Map && blank['id'] is int) createdTodos.add((api, blank['id'] as int));

    Todo? uni;
    await attempt(() async => uni = await api.createTodo('Café ☕ 日本語 <b>bold</b> "quotes"'));
    record('T6', 'createTodo with unicode, HTML and quotes round-trips unchanged', '200, text unchanged',
        () => uni?.description == 'Café ☕ 日本語 <b>bold</b> "quotes"');
    if (uni != null) createdTodos.add((api, uni!.id));

    final longText = 'x' * 1000;
    Todo? long;
    await attempt(() async => long = await api.createTodo(longText));
    record('T7', 'createTodo with a 1000-character description', 'docs silent on a length limit', () => true,
        note: last());
    if (long != null) createdTodos.add((api, long!.id));

    await attempt(api.listTodos);
    record('T8', 'listTodos shows the created todos', '200, todos present', () {
      final j = jsonDecode(client.lastBody);
      return client.lastStatus == 200 && j is List && j.any((t) => t['id'] == tid);
    });
    final listed = (jsonDecode(client.lastBody) as List).cast<Map>().firstWhere((t) => t['id'] == tid, orElse: () => {});
    record('T9', 'completed is a boolean in list answers (docs: boolean)', 'completed: boolean', () => listed['completed'] is bool,
        note: 'completed=${listed['completed']} (${listed['completed'].runtimeType})');

    await attempt(() => api.updateTodo(tid, description: 'first todo', completed: true));
    record('U1', 'updateTodo: complete', '200, completed true', () => client.lastStatus == 200 && jsonDecode(client.lastBody)['completed'] == true);

    await attempt(() => api.updateTodo(tid, description: 'first todo', completed: false));
    record('U2', 'updateTodo: uncomplete', '200, completed false', () => client.lastStatus == 200 && jsonDecode(client.lastBody)['completed'] == false);

    await attempt(() => api.updateTodo(tid, description: 'first todo, edited', completed: false));
    record('U3', 'updateTodo: edit the text', '200, new text', () => client.lastStatus == 200 && jsonDecode(client.lastBody)['description'] == 'first todo, edited');

    await attempt(() => api.updateTodo(tid, description: '', completed: false));
    record('U4', 'updateTodo with an empty description', '422 (description required)', () => client.lastStatus == 422);

    await attempt(() => raw('GET', '/api/users/$aId/todos/$tid', token: api.token));
    record('U5', 'GET one todo (not used by the app)', '200, the todo', () => client.lastStatus == 200 && jsonDecode(client.lastBody)['description'] == 'first todo, edited');

    await attempt(() => api.updateTodo(999999999, description: 'x', completed: false));
    record('U6', 'updateTodo on a todo that does not exist', '404', () => client.lastStatus == 404);

    await attempt(() => api.deleteTodo(999999999));
    record('D1', 'deleteTodo on a todo that does not exist', '404', () => client.lastStatus == 404);

    await attempt(() => raw('GET', '/api/users/$aId/todos/999999999', token: api.token));
    record('D2', 'GET a todo that does not exist', '404', () => client.lastStatus == 404);

    await attempt(() => api.deleteTodo(tid));
    record('D3', 'DELETE /api/users/{id}/todos/{id}, the path the Swagger page now documents', '200', () => client.lastStatus == 200);

    await attempt(() => raw('POST', '/api/users/$aId/todos', token: api.token, body: '{not json'));
    record('D4', 'createTodo with a malformed JSON body', '400', () => client.lastStatus == 400);

    await attempt(() => raw('GET', '/api/users/me', token: api.token));
    record('G1', 'GET /api/users/me returns the token\'s user, no password, no token', '200 (todos PR #2)', () {
      final j = jsonDecode(client.lastBody);
      return client.lastStatus == 200 && j is Map && j['id'] == aId && !j.containsKey('password') && !j.containsKey('token');
    }, pending: true);

    // the todo D3 deleted is created again so the cross-user checks below have one to attack
    Todo? again;
    await attempt(() async => again = await api.createTodo('first todo, edited'));
    if (again != null) createdTodos.add((api, again!.id));
    final tid2 = again?.id ?? -1;

    // ---------------------------------------------- missing / bad token
    await attempt(() => raw('GET', '/api/users/$aId/todos'));
    record('A1', 'list todos with no Authorization header', '401', () => client.lastStatus == 401);

    await attempt(() => raw('GET', '/api/users/$aId/todos', token: 'not-a-token'));
    record('A2', 'list todos with a garbage token', '401', () => client.lastStatus == 401);

    // ------------------------------------------------ someone else's todo
    await attempt(() => apiB.register(name: 'Check B', email: emailB, password: passB));
    record('O1', 'register user B', '200 with token and id', () => client.lastStatus == 200 && apiB.loggedIn);
    final bId = apiB.userId;

    await attempt(() => raw('GET', '/api/users/$bId/todos/$tid2', token: apiB.token));
    record('O2', "user B reads user A's todo (B's own id in the path)", '403 or 404', () => client.lastStatus == 403 || client.lastStatus == 404);

    await attempt(() => apiB.updateTodo(tid2, description: 'hijacked', completed: true));
    record('O3', "user B edits user A's todo", '403 or 404', () => client.lastStatus == 403 || client.lastStatus == 404);

    await attempt(() => apiB.deleteTodo(tid2));
    record('O4', "user B deletes user A's todo", '403 or 404', () => client.lastStatus == 403 || client.lastStatus == 404);

    await attempt(api.listTodos);
    record('O5', "user A's todo is unchanged after B's attempts", '200, text unchanged and still there', () {
      final j = jsonDecode(client.lastBody);
      return j is List && j.any((t) => t['id'] == tid2 && t['description'] == 'first todo, edited');
    });

    await attempt(apiB.listTodos);
    record("O6", "user B's list does not contain A's todos", '200, empty array', () => client.lastBody.trim() == '[]');

    // a user_id in the path that is not the token's user is a plain 403
    await attempt(() => raw('GET', '/api/users/$aId/todos', token: apiB.token));
    record('M1', "user B lists user A's todos with A's id in the path", '403 {message}', () => client.lastStatus == 403);

    await attempt(() => raw('DELETE', '/api/users/$aId/todos/$tid2', token: apiB.token));
    record('M2', "user B deletes user A's todo with A's id in the path", '403 {message}', () => client.lastStatus == 403);

    await attempt(() => raw('GET', '/api/users/999999999/todos', token: apiB.token));
    record('M3', 'a user_id that does not exist in the path', '403 {message}', () => client.lastStatus == 403);

    await attempt(api.listTodos);
    record('M4', "user A's todo survived the mismatched deletes", '200, still there',
        () => (jsonDecode(client.lastBody) as List).any((t) => t['id'] == tid2));

    // ---------------------------------------------------- per-user limit
    stdout.writeln('  (filling user A up to the documented limit of 25 todos)');
    await attempt(api.listTodos);
    var count = (jsonDecode(client.lastBody) as List).length;
    var refused = false;
    while (count < 27 && !refused) {
      try {
        final t = await api.createTodo('filler ${count + 1}');
        createdTodos.add((api, t.id));
        count++;
      } on ApiException {
        refused = true;
      }
    }
    final refusal = last();
    await attempt(api.listTodos);
    final serverCount = (jsonDecode(client.lastBody) as List).length;
    record('X1', 'create todos beyond the documented limit of 25 per user', 'the 26th todo is refused (4xx); the list holds 25',
        () => refused && serverCount == 25,
        note: refused ? '$refusal; the server lists $serverCount todos' : 'no refusal up to $count todos; the server lists $serverCount');

    // ------------------------------------------------------------ logout
    oldToken = api.token;
    await attempt(api.logout);
    record('S1', 'logout', '200', () => client.lastStatus == 200);

    await attempt(() => raw('GET', '/api/users/$aId/todos', token: oldToken));
    record('S2', 'list todos with the token from before logout', '401', () => client.lastStatus == 401);

    await attempt(() => raw('POST', '/api/users/logout', token: oldToken));
    record('S3', 'logout again with the same (dead) token', 'a 4xx or a harmless 200, docs silent', () => client.lastStatus < 500);

    await attempt(() => api.login(email: emailA, password: passA));
    record('S4', 'login again after logout', '200 with a new token', () => client.lastStatus == 200 && api.loggedIn && api.token != oldToken);

    // ------------------------------------------------- password reset
    await attempt(() => api.forgotPassword(emailA));
    record('F1', 'forgot password for a real user (request half only)', '200 "request accepted"', () => client.lastStatus == 200);

    await attempt(() => api.forgotPassword('nobody-${randomString(8)}@example.com'));
    record('F2', 'forgot password for an unknown email', '200, same answer as a real one (no account leak)', () => client.lastStatus == 200);

    await attempt(() => api.forgotPassword('not-an-email'));
    record('F3', 'forgot password with a malformed email', '422', () => client.lastStatus == 422);

    await attempt(() => api.resetPassword(email: emailA, code: '000000', password: passNew));
    record('F4', 'reset with a wrong 6-digit code (never the real one)', '400 invalid or expired code', () => client.lastStatus == 400);

    await attempt(() => api.resetPassword(email: emailA, code: '000000', password: 'short'));
    record('F5', 'reset with a wrong code and a too-short password', '400 or 422', () => client.lastStatus == 400 || client.lastStatus == 422);

    await attempt(() => api.login(email: emailA, password: passA));
    record('F6', 'the old password still works after the failed resets', '200', () => client.lastStatus == 200);
  } catch (e, st) {
    stdout.writeln('ABORTED: ${redact('$e')}\n$st');
    rows.add(Row('ABORT', 'the run stopped early', 'completes', redact('$e'), false));
  } finally {
    // ----------------------------------------------------------- cleanup
    stdout.writeln('Cleaning up...');
    for (final (owner, id) in createdTodos) {
      try {
        if (owner.loggedIn) await owner.deleteTodo(id);
      } on ApiException {
        // already gone
      }
    }
    for (final (id, token) in extraUsers) {
      await attempt(() => raw('DELETE', '/api/users/$id', token: token));
      record('CX', 'cleanup: delete a user a check created by mistake', '200', () => client.lastStatus == 200);
    }
    for (final (name, u) in [('A', api), ('B', apiB)]) {
      if (!u.loggedIn || u.userId == null) continue;
      final id = u.userId;
      await attempt(() => raw('DELETE', '/api/users/$id', token: u.token));
      record('C$name', 'cleanup: delete user $name (DELETE /api/users/{id})', '200', () => client.lastStatus == 200);
      await attempt(() => raw('GET', '/api/users/$id/todos', token: u.token));
      record('C${name}2', 'cleanup: the deleted user $name\'s token no longer works', '401', () => client.lastStatus == 401);
    }
    try {
      await attempt(() => TodosApi(apiKey: apiKey, client: client).checkKey());
      final after = jsonDecode(client.lastBody);
      final n = after is List ? after.length : -2;
      record('CZ', 'the key holds the same number of key-level todos as at the start', 'equal', () => n == keyTodosBefore,
          note: 'before=$keyTodosBefore, after=$n');
    } catch (_) {}
    record('E1', 'every error answer in the whole run was JSON {"message": "..."}', 'none that was not',
        () => client.badErrorBodies.isEmpty,
        note: client.badErrorBodies.isEmpty ? 'all of them were' : client.badErrorBodies.take(5).join('; '));
  }

  // ------------------------------------------------------------ results
  final b = StringBuffer()
    ..writeln('| # | Check | Expected per docs | Actual | Result |')
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final r in rows) {
    String cell(String s) => s.replaceAll('|', '\\|').replaceAll('\n', ' ');
    b.writeln('| ${r.id} | ${cell(r.what)} | ${cell(r.expected)} | ${cell(r.actual)} | ${r.result} |');
  }
  b
    ..writeln()
    ..writeln('${client.requests} requests sent, ${client.throttled} answered with 429 and retried.');
  File('tool/live_check/results.md').writeAsStringSync(b.toString());
  stdout.writeln('\n$b');
  exit(rows.any((r) => !r.pass && !r.pending) ? 1 : 0);
}
