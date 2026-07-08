import 'package:flutter/material.dart';

import '../services/live_tv_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final LiveTvService _service = LiveTvService();

  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.getLiveTvData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Live TV"),
        centerTitle: true,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final current = snapshot.data!["currentChannel"];
          final channels = snapshot.data!["channels"] as List;

          return Column(
            children: [
              const SizedBox(height: 20),

              // Reproductor
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Stack(
                  children: [
                    const Center(
                      child: Icon(
                        Icons.live_tv,
                        color: Colors.white,
                        size: 90,
                      ),
                    ),
                    Positioned(
                      top: 15,
                      left: 15,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          "EN VIVO",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                "${current["number"]} - ${current["name"]}",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Transmisión simulada",
                style: TextStyle(
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.keyboard_arrow_up),
                    label: const Text("Canal +"),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.keyboard_arrow_down),
                    label: const Text("Canal -"),
                  ),
                ],
              ),

              const SizedBox(height: 25),

              const Divider(),

              const Padding(
                padding: EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Lista de canales",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),

              Expanded(
                child: ListView.builder(
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final item = channels[index];

                    return ListTile(
                      leading: const Icon(Icons.tv),
                      title: Text(item["name"]),
                      subtitle: Text("Canal ${item["number"]}"),
                      trailing: const Icon(Icons.play_circle_fill),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}