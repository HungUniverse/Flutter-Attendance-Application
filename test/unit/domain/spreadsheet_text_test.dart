import 'package:fap_attendance/domain/spreadsheet_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('spreadsheetText', () {
    test('leaves safe plain strings untouched', () {
      expect(spreadsheetText('SE180001'), 'SE180001');
      expect(spreadsheetText('Nguyen Van An'), 'Nguyen Van An');
      expect(spreadsheetText('12345'), '12345');
      expect(spreadsheetText(''), '');
      expect(spreadsheetText('  normal text'), '  normal text');
    });

    test('prefixes formula-trigger characters with single quote', () {
      expect(spreadsheetText('=SUM(A1:A10)'), "'=SUM(A1:A10)");
      expect(spreadsheetText('+123456'), "'+123456");
      expect(spreadsheetText('-123456'), "'-123456");
      expect(spreadsheetText('@cmd'), "'@cmd");
      expect(spreadsheetText('\t=1+1'), "'\t=1+1");
      expect(spreadsheetText('\r=1+1'), "'\r=1+1");
      expect(spreadsheetText('  =HYPERLINK()'), "'  =HYPERLINK()");
      expect(spreadsheetText('  +cmd'), "'  +cmd");
      expect(spreadsheetText('  -cmd'), "'  -cmd");
      expect(spreadsheetText('  @user'), "'  @user");
    });
  });
}
