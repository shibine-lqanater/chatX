import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:io';

import 'services/network_service.dart';
import 'services/signaling_service.dart';
import 'services/audio_service.dart';

void main() {
  runApp(const IntercomApp());
}

class IntercomApp extends StatelessWidget {
  const IntercomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Intercom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E293B),
        ),
        useMaterial3: true,
      ),
      home: const RoleSelectionScreen(),
    );
  }
}

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
      Permission.location, // Needed for Wi-Fi info on some Android versions
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.record_voice_over, size: 80, color: Color(0xFF6366F1)),
              const SizedBox(height: 20),
              const Text(
                'Intercom المحلي',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 40),
              _buildRoleCard(
                title: 'مخرج (Director)',
                subtitle: 'إدارة المكالمة والتحكم في المتصلين',
                icon: Icons.settings_input_antenna,
                color: const Color(0xFF6366F1),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DirectorScreen())),
              ),
              const SizedBox(height: 20),
              _buildRoleCard(
                title: 'مصور (Photographer)',
                subtitle: 'الانضمام للمكالمة والبث الصوتي',
                icon: Icons.camera_alt,
                color: const Color(0xFF10B981),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PhotographerScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5), width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Director Screen ---
class DirectorScreen extends StatefulWidget {
  const DirectorScreen({super.key});

  @override
  State<DirectorScreen> createState() => _DirectorScreenState();
}

class _DirectorScreenState extends State<DirectorScreen> {
  final NetworkService _network = NetworkService();
  final SignalingService _signaling = SignalingService();
  final AudioService _audio = AudioService();
  
  String? deviceId;
  String? deviceName;
  Map<String, RemoteUser> users = {};

  @override
  void initState() {
    super.initState();
    _setupDirector();
  }

  String? localIp;

  Future<void> _setupDirector() async {
    localIp = await _network.getLocalIp();
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      deviceId = android.id;
      deviceName = android.model;
    } else {
      final ios = await info.iosInfo;
      deviceId = ios.identifierForVendor;
      deviceName = ios.name;
    }

    final port = await _signaling.startServer();
    await _network.startBroadcasting(deviceName ?? 'Director', port);

    _signaling.messages.listen(_handleMessage);
    await _audio.getUserMedia();
    
    setState(() {});
  }

  void _handleMessage(SignalingMessage message) async {
    final fromId = message.from;
    if (fromId == null) return;

    switch (message.type) {
      case SignalingMessageType.joinRequest:
        setState(() {
          users[fromId] = RemoteUser(
            id: fromId,
            name: message.data['name'],
            status: UserStatus.waiting,
          );
        });
        break;
      case SignalingMessageType.webrtcOffer:
        final answer = await _audio.createAnswer(fromId, RTCSessionDescription(
          message.data['sdp'],
          message.data['type'],
        ));
        _signaling.sendTo(fromId, SignalingMessage(
          type: SignalingMessageType.webrtcAnswer,
          data: answer.toMap(),
          from: deviceId,
        ));
        setState(() {
          users[fromId]?.status = UserStatus.connected;
        });
        break;
      case SignalingMessageType.webrtcIceCandidate:
        await _audio.addCandidate(fromId, RTCIceCandidate(
          message.data['candidate'],
          message.data['sdpMid'],
          message.data['sdpMLineIndex'],
        ));
        break;
      case SignalingMessageType.disconnect:
        setState(() {
          users.remove(fromId);
        });
        break;
      default:
        break;
    }
  }

  void _allowUser(RemoteUser user) async {
    setState(() {
      user.status = UserStatus.connecting;
    });

    // Create Peer Connection
    await _audio.initializePeerConnection(
      user.id,
      (candidate) {
        _signaling.sendTo(user.id, SignalingMessage(
          type: SignalingMessageType.webrtcIceCandidate,
          data: candidate.toMap(),
          from: deviceId,
        ));
      },
      (stream) {
        // Handle remote stream if needed (though Director listens to Photographer)
      },
    );

    _signaling.sendTo(user.id, SignalingMessage(
      type: SignalingMessageType.joinResponse,
      data: {'accepted': true},
      from: deviceId,
    ));
  }

  @override
  void dispose() {
    _network.stopBroadcasting();
    _signaling.close();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة المخرج'), 
        backgroundColor: Colors.transparent,
        actions: [
          if (localIp != null) Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(label: Text('IP: $localIp')),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('المصورون على الشبكة:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: users.isEmpty 
                ? const Center(child: Text('في انتظار انضمام المصورين...'))
                : ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users.values.elementAt(index);
                      return Card(
                        color: Colors.white.withOpacity(0.05),
                        child: ListTile(
                          title: Text(user.name),
                          subtitle: Text(user.status.name),
                          trailing: user.status == UserStatus.waiting 
                            ? ElevatedButton(
                                onPressed: () => _allowUser(user),
                                child: const Text('سماح بالدخول'),
                              )
                            : const Icon(Icons.check_circle, color: Colors.green),
                        ),
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

// --- Photographer Screen ---
class PhotographerScreen extends StatefulWidget {
  const PhotographerScreen({super.key});

  @override
  State<PhotographerScreen> createState() => _PhotographerScreenState();
}

class _PhotographerScreenState extends State<PhotographerScreen> {
  final NetworkService _network = NetworkService();
  final SignalingService _signaling = SignalingService();
  final AudioService _audio = AudioService();
  
  String? deviceId;
  String? deviceName;
  bool isConnected = false;
  bool isAccepted = false;

  @override
  void initState() {
    super.initState();
    _setupPhotographer();
  }

  Future<void> _setupPhotographer() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      deviceId = android.id;
      deviceName = android.model;
    } else {
      final ios = await info.iosInfo;
      deviceId = ios.identifierForVendor;
      deviceName = ios.name;
    }

    _network.discoverServices().listen((services) {
      if (!isConnected && services.isNotEmpty) {
        final service = services.first;
        _connectToDirector(service.host!, service.port!);
      }
    });
  }

  Future<void> _connectToDirector(String ip, int port) async {
    try {
      await _signaling.connectToServer(ip, port);
      setState(() => isConnected = true);

      _signaling.messages.listen(_handleMessage);

      _signaling.sendMessage(SignalingMessage(
        type: SignalingMessageType.joinRequest,
        data: {'name': deviceName},
        from: deviceId,
      ));
    } catch (e) {
      print('Connection failed: $e');
    }
  }

  void _handleMessage(SignalingMessage message) async {
    switch (message.type) {
      case SignalingMessageType.joinResponse:
        if (message.data['accepted'] == true) {
          setState(() => isAccepted = true);
          _startAudioStream(message.from!);
        }
        break;
      case SignalingMessageType.webrtcIceCandidate:
        await _audio.addCandidate(message.from!, RTCIceCandidate(
          message.data['candidate'],
          message.data['sdpMid'],
          message.data['sdpMLineIndex'],
        ));
        break;
      case SignalingMessageType.webrtcAnswer:
        await _audio.setRemoteDescription(message.from!, RTCSessionDescription(
          message.data['sdp'],
          message.data['type'],
        ));
        break;
      default:
        break;
    }
  }

  Future<void> _startAudioStream(String directorId) async {
    await _audio.getUserMedia();
    await _audio.initializePeerConnection(
      directorId,
      (candidate) {
        _signaling.sendMessage(SignalingMessage(
          type: SignalingMessageType.webrtcIceCandidate,
          data: candidate.toMap(),
          from: deviceId,
        ));
      },
      (stream) {},
    );

    final offer = await _audio.createOffer(directorId);
    _signaling.sendMessage(SignalingMessage(
      type: SignalingMessageType.webrtcOffer,
      data: offer.toMap(),
      from: deviceId,
    ));
  }

  @override
  void dispose() {
    _network.stopDiscovery();
    _signaling.close();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('شاشة المصور'), backgroundColor: Colors.transparent),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAccepted ? Icons.mic : (isConnected ? Icons.hourglass_empty : Icons.wifi_find),
              size: 100,
              color: isAccepted ? Colors.green : (isConnected ? Colors.orange : Colors.grey),
            ),
            const SizedBox(height: 20),
            Text(
              isAccepted 
                ? 'متصل ومسموح لك بالكلام' 
                : (isConnected ? 'في انتظار موافقة المخرج...' : 'جاري البحث عن المخرج...'),
              style: const TextStyle(fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Helper Models ---
enum UserStatus { waiting, connecting, connected }

class RemoteUser {
  final String id;
  final String name;
  UserStatus status;

  RemoteUser({required this.id, required this.name, required this.status});
}
