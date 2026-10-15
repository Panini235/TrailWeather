import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

enum PhotoPickSource { gallery, camera }

class PickedPhoto {
  const PickedPhoto(this.bytes, this.extension);

  final Uint8List bytes;
  final String extension;
}

/// 系统相册/相机选择边界，测试中替换。
abstract interface class PhotoPicker {
  /// 用户取消时返回 null。
  Future<PickedPhoto?> pick(PhotoPickSource source);
}

class ImagePickerPhotoPicker implements PhotoPicker {
  const ImagePickerPhotoPicker();

  @override
  Future<PickedPhoto?> pick(PhotoPickSource source) async {
    // 限制尺寸与质量：节点图片用于回看，不需要原图，避免占用过多空间。
    final file = await ImagePicker().pickImage(
      source: source == PhotoPickSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 82,
    );
    if (file == null) return null;
    final name = file.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 && dot < name.length - 1
        ? name.substring(dot + 1)
        : 'jpg';
    return PickedPhoto(await file.readAsBytes(), ext);
  }
}
