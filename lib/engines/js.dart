/// JavaScript semantics that Genbeya's engines rely on, so the ports behave
/// the same: `String(value)`, `JSON.stringify` of numbers, record checks.
library;

import 'dart:convert';

bool isRecord(Object? value) => value is Map;

/// `String(value)` in JavaScript, for the values YAML yields.
String jsString(Object? value) {
  if (value == null) return 'null';
  if (value is num) return jsNumber(value);
  if (value is List) {
    return value.map((v) => v == null ? '' : jsString(v)).join(',');
  }
  if (value is Map) return '[object Object]';
  return value.toString();
}

/// A number as JavaScript prints it: 8, 3.5, 100 (not 100.0).
String jsNumber(num value) {
  if (value is int) return value.toString();
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
  if (value == value.truncateToDouble() && value.abs() < 1e21) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// `JSON.stringify(value)` for comparing values the way the engines do.
String jsJson(Object? value) => jsonEncode(_normalize(value));

Object? _normalize(Object? value) {
  if (value is double &&
      value == value.truncateToDouble() &&
      value.abs() < 1e21) {
    return value.toInt();
  }
  if (value is List) return [for (final v in value) _normalize(v)];
  if (value is Map) {
    return {
      for (final e in value.entries) e.key.toString(): _normalize(e.value),
    };
  }
  return value;
}

/// `Number.isInteger(value)`.
bool isInteger(Object? value) =>
    value is int ||
    (value is double && value.isFinite && value == value.truncateToDouble());

/// `value.trim()` for strings, "" for anything else (Genbeya's `trimmed`).
String trimmed(Object? value) => value is String ? value.trim() : '';
