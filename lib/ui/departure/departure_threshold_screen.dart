import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/settings_repository.dart';
import '../../data/weather/departure_windows.dart';

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
      setState(() => _error = '黄色阵风须小于红色阵风；阵风范围 >0–100，降水 >0–200，气温 −80–10。');
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
          _error = '设置未能保存，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('出发窗口阈值')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('这些规则只用于出发窗口比较。颜色表示触发阈值，不代表安全等级。单位固定如下，不随显示单位变化。'),
          const SizedBox(height: 16),
          for (var i = 0; i < _fields.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TextFormField(
                controller: _fields[i],
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: const [
                    '黄色 · 阵风 ≥（m/s）',
                    '红色 · 阵风 ≥（m/s）',
                    '黄色 · 小时降水 ≥（mm）',
                    '红色 · 气温 ≤（℃）',
                  ][i],
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                validator: (text) {
                  final n = double.tryParse(text?.trim() ?? '');
                  return n == null || !n.isFinite ? '请输入有效数字' : null;
                },
              ),
            ),
          const Text('预计到达晚于出发日日落：黄色。缺少气温、阵风、降水或日落：信息不足。缺失值不会用 0 或其他变量代替。'),
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
            child: Text(_saving ? '保存中…' : '保存阈值'),
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
            child: const Text('恢复默认值（保存后生效）'),
          ),
        ],
      ),
    ),
  );
}
