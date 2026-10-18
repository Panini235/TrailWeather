import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/settings_repository.dart';
import '../../data/weather/departure_windows.dart';
import '../strings.dart';

class DepartureThresholdScreen extends ConsumerStatefulWidget {
  const DepartureThresholdScreen({super.key});
  @override
  ConsumerState<DepartureThresholdScreen> createState() => _ThresholdState();
}

class _ThresholdState extends ConsumerState<DepartureThresholdScreen> {
  final _form = GlobalKey<FormState>();
  late final List<TextEditingController> _fields;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = ref.read(settingsProvider).departureThresholds;
    _fields = [
      t.gustYellow,
      t.gustRed,
      t.precipYellow,
      t.coldRed,
    ].map((v) => TextEditingController(text: '$v')).toList();
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final v = _fields.map((f) => double.parse(f.text.trim())).toList();
    final t = DepartureThresholds(
      gustYellow: v[0],
      gustRed: v[1],
      precipYellow: v[2],
      coldRed: v[3],
    );
    if (!t.isValid) {
      setState(() => _error = S.departureThresholdInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(settingsProvider.notifier)
          .update(ref.read(settingsProvider).copyWith(departureThresholds: t));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = S.departureThresholdSaveFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(S.departureThresholdTitle)),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(S.departureThresholdIntro),
          const SizedBox(height: 16),
          for (var i = 0; i < _fields.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                controller: _fields[i],
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: const [
                    S.departureThresholdGustYellow,
                    S.departureThresholdGustRed,
                    S.departureThresholdPrecipYellow,
                    S.departureThresholdColdRed,
                  ][i],
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                validator: (text) {
                  final n = double.tryParse(text?.trim() ?? '');
                  return n == null || !n.isFinite
                      ? S.departureThresholdInvalidNumber
                      : null;
                },
              ),
            ),
          const Text(S.departureThresholdRulesNote),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving ? S.departureThresholdSaving : S.departureThresholdSave,
            ),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() {
                    const values = ['13.9', '17.2', '2.0', '-10.0'];
                    for (var i = 0; i < _fields.length; i++) {
                      _fields[i].text = values[i];
                    }
                    _error = null;
                  }),
            child: const Text(S.departureThresholdReset),
          ),
        ],
      ),
    ),
  );
}
