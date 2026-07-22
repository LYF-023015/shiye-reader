import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.updateAvailable,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUrl;
  final bool updateAvailable;
}

abstract final class UpdateService {
  static Future<AppUpdateInfo> check() async {
    final package = await PackageInfo.fromPlatform();
    final client = HttpClient()..userAgent = 'Shiye/${package.version}';
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/LYF-023015/shiye-reader/releases/latest',
        ),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('Update service unavailable');
      }
      final root = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      final tag = (root['tag_name'] as String? ?? '').replaceFirst('v', '');
      final url = Uri.parse(
        root['html_url'] as String? ??
            'https://github.com/LYF-023015/shiye-reader/releases/latest',
      );
      return AppUpdateInfo(
        currentVersion: package.version,
        latestVersion: tag,
        releaseUrl: url,
        updateAvailable: _compareVersions(tag, package.version) > 0,
      );
    } finally {
      client.close(force: true);
    }
  }

  static int _compareVersions(String a, String b) {
    final left = a
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map(int.parse)
        .toList();
    final right = b
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .map(int.parse)
        .toList();
    for (var index = 0; index < left.length || index < right.length; index++) {
      final comparison = (index < left.length ? left[index] : 0).compareTo(
        index < right.length ? right[index] : 0,
      );
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}
