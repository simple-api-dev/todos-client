import 'package:flutter/material.dart';

import '../todos_api.dart';

/// Turns any error into a sentence the user can read.
///
/// Statuses seen from this API, always with a JSON `{"message"}`: 400
/// (malformed JSON, bad reset code), 401 (bad/missing key, a token that is no
/// longer valid, or a failed login), 403 (a limit was reached, or a user_id
/// that is not yours), 404 (no such todo), 409 (email already registered, or
/// this key uses an external auth service), 422 (validation, the message says
/// which field) and 429 (rate limit).
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
      return e.message; // e.g. "User registration failed, email already registered to this developer account."
    case 422:
      return e.message; // e.g. "The password must be at least 8 characters."
    case 429:
      return 'Too many requests. Wait a few seconds and try again.';
    default:
      return e.message;
  }
}

/// Like [describeError], for the login form. A failed login is a 401 too
/// ("Invalid email or password."): it is shown as it is, and it is not an
/// expired session (nobody is logged in yet). Only a 401 about the key is
/// explained as a key problem.
String describeLoginError(Object e) =>
    e is ApiException && e.statusCode == 401 && !isKeyProblem(e) ? e.message : describeError(e);

/// True for a 401 about the apikey (as opposed to the token or a login).
bool isKeyProblem(ApiException e) =>
    e.statusCode == 401 && (e.message.toLowerCase().contains('api key') || e.message.toLowerCase().contains('apikey'));

/// True for a 401 caused by the user's token. Only for calls made while logged
/// in: a failed login is also a 401 and must not be passed through this.
bool isTokenProblem(ApiException e) => e.statusCode == 401 && !isKeyProblem(e);

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
