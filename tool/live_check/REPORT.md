# Live check report

Run against https://todos.simpleapi.dev with a throwaway public demo key, using
`tool/live_check/live_check.dart` (it reuses the app's own `TodosApi` client for
every call the app makes and raw requests for the edge cases).

**This shows what was tried, not that the API is bug free.** One run on one day,
one key, a handful of throwaway users, no load or concurrency testing.

This is the second report. The first one (before the API fixes of
[todos PR #1](https://github.com/simple-api-dev/todos/pull/1)) found the bugs
listed under "Earlier bugs"; this run re-tests them against the live API.

How it was run:

```bash
SIMPLEAPI_KEY=<a throwaway demo key> dart run tool/live_check/live_check.dart
```

- About one request per second (116 requests, 0 answered with 429).
- Test users were `simpleapi-sample-apps+<random>@agentmail.to` with random
  passwords generated at run time; the report redacts emails and tokens.
- Everything created was deleted at the end (todos, then the users with
  `DELETE /api/users/{id}`); rows `CA`-`CZ` verify that, including that the key
  holds the same number of key-level todos as before. One user was created by
  check R7 (see below); it was deleted too (row `CX`).
- Result column: PASS, FAIL, or PENDING. PENDING marks a check for a change
  that is merged but **not deployed yet** ([todos PR #2](https://github.com/simple-api-dev/todos/pull/2));
  it fails live today and is expected to pass after the deploy. Rows R7, R5b and
  G1 are the only PENDING ones.

## Summary

- **Fixed live, confirmed:** every item below under "Earlier bugs".
- **Still differing live:** only the three Part 1 items of todos PR #2 (R7, R5b,
  G1), because they are not deployed.
- **Nothing failed** apart from those. No new bug was found.

## Earlier bugs: status now

| Earlier finding | Now | Row |
| --- | --- | --- |
| Failed login answered 404 with the email in the message | **Fixed.** 401 `Invalid email or password.`, identical for a wrong password and an unknown email, no email echoed | L1, L2 |
| A short wrong password on login answered 422 | **Fixed.** 401, like any wrong password | L3 |
| Duplicate register answered 400 | **Fixed.** 409 | R6 |
| Malformed JSON answered 422 "name required" | **Fixed.** 400 `Malformed JSON in the request body.` (also on an authenticated route) | R4, D4 |
| `completed`, `enabled`, `admin` were 0/1 on reads | **Fixed.** Real booleans on list, login, register and writes | T2, T9, L6 |
| Token errors were plain text (`Unauthorized.1`), a missing todo a bare JSON string | **Fixed.** Every error in the run was JSON `{"message"}` | E1 |
| 26th todo was accepted | **Fixed.** The 26th is refused with 403; the server lists 25 | X1 |
| `user_id` in the path was ignored (another id returned the caller's todos with 200) | **Fixed.** A path id that is not the token's user is a plain 403, also for an id that does not exist; nothing is deleted | M1-M4 |
| Swagger documented a delete path that answered 404 (`/todo/{id}`) | **Fixed.** `DELETE /api/users/{user_id}/todos/{id}` works (200) | D3 |

## Differences still live (Part 1, not deployed)

These are in todos PR #2 and are expected to differ until it is deployed.

- **R7:** registering `name@host` (no dotted domain) answers 200 and creates a
  user; it should be 422. The check deleted that user afterwards.
- **R5b:** a successful register answers 200; it should be 201.
- **G1:** `GET /api/users/me` answers 405 `GET is not configured for this route.`;
  it should return the token's user without password or token.

`register/confirm` also changes to 201, but it needs the key owner's mailbox
and is not tested here.

## Notes

- **The app now accepts register as 200 or 201**, so it works before and after
  the deploy.
- **Anything new:** nothing wrong. Worth knowing: a description is limited to 256
  characters (row T7: 422 `The description may not be greater than 256 characters.`),
  and the login answer still carries `external_id` (null).
- **Fixed in the app because of the live API:** a failed login is a 401, which
  the app used to be able to read as "your session has ended". The login form now
  shows the API message, and a 401 only logs you out for calls made while logged in
  (row L1, and widget test "a failed login (401) ... is not an expired session").
- Removed workarounds: reading `completed` as 0/1, parsing plain-text and bare
  string errors, mapping a 404 login to "Wrong email or password", and the note
  about the wrong Swagger delete path.

## Results

| # | Check | Expected per docs | Actual | Result |
| --- | --- | --- | --- | --- |
| K1 | GET /api/todos with no apikey | 401 (key required) | HTTP 401 {"message":"Unauthorized.  Please provide a valid apikey.  Visit todos.simpleapi.dev\/get-key for your free apikey today."} | PASS |
| K2 | GET /api/todos with a bad apikey | 401 (key required) | HTTP 401 {"message":"Request failed.  API Key not found."} | PASS |
| K3 | POST /api/users/login with no apikey | 401 (key required) | HTTP 401 {"message":"Unauthorized.  Please provide a valid apikey.  Visit todos.simpleapi.dev\/get-key for your free apikey today."} | PASS |
| K4 | checkKey: GET /api/todos with the demo key (Settings) | 200 | HTTP 200 [] | PASS |
| R1 | register with a malformed email | 422 (validation) | HTTP 422 {"message":"The email must be a valid email address."} | PASS |
| R2 | register with a 5-character password | 422 (validation) | HTTP 422 {"message":"The password must be at least 8 characters."} | PASS |
| R3 | register without the required name | 422 (validation) | HTTP 422 {"message":"The name field is required."} | PASS |
| R4 | register with a malformed JSON body | 400 | HTTP 400 {"message":"Malformed JSON in the request body."} | PASS |
| R7 | register with an email without a dotted domain (name@host) | 422 (todos PR #2) | HTTP 200 {"name":"T","email":"nodotsfpczuqt19@localhost","enabled":true,"token":"<token>","admin":false,"id":462} | PENDING |
| R5 | register user A | 200 or 201 with token and id | HTTP 200 {"name":"Check A","email":"<email>","enabled":true,"token":"<token>","admin":false,"id":463} | PASS |
| R5b | a successful register answers 201 | 201 (todos PR #2) | HTTP 200 {"name":"Check A","email":"<email>","enabled":true,"token":"<token>","admin":false,"id":463} | PENDING |
| R6 | register the same email again | 409 | HTTP 409 {"message":"User registration failed, email already registered to this developer account."} | PASS |
| L1 | login with the wrong password | 401 "Invalid email or password." | HTTP 401 {"message":"Invalid email or password."} | PASS |
| L2 | login with an unknown email | 401, the same body as a wrong password (no account leak) | HTTP 401 {"message":"Invalid email or password."} | PASS |
| L3 | login with a 5-character password | 401 (not a 422) | HTTP 401 {"message":"Invalid email or password."} | PASS |
| L4 | login with an empty body | 422 (validation) | HTTP 422 {"message":"The email field is required.  The password field is required."} | PASS |
| L5 | login as user A (right credentials) | 200 with token, id, name, email | HTTP 200 {"id":463,"name":"Check A","email":"<email>","enabled":true,"token":"<token>","admin":false,"external_id":null} | PASS |
| L6 | login field types match the docs (enabled/admin are booleans) | enabled: boolean, admin: boolean | enabled=bool, admin=bool | PASS |
| T1 | listTodos for a new user | 200, empty array | HTTP 200 [] | PASS |
| T2 | createTodo | 200 with id, description, completed (boolean) | HTTP 200 {"description":"first todo","completed":false,"user_id":463,"author":"Check A","id":3312} | PASS |
| T3 | createTodo with an empty description | 422 (description required) | HTTP 422 {"message":"The description field is required."} | PASS |
| T4 | createTodo with no description field | 422 (description required) | HTTP 422 {"message":"The description field is required."} | PASS |
| T5 | createTodo with a whitespace-only description | a 4xx would be sensible, docs silent | HTTP 422 {"message":"The description field is required."} | PASS |
| T6 | createTodo with unicode, HTML and quotes round-trips unchanged | 200, text unchanged | HTTP 200 {"description":"Caf\u00e9 \u2615 \u65e5\u672c\u8a9e <b>bold<\/b> \"quotes\"","completed":false,"user_id":463,"author":"Check A","id":3313} | PASS |
| T7 | createTodo with a 1000-character description | docs silent on a length limit | HTTP 422 {"message":"The description may not be greater than 256 characters."} | PASS |
| T8 | listTodos shows the created todos | 200, todos present | HTTP 200 [{"id":3312,"user_id":463,"description":"first todo","completed":false,"author":"Check A","meta":null},{"id":3313,"user_id":463,"description":"Caf\u00e9 \u2615 \u65e5\u67... | PASS |
| T9 | completed is a boolean in list answers (docs: boolean) | completed: boolean | completed=false (bool) | PASS |
| U1 | updateTodo: complete | 200, completed true | HTTP 200 {"id":3312,"user_id":463,"description":"first todo","completed":true,"author":"Check A"} | PASS |
| U2 | updateTodo: uncomplete | 200, completed false | HTTP 200 {"id":3312,"user_id":463,"description":"first todo","completed":false,"author":"Check A"} | PASS |
| U3 | updateTodo: edit the text | 200, new text | HTTP 200 {"id":3312,"user_id":463,"description":"first todo, edited","completed":false,"author":"Check A"} | PASS |
| U4 | updateTodo with an empty description | 422 (description required) | HTTP 422 {"message":"The description field is required."} | PASS |
| U5 | GET one todo (not used by the app) | 200, the todo | HTTP 200 {"id":3312,"user_id":463,"description":"first todo, edited","completed":false,"author":"Check A","meta":null} | PASS |
| U6 | updateTodo on a todo that does not exist | 404 | HTTP 404 {"message":"Todo not found (999999999)"} | PASS |
| D1 | deleteTodo on a todo that does not exist | 404 | HTTP 404 {"message":"Todo not found (999999999)"} | PASS |
| D2 | GET a todo that does not exist | 404 | HTTP 404 {"message":"Todo 999999999 not found."} | PASS |
| D3 | DELETE /api/users/{id}/todos/{id}, the path the Swagger page now documents | 200 | HTTP 200 {"message":"Todo deleted (3312)"} | PASS |
| D4 | createTodo with a malformed JSON body | 400 | HTTP 400 {"message":"Malformed JSON in the request body."} | PASS |
| G1 | GET /api/users/me returns the token's user, no password, no token | 200 (todos PR #2) | HTTP 405 {"message":"GET is not configured for this route."} | PENDING |
| A1 | list todos with no Authorization header | 401 | HTTP 401 {"message":"Unauthorized.  Send the header Authorization: Bearer <token>."} | PASS |
| A2 | list todos with a garbage token | 401 | HTTP 401 {"message":"Invalid auth token.  Unauthorized."} | PASS |
| O1 | register user B | 200 with token and id | HTTP 200 {"name":"Check B","email":"<email>","enabled":true,"token":"<token>","admin":false,"id":464} | PASS |
| O2 | user B reads user A's todo (B's own id in the path) | 403 or 404 | HTTP 404 {"message":"Todo 3314 not found."} | PASS |
| O3 | user B edits user A's todo | 403 or 404 | HTTP 404 {"message":"Todo not found (3314)"} | PASS |
| O4 | user B deletes user A's todo | 403 or 404 | HTTP 404 {"message":"Todo not found (3314)"} | PASS |
| O5 | user A's todo is unchanged after B's attempts | 200, text unchanged and still there | HTTP 200 [{"id":3313,"user_id":463,"description":"Caf\u00e9 \u2615 \u65e5\u672c\u8a9e <b>bold<\/b> \"quotes\"","completed":false,"author":"Check A","meta":null},{"id":3314,"user_i... | PASS |
| O6 | user B's list does not contain A's todos | 200, empty array | HTTP 200 [] | PASS |
| M1 | user B lists user A's todos with A's id in the path | 403 {message} | HTTP 403 {"message":"Forbidden.  The user_id in the path does not belong to this auth token."} | PASS |
| M2 | user B deletes user A's todo with A's id in the path | 403 {message} | HTTP 403 {"message":"Forbidden.  The user_id in the path does not belong to this auth token."} | PASS |
| M3 | a user_id that does not exist in the path | 403 {message} | HTTP 403 {"message":"Forbidden.  The user_id in the path does not belong to this auth token."} | PASS |
| M4 | user A's todo survived the mismatched deletes | 200, still there | HTTP 200 [{"id":3313,"user_id":463,"description":"Caf\u00e9 \u2615 \u65e5\u672c\u8a9e <b>bold<\/b> \"quotes\"","completed":false,"author":"Check A","meta":null},{"id":3314,"user_i... | PASS |
| X1 | create todos beyond the documented limit of 25 per user | the 26th todo is refused (4xx); the list holds 25 | HTTP 403 {"message":"Maximum number of todos (25) per user has been reached. (Basic Acct)"}; the server lists 25 todos | PASS |
| S1 | logout | 200 | HTTP 200 true | PASS |
| S2 | list todos with the token from before logout | 401 | HTTP 401 {"message":"Invalid auth token.  Unauthorized."} | PASS |
| S3 | logout again with the same (dead) token | a 4xx or a harmless 200, docs silent | HTTP 401 {"message":"Invalid auth token.  Unauthorized."} | PASS |
| S4 | login again after logout | 200 with a new token | HTTP 200 {"id":463,"name":"Check A","email":"<email>","enabled":true,"token":"<token>","admin":false,"external_id":null} | PASS |
| F1 | forgot password for a real user (request half only) | 200 "request accepted" | HTTP 200 {"message":"If an account exists for that email, a reset code has been sent."} | PASS |
| F2 | forgot password for an unknown email | 200, same answer as a real one (no account leak) | HTTP 200 {"message":"If an account exists for that email, a reset code has been sent."} | PASS |
| F3 | forgot password with a malformed email | 422 | HTTP 422 {"message":"The email must be a valid email address."} | PASS |
| F4 | reset with a wrong 6-digit code (never the real one) | 400 invalid or expired code | HTTP 400 {"message":"Invalid or expired reset code."} | PASS |
| F5 | reset with a wrong code and a too-short password | 400 or 422 | HTTP 422 {"message":"The password must be at least 8 characters."} | PASS |
| F6 | the old password still works after the failed resets | 200 | HTTP 200 {"id":463,"name":"Check A","email":"<email>","enabled":true,"token":"<token>","admin":false,"external_id":null} | PASS |
| CX | cleanup: delete a user a check created by mistake | 200 | HTTP 200 {"message":"User deleted (462)"} | PASS |
| CA | cleanup: delete user A (DELETE /api/users/{id}) | 200 | HTTP 200 {"message":"User deleted (463)"} | PASS |
| CA2 | cleanup: the deleted user A's token no longer works | 401 | HTTP 401 {"message":"Invalid auth token.  Unauthorized."} | PASS |
| CB | cleanup: delete user B (DELETE /api/users/{id}) | 200 | HTTP 200 {"message":"User deleted (464)"} | PASS |
| CB2 | cleanup: the deleted user B's token no longer works | 401 | HTTP 401 {"message":"Invalid auth token.  Unauthorized."} | PASS |
| CZ | the key holds the same number of key-level todos as at the start | equal | before=0, after=0 | PASS |
| E1 | every error answer in the whole run was JSON {"message": "..."} | none that was not | all of them were | PASS |

116 requests sent, 0 answered with 429 and retried.

## Not tested and why

- **Completing a password reset.** Only the request half was exercised
  (`/forgot`, and `/reset` with a wrong code). Using the real emailed code would
  change a user's password and needs reading a mailbox.
- **The 10-users-per-key limit.** It would need 10 users on the shared demo key
  and could block other developers using it.
- **The key-level todos and user routes** (`/api/todos...` beyond the key check,
  `DELETE /api/users`, `GET /api/users`): the app does not use them and the
  delete-all routes could wipe other people's data on the shared demo key.
- **Admin routes and `POST /api/users/register/confirm`** (need the key owner's
  own email and an emailed code).
- **The 409 "external auth service" mode** (needs the key's settings changed).
- **A real 429.** None occurred at one request per second.
- **The deployed site in a real browser.** The widget tests drive the same
  screens with mocked HTTP.
- **Concurrency, large payloads, token expiry over time, `meta` on todos, and
  the `PATCH`/`HEAD` methods.**
