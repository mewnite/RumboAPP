/// Intención identificada a partir de la estructura del texto de búsqueda.
enum QueryIntentKind {
  stopCode,
  intersection,
  addressWithNumber,
  routeCode,
  poi,
  neighborhood,
  street,
  geographicArea,
  unknown,
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
    'av': 'avenida',
    'avda': 'avenida',
    'bvar': 'bulevar',
    'bvr': 'bulevar',
    'bv': 'bulevar',
    'bulevar': 'bulevar',
    'gral': 'general',
    'cno': 'camino',
    'tte': 'teniente',
    'dr': 'doctor',
    'sta': 'santa',
    'sto': 'santo',
    'pta': 'punta',
    'pto': 'puerto',
    'pje': 'pasaje',
    'pza': 'plaza',
    'rbla': 'rambla',
  };
  static const Map<String, String> _placeAliases = {
    'nuevocentro': 'nuevo centro',
    'nuevo centro shopping': 'nuevo centro shopping',
    'sodre': 'auditorio nacional adela reta',
    'auditorio adela reta': 'auditorio nacional adela reta',
    'catedral metropolitana': 'catedral metropolitana de montevideo',
    'catedral metropolitana montevideo': 'catedral metropolitana de montevideo',
    'catedral de montevideo': 'catedral metropolitana de montevideo',
  };
  static const Set<String> _knownPoiNames = {
    'sodre',
    'auditorio nacional adela reta',
    'nuevo centro',
    'nuevo centro shopping',
    'nuevo centro montevideo',
    'catedral metropolitana',
    'catedral metropolitana de montevideo',
    'teatro solis',
    'estadio centenario',
    'shopping punta carretas',
    'punta carretas shopping',
    'palacio salvo',
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
    r'^\s*(.+)\s+(?:y|x|esq\.?(?:\s+(?:de|con))?|esquina(?:\s+(?:de|con))?|con|\/|&)\s+(.+?)\s*$',
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
        .map((token) => _abbreviations[token] ?? _placeAliases[token] ?? token);
    final expanded = tokens.join(' ').trim();
    return _placeAliases[expanded] ?? expanded;
  }

  /// Matches whole street-name phrases while tolerating common street prefixes.
  bool streetMatches(String candidate, String requested) {
    final candidateTokens = normalizeText(candidate).split(' ');
    final requestedTokens = normalizeText(requested).split(' ');
    if (candidateTokens.isEmpty || requestedTokens.isEmpty) return false;

    const removablePrefixes = {
      'avenida',
      'calle',
      'camino',
      'bulevar',
      'rambla',
      'pasaje',
      'plaza',
      'general',
      'doctor',
      'ingeniero',
      'brigadier',
    };

    List<String> withoutKnownPrefixes(List<String> tokens) {
      var start = 0;
      while (start < tokens.length &&
          removablePrefixes.contains(tokens[start])) {
        start++;
      }
      return tokens.skip(start).toList(growable: false);
    }

    bool containsPhrase(List<String> haystack, List<String> needle) {
      if (needle.isEmpty || needle.length > haystack.length) return false;
      for (var start = 0; start + needle.length <= haystack.length; start++) {
        if (haystack.skip(start).take(needle.length).join(' ') ==
            needle.join(' ')) {
          return true;
        }
      }
      return false;
    }

    final candidateVariants = [
      candidateTokens,
      withoutKnownPrefixes(candidateTokens),
    ];
    final requestedVariants = [
      requestedTokens,
      withoutKnownPrefixes(requestedTokens),
    ];
    return candidateVariants.any(
      (candidateVariant) => requestedVariants.any(
        (requestedVariant) =>
            containsPhrase(candidateVariant, requestedVariant) ||
            containsPhrase(requestedVariant, candidateVariant),
      ),
    );
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
    final neighborhoodPattern = RegExp(
      r'\b(barrio|ciudad vieja|pocitos|parque rodó|parque rodo)\b',
      caseSensitive: false,
    );
    if (neighborhoodPattern.hasMatch(normalized)) {
      return ParsedQuery(
        raw: rawQuery,
        normalized: normalized,
        intent: QueryIntentKind.neighborhood,
      );
    }

    final geographicAreaPattern = RegExp(
      r'\b(rambla|playa|bahía|bahia)\b',
      caseSensitive: false,
    );
    if (geographicAreaPattern.hasMatch(normalized)) {
      return ParsedQuery(
        raw: rawQuery,
        normalized: normalized,
        intent: QueryIntentKind.geographicArea,
      );
    }

    final poiPattern = RegExp(
      r'\b(shopping|teatro|estadio|catedral|auditorio|terminal|mercado|'
      r'aeropuerto|hospital|palacio|plaza)\b',
      caseSensitive: false,
    );
    if (poiPattern.hasMatch(normalized) ||
        _knownPoiNames.contains(normalized)) {
      return ParsedQuery(
        raw: rawQuery,
        normalized: normalized,
        intent: QueryIntentKind.poi,
      );
    }

    final streetPattern = RegExp(
      r'\b(avenida|bulevar|camino|rambla|calle|pasaje|general)\b',
      caseSensitive: false,
    );
    if (streetPattern.hasMatch(normalized)) {
      return ParsedQuery(
        raw: rawQuery,
        normalized: normalized,
        intent: QueryIntentKind.street,
      );
    }

    return ParsedQuery(
      raw: rawQuery,
      normalized: normalized,
      intent: QueryIntentKind.general,
    );
  }
}
