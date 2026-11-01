/// The todo list screen.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../open_url.dart';
import '../todos_api.dart';
import 'auth_screen.dart';
import 'ui.dart';

/// The landing screen: your todo list. Logged out it explains itself and
/// offers to log in or register; logged in it lists, adds, edits, completes
/// and deletes todos.
class TodosScreen extends StatefulWidget {
  const TodosScreen({super.key, required this.state, required this.openUrl});

  final AppState state;
  final UrlOpener openUrl;

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  final _newText = TextEditingController();
  Future<List<Todo>>? _future;
  List<Todo> _todos = [];
  bool _wasLoggedIn = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onStateChanged);
    _onStateChanged();
  }

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    _newText.dispose();
    super.dispose();
  }

  /// Loads the list when a user logs in, forgets it when they log out.
  void _onStateChanged() {
    if (state.loggedIn && !_wasLoggedIn) {
      _future = _load();
    } else if (!state.loggedIn) {
      _future = null;
      _todos = [];
    }
    _wasLoggedIn = state.loggedIn;
  }

  // GET /api/users/{user_id}/todos
  Future<List<Todo>> _load() async {
    try {
      return _todos = await state.api.listTodos();
    } on ApiException catch (e) {
      // a 401 while logged in means the session is over
      if (e.statusCode == 401) state.sessionExpired();
      rethrow;
    }
  }

  /// Runs one write, shows a readable error if it fails, and logs the user
  /// out locally if the API says the token is no longer valid.
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) state.sessionExpired();
      if (mounted) showSnack(context, describeError(e));
    }
  }

  // POST /api/users/{user_id}/todos
  Future<void> _add() => _run(() async {
    final text = _newText.text.trim();
    if (text.isEmpty) return;
    final todo = await state.api.createTodo(text);
    _newText.clear();
    setState(() => _todos = [..._todos, todo]);
  });

  // PUT /api/users/{user_id}/todos/{id}  (completed flag)
  Future<void> _toggle(Todo t) => _run(() async {
    final saved = await state.api.updateTodo(t.id, description: t.description, completed: !t.completed);
    setState(() => _todos = [for (final x in _todos) x.id == t.id ? saved : x]);
  });

  // PUT /api/users/{user_id}/todos/{id}  (new text)
  Future<void> _edit(Todo t) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditDialog(initial: t.description),
    );
    if (text == null || text == t.description) return;
    await _run(() async {
      final saved = await state.api.updateTodo(t.id, description: text, completed: t.completed);
      setState(() => _todos = [for (final x in _todos) x.id == t.id ? saved : x]);
    });
  }

  // DELETE /api/users/{user_id}/todos/{id}
  Future<void> _delete(Todo t) => _run(() async {
    await state.api.deleteTodo(t.id);
    setState(
      () => _todos = [
        for (final x in _todos)
          if (x.id != t.id) x,
      ],
    );
  });

  // POST /api/users/login as the shared demo user
  Future<void> _demo() async {
    try {
      await state.loginDemo();
    } catch (e) {
      if (mounted) showSnack(context, describeLoginError(e));
    }
  }

  void _reload() => setState(() => _future = _load());

  void _openAuth({bool register = false}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AuthScreen(state: state, startAsRegister: register),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: BackToSimpleApi(openUrl: widget.openUrl),
          title: const Text('SimpleAPI Todos'),
          actions: [
            if (state.loggedIn) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 64),
                child: Center(child: Text('Hi, ${state.userName ?? 'you'}', overflow: TextOverflow.ellipsis)),
              ),
              TextButton(
                onPressed: state.logout,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Log out'),
              ),
            ] else
              TextButton(
                onPressed: _openAuth,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('Log in / Register'),
              ),
          ],
        ),
        body: Centered(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (!state.loggedIn) {
      return _LoggedOut(onDemo: _demo, onLogin: _openAuth, onRegister: () => _openAuth(register: true));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newText,
                  decoration: const InputDecoration(labelText: 'What needs doing?', border: OutlineInputBorder()),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _add, child: const Text('Add')),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Todo>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
              if (_todos.isEmpty) return const Center(child: Text('No todos yet. Add your first one above.'));
              return ListView(
                children: [
                  for (final t in _todos)
                    ListTile(
                      key: ValueKey(t.id),
                      leading: Checkbox(value: t.completed, onChanged: (_) => _toggle(t)),
                      title: Text(
                        t.description,
                        style: t.completed
                            ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)
                            : null,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(t)),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(t),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LoggedOut extends StatelessWidget {
  const _LoggedOut({required this.onDemo, required this.onLogin, required this.onRegister});

  final VoidCallback onDemo;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    // Scrolls on short screens so nothing is cut off.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Your todos', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'This sample talks to the free SimpleAPI Todos API. Every todo belongs to a user: try the shared demo '
              'account in one click, or create your own account (any email address, it is not verified).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onDemo, child: const Text('Try the demo account')),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(onPressed: onRegister, child: const Text('Create an account')),
                OutlinedButton(onPressed: onLogin, child: const Text('Log in')),
              ],
            ),
            const SizedBox(height: 16),
            const Text(demoNotice, key: Key('demo-notice'), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Owns its text controller so it is disposed only after the dialog is gone.
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.initial});

  final String initial;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit todo'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Description'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Save')),
      ],
    );
  }
}
