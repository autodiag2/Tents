import 'dart:async';

typedef ScriptSetCell = FutureOr<void> Function(int row, int column, String state);
typedef ScriptGetCell = String Function(int row, int column);
typedef ScriptPopup = FutureOr<void> Function(String text);
typedef ScriptWait = FutureOr<void> Function(int milliseconds);

class GameScriptInterpreter {
  GameScriptInterpreter({
    required this.gridSize,
    required this.getCell,
    required this.setCell,
    required this.showPopup,
    required this.wait,
  });

  final int gridSize;
  final ScriptGetCell getCell;
  final ScriptSetCell setCell;
  final ScriptPopup showPopup;
  final ScriptWait wait;

  static const int _maxSourceLines = 10000;
  static const int _maxExecutionSteps = 10000;
  static const int _maxLoopIterations = 5000;
  int _executionSteps = 0;
  late Map<String, Object?> _variables;

  Future<void> run(String source) async {
    final statements = _Parser(source).parse();
    _executionSteps = 0;
    _variables = {'grid_size': gridSize, 'size': gridSize};
    await _executeBlock(statements);
  }

  Future<void> _executeBlock(List<_Statement> statements) async {
    for (final statement in statements) {
      _executionSteps++;
      if (_executionSteps > _maxExecutionSteps) {
        throw StateError('Script stopped: execution limit exceeded.');
      }
      if (statement is _Assignment) {
        _variables[statement.name] = await _evaluate(statement.value, statement.line);
      } else if (statement is _ExpressionStatement) {
        await _evaluate(statement.expression, statement.line);
      } else if (statement is _IfStatement) {
        final condition = await _evaluate(statement.condition, statement.line);
        await _executeBlock(_truthy(condition) ? statement.body : statement.elseBody);
      } else if (statement is _ForStatement) {
        final iterable = await _evaluate(statement.iterable, statement.line);
        if (iterable is! List<Object?>) {
          _error(statement.line, 'for loops require range(...).');
        }
        if (iterable.length > _maxLoopIterations) {
          _error(statement.line, 'Loop exceeds the $_maxLoopIterations iteration limit.');
        }
        for (final value in iterable) {
          _variables[statement.variable] = value;
          await _executeBlock(statement.body);
        }
      }
    }
  }

  Future<Object?> _evaluate(_Expression expression, int line) async {
    if (expression is _Literal) return expression.value;
    if (expression is _Variable) {
      if (!_variables.containsKey(expression.name)) {
        _error(line, 'Unknown variable "' + expression.name + '".');
      }
      return _variables[expression.name];
    }
    if (expression is _Unary) {
      final value = await _evaluate(expression.operand, line);
      if (expression.operator == 'not') return !_truthy(value);
      if (value is! num) _error(line, 'Unary ' + expression.operator + ' requires a number.');
      return expression.operator == '-' ? -value : value;
    }
    if (expression is _Binary) {
      final left = await _evaluate(expression.left, line);
      if (expression.operator == 'and') {
        return _truthy(left) ? await _evaluate(expression.right, line) : left;
      }
      if (expression.operator == 'or') {
        return _truthy(left) ? left : await _evaluate(expression.right, line);
      }
      final right = await _evaluate(expression.right, line);
      return _applyBinary(expression.operator, left, right, line);
    }
    if (expression is _Call) {
      final arguments = <Object?>[];
      for (final argument in expression.arguments) {
        arguments.add(await _evaluate(argument, line));
      }
      return _call(expression.name, arguments, line);
    }
    _error(line, 'Unsupported expression.');
  }

  Object? _applyBinary(String operator, Object? left, Object? right, int line) {
    switch (operator) {
      case '==':
        return left == right;
      case '!=':
        return left != right;
      case 'in':
        if (right is List) return right.contains(left);
        if (right is String && left is String) return right.contains(left);
        _error(line, 'The right side of "in" must be a string or range.');
      case '+':
        if (left is String && right is String) return left + right;
        if (left is num && right is num) return left + right;
        _error(line, 'The + operator requires two numbers or two strings.');
      case '-':
      case '*':
      case '/':
      case '//':
      case '%':
        if (left is! num || right is! num) {
          _error(line, 'Operator "' + operator + '" requires numeric values.');
        }
        if ((operator == '/' || operator == '//' || operator == '%') && right == 0) {
          _error(line, 'Division by zero.');
        }
        switch (operator) {
          case '-':
            return left - right;
          case '*':
            return left * right;
          case '/':
            return left / right;
          case '//':
            return (left / right).floor();
          default:
            return left % right;
        }
      case '<':
      case '<=':
      case '>':
      case '>=':
        int comparison;
        if (left is num && right is num) {
          comparison = left.compareTo(right);
        } else if (left is String && right is String) {
          comparison = left.compareTo(right);
        } else {
          _error(line, 'Comparison requires two numbers or two strings.');
        }
        switch (operator) {
          case '<':
            return comparison < 0;
          case '<=':
            return comparison <= 0;
          case '>':
            return comparison > 0;
          default:
            return comparison >= 0;
        }
    }
    _error(line, 'Unknown operator "' + operator + '".');
  }

  Future<Object?> _call(String name, List<Object?> arguments, int line) async {
    switch (name) {
      case 'range':
        if (arguments.isEmpty || arguments.length > 3) {
          _error(line, 'range() expects one, two or three arguments.');
        }
        final start = arguments.length == 1 ? 0 : _integer(arguments[0], line);
        final stop = _integer(arguments.length == 1 ? arguments[0] : arguments[1], line);
        final step = arguments.length == 3 ? _integer(arguments[2], line) : 1;
        if (step == 0) _error(line, 'range() step cannot be zero.');
        final values = <Object?>[];
        var current = start;
        while (step > 0 ? current < stop : current > stop) {
          if (values.length >= _maxLoopIterations) {
            _error(line, 'range() exceeds the $_maxLoopIterations iteration limit.');
          }
          values.add(current);
          current += step;
        }
        return values;
      case 'tile':
      case 'get_tile':
        _requireArgumentCount(name, arguments, 2, line);
        final row = _coordinate(arguments[0], line);
        final column = _coordinate(arguments[1], line);
        _validateCell(row, column, line);
        return getCell(row, column);
      case 'tent':
      case 'cross':
      case 'clear':
        _requireArgumentCount(name, arguments, 2, line);
        final row = _coordinate(arguments[0], line);
        final column = _coordinate(arguments[1], line);
        _validateCell(row, column, line);
        await setCell(row, column, name == 'clear' ? 'empty' : name);
        return null;
      case 'wait':
        _requireArgumentCount(name, arguments, 1, line);
        final milliseconds = _integer(arguments[0], line);
        if (milliseconds < 0 || milliseconds > 10000) {
          _error(line, 'wait() must be between 0 and 10000 milliseconds.');
        }
        await wait(milliseconds);
        return null;
      case 'popup':
      case 'message':
        _requireArgumentCount(name, arguments, 1, line);
        await showPopup(_toString(arguments[0]));
        return null;
      case 'str':
        _requireArgumentCount(name, arguments, 1, line);
        return _toString(arguments[0]);
      case 'int':
        _requireArgumentCount(name, arguments, 1, line);
        final value = arguments[0];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
        _error(line, 'int() requires an integer-compatible value.');
      case 'len':
        _requireArgumentCount(name, arguments, 1, line);
        if (arguments[0] is String) return (arguments[0] as String).length;
        if (arguments[0] is List) return (arguments[0] as List).length;
        _error(line, 'len() requires a string or range.');
    }
    _error(line, 'Unknown instruction "' + name + '".');
  }

  int _coordinate(Object? value, int line) => _integer(value, line);

  int _integer(Object? value, int line) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    _error(line, 'Expected an integer value.');
  }

  void _validateCell(int row, int column, int line) {
    if (row < 1 || column < 1 || row > gridSize || column > gridSize) {
      _error(line, 'Coordinates must be between 1 and $gridSize.');
    }
  }

  void _requireArgumentCount(String name, List<Object?> arguments, int expected, int line) {
    if (arguments.length != expected) {
      _error(line, name + '() expects ' + expected.toString() + ' argument(s).');
    }
  }

  bool _truthy(Object? value) {
    if (value == null || value == false) return false;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value is List) return value.isNotEmpty;
    return true;
  }

  String _toString(Object? value) {
    if (value == null) return 'None';
    if (value == true) return 'True';
    if (value == false) return 'False';
    return value.toString();
  }

  Never _error(int line, String message) {
    throw FormatException('Line ' + line.toString() + ': ' + message);
  }
}

abstract class _Statement {
  const _Statement(this.line);
  final int line;
}

class _Assignment extends _Statement {
  const _Assignment(super.line, this.name, this.value);
  final String name;
  final _Expression value;
}

class _ExpressionStatement extends _Statement {
  const _ExpressionStatement(super.line, this.expression);
  final _Expression expression;
}

class _IfStatement extends _Statement {
  const _IfStatement(super.line, this.condition, this.body, this.elseBody);
  final _Expression condition;
  final List<_Statement> body;
  final List<_Statement> elseBody;
}

class _ForStatement extends _Statement {
  const _ForStatement(super.line, this.variable, this.iterable, this.body);
  final String variable;
  final _Expression iterable;
  final List<_Statement> body;
}

abstract class _Expression {
  const _Expression();
}

class _Literal extends _Expression {
  const _Literal(this.value);
  final Object? value;
}

class _Variable extends _Expression {
  const _Variable(this.name);
  final String name;
}

class _Unary extends _Expression {
  const _Unary(this.operator, this.operand);
  final String operator;
  final _Expression operand;
}

class _Binary extends _Expression {
  const _Binary(this.operator, this.left, this.right);
  final String operator;
  final _Expression left;
  final _Expression right;
}

class _Call extends _Expression {
  const _Call(this.name, this.arguments);
  final String name;
  final List<_Expression> arguments;
}

class _ScriptLine {
  const _ScriptLine(this.indent, this.text, this.number);
  final int indent;
  final String text;
  final int number;
}

class _Parser {
  _Parser(String source) {
    final rawLines = source.replaceAll('\t', '    ').split(RegExp(r'\r?\n'));
    if (rawLines.length > GameScriptInterpreter._maxSourceLines) {
      throw const FormatException('Script exceeds the 10000 line limit.');
    }
    for (var i = 0; i < rawLines.length; i++) {
      final withoutComment = _stripComment(rawLines[i]);
      final trimmed = withoutComment.trimLeft();
      final content = trimmed.trimRight();
      if (content.isEmpty) continue;
      final indent = withoutComment.length - trimmed.length;
      _lines.add(_ScriptLine(indent, _normaliseCommand(content), i + 1));
    }
  }

  final List<_ScriptLine> _lines = [];
  int _position = 0;

  List<_Statement> parse() {
    final result = _parseBlock(0);
    if (_position < _lines.length) {
      _error(_lines[_position], 'Unexpected indentation.');
    }
    return result;
  }

  List<_Statement> _parseBlock(int indent) {
    final statements = <_Statement>[];
    while (_position < _lines.length) {
      final line = _lines[_position];
      if (line.indent < indent) break;
      if (line.indent > indent) _error(line, 'Unexpected indentation.');
      if (line.text == 'else:' || line.text.startsWith('elif ')) {
        final branch = line.text.startsWith('elif ') ? 'elif' : 'else';
        _error(line, 'Unexpected ' + branch + '.');
      }
      if (line.text.startsWith('if ')) {
        statements.add(_parseIf(indent));
      } else if (line.text.startsWith('for ')) {
        statements.add(_parseFor(indent));
      } else {
        _position++;
        final assignment = _findAssignment(line.text);
        if (assignment != null) {
          final name = assignment.$1;
          if (_reservedNames.contains(name)) _error(line, '"' + name + '" is reserved.');
          final expression = _parseExpression(assignment.$2, line);
          statements.add(_Assignment(line.number, name, expression));
        } else {
          statements.add(_ExpressionStatement(line.number, _parseExpression(line.text, line)));
        }
      }
    }
    return statements;
  }

  _IfStatement _parseIf(int indent) {
    final line = _lines[_position++];
    final isElseIf = line.text.startsWith('elif ');
    if (!line.text.endsWith(':')) _error(line, 'if/elif statement must end with ":".');
    final conditionText = line.text.substring(isElseIf ? 5 : 3, line.text.length - 1).trim();
    if (conditionText.isEmpty) _error(line, 'Condition cannot be empty.');
    final condition = _parseExpression(conditionText, line);
    final body = _parseSuite(indent, line);
    var elseBody = <_Statement>[];
    if (_position < _lines.length && _lines[_position].indent == indent) {
      final next = _lines[_position];
      if (next.text.startsWith('elif ')) {
        elseBody = [_parseIf(indent)];
      } else if (next.text == 'else:') {
        _position++;
        elseBody = _parseSuite(indent, next);
      }
    }
    return _IfStatement(line.number, condition, body, elseBody);
  }

  _ForStatement _parseFor(int indent) {
    final line = _lines[_position++];
    final match = RegExp(r'^for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\s+(.+):$').firstMatch(line.text);
    if (match == null) _error(line, 'Expected: for variable in range(...):');
    final variable = match.group(1)!;
    if (_reservedNames.contains(variable)) _error(line, '"' + variable + '" is reserved.');
    final iterable = _parseExpression(match.group(2)!, line);
    final body = _parseSuite(indent, line);
    return _ForStatement(line.number, variable, iterable, body);
  }

  List<_Statement> _parseSuite(int parentIndent, _ScriptLine header) {
    if (_position >= _lines.length || _lines[_position].indent <= parentIndent) {
      _error(header, 'Expected an indented block.');
    }
    return _parseBlock(_lines[_position].indent);
  }

  _Expression _parseExpression(String source, _ScriptLine line) {
    try {
      return _ExpressionParser(source).parse();
    } on FormatException catch (error) {
      _error(line, error.message?.toString() ?? 'Invalid expression.');
    }
  }

  static final Set<String> _reservedNames = {
    'if', 'else', 'elif', 'for', 'in', 'and', 'or', 'not',
    'True', 'False', 'None', 'range', 'tile', 'get_tile',
    'tent', 'cross', 'clear', 'wait', 'popup', 'message',
    'str', 'int', 'len', 'grid_size', 'size',
  };

  String _normaliseCommand(String text) {
    final match = RegExp(r'^(tent|cross|clear|wait)\s+(.+)$').firstMatch(text);
    if (match == null) return text;
    final parts = match.group(2)!.trim().split(RegExp(r'\s+'));
    return match.group(1)! + '(' + parts.join(', ') + ')';
  }

  String _stripComment(String line) {
    String? quote;
    var escaped = false;
    for (var i = 0; i < line.length; i++) {
      final character = line[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == quote) {
          quote = null;
        }
      } else if (character == "'" || character == '"') {
        quote = character;
      } else if (character == '#') {
        return line.substring(0, i);
      }
    }
    return line;
  }

  (String, String)? _findAssignment(String text) {
    String? quote;
    var depth = 0;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final character = text[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == quote) {
          quote = null;
        }
        continue;
      }
      if (character == "'" || character == '"') {
        quote = character;
      } else if (character == '(') {
        depth++;
      } else if (character == ')') {
        depth--;
      } else if (character == '=' && depth == 0) {
        final previous = i > 0 ? text[i - 1] : '';
        final next = i + 1 < text.length ? text[i + 1] : '';
        if (previous != '=' && previous != '!' && previous != '<' && previous != '>' && next != '=') {
          final name = text.substring(0, i).trim();
          if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
            throw const FormatException('Assignment must use a variable name.');
          }
          return (name, text.substring(i + 1).trim());
        }
      }
    }
    return null;
  }

  Never _error(_ScriptLine line, String message) {
    throw FormatException('Line ' + line.number.toString() + ': ' + message);
  }
}

class _Token {
  const _Token(this.text, [this.kind = 'symbol']);
  final String text;
  final String kind;
}

class _ExpressionParser {
  _ExpressionParser(String source) : _tokens = _tokenize(source);
  final List<_Token> _tokens;
  int _position = 0;

  _Expression parse() {
    final expression = _parseOr();
    if (!_isAtEnd) _fail('Unexpected token "' + _peek.text + '".');
    return expression;
  }

  _Expression _parseOr() {
    var expression = _parseAnd();
    while (_match('or')) {
      expression = _Binary('or', expression, _parseAnd());
    }
    return expression;
  }

  _Expression _parseAnd() {
    var expression = _parseNot();
    while (_match('and')) {
      expression = _Binary('and', expression, _parseNot());
    }
    return expression;
  }

  _Expression _parseNot() {
    if (_match('not')) return _Unary('not', _parseNot());
    return _parseComparison();
  }

  _Expression _parseComparison() {
    var expression = _parseAdditive();
    while (_match('==', '!=', '<', '<=', '>', '>=', 'in')) {
      final operator = _previous.text;
      expression = _Binary(operator, expression, _parseAdditive());
    }
    return expression;
  }

  _Expression _parseAdditive() {
    var expression = _parseMultiplicative();
    while (_match('+', '-')) {
      final operator = _previous.text;
      expression = _Binary(operator, expression, _parseMultiplicative());
    }
    return expression;
  }

  _Expression _parseMultiplicative() {
    var expression = _parseUnary();
    while (_match('*', '/', '//', '%')) {
      final operator = _previous.text;
      expression = _Binary(operator, expression, _parseUnary());
    }
    return expression;
  }

  _Expression _parseUnary() {
    if (_match('+', '-')) return _Unary(_previous.text, _parseUnary());
    return _parsePrimary();
  }

  _Expression _parsePrimary() {
    if (_matchKind('number')) {
      final text = _previous.text;
      return _Literal(text.contains('.') ? double.parse(text) : int.parse(text));
    }
    if (_matchKind('string')) return _Literal(_previous.text);
    if (_match('True')) return const _Literal(true);
    if (_match('False')) return const _Literal(false);
    if (_match('None')) return const _Literal(null);
    if (_matchKind('identifier')) {
      final name = _previous.text;
      if (!_match('(')) return _Variable(name);
      final arguments = <_Expression>[];
      if (!_check(')')) {
        do {
          arguments.add(_parseOr());
        } while (_match(',') && !_check(')'));
      }
      _consume(')', 'Expected ")" after function arguments.');
      return _Call(name, arguments);
    }
    if (_match('(')) {
      final expression = _parseOr();
      _consume(')', 'Expected ")" after expression.');
      return expression;
    }
    _fail('Expected a value.');
  }

  bool _matchKind(String kind) {
    if (_checkKind(kind)) {
      _advance();
      return true;
    }
    return false;
  }

  bool _match(String first, [String? second, String? third, String? fourth, String? fifth, String? sixth, String? seventh]) {
    final values = [first, second, third, fourth, fifth, sixth, seventh];
    for (final value in values) {
      if (value != null && _check(value)) {
        _advance();
        return true;
      }
    }
    return false;
  }

  bool _check(String text) => !_isAtEnd && _peek.text == text;
  bool _checkKind(String kind) => !_isAtEnd && _peek.kind == kind;
  _Token get _peek => _tokens[_position];
  _Token get _previous => _tokens[_position - 1];
  bool get _isAtEnd => _position >= _tokens.length;

  _Token _advance() {
    if (!_isAtEnd) _position++;
    return _previous;
  }

  void _consume(String text, String message) {
    if (_check(text)) {
      _advance();
      return;
    }
    _fail(message);
  }

  Never _fail(String message) => throw FormatException(message);

  static List<_Token> _tokenize(String source) {
    final tokens = <_Token>[];
    var position = 0;
    while (position < source.length) {
      final character = source[position];
      if (RegExp(r'\s').hasMatch(character)) {
        position++;
        continue;
      }
      if (RegExp(r'[0-9]').hasMatch(character)) {
        final start = position++;
        while (position < source.length && RegExp(r'[0-9]').hasMatch(source[position])) {
          position++;
        }
        if (position + 1 < source.length && source[position] == '.' && RegExp(r'[0-9]').hasMatch(source[position + 1])) {
          position++;
          while (position < source.length && RegExp(r'[0-9]').hasMatch(source[position])) {
            position++;
          }
        }
        tokens.add(_Token(source.substring(start, position), 'number'));
        continue;
      }
      if (character == "'" || character == '"') {
        final quote = character;
        position++;
        final value = StringBuffer();
        var closed = false;
        while (position < source.length) {
          final current = source[position++];
          if (current == quote) {
            closed = true;
            break;
          }
          if (current == r'\') {
            if (position >= source.length) break;
            final escaped = source[position++];
            value.write(switch (escaped) {
              'n' => '\n',
              'r' => '\r',
              't' => '\t',
              '\\' => r'\',
              '"' => '"',
              "'" => "'",
              _ => escaped,
            });
          } else {
            value.write(current);
          }
        }
        if (!closed) throw const FormatException('Unterminated string literal.');
        tokens.add(_Token(value.toString(), 'string'));
        continue;
      }
      if (RegExp(r'[A-Za-z_]').hasMatch(character)) {
        final start = position++;
        while (position < source.length && RegExp(r'[A-Za-z0-9_]').hasMatch(source[position])) {
          position++;
        }
        tokens.add(_Token(source.substring(start, position), 'identifier'));
        continue;
      }
      final pair = position + 1 < source.length ? source.substring(position, position + 2) : '';
      if (['==', '!=', '<=', '>=', '//'].contains(pair)) {
        tokens.add(_Token(pair));
        position += 2;
        continue;
      }
      if ('+-*/%<>() ,'.contains(character)) {
        if (character != ' ') tokens.add(_Token(character));
        position++;
        continue;
      }
      throw FormatException('Unexpected character "' + character + '".');
    }
    return tokens;
  }
}
