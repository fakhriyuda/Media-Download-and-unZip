// image_classification_helper.dart (edited)
import 'dart:developer';
import 'dart:isolate';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:yudvatar/isolate.dart';

class ImageClassificationHelper {
  static const modelPath = 'assets/models/new_age_model.tflite';

  late final Interpreter interpreter;
  late final IsolateInference isolateInference;
  late Tensor inputTensor;
  late Tensor outputTensor;

  // Load model
  Future<void> _loadModel() async {
    final options = InterpreterOptions();

    options.addDelegate(XNNPackDelegate());

    interpreter = await Interpreter.fromAsset(modelPath, options: options);

    inputTensor = interpreter.getInputTensors().first;
    print('input tensor shape: ${inputTensor.shape}  type=${inputTensor.type}');
    outputTensor = interpreter.getOutputTensors().first;
    print(
      'output tensor shape: ${outputTensor.shape}  type=${outputTensor.type}',
    );
    print('Interpreter loaded successfully');
  }

  Future<void> initHelper() async {
    // await model load BEFORE starting isolate
    await _loadModel();
    isolateInference = IsolateInference();
    await isolateInference.start();
  }
  

  Future<Map<String, double>> _inference(InferenceModel inferenceModel) async {
    ReceivePort responsePort = ReceivePort();
    inferenceModel.responsePort = responsePort.sendPort;
    isolateInference.sendPort.send(inferenceModel);
    final results = await responsePort.first;
    // Expect map like {'result': {'age': 21.4}, 'debug': {...}} or {'result': {'age': ...}}
    if (results is Map && results.containsKey('result')) {
      final r = results['result'];
      if (r is Map<String, dynamic>) {
        // convert numeric values to double
        return r.map((k, v) => MapEntry(k, (v as num).toDouble()));
      }
    }
    // fallback if isolate directly returned a map
    if (results is Map<String, double>) return results;
    return {'age': 0.0};
  }

  // inference camera frame
  Future<Map<String, double>> inferenceCameraFrame(
    CameraImage cameraImage,
  ) async {
    final isolateModel = InferenceModel(
      cameraImage,
      null,
      interpreter.address,
      inputTensor.shape,
      outputTensor.shape,
    );
    return _inference(isolateModel);
  }

  // inference still image
  Future<Map<String, double>> inferenceImage(Image image) async {
    final isolateModel = InferenceModel(
      null,
      image,
      interpreter.address,
      inputTensor.shape,
      outputTensor.shape,
    );
    return _inference(isolateModel);
  }

  Future<void> close() async {
    isolateInference.close();
  }
}
