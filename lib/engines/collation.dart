/// Sorting names and titles as Genbeya does, with
/// `a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" })`:
/// ICU's root order (spaces, then punctuation and symbols, then numbers by
/// value, then characters that weigh like digits but aren't (², ①), then
/// letters), ignoring case and accents. Dart has no ICU, so the
/// weights come from a table generated from Node's ICU
/// (tool/conformance/make-collation.mjs); conformance cases compare the
/// results with ICU's. Two strings that differ only in case or accents
/// compare equal, and [stableSort] keeps them in the order they came, as
/// JavaScript's sort does.
library;

import 'collation_table.dart';
import 'unicode.dart';

final _digitLow = collationDigitWeight;

/// One unit of comparison: a primary weight, or a run of digits by value.
sealed class _Element {
  const _Element();
}

class _Weight extends _Element {
  const _Weight(this.weight);
  final int weight;
}

class _Number extends _Element {
  const _Number(this.digits);

  /// The digits without leading zeros ("0" for zero).
  final String digits;
}

int _weightOf(int code) {
  final weight = collationWeights[code];
  if (weight != null) return weight;
  if (code >= 0xac00 && code <= 0xd7a3) {
    return collationHangulWeight + code - 0xac00;
  }
  // ICU's implicit weights: unified Han, then the other Han, then the rest.
  const block = 0x110000;
  final coreHan =
      (code >= 0x4e00 && code <= 0x9fff) || (code >= 0xf900 && code <= 0xfaff);
  final otherHan =
      (code >= 0x3400 && code <= 0x4dbf) ||
      (code >= 0x20000 && code <= 0x3ffff);
  final group = coreHan ? 0 : (otherHan ? 1 : 2);
  return collationMaxWeight + 1 + group * block + code;
}

List<_Element> _elements(String text, {bool numeric = true}) {
  final elements = <_Element>[];
  final digits = StringBuffer();
  void endNumber() {
    if (digits.isEmpty) return;
    final value = digits.toString().replaceFirst(RegExp(r'^0+(?=.)'), '');
    elements.add(_Number(value));
    digits.clear();
  }

  for (final code in text.runes) {
    if (collationIgnorable.contains(code)) continue;
    final expansion = collationExpansions[code];
    if (expansion != null) {
      endNumber();
      elements.addAll(expansion.map(_Weight.new));
      continue;
    }
    final digit = numeric ? collationDigits[code] : null;
    if (digit != null) {
      digits.write(digit);
      continue;
    }
    endNumber();
    elements.add(_Weight(_weightOf(code)));
  }
  endNumber();
  return elements;
}

int _compareNumbers(String a, String b) {
  if (a.length != b.length) return a.length < b.length ? -1 : 1;
  return a.compareTo(b).sign;
}

int _compareElements(_Element a, _Element b) => switch ((a, b)) {
  (_Number(digits: final x), _Number(digits: final y)) => _compareNumbers(x, y),
  (_Number(), _Weight(:final weight)) => weight < _digitLow ? 1 : -1,
  (_Weight(:final weight), _Number()) => weight < _digitLow ? -1 : 1,
  (_Weight(weight: final x), _Weight(weight: final y)) => (x - y).sign,
};

/// Negative, zero or positive as [a] sorts before, with or after [b].
int collate(String a, String b) => _collatePrimary(a, b, numeric: true);

/// As [collate], but digits are characters, not numbers:
/// `a.localeCompare(b, undefined, { sensitivity: "base" })`.
int collateBase(String a, String b) => _collatePrimary(a, b, numeric: false);

int _collatePrimary(String a, String b, {required bool numeric}) {
  if (a == b) return 0;
  final x = _elements(a, numeric: numeric);
  final y = _elements(b, numeric: numeric);
  for (var i = 0; i < x.length && i < y.length; i++) {
    final order = _compareElements(x[i], y[i]);
    if (order != 0) return order;
  }
  return (x.length - y.length).sign;
}

/// Negative, zero or positive as [a] sorts before, with or after [b] by a
/// plain `a.localeCompare(b)`: ICU's root order at full strength. Base
/// letters decide first, then accents, then case (lower before upper);
/// digits are characters, not numbers.
int collateFull(String a, String b) {
  if (a == b) return 0;
  final x = _fullElements(a);
  final y = _fullElements(b);
  for (final level in [0, 1, 2]) {
    final p = x[level];
    final q = y[level];
    for (var i = 0; i < p.length && i < q.length; i++) {
      if (p[i] != q[i]) return p[i] < q[i] ? -1 : 1;
    }
    if (p.length != q.length) return p.length < q.length ? -1 : 1;
  }
  return 0;
}

const _ligature = 5000;

/// Primary, secondary and tertiary weights of [text], decomposed.
List<List<int>> _fullElements(String text) {
  final primary = <int>[];
  final secondary = <int>[];
  final tertiary = <int>[];
  for (final code in nfd(text).runes) {
    final markWeight = collationSecondary[code];
    if (collationIgnorable.contains(code)) {
      if (markWeight != null) secondary.add(markWeight);
      continue;
    }
    final case_ = collationTertiary[code] ?? 0;
    final expansion = collationExpansions[code];
    if (expansion != null) {
      // ICU weighs æ as a, a secondary weight above every accent, then e.
      primary.addAll(expansion);
      secondary.addAll([1, _ligature, 1]);
      tertiary.addAll([for (final _ in expansion) case_]);
      continue;
    }
    primary.add(_weightOf(code));
    // A letter like ø weighs as its base letter followed by a mark.
    secondary.addAll(markWeight == null ? const [1] : [1, 2000 + markWeight]);
    tertiary.add(case_);
  }
  return [primary, secondary, tertiary];
}

/// Sorts [list] in place, keeping equal elements in their order, as
/// JavaScript's `Array.prototype.sort` does (Dart's `sort` may not).
void stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  if (list.length < 2) return;
  final sorted = _mergeSort(list, compare);
  for (var i = 0; i < list.length; i++) {
    list[i] = sorted[i];
  }
}

/// A sorted copy of [items], keeping equal elements in their order.
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) =>
    _mergeSort(items.toList(), compare);

List<T> _mergeSort<T>(List<T> list, int Function(T a, T b) compare) {
  if (list.length < 2) return list;
  final middle = list.length ~/ 2;
  final left = _mergeSort(list.sublist(0, middle), compare);
  final right = _mergeSort(list.sublist(middle), compare);
  final merged = <T>[];
  var i = 0;
  var j = 0;
  while (i < left.length && j < right.length) {
    merged.add(compare(right[j], left[i]) < 0 ? right[j++] : left[i++]);
  }
  return merged
    ..addAll(left.skip(i))
    ..addAll(right.skip(j));
}
