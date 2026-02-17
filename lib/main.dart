import 'dart:io';
import 'dart:convert';
import 'dart:math'; // Para el modo aleatorio
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
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
        onAdLoaded: (ad) => setState(() => _isBannerLoaded = true),
        onAdFailedToLoad: (ad, error) { ad.dispose(); },
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
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Nueva Carpeta"),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: "Nombre de la lista")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          TextButton(onPressed: () {
            if (controller.text.isNotEmpty) {
              setState(() => _publicPlaylists[controller.text] = []);
              _saveData();
              Navigator.pop(context);
            }
          }, child: const Text("Crear")),
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
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {
                        setState(() => _publicPlaylists.remove(name));
                        _saveData();
                      }),
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (context) => PlaylistDetailScreen(
                          name: name, videoPaths: _publicPlaylists[name]!, 
                          onUpdate: (newList) { setState(() => _publicPlaylists[name] = newList); _saveData(); },
                        )
                      )),
                    )).toList(),
                  ),
          ),
          if (_isBannerLoaded && _bannerAd != null)
            SizedBox(width: _bannerAd!.size.width.toDouble(), height: _bannerAd!.size.height.toDouble(), child: AdWidget(ad: _bannerAd!)),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _createNewFolder, child: const Icon(Icons.create_new_folder)),
    );
  }

  @override
  void dispose() { _bannerAd?.dispose(); super.dispose(); }
}

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
  bool _isShuffle = false;
  bool _isLoopOne = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    // BLOQUEAR EL CELULAR EN HORIZONTAL AL ENTRAR
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
      looping: _isLoopOne,
      showControls: false, // Usamos nuestros controles propios
      allowFullScreen: false,
    );
    _videoController.addListener(() {
      if (_videoController.value.position >= _videoController.value.duration && !_isLoopOne) {
        _nextVideo();
      }
    });
  }

  void _nextVideo() {
    setState(() {
      if (_isShuffle) {
        _currentIndex = Random().nextInt(widget.playlist.length);
      } else if (_currentIndex < widget.playlist.length - 1) {
        _currentIndex++;
      } else {
        _currentIndex = 0;
      }
    });
    _refresh();
  }

  void _previousVideo() {
    setState(() {
      if (_currentIndex > 0) {
        _currentIndex--;
      } else {
        _currentIndex = widget.playlist.length - 1;
      }
    });
    _refresh();
  }

  // ADELANTAR O ATRASAR 10 SEGUNDOS
  void _seekRelative(int seconds) {
    final newPosition = _videoController.value.position + Duration(seconds: seconds);
    _videoController.seekTo(newPosition);
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
      endDrawer: _buildSideList(),
      body: Stack(
        children: [
          // VIDEO A PANTALLA COMPLETA
          Center(
            child: _chewieController != null 
                ? AspectRatio(
                    aspectRatio: _videoController.value.aspectRatio,
                    child: Chewie(controller: _chewieController!),
                  )
                : const CircularProgressIndicator(),
          ),
          
          // CAPA DE CONTROLES
          if (!_isLocked) ...[
            // BOTÓN DE LISTA (Superior Derecha)
            Positioned(
              top: 20,
              right: 80,
              child: Builder(builder: (context) => IconButton(
                icon: const Icon(Icons.list, size: 35, color: Colors.white),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              )),
            ),

            // CONTROLES PRINCIPALES (Centro Inferior)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ALEATORIO
                  IconButton(
                    icon: Icon(_isShuffle ? Icons.shuffle_on : Icons.shuffle),
                    onPressed: () => setState(() => _isShuffle = !_isShuffle),
                  ),
                  const SizedBox(width: 20),
                  // ATRASAR (Toque simple: anterior | Toque largo: -10 seg)
                  GestureDetector(
                    onTap: _previousVideo,
                    onLongPress: () => _seekRelative(-10),
                    child: const Icon(Icons.skip_previous, size: 50, color: Colors.white),
                  ),
                  const SizedBox(width: 30),
                  // PLAY / PAUSE
                  IconButton(
                    icon: Icon(
                      _videoController.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      size: 70,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _videoController.value.isPlaying ? _videoController.pause() : _videoController.play();
                      });
                    },
                  ),
                  const SizedBox(width: 30),
                  // ADELANTAR (Toque simple: siguiente | Toque largo: +10 seg)
                  GestureDetector(
                    onTap: _nextVideo,
                    onLongPress: () => _seekRelative(10),
                    child: const Icon(Icons.skip_next, size: 50, color: Colors.white),
                  ),
                  const SizedBox(width: 20),
                  // REPETIR
                  IconButton(
                    icon: Icon(_isLoopOne ? Icons.repeat_one_on : Icons.repeat_one),
                    onPressed: () {
                      setState(() { _isLoopOne = !_isLoopOne; _setupChewie(); });
                    },
                  ),
                ],
              ),
            ),
          ],

          // BOTÓN DE BLOQUEO (CANDADO)
          Positioned(
            top: 20,
            right: 20,
            child: GestureDetector(
              onDoubleTap: () {
                setState(() {
                  _isLocked = !_isLocked;
                  _setupChewie();
                });
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: Icon(_isLocked ? Icons.lock : Icons.lock_open, color: Colors.white, size: 30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // LISTA LATERAL
  Widget _buildSideList() {
    return Drawer(
      width: 300,
      backgroundColor: Colors.black87,
      child: ListView.builder(
        itemCount: widget.playlist.length,
        itemBuilder: (context, index) => ListTile(
          selected: _currentIndex == index,
          title: Text(widget.playlist[index].split('/').last, style: const TextStyle(color: Colors.white)),
          onTap: () {
            setState(() => _currentIndex = index);
            _refresh();
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    // IMPORTANTE: Devolver la rotación normal al salir del video
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _videoController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }
}