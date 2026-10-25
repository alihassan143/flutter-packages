// This file fetches real PDF samples over the network on every run (see
// `fetchInternal` below) - some are 100+ pages and take tens of seconds to
// download and parse (one has an explicit 3-minute `Timeout` because of it).
// That's exactly the kind of test that "gets stuck in some cases": its
// runtime depends on network conditions and file size, not on this
// codebase, so it doesn't belong in the default `dart test` run that CI and
// every other test file depend on being fast and deterministic. Excluded by
// default via dart_test.yaml; run explicitly with
// `dart test --run-skipped --tags=network`.
@Tags(['network'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:docx_creator/src/reader/pdf_reader/pdf_reader.dart';
import 'package:test/test.dart';

void main() {
  // Base URLs for pypdf sample files
  const baseUrls = [
    'https://raw.githubusercontent.com/py-pdf/sample-files/main',
    'https://raw.githubusercontent.com/py-pdf/sample-files/refs/heads/main',
  ];

  Future<Uint8List> fetchInternal(String filename) async {
    final client = HttpClient();
    Exception? lastError;

    for (final baseUrl in baseUrls) {
      try {
        final url = Uri.parse('$baseUrl/$filename');
        final request = await client.getUrl(url);
        final response = await request.close();

        if (response.statusCode == 200) {
          final bytes =
              await response.fold<List<int>>([], (a, b) => a..addAll(b));
          client.close();
          return Uint8List.fromList(bytes);
        }
      } catch (e) {
        lastError = Exception('Error fetching $filename from $baseUrl: $e');
      }
    }
    client.close();
    throw lastError ??
        Exception('Failed to load $filename from any known branch');
  }

  group('Real World pypdf Samples', () {
    // 1. Outlines
    test('Outlines (014-outlines)', () async {
      final bytes =
          await fetchInternal('014-outlines/mistitled_outlines_example.pdf');
      final doc = await PdfReader.loadFromBytes(bytes);

      expect(doc.outlines, isNotEmpty);
    });

    // 2. Encryption - password is "openpassword"
    test('Encryption (005-libreoffice-writer-password)', () async {
      final bytes = await fetchInternal(
          '005-libreoffice-writer-password/libreoffice-writer-password.pdf');

      // Password for this file is "openpassword"
      final doc =
          await PdfReader.loadFromBytes(bytes, password: 'openpassword');

      expect(doc.pageCount, greaterThan(0));

      // Check encryption status
      print('Is Encrypted: ${doc.isEncrypted}');
      if (doc.encryption != null) {
        print('Encryption Ready: ${doc.encryption!.isReady}');
        print('Encryption Algorithm: ${doc.encryption!.algorithmDescription}');
      }

      // Verify metadata
      print('Metadata Title: ${doc.metadata.title}');
      print('Metadata Author: ${doc.metadata.author}');

      // Verify content extraction
      final text = doc.text;
      print('Decrypted text: $text');
      print('Element count: ${doc.elements.length}');
      print('Warnings: ${doc.warnings}');

      // The encrypted PDF should have some text content after decryption
      expect(text.length, greaterThan(0),
          reason: 'Encrypted PDF should have decrypted text');

      expect(doc.encryption!.isReady, isTrue);
    });

    // 3. Attachments
    test('Attachments (025-attachment)', () async {
      final bytes = await fetchInternal('025-attachment/with-attachment.pdf');
      final doc = await PdfReader.loadFromBytes(bytes);
      expect(doc.attachments, isNotNull);
    });

    // 4. Large complex file
    test('Complex File (009-pdflatex-geotopo)', () async {
      final bytes = await fetchInternal('009-pdflatex-geotopo/GeoTopo.pdf');
      final doc = await PdfReader.loadFromBytes(bytes);
      expect(doc.pageCount, greaterThan(100));
      expect(doc.pageLabels, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    // 5. Metadata
    test('Metadata Verification (003-pdflatex-image)', () async {
      final bytes =
          await fetchInternal('003-pdflatex-image/pdflatex-image.pdf');
      final doc = await PdfReader.loadFromBytes(bytes);

      expect(doc.pageCount, greaterThan(0),
          reason: 'PDF should have at least 1 page');

      print('Checking metadata for 003-pdflatex-image...');
      print('Page count: ${doc.pageCount}');
      print('Version: ${doc.version}');
      print('Title: ${doc.metadata.title}');
      print('Author: ${doc.metadata.author}');
      print('Producer: ${doc.metadata.producer}');
      print('Creator: ${doc.metadata.creator}');

      expect(doc.metadata, isNotNull);
      expect(doc.metadata.pdfVersion, isNotEmpty);
    });
  });
}
