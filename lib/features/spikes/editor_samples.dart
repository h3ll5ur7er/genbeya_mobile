/// The text both editor spikes (GM-4) open: a short page, or about 2,000 lines.
library;

const shortSample = '''# Meeting notes

Agreed with @alex on 2026-11-21:

- [x] Render pages with the kit
- [ ] Try the editor on the phone: type, select, undo, autocorrect
- [ ] Compare with [[GM-4]]

> [!NOTE]
> Type [[ for references, @ for people and // for dates.

```mermaid
flowchart LR
  phone[Phone] --> kit[Kit]
```
''';

/// About 2,000 lines of varied Markdown, for scrolling and typing in a long file.
String longSample() {
  final buffer = StringBuffer('# A long page\n\n');
  for (var i = 1; buffer.toString().split('\n').length < 2000; i++) {
    buffer
      ..writeln('## Section $i')
      ..writeln()
      ..writeln(
        'Paragraph $i refers to [[GM-${i % 28 + 1}]] and was written by @alex on 2026-11-${(i % 28 + 1).toString().padLeft(2, '0')}.',
      )
      ..writeln(
        'It goes on long enough to wrap on a phone, with **bold**, _italic_ and `code` in it.',
      )
      ..writeln()
      ..writeln('- [ ] Item one of section $i')
      ..writeln('- [x] Item two of section $i')
      ..writeln()
      ..writeln('```dart')
      ..writeln('final section = $i;')
      ..writeln('```')
      ..writeln();
  }
  return buffer.toString();
}
