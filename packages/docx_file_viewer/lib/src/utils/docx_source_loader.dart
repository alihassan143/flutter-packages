import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

/// Resolves the document bytes for a `DocxView` from whichever source was
/// given (`bytes`, `file` or `path`).
///
/// `dart:io` file access is unavailable in browsers: calling
/// `File(...).readAsBytes()` there throws the opaque
/// `Unsupported operation: _Namespace` (issue #71). On the web this loader
/// therefore never touches `dart:io`; a `path` is loaded as a Flutter asset
/// instead, and a `File` is rejected with an actionable message.
class DocxSourceLoader {
  const DocxSourceLoader._();

  /// Loads the bytes. [isWeb] defaults to the current platform and exists
  /// so the web behaviour can be tested on the VM.
  static Future<Uint8List> load({
    Uint8List? bytes,
    File? file,
    String? path,
    bool isWeb = kIsWeb,
  }) async {
    if (bytes != null) return bytes;

    if (file != null) {
      if (isWeb) {
        throw UnsupportedError(
          'DocxView(file: ...) is not supported on the web: browsers have no '
          'file system, so a dart:io File cannot be read. Pass the document '
          'bytes instead, e.g. DocxView(bytes: ...). With file_picker, use '
          'pickFiles(withData: true) and PlatformFile.bytes.',
        );
      }
      return file.readAsBytes();
    }

    if (path != null) {
      if (isWeb) return _loadAsset(path);
      return File(path).readAsBytes();
    }

    throw ArgumentError('No document source provided');
  }

  static Future<Uint8List> _loadAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (e) {
      throw UnsupportedError(
        'DocxView(path: "$path") could not be loaded on the web. There is no '
        'file system in the browser, so on the web `path` must be a Flutter '
        'asset declared in pubspec.yaml; for any other document pass its '
        'bytes via DocxView(bytes: ...). Underlying error: $e',
      );
    }
  }
}
