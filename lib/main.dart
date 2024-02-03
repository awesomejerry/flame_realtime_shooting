import 'package:flame/game.dart';
import 'package:flame_realtime_shooting/game/game.dart';
import 'package:flame_realtime_shooting/lobby.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  await Supabase.initialize(
    url: 'https://hzgjnugmyfgqrzyqibmy.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh6Z2pudWdteWZncXJ6eXFpYm15Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDY5NDI0MjYsImV4cCI6MjAyMjUxODQyNn0.R5e-fakaHtGuyVLIWkkThaduUXWx2No62pjxpTxgPBg',
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 40),
  );
  runApp(const MyApp());
}

// Extract Supabase client for easy access to Supabase
final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'UFO Shooting Game',
      debugShowCheckedModeBanner: false,
      home: GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final MyGame _game;

  /// Holds the RealtimeChannel to sync game states
  RealtimeChannel? _gameChannel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/background.jpg', fit: BoxFit.cover),
          GameWidget(game: _game),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _game = MyGame(
      onGameStateUpdate: (position, health) async {
        ChannelResponse response;
        do {
          response = await _gameChannel!.sendBroadcastMessage(
            event: 'game_state',
            payload: {'x': position.x, 'y': position.y, 'health': health},
          );

          // wait for a frame to avoid infinite rate limiting loops
          await Future.delayed(Duration.zero);
          setState(() {});
        } while (response == ChannelResponse.rateLimited && health <= 0);
      },
      onGameOver: (playerWon) async {
        await showDialog(
          barrierDismissible: false,
          context: context,
          builder: ((context) {
            return AlertDialog(
              title: Text(playerWon ? 'You Won!' : 'You lost...'),
              actions: [
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await supabase.removeChannel(_gameChannel!);
                    _openLobbyDialog();
                  },
                  child: const Text('Back to Lobby'),
                ),
              ],
            );
          }),
        );
      },
    );

    // await for a frame so that the widget mounts
    await Future.delayed(Duration.zero);

    if (mounted) {
      _openLobbyDialog();
    }
  }

  void _openLobbyDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return LobbyDialog(
            onGameStarted: (gameId) async {
              // await a frame to allow subscribing to a new channel in a realtime callback
              await Future.delayed(Duration.zero);

              setState(() {});

              _game.startNewGame();

              _gameChannel = supabase.channel(gameId,
                  opts: const RealtimeChannelConfig(ack: true));

              _gameChannel!
                  .onBroadcast(
                    event: 'game_state',
                    callback: (payload, [_]) {
                      final position = Vector2(
                          payload['x'] as double, payload['y'] as double);
                      final opponentHealth = payload['health'] as int;
                      _game.updateOpponent(
                        position: position,
                        health: opponentHealth,
                      );

                      if (opponentHealth <= 0) {
                        if (!_game.isGameOver) {
                          _game.isGameOver = true;
                          _game.onGameOver(true);
                        }
                      }
                    },
                  )
                  .subscribe();
            },
          );
        });
  }
}
