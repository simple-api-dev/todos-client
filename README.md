# todos-client

A small Flutter **web** app that shows how to use the free
[SimpleApi Todos API](https://todos.simpleapi.dev/docs): register and log in
users, then add, edit, complete and delete their todos. It is a teaching sample:
no backend, no state-management package, and the only dependency besides Flutter
is [`http`](https://pub.dev/packages/http).

**Live demo:** https://simple-api-dev.github.io/todos-client/

## Keys

This is a **reference implementation**: the live demo opens straight on the
app, with no key prompt, because a demo key is compiled into it at build time.

**Use your own key.** In the app open **Settings -> Use your own key** and paste
a key; it is checked with one call and kept only in your browser's
localStorage, where it overrides the demo key. Get a free key at
https://keys.simpleapi.dev/?product=todos (product URL
`https://todos.simpleapi.dev`). Keys are sent only to `todos.simpleapi.dev`, as
the `apikey` query parameter. Users and their todos belong to your key, so every
developer has their own set of users (a key allows 10 users, and each user 25
todos).

**Set the demo key for your deployment.** The key is read with
`String.fromEnvironment('SIMPLEAPI_KEY')` and nothing is ever committed:

1. In your repository go to **Settings -> Secrets and variables -> Actions ->
   Variables** and add a repository **variable** named `SIMPLEAPI_KEY`.
2. Push to `main` (or run the workflow). It builds with
   `--dart-define=SIMPLEAPI_KEY=...`.

**Anything passed with `--dart-define` ends up in the compiled JavaScript, so
anyone can read it from the deployed site.** Use a free key made for a public
demo and expect strangers to use it. If the variable is empty, the app shows
"This demo has no key configured" with a link to get one.

## Screens and the API calls they use

| Screen | What it does | Calls |
| --- | --- | --- |
| **Todos** (`todos_screen.dart`) | The landing screen. Logged out it explains the sample and offers to log in or register. Logged in it lists your todos; add one, tick it complete (or untick it), edit its text, delete it. | `GET /api/users/{user_id}/todos`, `POST /api/users/{user_id}/todos`, `PUT /api/users/{user_id}/todos/{id}`, `DELETE /api/users/{user_id}/todos/{id}` |
| **Log in / Register** (`auth_screen.dart`) | Get a token. **Log out** is in the app bar. | `POST /api/users/register`, `POST /api/users/login`, `POST /api/users/logout` |
| **Reset password** (`forgot_screen.dart`) | Step 1: email a 6-digit code. Step 2: send the code with a new password. | `POST /api/users/forgot`, `POST /api/users/reset` |
| **Settings** (`settings_screen.dart`) | Use your own key instead of the demo key (or go back to it). | `GET /api/todos` (needs only the key; used as a one-call check) |

Every call lives in [`lib/todos_api.dart`](lib/todos_api.dart), one method per
endpoint with a comment naming it. The rest of the app never touches HTTP. The
login token is held in memory only, so reloading the page logs you out while
your own key, if you saved one, stays.

`{user_id}` is always the logged-in user's own id, taken from the register /
login answer. (The API reads the user from the token; the id in the path is not
a way to reach another user's todos.)

The API also has endpoints this sample does not use: `GET` one todo, the
key-level todo routes (`/api/todos...`, which are shared by everyone using the
key), deleting your account, and the admin routes; see the
[full docs](https://todos.simpleapi.dev/docs).

## Good to know

- Every error is JSON, `{"message": "..."}`; the app shows readable text for
  400 (malformed JSON, bad reset code), 401, 403, 404, 409, 422 and 429.
- A bad or missing key answers `401`. A dead token answers `401` too; the app
  then logs you out. A failed login is also a `401` ("Invalid email or
  password."); it is shown on the form and is not treated as an expired session.
- Registering an email that is already taken answers `409`. A new user answers
  `201` (the app also accepts `200`, which older deployments sent).
- A `user_id` in the path that is not yours answers `403`; the app always
  sends your own id.
- `completed`, `enabled` and `admin` are real booleans.
- Passwords need at least 8 characters. A user may have 25 todos; the 26th is
  refused with `403`.
- The API is rate limited, so a burst of clicks may be answered with `429`.
- More detail, with every status and body observed from the live API, is in
  [`tool/live_check/REPORT.md`](tool/live_check/REPORT.md).

## Run locally

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(stable; CI uses 3.47.8).

```bash
flutter pub get
flutter run -d chrome --dart-define=SIMPLEAPI_KEY=<your key>
```

Without `--dart-define`, paste your key under Settings instead.

Run the tests (all HTTP is mocked, nothing calls the real API):

```bash
flutter test
```

## Live check

[`tool/live_check/live_check.dart`](tool/live_check/live_check.dart) calls the
real API with the app's own client, plus edge cases (bad key, duplicate user,
someone else's todo, token after logout, ...), at about one request per second,
and deletes everything it creates. It reads the key from the environment and
never stores it:

```bash
SIMPLEAPI_KEY=<a throwaway demo key> dart run tool/live_check/live_check.dart
```

Use a throwaway key: it creates and deletes users on it.

## Project layout

```
lib/todos_api.dart        the whole API client
lib/app_state.dart        saved key + logged-in user (a ChangeNotifier)
lib/key_store*.dart       localStorage wrapper (+ in-memory one for tests)
lib/config.dart           the build-time key (SIMPLEAPI_KEY)
lib/screens/              the screens
test/                     unit tests for the client, widget tests for the app
tool/live_check/          live check against the real API + REPORT.md
```

## Deploy (GitHub Pages)

[`.github/workflows/pages.yml`](.github/workflows/pages.yml) runs on every push
to `main`: it installs Flutter, runs `flutter analyze` and `flutter test`,
builds with `flutter build web --release --base-href /todos-client/` and
publishes through the official `upload-pages-artifact` and `deploy-pages`
actions. In your fork or copy, add the `SIMPLEAPI_KEY` variable (see Keys) and set
**Settings -> Pages -> Source** to **GitHub Actions**. If you rename the
repository, change `--base-href` to match.
