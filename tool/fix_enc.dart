// Repara archivos .dart con texto UTF-8 doblemente codificado (mojibake
// "poblaciÃ³n" en vez de "población"). Detección:Lead byte 0xC2-0xFF
// interpretado como CP1252 produce code units que, re-empaquetadas como
// bytes CP1252, forman UTF-8 válido y decodifican a code points plausibles
// (latín, puntuación general, box drawing, flechas, dingbats).
//
// Uso:
//   dart run tool/fix_enc.dart analyze <ruta ...>   (dry-run, muestra diffs)
//   dart run tool/fix_enc.dart fix     <ruta ...>
import 'dart:convert';
import 'dart:io';

const _mojibakeLeads = {0x00C2, 0x00C3, 0x00E2, 0x00E4, 0x00E5, 0x00E6};

final _cp1252Reverse = <int, int>{
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
  0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
  0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
  0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
  0x017E: 0x9E, 0x0178: 0x9F,
};

List<int>? _cp1252Encode(List<int> units) {
  final out = <int>[];
  for (final u in units) {
    if (u < 0x80) {
      out.add(u);
    } else if (u <= 0xFF) {
      if (u >= 0x80 && u <= 0x9F) return null;
      out.add(u);
    } else if (_cp1252Reverse.containsKey(u)) {
      out.add(_cp1252Reverse[u]!);
    } else {
      return null;
    }
  }
  return out;
}

bool _isValidUtf8(List<int> bytes) {
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    int extra;
    int min;
    if (b < 0x80) {
      extra = 0;
      min = 0x80;
    } else if (b >= 0xC2 && b <= 0xDF) {
      extra = 1;
      min = 0x80;
    } else if (b >= 0xE0 && b <= 0xEF) {
      extra = 2;
      min = 0x800;
    } else if (b >= 0xF0 && b <= 0xF4) {
      extra = 3;
      min = 0x10000;
    } else {
      return false;
    }
    if (i + extra >= bytes.length) return false;
    var cp = extra == 0 ? b : b & (0x7F >> extra);
    for (var j = 1; j <= extra; j++) {
      final c = bytes[i + j];
      if (c < 0x80 || c > 0xBF) return false;
      cp = (cp << 6) | (c & 0x3F);
    }
    if (cp < min || cp > 0x10FFFF) return false;
    if (cp >= 0xD800 && cp <= 0xDFFF) return false;
    if (extra == 2 && b == 0xE0 && bytes[i + 1] < 0xA0) return false;
    i += extra + 1;
  }
  return true;
}

bool _plausibleDecoded(String decoded) {
  for (final u in decoded.runes) {
    final ok = (u >= 0x20 && u <= 0x24F) || // latin + extended
        (u >= 0x1E00 && u <= 0x1EFF) || // extended additional
        (u >= 0x2000 && u <= 0x206F) || // punctuation general
        (u >= 0x20A0 && u <= 0x20CF) || // currency
        (u >= 0x2190 && u <= 0x2BFF) || // flechas, box drawing, dingbats…
        (u >= 0x3000 && u <= 0x30FF); // kana (por si algún diagrama)
    if (!ok) return false;
  }
  return true;
}

({String repaired, List<(int, String, String)> changes}) repair(String s) {
  final out = StringBuffer();
  final changes = <(int, String, String)>[];
  final src = s.codeUnits;
  for (var i = 0; i < src.length;) {
    final lead = src[i];
    var advanced = false;
    if (_mojibakeLeads.contains(lead) && lead <= 0xFFFF) {
      for (var k = 4; k >= 2; k--) {
        if (i + k > src.length) continue;
        final cand = src.sublist(i, i + k);
        final bytes = _cp1252Encode(cand);
        if (bytes == null) continue;
        if (!_isValidUtf8(bytes)) continue;
        final decoded = utf8.decode(bytes);
        if (decoded.length >= k) continue;
        if (!_plausibleDecoded(decoded)) continue;
        changes.add((i, String.fromCharCodes(cand), decoded));
        out.write(decoded);
        i += k;
        advanced = true;
        break;
      }
    }
    if (!advanced) {
      out.writeCharCode(src[i]);
      i++;
    }
  }
  return (repaired: out.toString(), changes: changes);
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('uso: fix_enc.dart analyze|fix <ruta ...>');
    exit(64);
  }
  final mode = args[0];
  for (final path in args.sublist(1)) {
    final f = File(path);
    final s = utf8.decode(f.readAsBytesSync());
    final r = repair(s);
    print('${path.split(r'\').last}: ${r.changes.length} sustituciones');
    for (final (pos, from, to) in r.changes.take(mode == 'analyze' ? 20 : 0)) {
      print('  @$pos  "$from" -> "$to"');
    }
    if (mode == 'fix' && r.changes.isNotEmpty) {
      f.writeAsBytesSync(utf8.encode(r.repaired));
      print('  REPARADO');
    }
  }
}
