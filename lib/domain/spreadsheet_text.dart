/// Preserves text cells that a spreadsheet could interpret as formulas.
String spreadsheetText(String value) {
  final trimmed = value.trimLeft();
  final needsPrefix =
      value.startsWith('\t') ||
      value.startsWith('\r') ||
      trimmed.startsWith('=') ||
      trimmed.startsWith('+') ||
      trimmed.startsWith('-') ||
      trimmed.startsWith('@');
  return needsPrefix ? "'$value" : value;
}
