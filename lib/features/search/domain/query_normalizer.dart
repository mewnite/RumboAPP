/// Intención identificada a partir de la estructura del texto de búsqueda.
enum QueryIntentKind {
  stopCode,
  intersection,
  addressWithNumber,
  routeCode,
  general,
}

/// Consulta parseada con sus componentes estructurados.
class ParsedQuery {
  const ParsedQuery({
    required this.raw,
    required this.normalized,
    required this.intent,
    this.street1,
    this.street2,
    this.doorNumber,
    this.stopCode,
    this.routeCode,
  });

  final String raw;
  final String normalized;
  final QueryIntentKind intent;
  final String? street1;
  final String? street2;
  final int? doorNumber;
  final String? stopCode;
  final String? routeCode;

  @override
  String toString() =>
      'ParsedQuery(intent: $intent, normalized: "$normalized", street1: $street1, street2: $street2, doorNumber: $doorNumber, stopCode: $stopCode)';
}

/// Normalizador lingüístico y analizador semántico de consultas urbanas en Montevideo.
class MontevideoQueryParser {
  const MontevideoQueryParser();

  static const Map<String, String> _abbreviations = {
    'av.': 'avenida',
    'avda.': 'avenida',
    'av': 'avenida',
    'bvar.': 'bulevar',
    'bvar': 'bulevar',
    'bvr.': 'bulevar',
    'bvr': 'bulevar',
    'bv.': 'bulevar',
    'bv': 'bulevar',
    'bulevar': 'bulevar',
    'gral.': 'general',
    'gral': 'general',
    'cno.': 'camino',
    'cno': 'camino',
    'tte.': 'teniente',
    'tte': 'teniente',
    'dr.': 'doctor',
    'dr': 'doctor',
    'sta.': 'santa',
    'sta': 'santa',
    'sto.': 'santo',
    'sto': 'santo',
    'pta.': 'punta',
    'pta': 'punta',
    'pto.': 'puerto',
    'pto': 'puerto',
    'pje.': 'pasaje',
    'pje': 'pasaje',
  };

  static final RegExp _diacritics = RegExp(r'[áàäâéèëêíìïîóòöôúùüûñ]');
  static final RegExp _multiSpace = RegExp(r'\s+');
  static final RegExp _punctuation = RegExp(r'[^a-z0-9\s]');
  static final RegExp _stopCodePattern = RegExp(r'^\d{4,5}$');
  static final RegExp _routeCodePattern = RegExp(
    r'^(?:[a-z]\d{0,3}|\d{1,3}[a-z]?)$',
    caseSensitive: false,
  );
  static final RegExp _intersectionPattern = RegExp(
    r'^(.*?)\s+(?:y|esq\.?|esquina|con|\/)\s+(.*?)$',
    caseSensitive: false,
  );
  static final RegExp _doorNumberPattern = RegExp(
    r'^(.*?)(?:\s+(?:n[ro°\.]*\s*)?|,\s*)(\d{1,5})(?:\s+(?:bis|b|a))?$',
    caseSensitive: false,
  );

  /// Normaliza una cadena de texto eliminando acentos, estandarizando espacios y mayúsculas.
  String normalizeText(String input) {
    if (input.isEmpty) return '';
    final lower = input.toLowerCase().trim();
    final withoutAccents = lower.replaceAllMapped(_diacritics, (match) {
      switch (match.group(0)) {
        case 'á':
        case 'à':
        case 'ä':
        case 'â':
          return 'a';
        case 'é':
        case 'è':
        case 'ë':
        case 'ê':
          return 'e';
        case 'í':
        case 'ì':
        case 'ï':
        case 'î':
          return 'i';
        case 'ó':
        case 'ò':
        case 'ö':
        case 'ô':
          return 'o';
        case 'ú':
        case 'ù':
        case 'ü':
        case 'û':
          return 'u';
        case 'ñ':
          return 'n';
        default:
          return match.group(0)!;
      }
    });

    final withoutPunctuation = withoutAccents.replaceAll(_punctuation, ' ');
    final tokens = withoutPunctuation
        .split(_multiSpace)
        .map((token) => _abbreviations[token] ?? token);

    return tokens.join(' ').trim();
  }

  /// Analiza la consulta y extrae su intención probable y componentes geográficos.
  ParsedQuery parse(String rawQuery) {
    final trimmed = rawQuery.trim();
    final normalized = normalizeText(trimmed);

    if (normalized.isEmpty) {
      return ParsedQuery(
        raw: rawQuery,
        normalized: '',
        intent: QueryIntentKind.general,
      );
    }

    // 1. Código numérico de parada STM (ej. "3004", "4218")
    if (_stopCodePattern.hasMatch(trimmed)) {
      return ParsedQuery(
        raw: rawQuery,
        normalized: normalized,
        intent: QueryIntentKind.stopCode,
        stopCode: trimmed,
      );
    }

    // 2. Intersección de calles ("18 de Julio y Ejido", "Rivera esq Soca", "8 de Octubre / Propios")
    final matchIntersection = _intersectionPattern.firstMatch(trimmed);
    if (matchIntersection != null) {
      final s1 = matchIntersection.group(1)?.trim() ?? '';
      final s2 = matchIntersection.group(2)?.trim() ?? '';
      if (s1.isNotEmpty && s2.isNotEmpty && !RegExp(r'^\d+$').hasMatch(s2)) {
        return ParsedQuery(
          raw: rawQuery,
          normalized: normalized,
          intent: QueryIntentKind.intersection,
          street1: normalizeText(s1),
          street2: normalizeText(s2),
        );
      }
    }

    // 3. Dirección con número de puerta ("Av. Italia 2450", "18 de Julio 1234")
    final matchDoor = _doorNumberPattern.firstMatch(trimmed);
    if (matchDoor != null) {
      final street = matchDoor.group(1)?.trim() ?? '';
      final numberStr = matchDoor.group(2);
      final doorNumber = numberStr != null ? int.tryParse(numberStr) : null;
      if (street.isNotEmpty && doorNumber != null && doorNumber > 0) {
        return ParsedQuery(
          raw: rawQuery,
          normalized: normalized,
          intent: QueryIntentKind.addressWithNumber,
          street1: normalizeText(street),
          doorNumber: doorNumber,
        );
      }
    }

    // 4. Código de línea de transporte (ej. "522", "104", "D10", "G")
    if (_routeCodePattern.hasMatch(trimmed)) {
      return ParsedQuery(
        raw: rawQuery,
        normalized: normalized,
        intent: QueryIntentKind.routeCode,
        routeCode: trimmed.toUpperCase(),
      );
    }

    // 5. Búsqueda libre general
    return ParsedQuery(
      raw: rawQuery,
      normalized: normalized,
      intent: QueryIntentKind.general,
    );
  }
}
