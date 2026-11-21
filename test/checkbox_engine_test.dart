import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/engines/checkbox_engine.dart';

/// Genbeya's bytes are checked by the conformance cases (page.toggle,
/// task.toggle); these cover the stricter check the app adds.
void main() {
  group('isCheckboxItemAt', () {
    const source =
        '# T\n\n- [ ] a\n  * [x] b\n1. [X] c\n10) [ ] d\n> + [ ] e\nNo [ ] here\n';
    int at(String text) => source.indexOf(text);

    test('accepts the start of every kind of task list item', () {
      for (final item in [
        '- [ ] a',
        '* [x] b',
        '1. [X] c',
        '10) [ ] d',
        '+ [ ] e',
      ]) {
        expect(isCheckboxItemAt(source, at(item)), isTrue, reason: item);
      }
    });

    test('refuses offsets inside an item, before it, or in prose', () {
      expect(isCheckboxItemAt(source, at('- [ ] a') + 1), isFalse);
      expect(isCheckboxItemAt(source, at('  * [x] b')), isFalse);
      expect(isCheckboxItemAt(source, at('No [ ] here')), isFalse);
      expect(isCheckboxItemAt(source, at('[ ] here')), isFalse);
    });

    test('refuses offsets outside the text', () {
      expect(isCheckboxItemAt(source, -1), isFalse);
      expect(isCheckboxItemAt(source, source.length), isFalse);
      expect(isCheckboxItemAt(source, source.length + 10), isFalse);
    });

    test('refuses a list item without a checkbox', () {
      expect(isCheckboxItemAt('- plain\n', 0), isFalse);
      expect(isCheckboxItemAt('-[ ] tight\n', 0), isFalse);
    });
  });

  test('a page offset counts from the end of its frontmatter', () {
    const content = '---\r\ntitle: x\r\n---\r\n- [ ] One\r\n';
    expect(
      togglePageCheckbox(content, 0),
      '---\r\ntitle: x\r\n---\r\n- [x] One\r\n',
    );
    expect(togglePageCheckbox(content, 3), isNull);
    expect(togglePageCheckbox(content, -1), isNull);
  });

  test('toggleCheckboxAt keeps Genbeya\'s edges', () {
    expect(toggleCheckboxAt('- [ ] a', 50), '- [ ] a');
    expect(toggleCheckboxAt('no box', 0), 'no box');
    expect(() => toggleCheckboxAt('- [ ] a', -1), throwsRangeError);
  });
}
