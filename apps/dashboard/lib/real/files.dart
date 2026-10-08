/// Files in and out on the device (the web's `download.ts` and file inputs):
/// a save dialog on a desktop, the share sheet on a phone or tablet (whose
/// "Save to Files" is the save), the system pickers for a sheet or an image.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dashboard_core/dashboard_core.dart'
    show FileGateway, PickedFile;
import 'package:file_picker/file_picker.dart' as fp;
import 'package:file_selector/file_selector.dart' as fs;
import 'package:image_picker/image_picker.dart' as ip;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Whether this device saves through a dialog (a desktop) rather than the
/// share sheet.
bool get _desktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Uint8List _bytes(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);

class PlatformFileGateway implements FileGateway {
  const PlatformFileGateway();

  @override
  Future<String?> saveBytes(
    List<int> bytes, {
    required String filename,
    String? mimeType,
  }) async {
    if (_desktop) {
      final dot = filename.lastIndexOf('.');
      final ext = dot < 0 ? null : filename.substring(dot + 1);
      final where = await fs.getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: [
          if (ext != null)
            fs.XTypeGroup(
              label: ext.toUpperCase(),
              extensions: [ext],
              mimeTypes: mimeType == null ? null : [mimeType.split(';').first],
            ),
        ],
      );
      if (where == null) return null;
      await File(where.path).writeAsBytes(bytes, flush: true);
      return where.path;
    }
    // A phone or tablet: the file goes to a temporary folder and out through
    // the share sheet.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: filename)],
      ),
    );
    return result.status == ShareResultStatus.dismissed ? null : file.path;
  }

  @override
  Future<void> share(
    List<int> bytes, {
    required String filename,
    String? mimeType,
    String? text,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        files: [
          XFile.fromData(_bytes(bytes), name: filename, mimeType: mimeType),
        ],
        fileNameOverrides: [filename],
      ),
    );
  }

  @override
  Future<PickedFile?> pickFile({List<String>? extensions}) async {
    final any = extensions == null || extensions.isEmpty;
    final picked = await fp.FilePicker.pickFile(
      type: any ? fp.FileType.any : fp.FileType.custom,
      allowedExtensions: any ? null : extensions,
    );
    if (picked == null) return null;
    final x = picked.xFile;
    return PickedFile(
      name: picked.name,
      bytes: await x.readAsBytes(),
      mimeType: x.mimeType,
    );
  }

  @override
  Future<PickedFile?> pickImage() async {
    if (_desktop) {
      final x = await fs.openFile(
        acceptedTypeGroups: const [
          fs.XTypeGroup(
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
            mimeTypes: ['image/png', 'image/jpeg', 'image/webp', 'image/gif'],
          ),
        ],
      );
      if (x == null) return null;
      return PickedFile(
        name: x.name,
        bytes: await x.readAsBytes(),
        mimeType: x.mimeType,
      );
    }
    final x = await ip.ImagePicker().pickImage(source: ip.ImageSource.gallery);
    if (x == null) return null;
    return PickedFile(
      name: x.name,
      bytes: await x.readAsBytes(),
      mimeType: x.mimeType,
    );
  }
}
