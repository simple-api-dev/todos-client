import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todos_client/app.dart';
import 'package:todos_client/app_state.dart';
import 'package:todos_client/key_store.dart';

// Statuses and bodies below were observed from the live API
// (see tool/live_check/REPORT.md).

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

http.Response text(String body, int status) => http.Response(body, status, headers: {'content-type': 'text/html'});

const authAnswer = {'name': 'Ann', 'email': 'ann@example.com', 'enabled': true, 'token': 'tok', 'admin': false, 'id': 42};

Map<String, Object?> todoJson(int id, String description, {bool completed = false}) =>
    {'id': id, 'user_id': 42, 'description': description, 'completed': completed ? 1 : 0, 'author': 'Ann', 'meta': null};

/// Links the app asked to open.
final opened = <String>[];

/// Pumps the whole app against a fake server and records the requests.
/// [buildKey] stands in for the key passed with --dart-define at build time.
Future<List<http.Request>> pumpApp(
  WidgetTester tester, {
  KeyStore? store,
  String buildKey = 'build-key',
  required http.Response Function(http.Request) server,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  opened.clear();
  final seen = <http.Request>[];
  final client = MockClient((r) async {
    seen.add(r);
    return server(r);
  });
  final state = AppState(store: store ?? MemoryKeyStore(), buildKey: buildKey, client: client);
  await tester.pumpWidget(TodosApp(state: state, openUrl: opened.add));
  await tester.pumpAndSettle();
  return seen;
}

/// A tiny in-memory Todos API for user 42: enough to drive the whole UI.
class FakeServer {
  FakeServer([List<Map<String, Object?>>? initial]) : todos = [...?initial];

  final List<Map<String, Object?>> todos;
  int nextId = 100;
  http.Response? failNext;

  http.Response call(http.Request r) {
    final fail = failNext;
    if (fail != null && r.url.path.startsWith('/api/users/42/')) {
      failNext = null;
      return fail;
    }
    final path = r.url.path;
    if (path == '/api/todos' && r.method == 'GET') return json([]); // the key check
    if (path == '/api/users/login' || path == '/api/users/register') return json(authAnswer);
    if (path == '/api/users/logout') return json(true);
    if (path == '/api/users/42/todos' && r.method == 'GET') return json(todos);
    if (path == '/api/users/42/todos' && r.method == 'POST') {
      final body = jsonDecode(r.body) as Map;
      final todo = todoJson(nextId++, body['description'] as String, completed: body['completed'] == true);
      todos.add(todo);
      return json({...todo, 'completed': todo['completed'] == 1}..remove('meta'));
    }
    final one = RegExp(r'^/api/users/42/todos/(\d+)$').firstMatch(path);
    if (one != null) {
      final id = int.parse(one.group(1)!);
      final i = todos.indexWhere((t) => t['id'] == id);
      if (i < 0) return json({'message': 'Todo not found ($id)'}, 404);
      if (r.method == 'PUT') {
        final body = jsonDecode(r.body) as Map;
        todos[i] = todoJson(id, body['description'] as String, completed: body['completed'] == true);
        return json({...todos[i], 'completed': body['completed'] == true}..remove('meta'));
      }
      if (r.method == 'DELETE') {
        todos.removeAt(i);
        return json({'message': 'Todo deleted ($id)'});
      }
    }
    return json({'message': 'Not a valid api route - not found.'}, 404);
  }
}

Future<void> logIn(WidgetTester tester, {bool register = false}) async {
  await tester.tap(find.text('Log in / Register'));
  await tester.pumpAndSettle();
  if (register) {
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ann');
  }
  await tester.enterText(find.widgetWithText(TextField, 'Email'), 'ann@example.com');
  await tester.enterText(find.widgetWithText(TextField, 'Password'), 'secret-pass');
  await tester.tap(find.widgetWithText(FilledButton, register ? 'Register' : 'Log in'));
  await tester.pumpAndSettle();
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens straight on the page, logged out, using the build-time key without calling anything', (tester) async {
    final seen = await pumpApp(tester, server: FakeServer().call);

    expect(find.text('Your todos'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('This demo has no key configured'), findsNothing);
    expect(seen, isEmpty);
  });

  testWidgets('without any key it explains so, links to get one, and calls nothing', (tester) async {
    final seen = await pumpApp(tester, buildKey: '', server: FakeServer().call);

    expect(find.text('This demo has no key configured'), findsOneWidget);
    expect(find.text('Log in / Register'), findsNothing);
    expect(seen, isEmpty);

    await tester.tap(find.text('Get a free key'));
    expect(opened, ['https://keys.simpleapi.dev/?product=todos']);
  });

  testWidgets('register, then the empty list is shown; every call carries the key and the right user id', (tester) async {
    final seen = await pumpApp(tester, server: FakeServer().call);
    await logIn(tester, register: true);

    expect(find.text('Hi, Ann'), findsOneWidget);
    expect(find.text('No todos yet. Add your first one above.'), findsOneWidget);
    expect(seen.map((r) => '${r.method} ${r.url.path}'), ['POST /api/users/register', 'GET /api/users/42/todos']);
    expect(seen.every((r) => r.url.queryParameters['apikey'] == 'build-key'), isTrue);
    expect(seen.last.headers['Authorization'], 'Bearer tok');
  });

  testWidgets('login shows the saved todos, completed ones struck through', (tester) async {
    final server = FakeServer([todoJson(1, 'Buy milk'), todoJson(2, 'Walk dog', completed: true)]);
    await pumpApp(tester, server: server.call);
    await logIn(tester);

    expect(find.text('Buy milk'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(0)).value, isFalse);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isTrue);
    expect(tester.widget<Text>(find.text('Walk dog')).style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('add, complete, uncomplete, edit and delete a todo', (tester) async {
    final server = FakeServer();
    final seen = await pumpApp(tester, server: server.call);
    await logIn(tester);

    // add
    await tester.enterText(find.widgetWithText(TextField, 'What needs doing?'), 'Buy milk');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
    expect(seen.last.method, 'POST');
    expect(seen.last.url.path, '/api/users/42/todos');
    expect(jsonDecode(seen.last.body)['description'], 'Buy milk');

    // complete
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(seen.last.method, 'PUT');
    expect(seen.last.url.path, '/api/users/42/todos/100');
    expect(jsonDecode(seen.last.body), {'description': 'Buy milk', 'completed': true});
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    // uncomplete
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(jsonDecode(seen.last.body)['completed'], false);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    // edit
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'Buy oat milk');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Buy oat milk'), findsOneWidget);
    expect(jsonDecode(seen.last.body), {'description': 'Buy oat milk', 'completed': false});

    // delete
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(seen.last.method, 'DELETE');
    expect(seen.last.url.path, '/api/users/42/todos/100');
    expect(find.text('Buy oat milk'), findsNothing);
    expect(find.text('No todos yet. Add your first one above.'), findsOneWidget);
  });

  testWidgets('an empty new todo is not sent', (tester) async {
    final seen = await pumpApp(tester, server: FakeServer().call);
    await logIn(tester);
    final before = seen.length;
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(seen.length, before);
  });

  testWidgets('a wrong password (404 Login Failed) reads as wrong email or password', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'Login Failed (ann@example.com)'}, 404));
    await logIn(tester);

    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.text('Hi, Ann'), findsNothing);
  });

  testWidgets('register shows the validation text for a short password (422)', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'The password must be at least 8 characters.'}, 422));
    await logIn(tester, register: true);

    expect(find.text('The password must be at least 8 characters.'), findsOneWidget);
  });

  testWidgets('registering an email twice shows the API message (400)', (tester) async {
    await pumpApp(
      tester,
      server: (r) => json({'message': 'User registration failed, email already registered to this developer account.'}, 400),
    );
    await logIn(tester, register: true);

    expect(find.textContaining('email already registered'), findsOneWidget);
  });

  testWidgets('409 (key uses an external auth service) is shown as a conflict', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'This key uses an external auth service.'}, 409));
    await logIn(tester, register: true);

    expect(find.text('Conflict: This key uses an external auth service.'), findsOneWidget);
  });

  testWidgets('429 asks the user to wait', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'Throttle Limit Exceeded'}, 429));
    await logIn(tester);

    expect(find.text('Too many requests. Wait a few seconds and try again.'), findsOneWidget);
  });

  testWidgets('the 25-todo limit (403) shows the API message and keeps the list', (tester) async {
    final server = FakeServer([todoJson(1, 'Buy milk')]);
    await pumpApp(tester, server: server.call);
    await logIn(tester);

    server.failNext = json({'message': 'Maximum number of todos (25) per user has been reached. (Basic Acct)'}, 403);
    await tester.enterText(find.widgetWithText(TextField, 'What needs doing?'), 'One too many');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Maximum number of todos (25)'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'One too many'), findsNothing); // not added to the list
    expect(find.widgetWithText(TextField, 'One too many'), findsOneWidget); // typed text is kept
  });

  testWidgets('an empty description (422) on edit shows the message', (tester) async {
    final server = FakeServer([todoJson(1, 'Buy milk')]);
    await pumpApp(tester, server: server.call);
    await logIn(tester);

    server.failNext = json({'message': 'The description field is required.'}, 422);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Description'), 'x');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('The description field is required.'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('a todo that is already gone (404) is explained', (tester) async {
    final server = FakeServer([todoJson(1, 'Buy milk')]);
    await pumpApp(tester, server: server.call);
    await logIn(tester);

    server.failNext = json({'message': 'Todo not found (1)'}, 404);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not found. It may already have been deleted.'), findsOneWidget);
  });

  testWidgets('a dead token (401 plain text) logs the user out with an explanation', (tester) async {
    final server = FakeServer([todoJson(1, 'Buy milk')]);
    await pumpApp(tester, server: server.call);
    await logIn(tester);

    server.failNext = text('Invalid Auth Token. Unauthorized.2', 401);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Your session has ended. Please log in again.'), findsOneWidget);
    expect(find.text('Your todos'), findsOneWidget); // back on the logged-out page
    expect(find.text('Log in / Register'), findsOneWidget);
  });

  testWidgets('log out posts to the API and shows the logged-out page', (tester) async {
    final server = FakeServer([todoJson(1, 'Buy milk')]);
    final seen = await pumpApp(tester, server: server.call);
    await logIn(tester);

    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(seen.last.method, 'POST');
    expect(seen.last.url.path, '/api/users/logout');
    expect(find.text('Buy milk'), findsNothing);
    expect(find.text('Your todos'), findsOneWidget);
  });

  testWidgets('forgot password: request a code, then reset with it', (tester) async {
    final seen = await pumpApp(tester, server: (r) {
      if (r.url.path == '/api/users/forgot') {
        return json({'message': 'If an account exists for that email, a reset code has been sent.'});
      }
      return json({'message': 'Password updated.'});
    });
    await tester.tap(find.text('Log in / Register'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'ann@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Set new password'), findsNothing); // step 2 appears after step 1
    await tester.tap(find.text('Email me a code'));
    await tester.pumpAndSettle();
    expect(seen.last.url.path, '/api/users/forgot');
    expect(jsonDecode(seen.last.body), {'email': 'ann@example.com'});
    expect(find.textContaining('If an account exists'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '123456');
    await tester.enterText(find.widgetWithText(TextField, 'New password'), 'new-password');
    await tester.tap(find.text('Set new password'));
    await tester.pumpAndSettle();
    expect(seen.last.url.path, '/api/users/reset');
    expect(jsonDecode(seen.last.body), {'email': 'ann@example.com', 'code': '123456', 'password': 'new-password'});
    expect(find.textContaining('Password updated. You can log in now.'), findsOneWidget);
  });

  testWidgets('a wrong reset code (400) is shown and the form stays', (tester) async {
    await pumpApp(tester, server: (r) {
      if (r.url.path == '/api/users/forgot') return json({'message': 'If an account exists for that email, a reset code has been sent.'});
      return json({'message': 'Invalid or expired reset code.'}, 400);
    });
    await tester.tap(find.text('Log in / Register'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'ann@example.com');
    await tester.tap(find.text('Email me a code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '6-digit code'), '000000');
    await tester.enterText(find.widgetWithText(TextField, 'New password'), 'new-password');
    await tester.tap(find.text('Set new password'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid or expired reset code.'), findsOneWidget);
    expect(find.text('Set new password'), findsOneWidget);
  });

  group('Settings', () {
    testWidgets('a key saved in this browser overrides the build key', (tester) async {
      final seen = await pumpApp(tester, store: MemoryKeyStore('own-key'), server: FakeServer().call);
      await logIn(tester);

      expect(seen.every((r) => r.url.queryParameters['apikey'] == 'own-key'), isTrue);
    });

    testWidgets('saving a key checks it with GET /api/todos, stores it and uses it', (tester) async {
      final store = MemoryKeyStore();
      final seen = await pumpApp(tester, store: store, server: FakeServer().call);
      await openSettings(tester);
      expect(find.textContaining('You are using the demo key this site was built with.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'API key'), 'my-key');
      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();

      expect(seen.single.method, 'GET');
      expect(seen.single.url.path, '/api/todos');
      expect(seen.single.url.queryParameters['apikey'], 'my-key');
      expect(store.read(), 'my-key');

      await logIn(tester);
      expect(seen.last.url.queryParameters['apikey'], 'my-key');
    });

    testWidgets('a rejected key (401) shows the error and is not stored', (tester) async {
      final store = MemoryKeyStore();
      await pumpApp(tester, store: store, server: (_) => json({'message': 'Request failed.  API Key not found.'}, 401));
      await openSettings(tester);
      await tester.enterText(find.widgetWithText(TextField, 'API key'), 'bad-key');
      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();

      expect(find.textContaining('The API key was not accepted'), findsOneWidget);
      expect(find.textContaining('API Key not found'), findsOneWidget);
      expect(store.read(), isNull);
    });

    testWidgets('"Go back to the demo key" forgets the saved key', (tester) async {
      final store = MemoryKeyStore('own-key');
      final seen = await pumpApp(tester, store: store, server: FakeServer().call);
      await openSettings(tester);
      expect(find.textContaining('You are using your own key.'), findsOneWidget);

      await tester.tap(find.text('Go back to the demo key'));
      await tester.pumpAndSettle();

      expect(store.read(), isNull);
      await logIn(tester);
      expect(seen.last.url.queryParameters['apikey'], 'build-key');
    });

    testWidgets('"Get a free key" opens the key page for the todos product', (tester) async {
      await pumpApp(tester, server: FakeServer().call);
      await openSettings(tester);
      await tester.tap(find.text('Get a free key'));
      expect(opened, ['https://keys.simpleapi.dev/?product=todos']);
    });
  });
}
