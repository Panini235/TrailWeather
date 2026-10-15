import 'package:url_launcher/url_launcher.dart';

abstract interface class ExternalUrlLauncher {
  Future<bool> open(Uri uri);
}

class SystemExternalUrlLauncher implements ExternalUrlLauncher {
  const SystemExternalUrlLauncher();

  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
