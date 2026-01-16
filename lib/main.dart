import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;

void main() => runApp(const ChartMatcherApp());

class ChartMatcherApp extends StatelessWidget {
  const ChartMatcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "ChartMatcher",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class MatchResult {
  final File file;
  final double similarity;
  MatchResult({required this.file, required this.similarity});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? runningPhoto;
  String? selectedFolder;
  bool isScanning = false;
  List<MatchResult> results = [];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.photos.request();
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
  }

  Future<void> pickRunningPhoto() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.gallery);
    if (photo == null) return;
    setState(() {
      runningPhoto = File(photo.path);
      results = [];
    });
  }

  Future<void> pickFolder() async {
    final folder = await FilePicker.platform.getDirectoryPath();
    if (folder == null) return;
    setState(() {
      selectedFolder = folder;
      results = [];
    });
  }

  String computeAHash(File file) {
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return "";

    final resized = img.copyResize(decoded, width: 8, height: 8);
    final gray = img.grayscale(resized);

    int sum = 0;
    final pixels = <int>[];
    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        final p = gray.getPixel(x, y);
        final lum = img.getLuminance(p).round();
        pixels.add(lum);
        sum += lum;
      }
    }

    final avg = sum / pixels.length;
    final buffer = StringBuffer();
    for (final p in pixels) {
      buffer.write(p >= avg ? "1" : "0");
    }
    return buffer.toString();
  }

  int hammingDistance(String a, String b) {
    if (a.length != b.length) return 9999;
    int d = 0;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) d++;
    }
    return d;
  }

  Future<List<File>> getAllImagesFromFolder(String folderPath) async {
    final dir = Directory(folderPath);
    final list = dir.listSync(recursive: true);
    return list
        .whereType<File>()
        .where((f) {
          final p = f.path.toLowerCase();
          return p.endsWith(".jpg") ||
              p.endsWith(".jpeg") ||
              p.endsWith(".png") ||
              p.endsWith(".webp");
        })
        .toList();
  }

  Future<void> scanAndMatch() async {
    if (runningPhoto == null || selectedFolder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pick running chart + folder first")),
      );
      return;
    }

    setState(() {
      isScanning = true;
      results = [];
    });

    try {
      final runningHash = computeAHash(runningPhoto!);
      final images = await getAllImagesFromFolder(selectedFolder!);

      final matches = <MatchResult>[];
      for (final f in images) {
        final h = computeAHash(f);
        if (h.isEmpty) continue;
        final dist = hammingDistance(runningHash, h);
        final sim = 1 - (dist / 64);
        matches.add(MatchResult(file: f, similarity: sim));
      }

      matches.sort((a, b) => b.similarity.compareTo(a.similarity));

      setState(() {
        results = matches.take(20).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => isScanning = false);
    }
  }

  void openImage(File f) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FullImagePage(file: f)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("ChartMatcher")),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: pickRunningPhoto,
                    icon: const Icon(Icons.image),
                    label: const Text("Pick Running Chart"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: pickFolder,
                    icon: const Icon(Icons.folder),
                    label: const Text("Pick Past Folder"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (runningPhoto != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  runningPhoto!,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: isScanning ? null : scanAndMatch,
              child: Text(isScanning ? "Scanning..." : "Find Similar Charts"),
            ),
            const SizedBox(height: 10),
            if (isScanning) const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text("No matches yet"))
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final r = results[i];
                        return ListTile(
                          leading: Image.file(r.file, width: 55, height: 55),
                          title: Text(
                              "Similarity: ${(r.similarity * 100).toStringAsFixed(1)}%"),
                          subtitle: Text(r.file.path,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => openImage(r.file),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class FullImagePage extends StatelessWidget {
  final File file;
  const FullImagePage({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Matched Photo")),
      body: Center(child: Image.file(file)),
    );
  }
}
