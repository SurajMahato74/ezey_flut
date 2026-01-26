import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config.dart' as appConfig;

class CallTestWidget extends StatefulWidget {
  const CallTestWidget({super.key});

  @override
  State<CallTestWidget> createState() => _CallTestWidgetState();
}

class _CallTestWidgetState extends State<CallTestWidget> {
  RtcEngine? _engine;
  bool _permissionGranted = false;
  String _status = 'Not initialized';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.microphone.request();
    setState(() {
      _permissionGranted = status == PermissionStatus.granted;
      _status = _permissionGranted ? 'Permission granted' : 'Permission denied';
    });
  }

  Future<void> _testAgoraInit() async {
    try {
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(const RtcEngineContext(appId: appConfig.Config.agoraAppId));
      await _engine!.enableAudio();
      
      setState(() => _status = 'Agora initialized successfully');
    } catch (e) {
      setState(() => _status = 'Agora init failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call Test')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Status: $_status'),
            const SizedBox(height: 20),
            Text('Permission: ${_permissionGranted ? "✅" : "❌"}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _testAgoraInit,
              child: const Text('Test Agora Init'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _engine?.release();
    super.dispose();
  }
}