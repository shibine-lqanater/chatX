import 'dart:async';
import 'package:nsd/nsd.dart' as nsd;
import 'package:network_info_plus/network_info_plus.dart';

class NetworkService {
  static const String serviceType = '_intercom._tcp';
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  final _info = NetworkInfo();

  // Broadcast Director Service
  Future<void> startBroadcasting(String name, int port) async {
    _registration = await nsd.register(
      nsd.Service(name: name, type: serviceType, port: port),
    );
  }

  Future<void> stopBroadcasting() async {
    if (_registration != null) {
      await nsd.unregister(_registration!);
      _registration = null;
    }
  }

  // Discover Director Service
  Stream<List<nsd.Service>> discoverServices() async* {
    _discovery = await nsd.startDiscovery(serviceType);
    
    final controller = StreamController<List<nsd.Service>>();
    
    _discovery!.addListener(() {
      controller.add(_discovery!.services);
    });

    yield* controller.stream;
  }

  Future<void> stopDiscovery() async {
    if (_discovery != null) {
      await nsd.stopDiscovery(_discovery!);
      _discovery = null;
    }
  }

  Future<String?> getLocalIp() async {
    return await _info.getWifiIP();
  }
}
