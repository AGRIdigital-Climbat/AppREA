import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
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

  /// Post-proceso de captura (A+C): JPEG a 1280 px, calidad 75 y SIN EXIF
  /// (la fecha y las coordenadas ya se guardan en la BD, y la rotación se
  /// aplica sobre los píxeles con autoRotate). Escenas ultra-detail que
  /// sigan pasando de ~300 KB se re-comprimen a 1024 px q65.
  ///
  /// Resultado: foto nítida en pantalla de celular (≈1.2 MP HD) con 3-4x
  /// menos peso para subir en señal débil. Si algo falla se conserva la
  /// foto original: perder evidencia es peor que una foto pesada. Windows
  /// no usa el plugin (file_picker devuelve el archivo tal cual).
  Future<XFile> _optimizarFoto(XFile foto) async {
    if (Platform.isWindows) return foto;
    try {
      final antes = await File(foto.path).length();
      final tmp = await getTemporaryDirectory();
      final niveles = <List<int>>[
        [1280, 75],
        [1024, 65],
      ];
      var origen = foto.path;
      XFile? mejor;
      for (var i = 0; i < niveles.length; i++) {
        final destino =
            '${tmp.path}/edan_foto_${DateTime.now().microsecondsSinceEpoch}_$i.jpg';
        final res = await FlutterImageCompress.compressAndGetFile(
          origen,
          destino,
          minWidth: niveles[i][0],
          minHeight: niveles[i][0],
          quality: niveles[i][1],
          format: CompressFormat.jpeg,
          keepExif: false,
        );
        if (res == null) break;
        mejor = res;
        if (await File(res.path).length() <= 300 * 1024) break;
        origen = res.path;
      }
      if (mejor != null) {
        final despues = await File(mejor.path).length();
        if (despues < antes) {
          debugPrint('[ImageService] foto optimizada: '
              '${(antes >> 10)} KB -> ${(despues >> 10)} KB');
          return mejor;
        }
        // La "optimización" salió más grande (foto ya pequeña): mejor la
        // original, intacta.
        return foto;
      }
    } catch (e) {
      debugPrint('[ImageService] optimización falló, uso original: $e');
    }
    return foto;
  }

  Future<XFile?> takePhoto() async {
    if (Platform.isWindows) {
      return _pickFileWindows();
    }
    try {
      final foto = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      if (foto != null) return _optimizarFoto(foto);
      // Sin foto y sin excepción: el SO pudo matar la activity con la cámara
      // abierta (típico en Xiaomi/Huawei con poca RAM). Intentar rescate.
      return await recuperarFotoPerdida();
    } on PlatformException {
      // Cámara desconectada / app matada a mitad del intent.
      return await recuperarFotoPerdida();
    } catch (_) {
      return null;
    }
  }

  /// Recupera la foto si Android mató el proceso mientras la cámara estaba
  /// abierta (`getLostData`). `null` si no hay nada que recuperar. Solo
  /// Android/iOS; en Windows siempre `null`.
  Future<XFile?> recuperarFotoPerdida() async {
    if (Platform.isWindows) return null;
    try {
      final perdidos = await _picker.retrieveLostData();
      if (!perdidos.isEmpty && perdidos.file != null) {
        // La ruta de rescate puede traer la foto NATIVA de la cámara: también
        // pasa por la optimización.
        return _optimizarFoto(perdidos.file!);
      }
    } catch (_) {}
    return null;
  }

  Future<XFile?> pickFromGallery() async {
    if (Platform.isWindows) {
      return _pickFileWindows();
    }
    final foto = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (foto == null) return null;
    return _optimizarFoto(foto);
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
    final optimizadas = <XFile>[];
    for (final img in images) {
      optimizadas.add(await _optimizarFoto(img));
    }
    if (optimizadas.length > maxImages) {
      return optimizadas.sublist(0, maxImages);
    }
    return optimizadas;
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

  /// Guarda la foto en la carpeta persistente `report_photos` con el nombre
  /// `<photoUuid>.<ext>` (Etapa 4: localizable por uuid, sin colisiones por
  /// timestamp). Crea la carpeta si falta.
  Future<String> savePhotoLocally(XFile image, String photoUuid) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/report_photos');
    await dir.create(recursive: true);
    var ext = path.extension(image.path).toLowerCase();
    if (ext.isEmpty) ext = '.jpg';
    final savedImage =
        await File(image.path).copy('${dir.path}/$photoUuid$ext');
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
