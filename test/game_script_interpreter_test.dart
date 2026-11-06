import 'dart:io';
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
      getRowTarget: (_) => 0,
      getColumnTarget: (_) => 0,
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
      getRowTarget: (_) => 0,
      getColumnTarget: (_) => 0,
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
      getRowTarget: (_) => 0,
      getColumnTarget: (_) => 0,
    );

    expect(
      () => interpreter.run('tent(1, 4)'),
      throwsFormatException,
    );
  });


  test('supports list literals, nested index mutation, while, break and functions', () async {
    final messages = <String>[];
    final interpreter = GameScriptInterpreter(
      gridSize: 3,
      getCell: (_, __) => 'empty',
      setCell: (_, __, ___) {},
      showPopup: messages.add,
      wait: (_) {},
      getRowTarget: (row) => row,
      getColumnTarget: (column) => column + 1,
    );

    await interpreter.run('''
def factorial(value):
    if value <= 1:
        return 1
    return value * factorial(value - 1)

numbers = [1, 2]
append(numbers, 3)
matrix = [["empty", "empty"], ["empty", "empty"]]
matrix[1][0] = "tent"
counter = 0
while counter < 10:
    counter = counter + 1
    if counter == 3:
        break
result = factorial(5)
popup(str(result) + ":" + str(len(numbers)) + ":" + matrix[1][0] + ":" + str(counter))
''');

    expect(messages, ['120:3:tent:3']);
  });

  test('exposes row and column target values to functions and expressions', () async {
    final messages = <String>[];
    final interpreter = GameScriptInterpreter(
      gridSize: 3,
      getCell: (_, __) => 'empty',
      setCell: (_, __, ___) {},
      showPopup: messages.add,
      wait: (_) {},
      getRowTarget: (row) => [2, 0, 1][row - 1],
      getColumnTarget: (column) => [1, 1, 1][column - 1],
    );

    await interpreter.run('''
def target_sum():
    total = 0
    for index in range(1, grid_size + 1):
        total = total + row_target(index)
    return total

popup(str(target_sum()) + ":" + str(column_target(2)))
''');

    expect(messages, ['3:1']);
  });

  test('executes the standalone Tents solver script', () async {
    final board = List.generate(4, (_) => List<String>.filled(4, 'empty'));
    board[0][0] = 'tree';
    board[2][2] = 'tree';
    final messages = <String>[];
    final interpreter = GameScriptInterpreter(
      gridSize: 4,
      getCell: (row, column) => board[row - 1][column - 1],
      setCell: (row, column, state) {
        board[row - 1][column - 1] = state;
      },
      showPopup: messages.add,
      wait: (_) {},
      getRowTarget: (row) => [1, 0, 1, 0][row - 1],
      getColumnTarget: (column) => [0, 2, 0, 0][column - 1],
    );
    final script = await File('scripts/tents_solver.tents').readAsString();

    await interpreter.run(script);

    expect(board[0][1], 'tent');
    expect(board[2][1], 'tent');
    expect(board[0][0], 'tree');
    expect(board[2][2], 'tree');
    expect(messages, ['Puzzle solved.']);
  });

}
