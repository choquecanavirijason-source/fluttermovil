import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Probador/screens/widgets/design_thumbnail_image.dart';

void main() {
  testWidgets('embedded thumbnail keeps its provider during camera rebuilds', (
    tester,
  ) async {
    const source = 'data:image/png;base64,aGVsbG8=';
    Future<void> render(String path, Color color) => tester.pumpWidget(
      MaterialApp(
        home: DesignThumbnailImage(path: path, size: 34, color: color),
      ),
    );

    await render(source, Colors.white);
    final provider = tester.widget<Image>(find.byType(Image)).image;
    await render(source, Colors.green);
    expect(tester.widget<Image>(find.byType(Image)).image, same(provider));

    await render('data:image/png;base64,d29ybGQ=', Colors.green);
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      isNot(same(provider)),
    );
    await render('data:image/png;base64,%%%', Colors.green);
    expect(find.byIcon(Icons.image_not_supported), findsOneWidget);
  });
}
