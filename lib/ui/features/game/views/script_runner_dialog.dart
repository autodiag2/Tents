import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ScriptRunnerDialog extends StatefulWidget {
  const ScriptRunnerDialog({super.key, required this.onRun});
  final Future<void> Function(String source) onRun;
  @override
  State<ScriptRunnerDialog> createState() => _ScriptRunnerDialogState();
}

class _ScriptRunnerDialogState extends State<ScriptRunnerDialog> {
  final _name = TextEditingController();
  final _source = TextEditingController(text: 'tent 1 2\nwait 300\ntent 2 3');
  Box<String>? _box;
  String? _selected;
  bool _loading = true;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    Hive.openBox<String>('tents_game_scripts').then((box) {
      if (mounted) setState(() { _box = box; _loading = false; });
    });
  }

  void _select(String? name) {
    if (name == null) return;
    setState(() { _selected = name; _name.text = name; _source.text = _box!.get(name) ?? ''; });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _source.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a script name and commands.')));
      return;
    }
    await _box!.put(name, _source.text);
    if (mounted) setState(() => _selected = name);
  }

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      await widget.onRun(_source.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = _box?.keys.cast<String>().toList() ?? <String>[];
    return AlertDialog(
      title: const Text('Game scripts'),
      content: SizedBox(
        width: 480,
        child: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (names.isNotEmpty) DropdownButtonFormField<String>(
              value: names.contains(_selected) ? _selected : null,
              decoration: const InputDecoration(labelText: 'Saved script'),
              hint: const Text('Select a script'),
              items: names.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
              onChanged: _select,
            ),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Script name')),
            const SizedBox(height: 12),
            TextField(
              controller: _source, minLines: 8, maxLines: 14, autocorrect: false, enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Commands', alignLabelWithHint: true, border: OutlineInputBorder(),
                helperText: 'tent 1 2  |  cross 2 3  |  clear 1 2  |  wait 300',
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _loading || _running ? null : _save, child: const Text('Save')),
        FilledButton(onPressed: _loading || _running ? null : _run, child: Text(_running ? 'Running…' : 'Run')),
      ],
    );
  }
}
