/// Tekst uit een PDF halen met de plaats op de pagina, en die terugzetten in regels en kolommen.
///
/// Labo-verslagen (Helena, ziekenhuizen) zijn tabellen: analyse, resultaat, eenheid, referentie. In de PDF staat
/// elk vakje als losse tekst op een eigen plaats, dus de volgorde in het bestand zegt weinig. Hier wordt elke
/// tekst op zijn plek gezet en worden regels gevormd uit wat op dezelfde hoogte staat; een grote sprong naar
/// rechts begint een nieuwe kolom. Puur Dart (dart_pdf_reader leest de structuur), dus ook op het web.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_pdf_reader/dart_pdf_reader.dart';

/// Regels van alle pagina's, van boven naar onder; elke regel is een lijst kolommen van links naar rechts.
Future<List<List<String>>> pdfTableLines(Uint8List bytes) async {
  final doc = await PDFParser(ByteStream(bytes)).parse();
  final pages = await (await doc.catalog).getPages();
  final lines = <List<String>>[];
  for (var i = 0; i < pages.pageCount; i++) {
    final page = pages.getPageAtIndex(i);
    final fonts = <String, _Font>{};
    final resources = await page.resources;
    final fontDict = await doc.resolve<PDFDictionary>(resources?[const PDFName('Font')]);
    for (final e in fontDict?.entries.entries ?? const <MapEntry<PDFName, PDFObject>>[]) {
      final f = await doc.resolve<PDFDictionary>(e.value);
      if (f != null) fonts[e.key.value] = await _Font.load(doc, f, page.objectResolver);
    }
    final content = BytesBuilder(copy: false);
    for (final s in await page.contentStreams ?? const <PDFStreamObject>[]) {
      content
        ..add(await s.read(page.objectResolver))
        ..addByte(0x0A);
    }
    lines.addAll(_layout(_runs(content.takeBytes(), fonts)));
  }
  return lines;
}

/// Een stuk tekst op de pagina: begin (x, y), einde op de regel en lettergrootte.
class _Run {
  _Run(this.x, this.y, this.end, this.size, this.text);
  final double x, y, end, size;
  final String text;
}

// ── Lettertypes: van tekens in het bestand naar echte letters, en hun breedte ──

class _Font {
  _Font({required this.twoByte, required this.unicode, required this.widths, required this.defaultWidth});

  /// Type0 (Identity-H): elk teken is 2 bytes. Anders 1 byte.
  final bool twoByte;

  /// Uit de ToUnicode-tabel; ontbreekt die, dan WinAnsi.
  final Map<int, String> unicode;
  final Map<int, double> widths;
  final double defaultWidth;

  static Future<_Font> load(PDFDocument doc, PDFDictionary f, ObjectResolver resolver) async {
    final subtype = (await doc.resolve<PDFName>(f[const PDFName('Subtype')]))?.value;
    final twoByte = subtype == 'Type0';
    final unicode = <int, String>{};
    final toUnicode = await doc.resolve<PDFStreamObject>(f[const PDFName('ToUnicode')]);
    if (toUnicode != null) {
      try {
        _parseCMap(latin1.decode(await toUnicode.read(resolver)), unicode);
      } on Object {
        // Zonder tabel valt het terug op WinAnsi
      }
    }
    final widths = <int, double>{};
    var defaultWidth = 500.0;
    if (twoByte) {
      final descendants = await doc.resolve<PDFArray>(f[const PDFName('DescendantFonts')]);
      final cid = descendants == null || descendants.isEmpty ? null : await doc.resolve<PDFDictionary>(descendants.first);
      defaultWidth = (await doc.resolve<PDFNumber>(cid?[const PDFName('DW')]))?.toDouble() ?? 1000;
      final w = await doc.resolve<PDFArray>(cid?[const PDFName('W')]);
      if (w != null) {
        // [c [w1 w2 ...]] of [c1 c2 w]
        var i = 0;
        while (i < w.length) {
          final first = (await doc.resolve<PDFNumber>(w[i]))?.toInt();
          if (first == null || i + 1 >= w.length) break;
          final next = await doc.resolve<PDFObject>(w[i + 1]);
          if (next is PDFArray) {
            for (var j = 0; j < next.length; j++) {
              widths[first + j] = (await doc.resolve<PDFNumber>(next[j]))?.toDouble() ?? defaultWidth;
            }
            i += 2;
          } else if (next is PDFNumber && i + 2 < w.length) {
            final width = (await doc.resolve<PDFNumber>(w[i + 2]))?.toDouble() ?? defaultWidth;
            for (var c = first; c <= next.toInt(); c++) {
              widths[c] = width;
            }
            i += 3;
          } else {
            break;
          }
        }
      }
    } else {
      final base = (await doc.resolve<PDFName>(f[const PDFName('BaseFont')]))?.value ?? '';
      if (base.startsWith('Courier')) defaultWidth = 600;
      final firstChar = (await doc.resolve<PDFNumber>(f[const PDFName('FirstChar')]))?.toInt();
      final w = await doc.resolve<PDFArray>(f[const PDFName('Widths')]);
      if (firstChar != null && w != null) {
        for (var j = 0; j < w.length; j++) {
          widths[firstChar + j] = (await doc.resolve<PDFNumber>(w[j]))?.toDouble() ?? defaultWidth;
        }
      }
    }
    return _Font(twoByte: twoByte, unicode: unicode, widths: widths, defaultWidth: defaultWidth);
  }

  List<int> codes(List<int> bytes) => twoByte ? [for (var i = 0; i + 1 < bytes.length; i += 2) bytes[i] << 8 | bytes[i + 1]] : bytes;

  String char(int code) => unicode[code] ?? (twoByte ? '' : _winAnsi(code));

  double width(int code) => widths[code] ?? defaultWidth;
}

/// bfchar: `<01> <0041>`; bfrange: `<01> <05> <0041>` of `<01> <02> [<0041> <0042>]`.
void _parseCMap(String s, Map<int, String> out) {
  // Doeltekst in UTF-16: per 4 hexcijfers één code-eenheid (korter: één teken)
  String hex(String h) {
    if (h.isEmpty) return '';
    if (h.length <= 2) return String.fromCharCode(int.parse(h, radix: 16));
    final b = StringBuffer();
    for (var i = 0; i + 4 <= h.length; i += 4) {
      b.writeCharCode(int.parse(h.substring(i, i + 4), radix: 16));
    }
    return b.toString();
  }

  for (final block in RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true).allMatches(s)) {
    for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>').allMatches(block.group(1)!)) {
      out[int.parse(m.group(1)!, radix: 16)] = hex(m.group(2)!);
    }
  }
  for (final block in RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true).allMatches(s)) {
    for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<[0-9A-Fa-f]*>|\[[^\]]*\])').allMatches(block.group(1)!)) {
      final lo = int.parse(m.group(1)!, radix: 16), hi = int.parse(m.group(2)!, radix: 16);
      final dst = m.group(3)!;
      if (dst.startsWith('[')) {
        final items = RegExp(r'<([0-9A-Fa-f]*)>').allMatches(dst).toList();
        for (var c = lo; c <= hi && c - lo < items.length; c++) {
          out[c] = hex(items[c - lo].group(1)!);
        }
      } else {
        final base = int.parse(dst.substring(1, dst.length - 1), radix: 16);
        for (var c = lo; c <= hi && c - lo < 0x10000; c++) {
          out[c] = String.fromCharCode(base + c - lo);
        }
      }
    }
  }
}

/// WinAnsi: Latijn-1 met in 0x80–0x9F de tekens van Windows-1252.
String _winAnsi(int c) {
  const extra = {
    0x80: '€', 0x82: '‚', 0x84: '„', 0x85: '…', 0x8A: 'Š', 0x8C: 'Œ', 0x8E: 'Ž', //
    0x91: '‘', 0x92: '’', 0x93: '“', 0x94: '”', 0x95: '•', 0x96: '–', 0x97: '—', 0x9A: 'š', 0x9C: 'œ', 0x9E: 'ž', 0x9F: 'Ÿ',
  };
  return extra[c] ?? (c >= 0x20 ? String.fromCharCode(c) : '');
}

// ── Inhoud van de pagina uitvoeren: alleen wat de plaats van tekst bepaalt ──

/// Matrix [a b c d e f] zoals in PDF.
typedef _M = List<double>;

_M _mul(_M m, _M n) => [
  m[0] * n[0] + m[1] * n[2],
  m[0] * n[1] + m[1] * n[3],
  m[2] * n[0] + m[3] * n[2],
  m[2] * n[1] + m[3] * n[3],
  m[4] * n[0] + m[5] * n[2] + n[4],
  m[4] * n[1] + m[5] * n[3] + n[5],
];

const _identity = <double>[1, 0, 0, 1, 0, 0];

List<_Run> _runs(Uint8List content, Map<String, _Font> fonts) {
  final runs = <_Run>[];
  final stack = <_M>[];
  _M ctm = _identity;
  _M tm = _identity, tlm = _identity;
  _Font? font;
  var size = 0.0, charSpace = 0.0, wordSpace = 0.0, scale = 1.0, leading = 0.0, rise = 0.0;
  final operands = <Object>[];

  double num(int i) => (operands[i] as double?) ?? 0;

  void show(List<int> bytes, {List<Object>? array}) {
    final f = font;
    if (f == null) return;
    final start = _mul([size * scale, 0, 0, size, 0, rise], _mul(tm, ctm));
    final text = StringBuffer();
    var advance = 0.0;
    void glyphs(List<int> b) {
      for (final code in f.codes(b)) {
        final ch = f.char(code);
        text.write(ch);
        advance += (f.width(code) / 1000 * size + charSpace + (ch == ' ' && !f.twoByte ? wordSpace : 0)) * scale;
      }
    }

    if (array == null) {
      glyphs(bytes);
    } else {
      for (final item in array) {
        if (item is List<int>) {
          glyphs(item);
        } else if (item is double) {
          final shift = -item / 1000 * size * scale;
          // Een grote verschuiving binnen één TJ is meestal een spatie
          if (shift > size * 0.2 && text.isNotEmpty) text.write(' ');
          advance += shift;
        }
      }
    }
    final x = start[4], y = start[5];
    // Breedte op de pagina: de verschuiving door dezelfde matrices
    final endPt = _mul([1, 0, 0, 1, advance, 0], _mul(tm, ctm));
    tm = _mul([1, 0, 0, 1, advance, 0], tm);
    final s = text.toString();
    // Lettergrootte op de pagina: de hoogte van een letter na alle matrices
    final height = math.sqrt(start[2] * start[2] + start[3] * start[3]);
    if (s.trim().isNotEmpty) runs.add(_Run(x, y, endPt[4], height > 0 ? height : size, s));
  }

  for (final token in _tokens(content)) {
    if (token is! _Op) {
      operands.add(token);
      continue;
    }
    try {
      switch (token.name) {
        case 'q':
          stack.add(ctm);
        case 'Q':
          if (stack.isNotEmpty) ctm = stack.removeLast();
        case 'cm':
          ctm = _mul([num(0), num(1), num(2), num(3), num(4), num(5)], ctm);
        case 'BT':
          tm = tlm = _identity;
        case 'Tf':
          font = fonts[operands[0] as String];
          size = num(1);
        case 'Tc':
          charSpace = num(0);
        case 'Tw':
          wordSpace = num(0);
        case 'Tz':
          scale = num(0) / 100;
        case 'TL':
          leading = num(0);
        case 'Ts':
          rise = num(0);
        case 'Tm':
          tm = tlm = [num(0), num(1), num(2), num(3), num(4), num(5)];
        case 'Td':
          tm = tlm = _mul([1, 0, 0, 1, num(0), num(1)], tlm);
        case 'TD':
          leading = -num(1);
          tm = tlm = _mul([1, 0, 0, 1, num(0), num(1)], tlm);
        case 'T*':
          tm = tlm = _mul([1, 0, 0, 1, 0, -leading], tlm);
        case 'Tj':
          show(operands[0] as List<int>);
        case 'TJ':
          show(const [], array: operands[0] as List<Object>);
        case "'":
          tm = tlm = _mul([1, 0, 0, 1, 0, -leading], tlm);
          show(operands[0] as List<int>);
        case '"':
          wordSpace = num(0);
          charSpace = num(1);
          tm = tlm = _mul([1, 0, 0, 1, 0, -leading], tlm);
          show(operands[2] as List<int>);
      }
    } on Object {
      // Een onverwacht argument: deze opdracht overslaan
    }
    operands.clear();
  }
  return runs;
}

/// Regels: wat op (bijna) dezelfde hoogte staat, van boven naar onder. Kolommen: een sprong naar rechts van meer
/// dan ongeveer een letterbreedte.
List<List<String>> _layout(List<_Run> runs) {
  final sorted = [...runs]..sort((a, b) => b.y != a.y ? b.y.compareTo(a.y) : a.x.compareTo(b.x));
  final lines = <List<_Run>>[];
  for (final r in sorted) {
    final last = lines.isEmpty ? null : lines.last;
    if (last != null && (last.first.y - r.y).abs() <= r.size * 0.4) {
      last.add(r);
    } else {
      lines.add([r]);
    }
  }
  return [
    for (final line in lines)
      () {
        line.sort((a, b) => a.x.compareTo(b.x));
        final cells = <StringBuffer>[];
        double? end;
        for (final r in line) {
          final gap = end == null ? double.infinity : r.x - end;
          if (gap > r.size * 0.8) {
            cells.add(StringBuffer(r.text.trim()));
          } else {
            if (gap > r.size * 0.15 && !cells.last.toString().endsWith(' ')) cells.last.write(' ');
            cells.last.write(gap > r.size * 0.15 ? r.text.trimLeft() : r.text);
          }
          end = r.end;
        }
        return [
          for (final c in cells)
            if (c.toString().trim().isNotEmpty) c.toString().trim().replaceAll(RegExp(r'\s+'), ' '),
        ];
      }(),
  ].where((l) => l.isNotEmpty).toList();
}

// ── Inhoud in stukjes knippen: getallen, namen, teksten, rijen en opdrachten ──

class _Op {
  const _Op(this.name);
  final String name;
}

Iterable<Object> _tokens(Uint8List b) sync* {
  var i = 0;
  bool isWhite(int c) => c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0x00;
  bool isDelim(int c) =>
      c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25;
  final arrays = <List<Object>>[];

  Object? emit(Object v) {
    if (arrays.isNotEmpty) {
      arrays.last.add(v);
      return null;
    }
    return v;
  }

  while (i < b.length) {
    final c = b[i];
    if (isWhite(c)) {
      i++;
    } else if (c == 0x25) {
      // % commentaar
      while (i < b.length && b[i] != 0x0A && b[i] != 0x0D) {
        i++;
      }
    } else if (c == 0x28) {
      // (letterlijke tekst) met \-escapes en geneste haakjes
      final out = <int>[];
      var depth = 1;
      i++;
      while (i < b.length && depth > 0) {
        var ch = b[i++];
        if (ch == 0x5C && i < b.length) {
          ch = b[i++];
          switch (ch) {
            case 0x6E:
              out.add(0x0A);
            case 0x72:
              out.add(0x0D);
            case 0x74:
              out.add(0x09);
            case 0x62:
              out.add(0x08);
            case 0x66:
              out.add(0x0C);
            case 0x0D:
              if (i < b.length && b[i] == 0x0A) i++;
            case 0x0A:
              break;
            default:
              if (ch >= 0x30 && ch <= 0x37) {
                var v = ch - 0x30;
                for (var k = 0; k < 2 && i < b.length && b[i] >= 0x30 && b[i] <= 0x37; k++) {
                  v = v * 8 + b[i++] - 0x30;
                }
                out.add(v & 0xFF);
              } else {
                out.add(ch);
              }
          }
          continue;
        }
        if (ch == 0x28) depth++;
        if (ch == 0x29) depth--;
        if (depth > 0) out.add(ch);
      }
      final v = emit(out);
      if (v != null) yield v;
    } else if (c == 0x3C && i + 1 < b.length && b[i + 1] == 0x3C) {
      // << woordenboek >> (bv. bij BDC): overslaan
      var depth = 0;
      while (i + 1 < b.length) {
        if (b[i] == 0x3C && b[i + 1] == 0x3C) {
          depth++;
          i += 2;
        } else if (b[i] == 0x3E && b[i + 1] == 0x3E) {
          depth--;
          i += 2;
          if (depth == 0) break;
        } else {
          i++;
        }
      }
    } else if (c == 0x3C) {
      // <hex>
      i++;
      final h = StringBuffer();
      while (i < b.length && b[i] != 0x3E) {
        if (!isWhite(b[i])) h.writeCharCode(b[i]);
        i++;
      }
      i++;
      var s = h.toString();
      if (s.length.isOdd) s += '0';
      final v = emit([for (var k = 0; k + 1 < s.length; k += 2) int.tryParse(s.substring(k, k + 2), radix: 16) ?? 0]);
      if (v != null) yield v;
    } else if (c == 0x5B) {
      arrays.add([]);
      i++;
    } else if (c == 0x5D) {
      i++;
      if (arrays.isNotEmpty) {
        final a = arrays.removeLast();
        final v = emit(a);
        if (v != null) yield v;
      }
    } else if (c == 0x2F) {
      // /Naam
      i++;
      final s = StringBuffer();
      while (i < b.length && !isWhite(b[i]) && !isDelim(b[i])) {
        s.writeCharCode(b[i++]);
      }
      final v = emit(s.toString());
      if (v != null) yield v;
    } else {
      final s = StringBuffer();
      while (i < b.length && !isWhite(b[i]) && !isDelim(b[i])) {
        s.writeCharCode(b[i++]);
      }
      if (s.isEmpty) {
        i++;
        continue;
      }
      final word = s.toString();
      final n = double.tryParse(word);
      if (n != null) {
        final v = emit(n);
        if (v != null) yield v;
      } else if (word == 'BI') {
        // Ingebedde afbeelding: overslaan tot EI
        while (i + 2 < b.length && !(b[i] == 0x45 && b[i + 1] == 0x49 && isWhite(b[i + 2]))) {
          i++;
        }
        i += 2;
      } else if (arrays.isEmpty) {
        yield _Op(word);
      }
    }
  }
}
