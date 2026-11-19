import 'dart:async';
import 'package:flutter/material.dart';
import 'strings.dart';

/// نوار پیشرفت با پیش‌نمایش صفحه هنگام درگ.
class Scrubber extends StatefulWidget {
  const Scrubber({
    super.key, required this.count, required this.current, required this.rtl,
    required this.onSeek, required this.thumbBuilder,
  });
  final int count, current;
  final bool rtl;
  final ValueChanged<int> onSeek;
  final Widget Function(int index) thumbBuilder;

  @override
  State<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<Scrubber> {
  int? _drag;
  int? _thumbIdx;
  Timer? _t;

  void _onChanged(double v) {
    final i = v.round();
    setState(() => _drag = i);
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _thumbIdx = i);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count < 2) return const SizedBox(height: 48);
    final value = (_drag ?? widget.current).clamp(0, widget.count - 1).toDouble();
    final frac = value / (widget.count - 1);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_drag != null)
        SizedBox(
          height: 170,
          child: Align(
            alignment: Alignment(((widget.rtl ? 1 - frac : frac) * 2 - 1) * 0.8, 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 96, height: 136,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: _thumbIdx == null ? null : widget.thumbBuilder(_thumbIdx!),
              ),
              const SizedBox(height: 4),
              Text('${S.fa(_drag! + 1)} / ${S.fa(widget.count)}', style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      Directionality(
        textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Slider(
          min: 0,
          max: (widget.count - 1).toDouble(),
          value: value,
          onChanged: _onChanged,
          onChangeEnd: (v) {
            widget.onSeek(v.round());
            setState(() {
              _drag = null;
              _thumbIdx = null;
            });
          },
        ),
      ),
    ]);
  }
}
