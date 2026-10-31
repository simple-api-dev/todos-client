/// The small data types shared by the API client and the screens.
library;

/// Thrown for any non-2xx answer. [message] is the API's own text,
/// e.g. "Invalid email or password."
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class Todo {
  const Todo({required this.id, required this.description, required this.completed});

  final int id;
  final String description;
  final bool completed;

  /// `completed` is a real boolean on every route.
  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: (json['id'] as num).toInt(),
      description: '${json['description'] ?? ''}',
      completed: json['completed'] == true,
    );
  }
}

/// What login / register answer with. [token] is null only for a 2xx answer
/// that carried no token.
class AuthResult {
  const AuthResult({this.token, this.id, this.name = '', this.message = ''});

  final String? token;
  final int? id;
  final String name;
  final String message;
}
