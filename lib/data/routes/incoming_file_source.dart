import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 外部应用传入的文件（“用徒步天气打开” / 分享）。
class IncomingFile {
  const IncomingFile({required this.uri, required this.name});

  /// 平台文件标识（Android 为 content:// 或 file:// URI），只用于读取，不记录日志。
  final String uri;
  final String name;

  static IncomingFile? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final uri = raw['uri'];
    if (uri is! String || uri.isEmpty) return null;
    final name = raw['name'];
    return IncomingFile(
      uri: uri,
      name: name is String && name.isNotEmpty ? name : 'shared-file',
    );
  }
}

/// 外部传入文件的来源。抽象层便于组件测试，平台未接入时为空实现。
abstract interface class IncomingFileSource {
  /// 冷启动时由外部文件拉起的那个文件（只返回一次）。
  Future<IncomingFile?> initialFile();

  /// App 运行中收到的新文件。
  Stream<IncomingFile> get files;

  Future<Uint8List> readBytes(IncomingFile file);
}

/// Android：MainActivity 通过 MethodChannel 传递 VIEW / SEND intent 中的 URI，
/// 字节在原生后台线程读取（上限 30 MB）。
class MethodChannelIncomingFileSource implements IncomingFileSource {
  MethodChannelIncomingFileSource() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFile') {
        final f = IncomingFile.fromPlatform(call.arguments);
        if (f != null) _files.add(f);
      }
    });
  }

  static const _channel = MethodChannel('trailweather/incoming_file');
  final _files = StreamController<IncomingFile>.broadcast();

  @override
  Stream<IncomingFile> get files => _files.stream;

  @override
  Future<IncomingFile?> initialFile() async {
    try {
      return IncomingFile.fromPlatform(
        await _channel.invokeMethod<Object?>('getInitialFile'),
      );
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<Uint8List> readBytes(IncomingFile file) async {
    final bytes = await _channel.invokeMethod<Uint8List>('readBytes', {
      'uri': file.uri,
    });
    if (bytes == null) throw const FormatException('文件为空或无法读取');
    return bytes;
  }
}

class NoIncomingFiles implements IncomingFileSource {
  const NoIncomingFiles();

  @override
  Stream<IncomingFile> get files => const Stream.empty();

  @override
  Future<IncomingFile?> initialFile() async => null;

  @override
  Future<Uint8List> readBytes(IncomingFile file) =>
      Future.error(UnsupportedError('当前平台不支持外部传入文件'));
}

/// 目前只有 Android 接入了原生通道；iOS 待接入 AppDelegate 并经 iOS 构建验证。
final incomingFileSourceProvider = Provider<IncomingFileSource>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return MethodChannelIncomingFileSource();
  }
  return const NoIncomingFiles();
});
