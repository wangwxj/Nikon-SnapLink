import 'package:flutter_test/flutter_test.dart';
import 'package:snaplink/engine/update/app_update_manager.dart';

void main() {
  group('AppUpdateManager 语义化版本比对与解析单元测试', () {
    test('isNewerVersion 版本号对比算法精确性校验', () {
      // 远程主版本号更高
      expect(AppUpdateManager.isNewerVersion('2.0.0', '1.1.0'), isTrue);
      expect(AppUpdateManager.isNewerVersion('v2.0.0', '1.1.0'), isTrue);

      // 远程次版本号更高
      expect(AppUpdateManager.isNewerVersion('1.2.0', '1.1.0'), isTrue);
      expect(AppUpdateManager.isNewerVersion('v1.2.0', 'v1.1.0'), isTrue);
      expect(AppUpdateManager.isNewerVersion('1.10.0', '1.9.0'), isTrue);

      // 远程修订号更高
      expect(AppUpdateManager.isNewerVersion('1.1.1', '1.1.0'), isTrue);
      expect(AppUpdateManager.isNewerVersion('v1.1.9', '1.1.0'), isTrue);

      // 版本相同：不应提示更新
      expect(AppUpdateManager.isNewerVersion('1.1.0', '1.1.0'), isFalse);
      expect(AppUpdateManager.isNewerVersion('v1.1.0', '1.1.0'), isFalse);
      expect(AppUpdateManager.isNewerVersion('1.1.0', 'v1.1.0'), isFalse);

      // 远程版本更低（例如当前 1.1.0，远程 1.0.0）：绝不提示更新
      expect(AppUpdateManager.isNewerVersion('1.0.0', '1.1.0'), isFalse);
      expect(AppUpdateManager.isNewerVersion('v1.0.0', '1.1.0'), isFalse);
      expect(AppUpdateManager.isNewerVersion('1.0.9', '1.1.0'), isFalse);
    });

    test('AppReleaseInfo.fromGiteeJson 提取与组装校验', () {
      final giteeRawJson = {
        'tag_name': 'v1.2.0',
        'name': 'v1.2.0 重大功能更新',
        'body': '1. 新增远程更新检测\n2. 优化连接速率',
        'created_at': '2026-10-08T18:00:00+08:00',
        'assets': [
          {
            'name': 'SnapLink-release-1.2.0.apk',
            'browser_download_url': 'https://gitee.com/lyb82ndkkkl/Nikon-SnapLink/releases/download/v1.2.0/SnapLink-release-1.2.0.apk',
            'size': 56586036,
          },
          {
            'name': 'source.zip',
            'browser_download_url': 'https://gitee.com/archive.zip',
          }
        ]
      };

      final info = AppReleaseInfo.fromGiteeJson(giteeRawJson);
      expect(info.versionName, equals('1.2.0'));
      expect(info.tagName, equals('v1.2.0'));
      expect(info.title, equals('v1.2.0 重大功能更新'));
      expect(info.changelog, contains('1. 新增远程更新检测'));
      expect(info.downloadUrl, equals('https://gitee.com/lyb82ndkkkl/Nikon-SnapLink/releases/download/v1.2.0/SnapLink-release-1.2.0.apk'));
      expect(info.sourceName, equals('Gitee'));
      expect(info.fileSize, equals(56586036));
    });

    test('AppReleaseInfo.fromGitHubJson 提取与组装校验', () {
      final githubRawJson = {
        'tag_name': '1.2.0',
        'name': 'v1.2.0 首发',
        'body': '修复已知错误',
        'published_at': '2026-10-08T18:00:00Z',
        'assets': [
          {
            'name': 'SnapLink-release-1.2.0.apk',
            'browser_download_url': 'https://github.com/lyb82ndkf-lab/Nikon-SnapLink/releases/download/1.2.0/SnapLink-release-1.2.0.apk',
            'size': 56586036,
          }
        ]
      };

      final info = AppReleaseInfo.fromGitHubJson(githubRawJson);
      expect(info.versionName, equals('1.2.0'));
      expect(info.sourceName, equals('GitHub'));
      expect(info.downloadUrl, contains('SnapLink-release-1.2.0.apk'));
      expect(info.fileSize, equals(56586036));
    });

    test('formatBytes 存储容量友好显示校验', () {
      expect(AppUpdateManager.formatBytes(500), equals('500 B'));
      expect(AppUpdateManager.formatBytes(2048), equals('2 KB'));
      expect(AppUpdateManager.formatBytes(56586036), equals('54.0 MB'));
    });
  });
}
