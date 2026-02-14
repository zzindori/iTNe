import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../config/app_strings.dart';

class CameraPreviewSection extends StatefulWidget {
  final CameraController? controller;
  final bool isInitialized;
  final String? errorMessage;
  final double minZoom;
  final double maxZoom;
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;

  const CameraPreviewSection({
    super.key,
    required this.controller,
    required this.isInitialized,
    required this.minZoom,
    required this.maxZoom,
    required this.currentZoom,
    required this.onZoomChanged,
    this.errorMessage,
  });

  @override
  State<CameraPreviewSection> createState() => _CameraPreviewSectionState();
}

class _CameraPreviewSectionState extends State<CameraPreviewSection> {
  double _scaleStart = 1.0;
  Offset? _focusPoint;
  bool _focusVisible = false;
  double _focusScale = 1.0;
  Timer? _focusTimer;

  @override
  void dispose() {
    _focusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.errorMessage != null) {
      return _buildStatusScreen(AppStrings.instance.cameraError, Icons.error_outline);
    }

    final controller = widget.controller;
    if (!widget.isInitialized || controller == null) {
      return _buildStatusScreen(AppStrings.instance.cameraInitializing, Icons.hourglass_empty);
    }

    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: Builder(
                builder: (context) {
                  return GestureDetector(
                    onScaleStart: (details) {
                      if (details.pointerCount >= 2) {
                        _scaleStart = widget.currentZoom;
                      }
                    },
                    onScaleUpdate: (details) {
                      if (details.pointerCount < 2) {
                        return;
                      }
                      if (widget.maxZoom <= widget.minZoom) {
                        return;
                      }
                      final next = (_scaleStart * details.scale).clamp(widget.minZoom, widget.maxZoom);
                      widget.onZoomChanged(next);
                    },
                    onTapDown: (details) async {
                      if (!controller.value.isInitialized) {
                        return;
                      }
                      final box = context.findRenderObject() as RenderBox;
                      final local = details.localPosition;
                      setState(() {
                        _focusPoint = local;
                        _focusVisible = true;
                        _focusScale = 1.25;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _focusScale = 1.0;
                        });
                      });
                      _focusTimer?.cancel();
                      _focusTimer = Timer(const Duration(milliseconds: 800), () {
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          _focusVisible = false;
                        });
                      });
                      final size = box.size;
                      final dx = (local.dx / size.width).clamp(0.0, 1.0);
                      final dy = (local.dy / size.height).clamp(0.0, 1.0);

                      try {
                        await controller.setFocusMode(FocusMode.auto);
                        await controller.setFocusPoint(Offset(dx, dy));
                        await controller.setExposurePoint(Offset(dx, dy));
                      } catch (_) {
                        // ignore unsupported focus/exposure
                      }
                    },
                    child: Stack(
                      children: [
                        CameraPreview(controller),
                        if (_focusPoint != null)
                          Positioned(
                            left: _focusPoint!.dx - 22,
                            top: _focusPoint!.dy - 22,
                            child: AnimatedOpacity(
                              opacity: _focusVisible ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 120),
                              child: AnimatedScale(
                                scale: _focusScale,
                                duration: const Duration(milliseconds: 120),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.6),
                                  ),
                                  child: Center(
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(width: 16, height: 2, color: Colors.white),
                                        Container(width: 2, height: 16, color: Colors.white),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusScreen(String message, IconData icon) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: Colors.white54),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}