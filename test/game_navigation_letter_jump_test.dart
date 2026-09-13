import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/letter_jump.dart';

void main() {
  const groups = ['A', 'A', 'B', 'B', 'D', 'D'];
  int? target(int current, bool forward) => LetterJump.targetIndex(
    length: groups.length,
    currentIndex: current,
    forward: forward,
    letterAt: (index) => groups[index],
  );

  test('next group lands on its first game and skips missing letters', () {
    expect(target(0, true), 2);
    expect(target(1, true), 2);
    expect(target(3, true), 4);
  });
  test('previous group lands on its first game from inside a group', () {
    expect(target(3, false), 0);
    expect(target(5, false), 2);
  });
  test('alphabet ends do not move selection', () {
    expect(target(1, false), isNull);
    expect(target(4, true), isNull);
  });
}
