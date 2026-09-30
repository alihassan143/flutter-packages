import 'dart:io';

import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const DocxViewerExampleApp());
}

class DocxViewerExampleApp extends StatelessWidget {
  const DocxViewerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DOCX Viewer Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _selectedFile;
  Uint8List? _demoBytes;
  bool _enableZoom = true;
  bool _darkMode = false;
  final bool _isLoading = false;
  String? _errorMessage;

  // Search state
  late DocxSearchController _searchController;
  final TextEditingController _searchTextController = TextEditingController();
  bool _isSearchActive = false;

  @override
  void initState() {
    super.initState();
    _searchController = DocxSearchController();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Rebuild to update match counts
    if (mounted) setState(() {});
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx'],
      // Browsers expose no file paths (and dart:io File can't be read
      // there), so on the web read the picked file's bytes directly.
      withData: kIsWeb,
    );

    if (kIsWeb) {
      final bytes = result?.files.single.bytes;
      if (bytes != null) {
        setState(() {
          _selectedFile = null;
          _demoBytes = bytes;
          _errorMessage = null;
        });
      }
      return;
    }

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _demoBytes = null;
        _errorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickFile,
        child: const Icon(Icons.folder_open),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSearchActive) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _isSearchActive = false;
              _searchController.clear();
              _searchTextController.clear();
            });
          },
        ),
        title: TextField(
          controller: _searchTextController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search text...',
            border: InputBorder.none,
          ),
          onSubmitted: (value) => _searchController.search(value),
          onChanged: (value) => _searchController.search(value),
          textInputAction: TextInputAction.search,
        ),
        actions: [
          // Match Counter
          if (_searchController.matchCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  '${_searchController.currentMatchIndex + 1}/${_searchController.matchCount}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          // Navigation Buttons
          IconButton(
            icon: const Icon(Icons.expand_less),
            onPressed: _searchController.previousMatch,
            tooltip: 'Previous',
          ),
          IconButton(
            icon: const Icon(Icons.expand_more),
            onPressed: _searchController.nextMatch,
            tooltip: 'Next',
          ),
        ],
      );
    }

    return AppBar(
      title: const Text('DOCX Viewer'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() {
              _isSearchActive = true;
            });
          },
          tooltip: 'Search',
        ),
        IconButton(
          icon: Icon(_darkMode ? Icons.light_mode : Icons.dark_mode),
          onPressed: () => setState(() => _darkMode = !_darkMode),
          tooltip: 'Toggle theme',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.settings),
          onSelected: (value) {
            setState(() {
              if (value == 'zoom') _enableZoom = !_enableZoom;
            });
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              value: 'zoom',
              checked: _enableZoom,
              child: const Text('Enable Zoom'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading demo document...'),
          ],
        ),
      );
    }

    if (_selectedFile == null && _demoBytes == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 14, color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'No document selected',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open File'),
            ),
          ],
        ),
      );
    }

    return DocxView(
      file: _selectedFile,
      bytes: _demoBytes,
      config: DocxViewConfig(
        enableSearch: true, // Always enable logic, we control interaction
        enableZoom: _enableZoom,
        theme: _darkMode ? DocxViewTheme.dark() : DocxViewTheme.light(),
        backgroundColor: _darkMode ? const Color(0xFF1E1E1E) : Colors.white,
        showDebugInfo: true,
      ),
      searchController: _searchController, // Pass explicit controller
    );
  }
}
