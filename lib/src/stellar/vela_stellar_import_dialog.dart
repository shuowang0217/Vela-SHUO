import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../network/vela_flclash_subscription_adapter.dart';
import '../subscription/vela_subscription_controller.dart';
import '../theme/vela_palettes.dart';

/// Compact sail-inspired import dialog, modeled after the approved reference:
/// optional name, one URL, and an import action. The dialog closes ONLY after
/// FlClash has applied the real profile; error/timeout keeps the URL editable.
class VelaStellarImportDialog extends StatefulWidget {
  const VelaStellarImportDialog({
    super.key,
    required this.controller,
    this.stageOnly = false,
  });

  final VelaSubscriptionController controller;
  final bool stageOnly;

  @override
  State<VelaStellarImportDialog> createState() =>
      _VelaStellarImportDialogState();
}

class _VelaStellarImportDialogState extends State<VelaStellarImportDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();
  bool _importing = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || clip?.text == null) return;
      _url.text = clip!.text!.trim();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '无法读取剪贴板，请手动粘贴 URL');
    }
  }

  Future<void> _submit() async {
    if (_importing || !_form.currentState!.validate()) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      // Connected imports are downloaded into the encrypted airport list;
      // applying a profile is a separate explicit user choice.
      final native = widget.controller;
      final ok = native is VelaFlClashSubscriptionController
          ? await native.importFromUrlNamed(_url.text.trim(),
              name: _name.text, stageOnly: widget.stageOnly)
          : await native.importFromUrl(_url.text.trim());
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _error = widget.controller.error ??
              'FlClash 订阅导入失败，请检查 URL 或网络';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'FlClash 导入失败，请检查链接与网络');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = VelaThemeRuntime.active;
    final existing = widget.controller.nodes.isNotEmpty;
    return Dialog(
      key: const ValueKey('stellar_import_dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: t.line, width: 1),
        borderRadius: BorderRadius.circular(23),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 410),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.sailing_rounded, color: t.accent, size: 26),
                const SizedBox(width: 10),
                Expanded(child: Text('从 URL 导入',
                  style: TextStyle(color: t.text, fontSize: 21,
                    fontWeight: FontWeight.w700))),
                IconButton(
                  tooltip: '关闭',
                  onPressed: _importing ? null : () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: t.muted),
                ),
              ]),
              const SizedBox(height: 5),
              Text(widget.stageOnly
                  ? '连接中安全获取订阅，不改变正在使用的机场'
                  : '新机场自动保存，不覆盖已有配置',
                style: TextStyle(color: t.muted, fontSize: 12)),
              const SizedBox(height: 20),
              TextFormField(
                key: const ValueKey('stellar_import_name'),
                controller: _name,
                enabled: !_importing,
                maxLength: 64,
                decoration: InputDecoration(
                  labelText: '名称（可选）',
                  hintText: '为这条航线取个名字',
                  prefixIcon: const Icon(Icons.edit_outlined, size: 19),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13)),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 13),
              TextFormField(
                key: const ValueKey('stellar_import_url'),
                controller: _url,
                enabled: !_importing,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.url],
                autocorrect: false,
                minLines: 1,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: '订阅 URL',
                  hintText: 'https://...',
                  prefixIcon: const Icon(Icons.link_rounded, size: 19),
                  suffixIcon: IconButton(
                    tooltip: '粘贴 URL',
                    onPressed: _importing ? null : _paste,
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13)),
                ),
                validator: (value) {
                  final input = value?.trim() ?? '';
                  if (input.isEmpty) return '请输入订阅链接';
                  final uri = Uri.tryParse(input);
                  if (uri == null || uri.scheme != 'https' ||
                      uri.host.isEmpty || uri.userInfo.isNotEmpty) {
                    return '请输入有效的 HTTPS 订阅链接';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              if (existing) ...[
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: t.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    widget.stageOnly
                        ? '新机场将保存到列表，点击机场卡片可切换并自动重连。'
                        : '新机场加入列表，已有订阅保持保存。',
                    style: TextStyle(fontSize: 11, color: t.muted))),
                ]),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(
                  color: Color(0xFFD47575), fontSize: 12)),
              ],
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: _importing ? null : () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  key: const ValueKey('stellar_import_submit'),
                  onPressed: _importing ? null : _submit,
                  icon: _importing
                      ? const SizedBox(width: 17, height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sailing_rounded, size: 17),
                  label: Text(_importing ? '正在导入' : '导入'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
