import 'package:flutter_test/flutter_test.dart';
import 'package:tents/ui/features/game/views/game_script_interpreter.dart';

void main() {
  test('executes nested loops and reads tile states', () async {
    final board = List.generate(3, (_) => List<String>.filled(3, 'empty'));
    board[1][1] = 'tree';
    board[0][0] = 'cross';
    final messages = <String>[];

    final interpreter = GameScriptInterpreter(
      gridSize: 3,
      getCell: (row, column) => board[row - 1][column - 1],
      setCell: (row, column, state) {
        board[row - 1][column - 1] = state;
      },
      showPopup: messages.add,
      wait: (_) {},
    );

    await interpreter.run('''
for row in range(1, grid_size + 1):
    for col in range(1, grid_size + 1):
        state = tile(row, col)
        if state == "empty":
            tent(row, col)
        elif state == "tree":
            popup("Tree at " + str(row) + ", " + str(col))
        else:
            cross(row, col)
''');

    expect(board[1][1], 'tree');
    expect(board[0][0], 'cross');
    expect(board[0][1], 'tent');
    expect(board[2][2], 'tent');
    expect(messages, ['Tree at 2, 2']);
  });

  test('supports variables in commands and if/else blocks', () async {
    final board = List.generate(4, (_) => List<String>.filled(4, 'empty'));
    final messages = <String>[];
    final interpreter = GameScriptInterpreter(
      gridSize: 4,
      getCell: (row, column) => board[row - 1][column - 1],
      setCell: (row, column, state) {
        board[row - 1][column - 1] = state;
      },
      showPopup: messages.add,
      wait: (_) {},
    );

    await interpreter.run('''
row = 1
column = grid_size - 1
if tile(row, column) == "empty" and row < column:
    tent(row, column)
else:
    popup("Cell is " + tile(row, column))
''');

    expect(board[0][2], 'tent');
    expect(messages, isEmpty);
  });

  test('reports out-of-range coordinates', () async {
    final interpreter = GameScriptInterpreter(
      gridSize: 3,
      getCell: (_, __) => 'empty',
      setCell: (_, __, ___) {},
      showPopup: (_) {},
      wait: (_) {},
    );

    expect(
      () => interpreter.run('tent(1, 4)'),
      throwsFormatException,
    );
  });
}
