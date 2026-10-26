import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Text;
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

/// What the room QR code contains. Old/plain codes (just the code) are accepted too.
String roomQrData(String code) => 'roommate:$code';

String? parseRoomQr(String raw) {
  var v = raw.trim();
  if (v.toLowerCase().startsWith('roommate:')) v = v.substring(9).trim();
  v = v.toUpperCase();
  // a room code is short letters/digits; ignore any other kind of QR code
  if (v.length < 4 || v.length > 20 || !RegExp(r'^[A-Z0-9\-]+$').hasMatch(v)) return null;
  return v;
}


/// The room QR as a PNG picture (white border included) for saving / sharing.
Future<Uint8List> roomQrPng() async {
  const total = 1200.0;
  const margin = 100.0;
  final painter = QrPainter(
    data: roomQrData(appState.roomCode),
    version: QrVersions.auto,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF000000),
    ),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, total, total));
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, total, total),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.translate(margin, margin);
  painter.paint(canvas, const Size(total - 2 * margin, total - 2 * margin));
  final image = await recorder.endRecording().toImage(total.toInt(), total.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<File> _roomQrFile() async {
  final bytes = await roomQrPng();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/RoomMate_${appState.roomCode}.png');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

/// Saves the QR picture to the phone's gallery.
Future<void> downloadRoomQr(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await Gal.putImageBytes(await roomQrPng(), album: 'RoomMate');
    messenger.showSnackBar(const SnackBar(content: Text('QR code saved to your gallery')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save the QR code. Try Share instead. ($e)')));
  }
}

/// Opens the share sheet (WhatsApp, Drive, email...) with the QR picture.
Future<void> shareRoomQr(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await _roomQrFile();
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: 'Join my RoomMate room "${appState.roomName}". Scan this QR code in the app, or use room code ${appState.roomCode}.',
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not share the QR code: $e')));
  }
}

/// Lets the user pick a photo / screenshot of a room QR code and reads the room code from it.
/// Returns null if nothing was picked; shows a message if the picture has no RoomMate QR.
Future<String?> pickRoomQrFromPhoto(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return null;
  final controller = MobileScannerController();
  try {
    final capture = await controller.analyzeImage(file.path);
    for (final b in capture?.barcodes ?? const <Barcode>[]) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final code = parseRoomQr(raw);
      if (code != null) return code;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('No RoomMate QR code found in that photo')),
    );
    return null;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not read that photo: $e')));
    return null;
  } finally {
    await controller.dispose();
  }
}

/// Camera screen: points at a room QR code and returns the room code (String) via Navigator.pop.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final code = parseRoomQr(raw);
      if (code != null) {
        _done = true;
        Navigator.pop(context, code);
        return;
      }
      setState(() => _hint = 'That is not a RoomMate QR code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan room QR code'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Flashlight',
            icon: const Icon(Icons.flashlight_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              _hint ?? 'Point the camera at the QR code on the room owner\'s phone',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _hint == null ? Colors.white : Colors.orangeAccent,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the room's QR code so a friend can scan it to ask to join.
void showRoomQr(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(appState.roomName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            // fixed-size box: QrImageView cannot be measured by AlertDialog without it
            child: SizedBox(
              width: 210,
              height: 210,
              child: QrImageView(
                data: roomQrData(appState.roomCode),
                version: QrVersions.auto,
                size: 210,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF000000),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF000000),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(appState.roomCode,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: 3)),
          const SizedBox(height: 6),
          const Text(
            'Ask your roommate to open RoomMate, tap Scan QR Code and point their camera here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        TextButton.icon(
          onPressed: () => downloadRoomQr(context),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download'),
        ),
        ElevatedButton.icon(
          onPressed: () => shareRoomQr(context),
          icon: const Icon(Icons.share_rounded, size: 18),
          label: const Text('Share'),
        ),
      ],
    ),
  );
}
