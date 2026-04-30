import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

class AudioService {
  webrtc.MediaStream? _localStream;
  
  final Map<String, webrtc.RTCPeerConnection> _peerConnections = {};

  Future<webrtc.MediaStream> getUserMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    };
    _localStream = await webrtc.navigator.mediaDevices.getUserMedia(constraints);
    return _localStream!;
  }

  Future<webrtc.RTCPeerConnection> initializePeerConnection(String userId, Function(webrtc.RTCIceCandidate) onIceCandidate, Function(webrtc.MediaStream) onRemoteStream) async {
    final configuration = {
      'iceServers': [], // Local network only, no STUN needed usually
      'sdpSemantics': 'unified-plan',
    };

    final pc = await webrtc.createPeerConnection(configuration);
    
    pc.onIceCandidate = onIceCandidate;
    pc.onAddStream = onRemoteStream;
    
    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });
    }

    _peerConnections[userId] = pc;
    return pc;
  }

  Future<webrtc.RTCSessionDescription> createOffer(String userId) async {
    final pc = _peerConnections[userId];
    final offer = await pc!.createOffer();
    await pc.setLocalDescription(offer);
    return offer;
  }

  Future<webrtc.RTCSessionDescription> createAnswer(String userId, webrtc.RTCSessionDescription offer) async {
    final pc = _peerConnections[userId];
    await pc!.setRemoteDescription(offer);
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(String userId, webrtc.RTCSessionDescription sdp) async {
    await _peerConnections[userId]?.setRemoteDescription(sdp);
  }

  Future<void> addCandidate(String userId, webrtc.RTCIceCandidate candidate) async {
    await _peerConnections[userId]?.addCandidate(candidate);
  }

  void dispose() {
    _localStream?.dispose();
    _peerConnections.forEach((key, pc) => pc.dispose());
    _peerConnections.clear();
  }
}
