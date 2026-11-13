import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:mija_time_sync/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MijaTimeSyncApp());
}

class MijaTimeSyncApp extends StatelessWidget {
  const MijaTimeSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mija Time Sync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B63)),
        useMaterial3: true,
      ),
      home: const FindDevicesScreen(),
    );
  }
}

class FindDevicesScreen extends StatefulWidget {
  const FindDevicesScreen({super.key});

  @override
  State<FindDevicesScreen> createState() => _FindDevicesScreenState();
}

class _FindDevicesScreenState extends State<FindDevicesScreen> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Map<String, DiscoveredDevice> _devices = {};
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<BleStatus>? _statusSubscription;
  BleStatus _status = BleStatus.unknown;
  bool _isScanning = false;
  String? _error;

  static final Uuid _environmentService = Uuid.parse(
    '0000181a-0000-1000-8000-00805f9b34fb',
  );
  static final Uuid _mijaTimeService = Uuid.parse(
    'ebe0ccb0-7a0a-4b0c-8a1a-6ff2997da3a6',
  );

  @override
  void initState() {
    super.initState();
    _statusSubscription = _ble.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleScan() async {
    if (_isScanning) {
      await _scanSubscription?.cancel();
      if (mounted) setState(() => _isScanning = false);
      return;
    }

    final permissionGranted = await _requestScanPermission();
    if (!permissionGranted) {
      if (mounted) {
        setState(() => _error = 'Bluetooth permission is required to scan.');
      }
      return;
    }

    setState(() {
      _devices.clear();
      _error = null;
      _isScanning = true;
    });
    _scanSubscription = _ble.scanForDevices(
      withServices: [_environmentService, _mijaTimeService],
      scanMode: ScanMode.lowLatency,
    ).listen(
      (device) {
        if (mounted) setState(() => _devices[device.id] = device);
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _error = error.toString();
            _isScanning = false;
          });
        }
      },
    );
  }

  Future<bool> _requestScanPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final permissions = androidInfo.version.sdkInt >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
    final statuses = await permissions.request();
    return statuses.values.every((status) => status.isGranted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mija Time Sync')),
      body: Column(
        children: [
          ListTile(
            leading: Icon(
              _status == BleStatus.ready
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
            ),
            title: Text('Bluetooth: ${_status.name}'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Text(
                      _isScanning
                          ? 'Searching nearby devices...'
                          : 'No devices found',
                    ),
                  )
                : ListView(
                    children: _devices.values
                        .map(
                          (device) => ScanResultTile(
                            device: device,
                            onTap: () async {
                              await _scanSubscription?.cancel();
                              if (!mounted) return;
                              setState(() => _isScanning = false);
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DeviceScreen(
                                    ble: _ble,
                                    device: device,
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                        .toList(),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleScan,
        icon: Icon(_isScanning ? Icons.stop : Icons.search),
        label: Text(_isScanning ? 'Stop scan' : 'Scan'),
      ),
    );
  }
}

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({required this.ble, required this.device, super.key});

  final FlutterReactiveBle ble;
  final DiscoveredDevice device;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  DeviceConnectionState _connectionState = DeviceConnectionState.disconnected;
  bool _isBusy = false;

  static final Uuid _serviceId = Uuid.parse(
    'ebe0ccb0-7a0a-4b0c-8a1a-6ff2997da3a6',
  );
  static final Uuid _timeCharacteristicId = Uuid.parse(
    'ebe0ccb7-7a0a-4b0c-8a1a-6ff2997da3a6',
  );

  @override
  void initState() {
    super.initState();
    _connectionSubscription = widget.ble
        .connectToDevice(
      id: widget.device.id,
      connectionTimeout: const Duration(seconds: 10),
    )
        .listen(
      (update) {
        if (mounted) setState(() => _connectionState = update.connectionState);
      },
      onError: (Object error) {
        if (mounted) _showMessage('Connection failed: $error');
      },
    );
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _setDeviceTime() async {
    setState(() => _isBusy = true);
    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: _serviceId,
        characteristicId: _timeCharacteristicId,
        deviceId: widget.device.id,
      );
      final now = DateTime.now();
      final data = ByteData(5)
        ..setInt32(0, now.millisecondsSinceEpoch ~/ 1000, Endian.little)
        ..setInt8(4, now.timeZoneOffset.inHours);
      await widget.ble.writeCharacteristicWithResponse(
        characteristic,
        value: data.buffer.asUint8List(),
      );
      if (mounted) _showMessage('Time synchronized');
    } catch (error) {
      if (mounted) _showMessage('Could not set time: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connectionState == DeviceConnectionState.connected;
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Icon(
              connected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
            ),
            title: Text(_connectionState.name),
            subtitle: Text(widget.device.id),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: connected && !_isBusy ? _setDeviceTime : null,
            icon: _isBusy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.schedule),
            label: const Text('Synchronize time'),
          ),
        ],
      ),
    );
  }
}
