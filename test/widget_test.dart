import 'package:flutter_test/flutter_test.dart';
import 'package:fitnees_app/main.dart';

void main() {
  testWidgets('FitnessApp renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FitnessApp());
    expect(find.text('Fitness App — Login'), findsOneWidget);
  });
}