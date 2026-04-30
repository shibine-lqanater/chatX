import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum SignalingMessageType {
  joinRequest,
  joinResponse,
  webrtcOffer,
  webrtcAnswer,
  webrtcIceCandidate,
  userUpdate,
  disconnect
}

class SignalingMessage {
  final SignalingMessageType type;
  final Map<String, dynamic> data;
  final String? from;

  SignalingMessage({required this.type, required this.data, this.from});

  Map<String, dynamic> toJson() => {
    'type': type.index,
    'data': data,
    'from': from,
  };

  factory SignalingMessage.fromJson(Map<String, dynamic> json) => SignalingMessage(
    type: SignalingMessageType.values[json['type']],
    data: json['data'],
    from: json['from'],
  );
}

class SignalingService {
  ServerSocket? _server;
  Socket? _clientSocket;
  final List<Socket> _connectedClients = [];
  
  final _messageController = StreamController<SignalingMessage>.broadcast();
  Stream<SignalingMessage> get messages => _messageController.stream;

  // For Director
  Future<int> startServer() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server!.listen((socket) {
      _connectedClients.add(socket);
      socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((data) {
        try {
          final message = SignalingMessage.fromJson(jsonDecode(data));
          _messageController.add(message);
        } catch (e) {
          print('Error decoding message: $e');
        }
      }, onDone: () {
        _connectedClients.remove(socket);
      });
    });
    return _server!.port;
  }

  void broadcast(SignalingMessage message) {
    final encoded = jsonEncode(message.toJson()) + '\n';
    for (var client in _connectedClients) {
      client.write(encoded);
    }
  }

  void sendTo(String targetId, SignalingMessage message) {
    // For simplicity, we still broadcast or could add logic to filter
    broadcast(message);
  }

  // For Photographer
  Future<void> connectToServer(String ip, int port) async {
    _clientSocket = await Socket.connect(ip, port);
    _clientSocket!.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((data) {
      try {
        final message = SignalingMessage.fromJson(jsonDecode(data));
        _messageController.add(message);
      } catch (e) {
        print('Error decoding message: $e');
      }
    });
  }

  void sendMessage(SignalingMessage message) {
    if (_clientSocket != null) {
      _clientSocket!.write(jsonEncode(message.toJson()) + '\n');
    }
  }

  Future<void> close() async {
    await _server?.close();
    await _clientSocket?.close();
    for (var client in _connectedClients) {
      await client.close();
    }
    _connectedClients.clear();
  }
}
