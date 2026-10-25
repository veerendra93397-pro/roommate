import 'package:flutter_test/flutter_test.dart';
import 'package:roommate/main.dart';

void main() {
  testWidgets('App starts on the login screen', (tester) async {
    await tester.pumpWidget(const RoomMateApp());
    expect(find.text('RoomMate'), findsOneWidget);
  });
}