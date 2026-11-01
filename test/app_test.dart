import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todos_client/app.dart';
import 'package:todos_client/app_state.dart';

// All HTTP is mocked; nothing here calls the real API.

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

http.Response text(String body, int status) => http.Response(body, status, headers: {'content-type': 'text/html'});

const authAnswer = {
  'token': 'tok',
  'expires_at': '2026-12-01T03:47:06Z',
  'user': {
    'id': 42,
    'name': 'Ann',
    'email': 'ann@example.com',
    'admin': false,
    'enabled': true,
    'created_at': '2026-11-01T03:47:06Z',
    'updated_at': '2026-11-01T03:47:06Z',
  },
};

Map<String, Object?> todoJson(int id, String description, {bool completed = false}) => {
  'id': id,
  'user_id': 42,
  'description': description,
  'completed': completed,
  'author': 'Ann',
  'meta': null,
  'created_at': '2026-11-01T03:47:06Z',
  'updated_at': '2026-11-01T03:47:06Z',
};

/// One page of a list, as every list answers.
Map<String, Object?> page(List<Object?> rows) => {'data': rows, 'total': rows.length, 'page': 1, 'per_page': 25};

/// Links the app asked to open.
final opened = <String>[];

/// Pumps the whole app against a fake server and records the requests.
/// [buildKey] stands in for the key passed with --dart-define at build time.
Future<List<http.Request>> pumpApp(
  WidgetTester tester, {
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
  final state = AppState(apiKey: buildKey, client: client);
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
    if (path == '/api/users/login') return json(authAnswer);
    if (path == '/api/users/register') return json(authAnswer, 201);
    if (path == '/api/users/logout') return json({'message': 'Logged out.'});
    if (path == '/api/users/42/todos' && r.method == 'GET') return json(page(todos));
    if (path == '/api/users/42/todos' && r.method == 'POST') {
      final body = jsonDecode(r.body) as Map;
      final todo = todoJson(nextId++, body['description'] as String, completed: body['completed'] == true);
      todos.add(todo);
      return json(todo, 201);
    }
    final one = RegExp(r'^/api/users/42/todos/(\d+)$').firstMatch(path);
    if (one != null) {
      final id = int.parse(one.group(1)!);
      final i = todos.indexWhere((t) => t['id'] == id);
      if (i < 0) return json({'message': 'Todo not found ($id)'}, 404);
      if (r.method == 'PUT') {
        // only the fields sent change
        todos[i] = {...todos[i], ...(jsonDecode(r.body) as Map<String, Object?>)};
        return json(todos[i]);
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

void main() {
  testWidgets('opens straight on the page, logged out, using the build-time key without calling anything', (
    tester,
  ) async {
    final seen = await pumpApp(tester, server: FakeServer().call);

    expect(find.text('Your todos'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(seen, isEmpty);
  });

  testWidgets('the landing screen makes the demo account the main action and shows the demo notice', (tester) async {
    await pumpApp(tester, server: FakeServer().call);

    expect(find.widgetWithText(FilledButton, 'Try the demo account'), findsOneWidget);
    expect(find.byKey(const Key('demo-notice')), findsOneWidget);
    expect(
      find.text('This is a shared demo. Data resets every night. Do not use a real password or any private details.'),
      findsOneWidget,
    );
  });

  testWidgets('"Try the demo account" logs in as the demo user in one click and shows their list', (tester) async {
    final server = FakeServer([todoJson(1, 'Water the plants', completed: true)]);
    final seen = await pumpApp(tester, server: server.call);

    await tester.tap(find.text('Try the demo account'));
    await tester.pumpAndSettle();

    final login = seen.firstWhere((r) => r.url.path == '/api/users/login');
    expect(jsonDecode(login.body), {'email': 'demo@simpleapi.dev', 'password': 'try-the-demo'});
    expect(login.headers.containsKey('Authorization'), isFalse);
    expect(find.text('Water the plants'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('the log in screen also offers the demo account and shows the demo notice', (tester) async {
    final server = FakeServer([todoJson(1, 'Water the plants')]);
    await pumpApp(tester, server: server.call);
    await tester.tap(find.text('Log in / Register'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('demo-notice')), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Try the demo account'));
    await tester.pumpAndSettle();

    expect(find.text('Water the plants'), findsOneWidget);
  });

  testWidgets('the register screen shows the demo notice', (tester) async {
    await pumpApp(tester, server: FakeServer().call);
    await tester.tap(find.text('Log in / Register'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('demo-notice')), findsOneWidget);
  });

  testWidgets('a failed demo login shows the API message', (tester) async {
    await pumpApp(tester, server: (_) => json({'message': 'Invalid email or password.'}, 401));
    await tester.tap(find.text('Try the demo account'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid email or password.'), findsOneWidget);
  });

  testWidgets('the back arrow opens the SimpleAPI home page, with a tooltip', (tester) async {
    await pumpApp(tester, server: FakeServer().call);

    expect(find.byTooltip('Back to SimpleAPI'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to SimpleAPI'));
    expect(opened, ['https://simpleapi.dev']);
  });

  testWidgets('at 360px wide the app bar shows the full title and fits its actions, logged out and in', (tester) async {
    await pumpApp(tester, server: FakeServer().call);
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();

    // The test font is about twice as wide as Roboto, so this checks the layout (no overflow, nothing cut
    // off) rather than exact widths. In Roboto the title is about 137px and leaves room for the actions.
    expect(find.text('SimpleAPI Todos'), findsOneWidget);
    expect(find.text('Log in / Register'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Try the demo account'));
    await tester.pumpAndSettle();
    expect(find.text('SimpleAPI Todos'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('register, then the empty list is shown; every call carries the key and the right user id', (
    tester,
  ) async {
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
    expect(jsonDecode(seen.last.body), {'completed': true});
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
    expect(jsonDecode(seen.last.body), {'description': 'Buy oat milk'});

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

  testWidgets('a failed login (401) shows the API message and is not an expired session', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'Invalid email or password.'}, 401));
    await logIn(tester);

    expect(find.text('Invalid email or password.'), findsOneWidget);
    expect(find.textContaining('session has ended'), findsNothing);
    expect(find.textContaining('API key'), findsNothing);
    expect(find.text('Hi, Ann'), findsNothing);
    // still on the login form, so the user can try again
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
  });

  testWidgets('a 401 about the key on the login form is explained as a key problem', (tester) async {
    await pumpApp(
      tester,
      server: (r) => json({
        'message':
            'Unauthorized. Please provide a valid apikey. Get a free key at https://keys.simpleapi.dev/?product=todos',
      }, 401),
    );
    await logIn(tester);

    expect(find.textContaining('The API key was not accepted'), findsOneWidget);
  });

  testWidgets('register shows the validation text for a short password (422)', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'The password must be at least 8 characters.'}, 422));
    await logIn(tester, register: true);

    expect(find.text('The password must be at least 8 characters.'), findsOneWidget);
  });

  testWidgets('registering an email twice shows the API message (409)', (tester) async {
    await pumpApp(
      tester,
      server: (r) =>
          json({'message': 'User registration failed, email already registered to this developer account.'}, 409),
    );
    await logIn(tester, register: true);

    expect(find.textContaining('email already registered'), findsOneWidget);
  });

  testWidgets('409 (key uses an external auth service) is shown as a conflict', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'This key uses an external auth service.'}, 409));
    await logIn(tester, register: true);

    expect(find.text('This key uses an external auth service.'), findsOneWidget);
  });

  testWidgets('register logs the user in when the API answers 201', (tester) async {
    final server = FakeServer();
    await pumpApp(tester, server: server.call);
    await logIn(tester, register: true);

    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Create an account'), findsNothing);
  });

  testWidgets('a full demo key (403 on register) shows the demo-full message', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'Maximum of 25 users per key reached.'}, 403));
    await logIn(tester, register: true);

    expect(find.text('The demo is full. It resets every night.'), findsOneWidget);
  });

  testWidgets('login and register never send the bearer token, even after a session ended', (tester) async {
    final server = FakeServer([todoJson(1, 'Buy milk')]);
    final seen = await pumpApp(tester, server: server.call);
    await logIn(tester);
    server.failNext = json({'message': 'Unauthorized.'}, 401);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Log in / Register'), findsOneWidget);

    seen.clear();
    await logIn(tester);
    expect(seen.where((r) => r.url.path == '/api/users/login').single.headers.containsKey('Authorization'), isFalse);
  });

  testWidgets('a malformed JSON body (400) shows the API message', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'Malformed JSON in the request body.'}, 400));
    await logIn(tester, register: true);

    expect(find.text('Malformed JSON in the request body.'), findsOneWidget);
  });

  testWidgets('a user_id that is not yours (403) shows the message and keeps you logged in', (tester) async {
    final server = FakeServer([todoJson(1, 'Buy milk')]);
    await pumpApp(tester, server: server.call);
    await logIn(tester);

    server.failNext = json({'message': 'Forbidden.  The user_id in the path does not belong to this auth token.'}, 403);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('does not belong to this auth token'), findsOneWidget);
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets('503 says the service is busy', (tester) async {
    await pumpApp(tester, server: (r) => json({'message': 'Key service unavailable. Please try again shortly.'}, 503));
    await logIn(tester);

    expect(find.text('The service is busy. Please try again shortly.'), findsOneWidget);
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

    server.failNext = json({'message': 'Maximum of 25 todos per user reached.'}, 403);
    await tester.enterText(find.widgetWithText(TextField, 'What needs doing?'), 'One too many');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Maximum of 25 todos'), findsOneWidget);
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

  testWidgets('a dead token (401) logs the user out with an explanation', (tester) async {
    final server = FakeServer([todoJson(1, 'Buy milk')]);
    await pumpApp(tester, server: server.call);
    await logIn(tester);

    server.failNext = json({'message': 'Invalid auth token.  Unauthorized.'}, 401);
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
    final seen = await pumpApp(
      tester,
      server: (r) {
        if (r.url.path == '/api/users/forgot') {
          return json({'message': 'If an account exists for that email, a reset code has been sent.'});
        }
        return json({'message': 'Password updated.'});
      },
    );
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
    await pumpApp(
      tester,
      server: (r) {
        if (r.url.path == '/api/users/forgot') {
          return json({'message': 'If an account exists for that email, a reset code has been sent.'});
        }
        return json({'message': 'Invalid or expired reset code.'}, 400);
      },
    );
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
}
