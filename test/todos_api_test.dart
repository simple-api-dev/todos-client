import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todos_client/todos_api.dart';

// A made-up value: the tests never touch the real API or a real key.
const fakeKey = 'test-key';

// Statuses and bodies below were observed from the live API
// (see tool/live_check/REPORT.md).

/// Builds an API whose HTTP client answers with [handler] and records requests.
(TodosApi, List<http.Request>) apiWith(
  http.Response Function(http.Request) handler, {
  String? token,
  int? userId,
}) {
  final seen = <http.Request>[];
  final client = MockClient((request) async {
    seen.add(request);
    return handler(request);
  });
  return (TodosApi(apiKey: fakeKey, token: token, userId: userId, client: client), seen);
}

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

http.Response text(String body, int status) => http.Response(body, status, headers: {'content-type': 'text/html'});

/// A logged-in API for user 42.
(TodosApi, List<http.Request>) loggedIn(http.Response Function(http.Request) handler) =>
    apiWith(handler, token: 'tok', userId: 42);

void main() {
  test('sends the key as the apikey query parameter, not as a header', () async {
    final (api, seen) = apiWith((_) => json([]));
    await api.checkKey();

    final r = seen.single;
    expect(r.method, 'GET');
    expect(r.url.host, 'todos.simpleapi.dev');
    expect(r.url.path, '/api/todos');
    expect(r.url.queryParameters['apikey'], fakeKey);
    expect(r.headers.containsKey('Authorization'), isFalse);
    expect(r.headers.values.any((v) => v.contains(fakeKey)), isFalse);
  });

  test('login stores the token and the user id, and later calls use both', () async {
    final (api, seen) = apiWith((r) {
      if (r.url.path == '/api/users/login') {
        // Real login answer: enabled/admin are 0/1 here, not booleans.
        return json({'id': 456, 'name': 'Check A', 'email': 'a@example.com', 'enabled': 1, 'token': 'tok-1', 'admin': 0, 'warnings': 0, 'external_id': null});
      }
      return json([]);
    });
    final result = await api.login(email: 'a@example.com', password: 'secret-pass');
    expect(result.token, 'tok-1');
    expect(result.id, 456);
    expect(result.name, 'Check A');
    expect(jsonDecode(seen.single.body), {'email': 'a@example.com', 'password': 'secret-pass'});

    await api.listTodos();
    final r = seen.last;
    expect(r.url.path, '/api/users/456/todos'); // always the user's own id
    expect(r.headers['Authorization'], 'Bearer tok-1');
  });

  test('register sends name, email and password and logs in', () async {
    final (api, seen) = apiWith((_) => json({'name': 'Check A', 'email': 'a@example.com', 'enabled': true, 'token': 'tok-r', 'admin': false, 'id': 456}));
    final result = await api.register(name: 'Check A', email: 'a@example.com', password: 'secret-pass');

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/users/register');
    expect(jsonDecode(seen.single.body), {'name': 'Check A', 'email': 'a@example.com', 'password': 'secret-pass'});
    expect(result.token, 'tok-r');
    expect(api.loggedIn, isTrue);
    expect(api.userId, 456);
  });

  test('a 2xx answer without a token is reported, not treated as a login', () async {
    final (api, _) = apiWith((_) => json({'message': 'Check your email'}));
    final result = await api.login(email: 'a@example.com', password: 'secret-pass');
    expect(result.token, isNull);
    expect(result.message, 'Check your email');
    expect(api.loggedIn, isFalse);
  });

  test('logout posts and forgets the token even when the API refuses', () async {
    final (api, seen) = loggedIn((_) => json(true)); // the API answers `true`
    await api.logout();
    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/users/logout');
    expect(api.token, isNull);
    expect(api.userId, isNull);

    final (api2, _) = loggedIn((_) => text('Invalid Auth Token. Unauthorized.2', 401));
    await expectLater(api2.logout(), throwsA(isA<ApiException>()));
    expect(api2.loggedIn, isFalse);
  });

  test('listTodos parses the list; completed arrives as 0/1 on reads', () async {
    final (api, seen) = loggedIn((_) => json([
          {'id': 3260, 'user_id': 42, 'description': 'first todo', 'completed': 0, 'author': 'Check A', 'meta': null},
          {'id': 3261, 'user_id': 42, 'description': 'second', 'completed': 1, 'author': 'Check A', 'meta': null},
        ]));
    final todos = await api.listTodos();

    expect(seen.single.method, 'GET');
    expect(seen.single.url.path, '/api/users/42/todos');
    expect(todos.map((t) => t.id), [3260, 3261]);
    expect(todos.map((t) => t.completed), [false, true]);
    expect(todos.first.description, 'first todo');
  });

  test('createTodo posts the description and parses the boolean answer', () async {
    final (api, seen) = loggedIn((_) => json({'description': 'first todo', 'completed': false, 'user_id': 42, 'author': 'Check A', 'id': 3260}));
    final todo = await api.createTodo('first todo');

    expect(seen.single.method, 'POST');
    expect(seen.single.url.path, '/api/users/42/todos');
    expect(jsonDecode(seen.single.body), {'description': 'first todo', 'completed': false});
    expect(todo.id, 3260);
    expect(todo.completed, isFalse);
  });

  test('updateTodo puts the description and the completed flag', () async {
    final (api, seen) = loggedIn((_) => json({'id': 3260, 'user_id': 42, 'description': 'first todo', 'completed': true, 'author': 'Check A'}));
    final todo = await api.updateTodo(3260, description: 'first todo', completed: true);

    expect(seen.single.method, 'PUT');
    expect(seen.single.url.path, '/api/users/42/todos/3260');
    expect(jsonDecode(seen.single.body), {'description': 'first todo', 'completed': true});
    expect(todo.completed, isTrue);
  });

  test('deleteTodo uses /todos/{id}, not the /todo/{id} the Swagger page shows', () async {
    final (api, seen) = loggedIn((_) => json({'message': 'Todo deleted (3260)'}));
    await api.deleteTodo(3260);

    expect(seen.single.method, 'DELETE');
    expect(seen.single.url.path, '/api/users/42/todos/3260');
  });

  test('forgot and reset post the right bodies', () async {
    final (api, seen) = apiWith((r) => r.url.path.endsWith('forgot')
        ? json({'message': 'If an account exists for that email, a reset code has been sent.'})
        : json({'message': 'Password updated.'}));

    expect(await api.forgotPassword('a@example.com'), startsWith('If an account exists'));
    expect(seen.last.url.path, '/api/users/forgot');
    expect(jsonDecode(seen.last.body), {'email': 'a@example.com'});

    await api.resetPassword(email: 'a@example.com', code: '123456', password: 'new-password');
    expect(seen.last.url.path, '/api/users/reset');
    expect(jsonDecode(seen.last.body), {'email': 'a@example.com', 'code': '123456', 'password': 'new-password'});
  });

  test('todo calls without a login fail locally, without any request', () async {
    final (api, seen) = apiWith((_) => json([]));
    await expectLater(api.listTodos(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
    expect(seen, isEmpty);
  });

  group('errors, as the live API really answers', () {
    Future<ApiException> failing(http.Response response) async {
      final (api, _) = loggedIn((_) => response);
      try {
        await api.listTodos();
      } on ApiException catch (e) {
        return e;
      }
      fail('expected an ApiException');
    }

    test('401 missing key: JSON message', () async {
      final e = await failing(json({'message': 'Unauthorized.  Please provide a valid apikey.  Visit todos.simpleapi.dev/get-key for your free apikey today.'}, 401));
      expect(e.statusCode, 401);
      expect(e.message, startsWith('Unauthorized.  Please provide a valid apikey'));
    });

    test('401 bad token: plain text, not JSON', () async {
      final e = await failing(text('Invalid Auth Token. Unauthorized.2', 401));
      expect(e.statusCode, 401);
      expect(e.message, 'Invalid Auth Token. Unauthorized.2');
    });

    test('404: a bare JSON string', () async {
      final e = await failing(http.Response('"Todo 999999999 not found."', 404));
      expect(e.statusCode, 404);
      expect(e.message, 'Todo 999999999 not found.');
    });

    test('404 on update: a JSON message', () async {
      final e = await failing(json({'message': 'Todo not found (3260)'}, 404));
      expect(e.message, 'Todo not found (3260)');
    });

    test('403: the per-user todo limit', () async {
      final e = await failing(json({'message': 'Maximum number of todos (25) per user has been reached. (Basic Acct)'}, 403));
      expect(e.statusCode, 403);
      expect(e.message, contains('Maximum number of todos (25)'));
    });

    test('422: validation message', () async {
      final e = await failing(json({'message': 'The description field is required.'}, 422));
      expect(e.statusCode, 422);
      expect(e.message, 'The description field is required.');
    });

    test('429 and an empty body fall back to a generic message', () async {
      final e = await failing(http.Response('', 429));
      expect(e.statusCode, 429);
      expect(e.message, 'Request failed (HTTP 429).');
    });
  });

  test('a network failure becomes an ApiException with status 0', () async {
    final api = TodosApi(apiKey: fakeKey, client: MockClient((_) async => throw http.ClientException('offline')));
    await expectLater(api.checkKey(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 0)));
  });
}
