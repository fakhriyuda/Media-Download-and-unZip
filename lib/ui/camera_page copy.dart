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
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yudvatar/image_classification_helper.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.camera});

  final List<CameraDescription> camera;

  @override
  State<StatefulWidget> createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller; // <- nullable
  bool _initializing = false;
  bool _isStreaming = false;
  bool _isProcessing = false;

  int _lastTsMs = 0;
  int _minGapMs = 120; // ~8 FPS; increase to 150–200ms if still unstable

  late ImageClassificationHelper imageClassificationHelper;
  Map<String, double>? classification;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    imageClassificationHelper = ImageClassificationHelper();
    imageClassificationHelper.initHelper();

    // kick off camera after first frame (avoids build-time race)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCamera();
    });
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final ctrl = CameraController(
        widget.camera.first,
        ResolutionPreset.low, // try low → medium only if stable
        imageFormatGroup:
            ImageFormatGroup.yuv420, // Android-friendly for analysis
        enableAudio: false,
      );
      await ctrl.initialize();

      // Optional: lock orientation to reduce reconfig churn
      await ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp);

      // Optional: no flash to avoid reconfigs
      await ctrl.setFlashMode(FlashMode.off);
      _controller = ctrl;
      if (mounted) setState(() {});
      await _startStreamIfReady();
    } catch (e) {
      debugPrint('initCamera error: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<void> _startStreamIfReady() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_isStreaming || c.value.isStreamingImages) return;
    // tiny delay helps some devices after onOpened()
    await Future.delayed(const Duration(milliseconds: 120));
    await c.startImageStream(imageAnalysis);
    _isStreaming = true;
  }

  Future<void> _stopStreamIfAny() async {
    final c = _controller;
    if (c == null) return;
    if (!c.value.isInitialized) return;
    if (!c.value.isStreamingImages) return;
    try {
      await c.stopImageStream();
    } catch (_) {}
    _isStreaming = false;
  }

  Future<void> imageAnalysis(CameraImage frame) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTsMs < _minGapMs) return;
    if (_isProcessing) return;
    _lastTsMs = now;

    _isProcessing = true;
    try {
      classification = await imageClassificationHelper.inferenceCameraFrame(
        frame,
      );
    } catch (e) {
      debugPrint('imageAnalysis error: $e');
    } finally {
      _isProcessing = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        await _stopStreamIfAny();
        await _controller?.dispose();
        _controller = null; // important
        break;
      case AppLifecycleState.resumed:
        await _initCamera();
        break;
      case AppLifecycleState.detached:
        break;

      case AppLifecycleState.hidden:
        await _stopStreamIfAny();
        await _controller?.dispose();
        _controller = null;
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStreamIfAny();
    _controller?.dispose();
    imageClassificationHelper.close();
    super.dispose();
  }

  Widget _cameraWidget(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * c.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return Transform.scale(
      scale: scale,
      child: Center(child: CameraPreview(c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final initialized = c?.value.isInitialized ?? false;

    return SafeArea(
      child: Stack(
        children: [
          if (initialized)
            _cameraWidget(context)
          else
            const Center(child: CircularProgressIndicator()),

          // bottom info
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.white.withOpacity(0.85),
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (classification != null) ...[
                    if (classification!['age_years'] != null)
                      Row(
                        children: [
                          const Text(
                            'Age',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            '${classification!['age_years']!.toStringAsFixed(1)} y',
                          ),
                        ],
                      ),
                    if (classification!['p_male'] != null &&
                        classification!['p_female'] != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text(
                            'Gender',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            (classification!['p_female']! >= 0.5)
                                ? 'Female'
                                : 'Male',
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Male'),
                          const Spacer(),
                          Text(classification!['p_male']!.toStringAsFixed(3)),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Female'),
                          const Spacer(),
                          Text(classification!['p_female']!.toStringAsFixed(3)),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
