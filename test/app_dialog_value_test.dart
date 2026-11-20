import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/theme/vellum_theme.dart';
import 'package:vellum/widgets/ui/app_controls.dart';
import 'package:vellum/widgets/ui/app_dialog.dart';

/// A dialog whose action depends on a field.
///
/// The action list is built once, when the dialog opens. Reading the field's
/// text there captured whatever it held *before* anyone could type — which is
/// how "新建文件夹" popped an empty name and "设置备份密码" claimed no password
/// had been entered. These tests pin the fix: the value is read at the tap.
void main() {
  Widget host({
    required Future<String?> Function(BuildContext) open,
    required ValueChanged<String?> onResult,
  }) => MaterialApp(
    theme: VellumTheme.forBrightness(Brightness.light),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: AppTextButton(
            label: 'open',
            onPressed: () async => onResult(await open(context)),
          ),
        ),
      ),
    ),
  );

  testWidgets('the confirm action reads the field at the moment of the tap', (
    tester,
  ) async {
    final controller = TextEditingController();
    String? result;

    await tester.pumpWidget(
      host(
        onResult: (value) => result = value,
        open: (context) => showAppDialog<String>(
          context: context,
          title: '新建文件夹',
          contentController: controller,
          content: CupertinoTextField(controller: controller),
          actions: [
            AppDialogAction<String>(
              label: '创建',
              valueBuilder: () => controller.text.trim(),
              enabledBuilder: () => controller.text.trim().isNotEmpty,
              isDefault: true,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The field starts empty, so the action must not be offered yet.
    final createButton = tester.widget<AppTextButton>(
      find.widgetWithText(AppTextButton, '创建'),
    );
    expect(
      createButton.onPressed,
      isNull,
      reason: 'an empty name must not be submittable',
    );

    await tester.enterText(find.byType(CupertinoTextField), '文件夹 A');
    await tester.pump();

    final enabled = tester.widget<AppTextButton>(
      find.widgetWithText(AppTextButton, '创建'),
    );
    expect(enabled.onPressed, isNotNull, reason: 'typing must enable the action');

    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(result, '文件夹 A');
    controller.dispose();
  });

  testWidgets('a cancel action still pops null', (tester) async {
    final controller = TextEditingController();
    String? result = 'unset';

    await tester.pumpWidget(
      host(
        onResult: (value) => result = value,
        open: (context) => showAppDialog<String>(
          context: context,
          title: '新建文件夹',
          contentController: controller,
          content: CupertinoTextField(controller: controller),
          actions: [
            AppDialogAction<String>(
              label: '创建',
              valueBuilder: () => controller.text.trim(),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '不会用到的名字');
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    controller.dispose();
  });

  testWidgets('a constant value still pops without a builder', (tester) async {
    String? result;

    await tester.pumpWidget(
      host(
        onResult: (value) => result = value,
        open: (context) => showAppDialog<String>(
          context: context,
          title: 'Choose',
          actions: const [
            AppDialogAction<String>(label: 'Two', value: 'two', isDefault: true),
          ],
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();

    expect(result, 'two');
  });
}
