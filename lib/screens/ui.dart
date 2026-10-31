import 'package:flutter/material.dart';

import '../todos_api.dart';

/// Turns any error into a sentence the user can read.
///
/// Statuses seen from this API: 400 (duplicate email, bad reset code), 401
/// (bad/missing key, or a token that is no longer valid), 403 (a limit was
/// reached), 404 (no such todo, or a failed login), 409 (this key uses an
/// external auth service), 422 (validation, the message says which field)
/// and 429 (rate limit).
String describeError(Object e) {
  if (e is! ApiException) return 'Something went wrong: $e';
  switch (e.statusCode) {
    case 401:
      return isTokenProblem(e)
          ? 'Your session has ended. Please log in again.'
          : 'The API key was not accepted. Check it under Settings. (${e.message})';
    case 400:
    case 403:
      // The message is already a clear sentence, e.g. "Maximum number of todos
      // (25) per user has been reached." or "...email already registered...".
      return e.message;
    case 404:
      return 'Not found. It may already have been deleted. (${e.message})';
    case 409:
      return 'Conflict: ${e.message}';
    case 422:
      return e.message; // e.g. "The password must be at least 8 characters."
    case 429:
      return 'Too many requests. Wait a few seconds and try again.';
    default:
      return e.message;
  }
}

/// Like [describeError], for the login form: a failed login answers 404
/// ("Login Failed"), which would read as "not found" if shown as-is.
String describeLoginError(Object e) =>
    e is ApiException && e.statusCode == 404 ? 'Wrong email or password.' : describeError(e);

/// True for a 401 caused by the user's token (as opposed to the apikey).
bool isTokenProblem(ApiException e) =>
    e.statusCode == 401 && !e.message.toLowerCase().contains('api key') && !e.message.toLowerCase().contains('apikey');

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Shown when a request fails, with a retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(describeError(error), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ]),
      ),
    );
  }
}

/// Centers page content in a readable column on wide screens.
class Centered extends StatelessWidget {
  const Centered({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child));
}
