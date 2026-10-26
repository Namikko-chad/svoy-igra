/// Tolerant readers for hand-written `fromJson` factories: a missing or
/// mistyped field yields a default instead of a crash on the TV.
typedef Json = Map<String, dynamic>;

Json asJson(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};

String asString(Object? v, [String fallback = '']) => v is String ? v : fallback;

String? asStringOrNull(Object? v) => v is String ? v : null;

/// A string that is absent, null or blank reads as null.
String? asNonEmptyOrNull(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

int asInt(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

int? asIntOrNull(Object? v) => v is num ? v.toInt() : null;

bool asBool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

List<T> asList<T>(Object? v, T Function(Object? item) parse) =>
    v is List ? v.map(parse).toList(growable: false) : <T>[];
