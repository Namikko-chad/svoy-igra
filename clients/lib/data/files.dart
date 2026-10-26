import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

/// Picks one file. Returns null on cancel. [extensions] are checked after
/// picking (Android's picker does not know `.dub`).
Future<PlatformFile?> pickOneFile({FileType type = FileType.any}) => FilePicker.pickFile(type: type);

/// Picks several files (media upload).
Future<List<PlatformFile>> pickManyFiles({FileType type = FileType.any}) => FilePicker.pickFiles(type: type);

/// Streams a picked file into a multipart part without loading it in memory
/// when it is on disk.
Future<MultipartFile> multipartOf(PlatformFile f) async {
  final path = f.path;
  if (path != null) return MultipartFile.fromFile(path, filename: f.name);
  final length = f.lengthSync() ?? await f.length();
  if (length == null) return MultipartFile.fromBytes(await f.readAsBytes(), filename: f.name);
  return MultipartFile.fromStream(() => f.readAsByteStream(), length, filename: f.name);
}

/// Shows the system "save as" dialog. Returns false when cancelled.
Future<bool> saveBytes(String fileName, Uint8List bytes, {String mimeType = 'application/octet-stream'}) async {
  final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
  return uri != null;
}
