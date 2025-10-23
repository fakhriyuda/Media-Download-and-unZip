import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as im;
import 'package:tflite_flutter/tflite_flutter.dart';

class ImageClassificationHelper {
  late final Interpreter _age;
  late final Interpreter _gender;
  late final List<String> _genderLabels;

  // Input sizes (read from tensors at init)
  late final int _ageH, _ageW, _genH, _genW;

  bool _isReady = false;

  Future<void> initHelper() async {
    // Load models
    _age = await Interpreter.fromAsset('assets/models/new_age_model.tflite');
    _gender = await Interpreter.fromAsset('assets/models/new_gender_fp32.tflite');

    // Read input tensor shapes
    final ageShape = _age.getInputTensor(0).shape; // [1,H,W,3]
    final genShape = _gender.getInputTensor(0).shape; // [1,H,W,3]
    _ageH = ageShape[1];
    _ageW = ageShape[2];
    _genH = genShape[1];
    _genW = genShape[2];

    // Load labels
    final txt = await rootBundle.loadString('assets/models/new_labels_gender.txt');
    _genderLabels = txt.split('\n').where((e) => e.trim().isNotEmpty).toList();

    _isReady = true;
  }

  void close() {
    _age.close();
    _gender.close();
  }

  /// Convert CameraImage (YUV420 on Android / BGRA8888 on iOS) to RGB image package.
  im.Image _cameraToImageRGB({
    required List<Plane> planes,
    required int width,
    required int height,
    required bool isBGRA,
  }) {
    if (isBGRA) {
      // iOS: BGRA8888 → RGBA → RGB
      final bytes = planes.first.bytes;
      final img = im.Image.fromBytes(
        width: width,
        height: height,
        bytes: bytes.buffer,
        order: im.ChannelOrder.bgra, // input bytes are BGRA
      );
      return im.copyRotate(
        img,
        angle: 0,
      ); // ensure no-op; already RGBA internally
    }

    // Android: YUV420 → RGB (fast conversion)
    final p0 = planes[0], p1 = planes[1], p2 = planes[2];
    final int uvRowStride = p1.bytesPerRow;
    final int uvPixelStride = p1.bytesPerPixel ?? 1;

    final img = im.Image(width: width, height: height);
    final Uint8List y = p0.bytes, u = p1.bytes, v = p2.bytes;

    int yp = 0;
    for (int j = 0; j < height; j++) {
      int uvp = (j >> 1) * uvRowStride;
      int up = uvp;
      int vp = uvp;
      for (int i = 0; i < width; i++) {
        final int yVal = y[yp++] & 0xff;
        final int uVal = u[up] & 0xff;
        final int vVal = v[vp] & 0xff;

        final int c = yVal - 16;
        final int d = uVal - 128;
        final int e = vVal - 128;

        int r = (298 * c + 409 * e + 128) >> 8;
        int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
        int b = (298 * c + 516 * d + 128) >> 8;

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        img.setPixelRgb(i, j, r, g, b);

        if ((i & 1) == 1) {
          up += uvPixelStride;
          vp += uvPixelStride;
        }
      }
    }
    return img;
  }

  /// Resizes and packs into Float32List NHWC with either [0,1] or ResNetV2 [-1,1].
  Float32List _toFloatTensor(
    im.Image src,
    int H,
    int W, {
    required bool resnetV2, // true for gender
  }) {
    final img = im.copyResize(
      src,
      width: W,
      height: H,
      interpolation: im.Interpolation.average,
    );
    final out = Float32List(H * W * 3);
    int i = 0;
    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        final p = img.getPixel(x, y);
        double r = p.getChannel(im.Channel.red).toDouble();
        double g = p.getChannel(im.Channel.green).toDouble();
        double b = p.getChannel(im.Channel.blue).toDouble();
        if (resnetV2) {
          // ResNetV2: [-1,1] = (x/127.5) - 1
          r = r / 127.5 - 1.0;
          g = g / 127.5 - 1.0;
          b = b / 127.5 - 1.0;
        } else {
          // Generic float32: [0,1]
          r = r / 255.0;
          g = g / 255.0;
          b = b / 255.0;
        }
        out[i++] = r;
        out[i++] = g;
        out[i++] = b;
      }
    }
    return out;
  }

  /// Runs both models and returns a structured map:
  /// {
  ///   'age_years': 27.2,
  ///   'p_male': 0.269,
  ///   'p_female': 0.731,
  ///   'gender_label': 'Female'
  /// }

  // ---- safe helpers (no extensions) ----
  List<dynamic> reshapeList(List<dynamic> data, List<int> shape) {
    // makes a nested List with the given shape from a flat List
    final src = List<dynamic>.from(data);
    List<dynamic> build(int depth) {
      if (depth == shape.length - 1) {
        return List.generate(shape[depth], (_) => src.removeAt(0));
      }
      return List.generate(shape[depth], (_) => build(depth + 1));
    }

    return build(0);
  }

  List<dynamic> flattenList(dynamic v) {
    if (v is! List) return [v];
    return v.expand((e) => flattenList(e)).toList();
  }

  Future<Map<String, double>> inferenceCameraFrame(CameraImage frame) async {
    if (!_isReady) return {};

    // 1) Camera → RGB image
    final rgb = _cameraToImageRGB(
      planes: frame.planes,
      width: frame.width,
      height: frame.height,
      isBGRA: frame.format.group == ImageFormatGroup.bgra8888,
    );

    // (Optional) you can face-crop here if you integrate a face detector

    // 2) AGE (float [0,1])
    final ageIn = _toFloatTensor(rgb, _ageH, _ageW, resnetV2: false);
    final ageInput = reshapeList(
      ageIn.toList(), // Float32List -> List
      [1, _ageH, _ageW, 3],
    );

    final ageOutShape = _age.getOutputTensor(0).shape; // e.g. [1,1]
    final ageOutFlat = List.filled(ageOutShape.reduce((a, b) => a * b), 0.0);
    final ageOut = reshapeList(ageOutFlat, ageOutShape);
    _age.run(ageInput, ageOut);
    final ageYears = (flattenList(ageOut).first as double);

    // 3) GENDER (ResNetV2 [-1,1]) → one logit
    final genIn = _toFloatTensor(rgb, _genH, _genW, resnetV2: true);
    final genInput = reshapeList(genIn.toList(), [1, _genH, _genW, 3]);

    final genOutShape = _gender.getOutputTensor(0).shape; // [1,1]
    final genOutFlat = List.filled(genOutShape.reduce((a, b) => a * b), 0.0);
    final genOut = reshapeList(genOutFlat, genOutShape);
    _gender.run(genInput, genOut);

    final logit = (flattenList(genOut).first as double);
    final pFemale = 1.0 / (1.0 + exp(-logit));
    final pMale = 1.0 - pFemale;

    // 4) Return unified map (keep doubles for your existing UI)
    return <String, double>{
      'age_years': ageYears,
      'p_male': pMale,
      'p_female': pFemale,
      // you can also expose label index if needed
    };
  }
}

/// Small helpers
extension _Shape on List {
  List reshape(List<int> shape) {
    List _r(List data, int depth) {
      if (depth == shape.length - 1) {
        return List.generate(shape[depth], (_) => data.removeAt(0));
      }
      return List.generate(shape[depth], (_) => _r(data, depth + 1));
    }

    return _r(List.from(this), 0);
  }
}

extension _Flat on List {
  List flatten() => _flatten(this);
  static List _flatten(List l) =>
      l.expand((e) => e is List ? _flatten(e) : [e]).toList();
}
