import 'dart:io';
import 'dart:typed_data';

import 'package:docx_file_viewer/src/utils/docx_source_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #71: on the web, `File(...).readAsBytes()` throws the opaque
/// "Unsupported operation: _Namespace". The loader must never touch
/// dart:io there and must explain what to pass instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bytes are returned as-is on every platform', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(await DocxSourceLoader.load(bytes: bytes, isWeb: true), bytes);
    expect(await DocxSourceLoader.load(bytes: bytes, isWeb: false), bytes);
  });

  test('a File on the web fails with an actionable message', () async {
    await expectLater(
      DocxSourceLoader.load(file: File('x.docx'), isWeb: true),
      throwsA(isA<UnsupportedError>().having((e) => e.message, 'message',
          allOf(contains('bytes'), isNot(contains('_Namespace'))))),
    );
  });

  test('a path on the web is loaded as an asset, with a clear error if missing',
      () async {
    await expectLater(
      DocxSourceLoader.load(path: 'assets/missing.docx', isWeb: true),
      throwsA(isA<UnsupportedError>()
          .having((e) => e.message, 'message', contains('asset'))),
    );
  });

  test('files are read from disk on native platforms', () async {
    final dir = await Directory.systemTemp.createTemp('docx_loader');
    final file = File('${dir.path}/doc.docx')..writeAsBytesSync([7, 8]);
    expect(await DocxSourceLoader.load(file: file, isWeb: false), [7, 8]);
    expect(await DocxSourceLoader.load(path: file.path, isWeb: false), [7, 8]);
    await dir.delete(recursive: true);
  });
}
