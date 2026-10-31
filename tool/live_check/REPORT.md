# Live check report

Run against https://todos.simpleapi.dev with a throwaway demo key, using
`tool/live_check/live_check.dart` (it reuses the app's own `TodosApi` client for
every call the app makes and raw requests for the edge cases).

**This shows what was tried, not that the API is bug free.** One run on one day,
one key, a handful of throwaway users, no load or concurrency testing.

How it was run:

```bash
SIMPLEAPI_KEY=<a throwaway demo key> dart run tool/live_check/live_check.dart
```

- About one request per second; a 429 would be retried with back-off (none happened).
- Test users were `simpleapi-sample-apps+<random>@agentmail.to` with random
  passwords generated at run time; the report redacts emails and tokens.
- Everything created was deleted at the end (todos, then both users with
  `DELETE /api/users/{id}`); rows `CA`-`CZ` verify that, including that the key
  holds the same number of key-level todos as before.
- The run was done twice (the second after fixing the app bugs below and
  tightening check X1); the table is from the second run. Both runs cleaned up.
- "Expected per docs" is what the Swagger page at `/docs` says. Where it is
  silent (most error statuses) the column says so and any 4xx passes; the exact
  status is in the Actual column.

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
| R4 | register with a malformed JSON body | a 4xx, docs silent | HTTP 422 {"message":"The name field is required.  The email field is required.  The password field is required."} | PASS |
| R5 | register user A | 200 with token and id | HTTP 200 {"name":"Check A","email":"<email>","enabled":true,"token":"<token>","admin":false,"id":458} | PASS |
| R6 | register the same email again | a 4xx (409 or 422), docs silent | HTTP 400 {"message":"User registration failed, email already registered to this developer account."} | PASS |
| L1 | login with the wrong password | a 4xx (docs list only 200) | HTTP 404 {"message":"Login Failed (<email>)"} | PASS |
| L2 | login with an unknown email | a 4xx (docs list only 200) | HTTP 404 {"message":"Login Failed (<email>)"} | PASS |
| L3 | login with a 5-character password | a 4xx (docs list only 200) | HTTP 422 {"message":"The password must be at least 8 characters."} | PASS |
| L4 | login with an empty body | 422 (validation) | HTTP 422 {"message":"The email field is required.  The password field is required."} | PASS |
| L5 | login as user A (right credentials) | 200 with token, id, name, email | HTTP 200 {"id":458,"name":"Check A","email":"<email>","enabled":1,"token":"<token>","admin":0,"warnings":0,"external_id":null} | PASS |
| L6 | login field types match the docs (enabled/admin are booleans) | enabled: boolean, admin: boolean | enabled=int, admin=int | FAIL |
| T1 | listTodos for a new user | 200, empty array | HTTP 200 [] | PASS |
| T2 | createTodo | 200 with id, description, completed | HTTP 200 {"description":"first todo","completed":false,"user_id":458,"author":"Check A","id":3286} | PASS |
| T3 | createTodo with an empty description | 422 (description required) | HTTP 422 {"message":"The description field is required."} | PASS |
| T4 | createTodo with no description field | 422 (description required) | HTTP 422 {"message":"The description field is required."} | PASS |
| T5 | createTodo with a whitespace-only description | a 4xx would be sensible, docs silent | HTTP 422 {"message":"The description field is required."} | PASS |
| T6 | createTodo with unicode, HTML and quotes round-trips unchanged | 200, text unchanged | HTTP 200 {"description":"Caf\u00e9 \u2615 \u65e5\u672c\u8a9e <b>bold<\/b> \"quotes\"","completed":false,"user_id":458,"author":"Check A","id":3287} | PASS |
| T7 | createTodo with a 1000-character description | docs silent on a length limit | HTTP 422 {"message":"The description may not be greater than 256 characters."} | PASS |
| T8 | listTodos shows the created todos | 200, todos present | HTTP 200 [{"id":3286,"user_id":458,"description":"first todo","completed":0,"author":"Check A","meta":null},{"id":3287,"user_id":458,"description":"Caf\u00e9 \u2615 \u65e5\u672c\u... | PASS |
| T9 | completed is a boolean in list answers (docs: boolean) | completed: boolean | completed=0 (int) | FAIL |
| U1 | updateTodo: complete | 200, completed true | HTTP 200 {"id":3286,"user_id":458,"description":"first todo","completed":true,"author":"Check A"} | PASS |
| U2 | updateTodo: uncomplete | 200, completed false | HTTP 200 {"id":3286,"user_id":458,"description":"first todo","completed":false,"author":"Check A"} | PASS |
| U3 | updateTodo: edit the text | 200, new text | HTTP 200 {"id":3286,"user_id":458,"description":"first todo, edited","completed":false,"author":"Check A"} | PASS |
| U4 | updateTodo with an empty description | 422 (description required) | HTTP 422 {"message":"The description field is required."} | PASS |
| U5 | GET one todo (not used by the app) | 200, the todo | HTTP 200 {"id":3286,"user_id":458,"description":"first todo, edited","completed":0,"author":"Check A","meta":null} | PASS |
| U6 | updateTodo on a todo that does not exist | 404 | HTTP 404 {"message":"Todo not found (999999999)"} | PASS |
| D1 | deleteTodo on a todo that does not exist | 404 | HTTP 404 {"message":"Todo not found (999999999)"} | PASS |
| D2 | GET a todo that does not exist | 404 | HTTP 404 "Todo 999999999 not found." | PASS |
| D3 | DELETE /api/users/{id}/todo/{id} exactly as the Swagger page documents it | 200 (documented path) | HTTP 404 {"message":"Not a valid api route - not found."} | FAIL |
| A1 | list todos with no Authorization header | 401 | HTTP 401 Unauthorized.1 | PASS |
| A2 | list todos with a garbage token | 401 | HTTP 401 Invalid Auth Token. Unauthorized.2 | PASS |
| O1 | register user B | 200 with token and id | HTTP 200 {"name":"Check B","email":"<email>","enabled":true,"token":"<token>","admin":false,"id":459} | PASS |
| O2 | user B reads user A's todo (B's own id in the path) | 403 or 404 | HTTP 404 "Todo 3286 not found." | PASS |
| O3 | user B edits user A's todo | 403 or 404 | HTTP 404 {"message":"Todo not found (3286)"} | PASS |
| O4 | user B deletes user A's todo | 403 or 404 | HTTP 404 {"message":"Todo not found (3286)"} | PASS |
| O5 | user A's todo is unchanged after B's attempts | 200, text unchanged and still there | HTTP 200 [{"id":3286,"user_id":458,"description":"first todo, edited","completed":0,"author":"Check A","meta":null},{"id":3287,"user_id":458,"description":"Caf\u00e9 \u2615 \u65e5... | PASS |
| O6 | user B's list does not contain A's todos | 200, empty array | HTTP 200 [] | PASS |
| X1 | create todos beyond the documented limit of 25 per user | the 26th todo is refused (4xx); the list holds 25 | HTTP 403 {"message":"Maximum number of todos (25) per user has been reached. (Basic Acct)"}; the server lists 26 todos | FAIL |
| S1 | logout | 200 | HTTP 200 true | PASS |
| S2 | list todos with the token from before logout | 401 | HTTP 401 Invalid Auth Token. Unauthorized.2 | PASS |
| S3 | logout again with the same (dead) token | a 4xx or a harmless 200, docs silent | HTTP 401 Invalid Auth Token. Unauthorized.2 | PASS |
| S4 | login again after logout | 200 with a new token | HTTP 200 {"id":458,"name":"Check A","email":"<email>","enabled":1,"token":"<token>","admin":0,"warnings":0,"external_id":null} | PASS |
| F1 | forgot password for a real user (request half only) | 200 "request accepted" | HTTP 200 {"message":"If an account exists for that email, a reset code has been sent."} | PASS |
| F2 | forgot password for an unknown email | 200, same answer as a real one (no account leak) | HTTP 200 {"message":"If an account exists for that email, a reset code has been sent."} | PASS |
| F3 | forgot password with a malformed email | 422 | HTTP 422 {"message":"The email must be a valid email address."} | PASS |
| F4 | reset with a wrong 6-digit code (never the real one) | 400 invalid or expired code | HTTP 400 {"message":"Invalid or expired reset code."} | PASS |
| F5 | reset with a wrong code and a too-short password | 400 or 422 | HTTP 422 {"message":"The password must be at least 8 characters."} | PASS |
| F6 | the old password still works after the failed resets | 200 | HTTP 200 {"id":458,"name":"Check A","email":"<email>","enabled":1,"token":"<token>","admin":0,"warnings":0,"external_id":null} | PASS |
| CA | cleanup: delete user A (DELETE /api/users/{id}) | 200 | HTTP 200 {"message":"User deleted (458)"} | PASS |
| CA2 | cleanup: the deleted user A's token no longer works | 401 | HTTP 401 Invalid Auth Token. Unauthorized.2 | PASS |
| CB | cleanup: delete user B (DELETE /api/users/{id}) | 200 | HTTP 200 {"message":"User deleted (459)"} | PASS |
| CB2 | cleanup: the deleted user B's token no longer works | 401 | HTTP 401 Invalid Auth Token. Unauthorized.2 | PASS |
| CZ | the key holds the same number of key-level todos as at the start | equal | before=0, after=0 | PASS |

108 requests sent, 0 answered with 429 and retried.

## App bugs (fixed)

Found by the widget tests and by this run, fixed in this PR:

1. **Edit dialog crashed the framework.** `_edit` disposed its
   `TextEditingController` as soon as `showDialog` returned, while the dialog
   was still animating closed ("TextEditingController was used after being
   disposed"). The dialog is now its own `StatefulWidget` that owns the
   controller. (Found by the widget test, not by the live run.)
2. **A wrong password read "Not found. It may already have been deleted."**
   Login failures answer **404** (`Login Failed (<email>)`, rows L1/L2), so the
   generic 404 text was wrong for the login form. The login form now says
   "Wrong email or password."
3. **The per-user limit message was hidden.** The limit answers **403**
   (`Maximum number of todos (25) per user has been reached.`, row X1); the first
   draft replaced it with a generic "not allowed". 403 and 400 now show the API's
   own sentence.
4. **Plain-text and bare-string errors.** The user routes answer a missing or
   dead token with plain text (`Unauthorized.1`, `Invalid Auth Token.
   Unauthorized.2`, rows A1/A2/S2) and a missing todo with a bare JSON string
   (`"Todo 9 not found."`, row D2). The client now reads all three error shapes,
   and a 401 caused by the token (not the key) logs the user out locally with
   "Your session has ended."
5. **The documented delete path does not work** (see below); the app uses the
   working `/todos/{id}` path.

## API bugs or doc mismatches (not fixed)

These are the API's, not the app's. The app works around each one.

1. **Delete path (row D3).** Swagger documents
   `DELETE /api/users/{user_id}/todo/{id}` (and `DELETE /api/todo/{id}`); both
   answer `404 {"message":"Not a valid api route - not found."}`. The working
   route is `DELETE /api/users/{user_id}/todos/{id}` (plural). (`DELETE
   /api/todo/{id}` also answered 404 in an exploratory call on an existing
   user todo; that call is not in the table.)
2. **Per-user limit is off by one (row X1).** The docs and the error message say
   25 todos per user. The 26th todo was accepted (the list held 26) and the 27th
   was refused with `403`. The first run counted 26 at the refusal; the second run asked the server for its own count (row X1) and got 26 again.
3. **`completed` and `enabled`/`admin` change type between routes (rows L6, T9).**
   Writes answer `"completed": true`, reads answer `"completed": 0|1`; register
   answers `enabled`/`admin` as booleans, login as `1`/`0`. The docs say boolean.
   The client accepts both.
4. **Failed login answers 404 (rows L1, L2)** rather than 401, with the email in
   the message. The docs list only 200 for login. Wrong password and unknown
   email give the same answer (good: no account enumeration), but 404 is an
   unusual status for it.
5. **Inconsistent error formats.** Most errors are `{"message": "..."}`, but a
   missing todo on GET is a bare JSON string and token errors are plain text
   with a trailing digit (`Unauthorized.1`, `Unauthorized.2`).
6. **Duplicate registration answers 400 (row R6)**, not 409 or 422. The Swagger
   intro says 409 is used when the key delegates to an external auth service; it
   does not document 400 here.
7. **Docs mention an unrelated registration link** (`https://todoapi.net/register`)
   in the Swagger intro, not `keys.simpleapi.dev`.
8. **`user_id` in the path is ignored (exploratory call, not in the table).**
   Once, while exploring, a read-only `GET /api/users/999999/todos` with a valid
   user's token returned that user's own todos with `200`; the id in the path
   was ignored in favour of the token's. This is a deliberate-looking design but
   undocumented. Note that this was the only request in the whole session that
   sent a `user_id` other than the logged-in user's; the app and the harness
   always send the user's own id. The harness's "someone else's todo" checks
   (O2-O6) use user B's own id with user A's todo id.

Things that behaved as documented or better: the key is required everywhere
(K1-K3); validation answers 422 with readable messages (R1-R3, T3-T5, U4);
other users' todos are invisible and untouchable (O2-O6); tokens die on logout
and on user deletion (S2, CA2, CB2); the forgot-password answer is identical for
real and unknown emails (F1, F2); CORS preflight allows every method and header
the app uses (checked separately with `curl`, not in the table).

## Not tested and why

- **Completing a password reset.** Only the request half was exercised
  (`/forgot`, and `/reset` with a wrong code). Using the real emailed code would
  change a user's password and needs reading a mailbox; the app's reset screen
  is covered by widget tests with mocked HTTP only.
- **The 10-users-per-key limit.** It would need 10 users on the shared demo key
  and could block other developers using it; not worth the risk.
- **The 100 generic (key-level) todos and the other key-level routes**
  (`GET/POST/PUT/DELETE /api/todos...`, `DELETE /api/todos/`, `DELETE
  /api/users`, `GET /api/users`): the app does not use them (only `GET
  /api/todos` as a key check), and the delete-all routes could wipe other
  people's data on the shared demo key.
- **Admin routes and `POST /api/users/register/confirm`** (needs the key
  owner's own email and an emailed code).
- **The 409 "external auth service" mode.** It needs the key to be pointed at
  another auth service (`POST https://keys.simpleapi.dev/api/keys/auth-url`),
  which changes the key's settings; the 409 text in the app is covered by a
  widget test with a mocked body only.
- **A real 429.** None occurred at one request per second; the 429 text in the
  app is covered by a widget test with a mocked answer only.
- **The deployed site in a real browser.** The release build compiles and CORS
  preflights pass, but I did not drive the UI in a browser; the widget tests
  drive the same screens with mocked HTTP.
- **Rate-limit behaviour, concurrency, large payloads, token expiry over time,
  `meta` on todos, and the `PATCH`/`HEAD` methods.**
