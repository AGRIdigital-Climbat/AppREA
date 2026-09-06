import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';

/// Servicio de imágenes multiplataforma.
/// - Android/iOS: image_picker (cámara y galería)
/// - Windows: file_picker (seleccionar archivo de imagen)
class ImageService {
  static final ImageService _instance = ImageService._();
  factory ImageService() => _instance;
  ImageService._();

  final ImagePicker _picker = ImagePicker();

  Future<XFile?> takePhoto() async {
    if (Platform.isWindows) {
      return _pickFileWindows();
    }
    return await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1080,
    );
  }

  Future<XFile?> pickFromGallery() async {
    if (Platform.isWindows) {
      return _pickFileWindows();
    }
    return await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1080,
    );
  }

  Future<List<XFile>> pickMultipleFromGallery({int maxImages = 5}) async {
    if (Platform.isWindows) {
      return _pickMultipleFilesWindows(maxImages: maxImages);
    }
    final images = await _picker.pickMultiImage(
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (images.length > maxImages) {
      return images.sublist(0, maxImages);
    }
    return images;
  }

  /// Windows: seleccionar archivo de imagen via file_picker.
  Future<XFile?> _pickFileWindows() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: 'Seleccionar imagen',
    );
    if (result.isEmpty) return null;
    final filePath = result.first.path;
    if (filePath == null) return null;
    return XFile(filePath);
  }

  /// Windows: seleccionar múltiples archivos de imagen.
  Future<List<XFile>> _pickMultipleFilesWindows({int maxImages = 5}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: 'Seleccionar imágenes',
    );
    if (result.isEmpty) return [];
    final files = result
        .where((f) => f.path != null)
        .map((f) => XFile(f.path!))
        .toList();
    if (files.length > maxImages) {
      return files.sublist(0, maxImages);
    }
    return files;
  }

  Future<String> saveImageLocally(XFile image) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${path.basename(image.path)}';
    final savedImage = await File(image.path).copy('${appDir.path}/$fileName');
    return savedImage.path;
  }

  Future<String?> imageToBase64(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteImage(String imagePath) async {
    final file = File(imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteImages(List<String> paths) async {
    for (final path in paths) {
      await deleteImage(path);
    }
  }

  Future<void> clearAllImages() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final entities = appDir.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (ext == '.jpg' ||
              ext == '.jpeg' ||
              ext == '.png' ||
              ext == '.webp' ||
              ext == '.gif') {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }
}
