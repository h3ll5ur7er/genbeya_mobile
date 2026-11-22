import 'package:flutter_test/flutter_test.dart';
import 'package:genbeya_mobile/managers/web_links.dart';

void main() {
  test('forge web links: the repository and what follows it', () {
    expect(parseWebLink('https://github.com/genbeya/genbeya'), (
      remote: 'https://github.com/genbeya/genbeya',
      rest: null,
    ));
    expect(
      parseWebLink(
        'https://github.com/genbeya/genbeya/blob/develop/tasks/GENBEYA-12.md#L3',
      ),
      (
        remote: 'https://github.com/genbeya/genbeya',
        rest: 'develop/tasks/GENBEYA-12.md',
      ),
    );
    expect(parseWebLink('https://github.com/a/b/tree/feature/x/docs'), (
      remote: 'https://github.com/a/b',
      rest: 'feature/x/docs',
    ));
    expect(parseWebLink('https://github.com/a/b/pulls'), (
      remote: 'https://github.com/a/b',
      rest: null,
    ));
    expect(
      parseWebLink(
        'https://gitlab.com/group/sub/repo/-/blob/main/docs/Getting%20started.md',
      ),
      (
        remote: 'https://gitlab.com/group/sub/repo',
        rest: 'main/docs/Getting started.md',
      ),
    );
    expect(parseWebLink('https://gitlab.example.com/team/app'), (
      remote: 'https://gitlab.example.com/team/app',
      rest: null,
    ));
    expect(parseWebLink('https://bitbucket.org/team/repo/src/main/README.md'), (
      remote: 'https://bitbucket.org/team/repo',
      rest: 'main/README.md',
    ));
    expect(parseWebLink('https://example.com/a/b/blob/main/x'), isNull);
    expect(parseWebLink('https://github.com/a'), isNull);
    expect(parseWebLink('genbeya://open?x'), isNull);
    expect(parseWebLink('not a link'), isNull);
  });

  test('the path after a branch whose name may hold slashes', () {
    expect(
      pathOnBranch('feature/x/docs/Home.md', ['main', 'feature/x']),
      'docs/Home.md',
    );
    expect(
      pathOnBranch('main/tasks/A-1.md', ['main', 'genbeya']),
      'tasks/A-1.md',
    );
    expect(
      pathOnBranch('genbeya/tasks/A-1.md', ['main', 'genbeya']),
      'tasks/A-1.md',
    );
    expect(pathOnBranch('main', ['main']), '');
    expect(pathOnBranch('other/x.md', ['main']), isNull);
  });
}
