import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperService {
  WallpaperService._();

  static const _channel = MethodChannel('com.locksync/wallpaper');

  /// Set the lock screen wallpaper from PNG bytes.
  /// On Android: sets the lock screen wallpaper directly.
  /// On iOS: saves to camera roll and shows guided instructions.
  static Future<void> setLockScreenWallpaper(
    Uint8List imageBytes, {
    BuildContext? context,
  }) async {
    if (Platform.isAndroid) {
      await _setAndroidLockScreen(imageBytes, context: context);
    } else if (Platform.isIOS) {
      await _saveAndGuideIOS(imageBytes, context: context);
    }
  }

  static Future<void> _setAndroidLockScreen(
    Uint8List imageBytes, {
    BuildContext? context,
  }) async {
    try {
      // Save to temp file first
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/locksync_wallpaper.png');
      await file.writeAsBytes(imageBytes);

      // Try platform channel to set wallpaper
      try {
        await _channel.invokeMethod('setLockScreenWallpaper', {
          'path': file.path,
        });

        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lock screen wallpaper updated!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } on MissingPluginException {
        // Fallback: save to gallery
        await _saveToGallery(imageBytes);
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Image saved to gallery. Set it as lock screen in Settings.'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      // Final fallback
      await _saveToGallery(imageBytes);
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Image saved to gallery. Set it as lock screen manually.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static Future<void> _saveAndGuideIOS(
    Uint8List imageBytes, {
    BuildContext? context,
  }) async {
    await _saveToGallery(imageBytes);

    if (context != null && context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Image Saved!',
            style: TextStyle(color: Colors.white),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your LockSync image has been saved to Photos.',
                style: TextStyle(color: Colors.white70),
              ),
              SizedBox(height: 16),
              Text(
                'To set it as your lock screen:',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              _IOSStep(number: '1', text: 'Open Settings → Wallpaper'),
              _IOSStep(
                  number: '2', text: 'Tap "Add New Wallpaper"'),
              _IOSStep(
                  number: '3',
                  text: 'Select the most recent photo from your Camera Roll'),
              _IOSStep(number: '4', text: 'Set as Lock Screen'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it!'),
            ),
          ],
        ),
      );
    }
  }

  static Future<void> _saveToGallery(Uint8List imageBytes) async {
    await ImageGallerySaverPlus.saveImage(
      imageBytes,
      quality: 100,
      name: 'locksync_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Set the lock screen wallpaper silently (no UI feedback).
  /// Safe to call from background contexts.  Android only.
  static Future<void> setWallpaperSilent(Uint8List imageBytes) async {
    if (!Platform.isAndroid) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/locksync_wallpaper.png');
      await file.writeAsBytes(imageBytes);
      await _channel.invokeMethod('setLockScreenWallpaper', {
        'path': file.path,
      });
    } catch (_) {
      // Silently fail — auto-update is best-effort
    }
  }

  /// Allow the activity to display over the Android lock screen.
  /// Call with [show] = true so the canvas (or a full-screen notification)
  /// can appear without the user needing to unlock first.
  static Future<void> setShowOnLockScreen(bool show) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setShowOnLockScreen', {'show': show});
    } catch (_) {}
  }

  /// Save the latest canvas image to gallery (for iOS "refresh & save")
  static Future<void> saveToGallery(
    Uint8List imageBytes, {
    BuildContext? context,
  }) async {
    await _saveToGallery(imageBytes);
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image saved to Photos!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _IOSStep extends StatelessWidget {
  final String number;
  final String text;
  const _IOSStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(right: 8, top: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
