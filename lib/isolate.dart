/*
 * Copyright 2023 The TensorFlow Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *             http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image/image.dart' as im;

import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:yudvatar/image_utils.dart';

class IsolateInference {
  static const String _debugName = "TFLITE_INFERENCE";
  final ReceivePort _receivePort = ReceivePort();
  late Isolate _isolate;
  late SendPort _sendPort;

  SendPort get sendPort => _sendPort;

  Future<void> start() async {
    _isolate = await Isolate.spawn<List<dynamic>>(entryPoint, [
      _receivePort.sendPort,
      'assets/models/new_age_model.tflite',
    ], debugName: _debugName);
    _sendPort = await _receivePort.first;
  }

  Future<void> close() async {
    _isolate.kill();
    _receivePort.close();
  }

  // Replace your existing entryPoint with this:
  // Change signature to accept List<dynamic> initialMessage
  static void entryPoint(List<dynamic> initialMessage) async {
    final SendPort mainSendPort = initialMessage[0] as SendPort;
    final String modelPath = initialMessage[1] as String;

    final ReceivePort port = ReceivePort();
    mainSendPort.send(port.sendPort);

    // Load interpreter once INSIDE this isolate
    Interpreter interpreter;
    try {
      final options = InterpreterOptions();
      // add delegates if desired (wrap in try/catch)
      try {
        if (Platform.isAndroid) options.addDelegate(XNNPackDelegate());
        if (Platform.isIOS) options.addDelegate(GpuDelegate());
      } catch (_) {}
      interpreter = await Interpreter.fromAsset(modelPath, options: options);
    } catch (e, st) {
      debugPrint('Isolate: failed to load model: $e\n$st');
      // respond with error for any incoming message
      await for (final _ in port) {
        // ignore or forward errors as needed
      }
      return;
    }

    // now listen for InferenceModel instances on port and use this interpreter
    await for (final InferenceModel isolateModel in port) {
      // ... use `interpreter` below when running inference ...
    }
  }

  //end
}

class InferenceModel {
  CameraImage? cameraImage;
  image_lib.Image? image;
  int interpreterAddress;
  List<int> inputShape;
  List<int> outputShape;
  late SendPort responsePort;

  InferenceModel(
    this.cameraImage,
    this.image,
    this.interpreterAddress,
    this.inputShape,
    this.outputShape,
  );
  bool isCameraFrame() => cameraImage != null;
}
