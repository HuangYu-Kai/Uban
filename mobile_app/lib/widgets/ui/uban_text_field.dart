import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'uban_text.dart';

/// 設計稿 `.field` + `.input`：高 58、圓角 18、1.5px line 邊框、
/// focus 時邊框 brand + 4px 18% 光圈；label 15/700 text2。
class UbanTextField extends StatefulWidget {
  final String? label;
  final String? hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final bool readOnly;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextAlign textAlign;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? errorText;

  const UbanTextField({
    super.key,
    this.label,
    this.hintText,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.readOnly = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
  });

  @override
  State<UbanTextField> createState() => _UbanTextFieldState();
}

class _UbanTextFieldState extends State<UbanTextField> {
  FocusNode? _ownNode;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant UbanTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
    }
  }

  void _onFocus() {
    if (_focused != _node.hasFocus && mounted) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final radius = BorderRadius.circular(18);
    final hasError = widget.errorText != null;
    final borderColor = hasError ? c.danger : (_focused ? c.brand : c.line);

    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: 1.5),
        );

    final field = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: (hasError ? c.danger : c.brand).withValues(alpha: .18),
                  spreadRadius: 4,
                ),
              ]
            : const [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _node,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        obscureText: widget.obscureText,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        readOnly: widget.readOnly,
        maxLines: widget.obscureText ? 1 : widget.maxLines,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        textAlign: widget.textAlign,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
        cursorColor: c.brand,
        style: ubanText(18, FontWeight.w500, c.text, height: 1.5),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: ubanText(18, FontWeight.w500, c.text3, height: 1.5),
          counterText: '',
          filled: true,
          fillColor: c.surface,
          constraints: const BoxConstraints(minHeight: 58),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          border: border(borderColor),
          enabledBorder: border(borderColor),
          focusedBorder: border(borderColor),
          disabledBorder: border(c.line),
          errorBorder: border(c.danger),
          focusedErrorBorder: border(c.danger),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ubanText(15, FontWeight.w700, c.text2)),
          const SizedBox(height: 6),
        ],
        field,
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.errorText!,
                style: ubanText(14, FontWeight.w500, c.danger)),
          ),
      ],
    );
  }
}
