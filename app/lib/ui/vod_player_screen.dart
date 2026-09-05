import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/vod.dart';

/// Full-screen movie player. Unlike live TV, VOD is seekable, so this uses
/// media_kit's stock scrubber/controls instead of the custom live overlay
/// (which is built for channel-up/down, not pause/seek).
class VodPlayerScreen extends StatefulWidget {
  final VodItem item;
  const VodPlayerScreen({super.key, required this.item});
  @override
  State<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends State<VodPlayerScreen> {
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  String? error;

  @override
  void initState() {
    super.initState();
    player.stream.error.listen((e) { if (mounted) setState(() => error = e); });
    player.open(Media(widget.item.streamUrl));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: Text(widget.item.name)),
      extendBodyBehindAppBar: true,
      body: Stack(fit: StackFit.expand, children: [
        Video(controller: controller),
        if (error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Playback error: $error',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontSize: 18)),
            ),
          ),
      ]),
    );
  }
}
