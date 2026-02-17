import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart'; // Librería de anuncios

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize(); // Inicializa Google Ads al arrancar
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RohuReproducciones',
      theme: ThemeData.dark(),
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
  Map<String, List<String>> _publicPlaylists = {};
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  // ESTE ES TU CÓDIGO DE BANNER (EL QUE TIENE LA BARRA /)
  final String _adUnitId = 'ca-app-pub-3059778872079066/3138343100'; 

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadBanner();
  }

  void _loadBanner() {
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isBannerLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          print('Error al cargar el banner: $error');
        },
      ),
    )..load();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _publicPlaylists = _decode(prefs.getString('public_playlists'));
    });
  }

  Map<String, List<String>> _decode(String? data) {
    if (data == null || data.isEmpty) return {};
    try {
      return Map<String, List<String>>.from(
        json.decode(data).map((k, v) => MapEntry(k, List<String>.from(v))),
      );
    } catch (e) { return {}; }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('public_playlists', json.encode(_publicPlaylists));
  }

  void _createNewFolder() {
    TextEditingController _controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nueva Carpeta"),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Nombre de la lista"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          TextButton(
            onPressed: () {
              if (_controller.text.isNotEmpty) {
                setState(() => _publicPlaylists[_controller.text] = []);
                _saveData();
                Navigator.pop(context);
              }
            },
            child: const Text("Crear"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("RohuReproducciones")),
      body: Column(
        children: [
          Expanded(
            child: _publicPlaylists.isEmpty
                ? const Center(child: Text("Presiona + para crear una carpeta"))
                : ListView(
                    children: _publicPlaylists.keys.map((name) => ListTile(
                      leading: const Icon(Icons.folder, color: Colors.amber),
                      title: Text(name),
                      subtitle: Text("${_publicPlaylists[name]!.length} videos"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => _publicPlaylists.remove(name));
                          _saveData();
                        },
                      ),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (context) => PlaylistDetailScreen(
                          name: name, 
                          videoPaths: _publicPlaylists[name]!, 
                          onUpdate: (newList) {
                            setState(() => _publicPlaylists[name] = newList);
                            _saveData();
                          },
                        )
                      )),
                    )).toList(),
                  ),
          ),
          // AQUÍ SE MUESTRA EL BANNER SI CARGÓ CORRECTAMENTE
          if (_isBannerLoaded && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewFolder,
        child: const Icon(Icons.create_new_folder),
      ),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }
}

// --- CLASE DETALLE (REORDENAR Y AGREGAR) ---
class PlaylistDetailScreen extends StatefulWidget {
  final String name;
  final List<String> videoPaths;
  final Function(List<String>) onUpdate;
  const PlaylistDetailScreen({super.key, required this.name, required this.videoPaths, required this.onUpdate});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: widget.videoPaths.isEmpty
          ? const Center(child: Text("Agrega videos a esta lista"))
          : ReorderableListView(
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = widget.videoPaths.removeAt(oldIndex);
                  widget.videoPaths.insert(newIndex, item);
                });
                widget.onUpdate(widget.videoPaths);
              },
              children: [
                for (int i = 0; i < widget.videoPaths.length; i++)
                  ListTile(
                    key: Key('$i-${widget.videoPaths[i]}'),
                    leading: const Icon(Icons.drag_handle),
                    title: Text(widget.videoPaths[i].split('/').last),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (context) => VideoPlayerScreen(playlist: widget.videoPaths, initialIndex: i)
                    )),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: true);
          if (result != null) {
            setState(() => widget.videoPaths.addAll(result.paths.whereType<String>()));
            widget.onUpdate(widget.videoPaths);
          }
        },
        child: const Icon(Icons.video_library),
      ),
    );
  }
}

// --- REPRODUCTOR (CON WAKELOCK Y BLOQUEO) ---
class VideoPlayerScreen extends StatefulWidget {
  final List<String> playlist;
  final int initialIndex;
  const VideoPlayerScreen({super.key, required this.playlist, required this.initialIndex});
  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;
  late int _currentIndex;
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _currentIndex = widget.initialIndex;
    _initPlayer();
  }

  void _initPlayer() async {
    _videoController = VideoPlayerController.file(File(widget.playlist[_currentIndex]));
    await _videoController.initialize();
    _setupChewie();
    setState(() {});
  }

  void _setupChewie() {
    _chewieController = ChewieController(
      videoPlayerController: _videoController,
      autoPlay: true,
      looping: false,
      fullScreenByDefault: true,
      showControls: !_isLocked, 
      allowFullScreen: true,
    );
    _videoController.addListener(() {
      if (_videoController.value.position >= _videoController.value.duration) _nextVideo();
    });
  }

  void _nextVideo() {
    if (_currentIndex < widget.playlist.length - 1) {
      _currentIndex++;
      _refresh();
    } else {
      _currentIndex = 0;
      _refresh();
    }
  }

  void _refresh() {
    _videoController.dispose();
    _chewieController?.dispose();
    _initPlayer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _chewieController != null 
                ? Chewie(controller: _chewieController!) 
                : const CircularProgressIndicator(),
          ),
          if (_isLocked)
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onDoubleTap: () {
                  setState(() {
                    _isLocked = false;
                    _setupChewie();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.lock_outline, color: Colors.white, size: 30),
                ),
              ),
            ),
          if (!_isLocked && _chewieController != null)
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.lock_open, color: Colors.white, size: 30),
                onPressed: () {
                  setState(() {
                    _isLocked = true;
                    _setupChewie();
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }
}