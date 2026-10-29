import 'package:flutter_test/flutter_test.dart';
import 'package:rumbo/features/search/domain/query_normalizer.dart';

void main() {
  const parser = MontevideoQueryParser();

  group('MontevideoQueryParser - Normalización de texto', () {
    test('remueve tildes y diacríticos preservando legibilidad', () {
      expect(
        parser.normalizeText('Árbol Ébano Ígneo Óptimo Único'),
        'arbol ebano igneo optimo unico',
      );
      expect(
        parser.normalizeText('Constitución y Médanos'),
        'constitucion y medanos',
      );
      expect(
        parser.normalizeText('José Batlle y Ordóñez'),
        'jose batlle y ordonez',
      );
      expect(parser.normalizeText('Güemes'), 'guemes');
    });

    test('colapsa espacios múltiples y pasa a minúsculas', () {
      expect(
        parser.normalizeText('   Av.   Italia   2450  '),
        'avenida italia 2450',
      );
      expect(parser.normalizeText('18   de   JULIO'), '18 de julio');
    });

    test('elimina signos de puntuación y normaliza consultas', () {
      expect(parser.normalizeText('¿DÓNDE—está? Plaza!'), 'donde esta plaza');
      expect(parser.normalizeText('Bvar., Artigas /'), 'bulevar artigas');
    });

    test('expande abreviaturas comunes de Montevideo', () {
      expect(parser.normalizeText('Av. 18 de Julio'), 'avenida 18 de julio');
      expect(parser.normalizeText('Bvar. Artigas'), 'bulevar artigas');
      expect(parser.normalizeText('Gral. Flores'), 'general flores');
      expect(parser.normalizeText('Cno. Carrasco'), 'camino carrasco');
      expect(
        parser.normalizeText('Dr. Manuel Quintela'),
        'doctor manuel quintela',
      );
      expect(parser.normalizeText('Sta. Lucía'), 'santa lucia');
    });
  });

  group('MontevideoQueryParser - Clasificación de intención', () {
    test('identifica códigos numéricos de parada del STM', () {
      final q1 = parser.parse('3004');
      expect(q1.intent, QueryIntentKind.stopCode);
      expect(q1.stopCode, '3004');

      final q2 = parser.parse('4218');
      expect(q2.intent, QueryIntentKind.stopCode);
      expect(q2.stopCode, '4218');
    });

    test('identifica intersecciones con separadores típicos ("y", "esq.", "con", "/")', () {
      final q1 = parser.parse('18 de Julio y Ejido');
      expect(q1.intent, QueryIntentKind.intersection);
      expect(q1.street1, '18 de julio');
      expect(q1.street2, 'ejido');

      final q2 = parser.parse('Rivera esq Soca');
      expect(q2.intent, QueryIntentKind.intersection);
      expect(q2.street1, 'rivera');
      expect(q2.street2, 'soca');

      final q3 = parser.parse('Av. Brasil / Libertad');
      expect(q3.intent, QueryIntentKind.intersection);
      expect(q3.street1, 'avenida brasil');
      expect(q3.street2, 'libertad');

      final q4 = parser.parse('Colonia esq. Convención');
      expect(q4.intent, QueryIntentKind.intersection);
      expect(q4.street1, 'colonia');
      expect(q4.street2, 'convencion');
    });

    test('identifica direcciones con número de puerta', () {
      final q1 = parser.parse('Av. Italia 2450');
      expect(q1.intent, QueryIntentKind.addressWithNumber);
      expect(q1.street1, 'avenida italia');
      expect(q1.doorNumber, 2450);

      final q2 = parser.parse('Bvar. Artigas 1825 bis');
      expect(q2.intent, QueryIntentKind.addressWithNumber);
      expect(q2.street1, 'bulevar artigas');
      expect(q2.doorNumber, 1825);

      final q3 = parser.parse('San José, 1114');
      expect(q3.intent, QueryIntentKind.addressWithNumber);
      expect(q3.street1, 'san jose');
      expect(q3.doorNumber, 1114);
    });

    test('identifica códigos de línea de ómnibus', () {
      expect(parser.parse('522').intent, QueryIntentKind.routeCode);
      expect(parser.parse('104').intent, QueryIntentKind.routeCode);
      expect(parser.parse('D10').intent, QueryIntentKind.routeCode);
      expect(parser.parse('G').intent, QueryIntentKind.routeCode);
    });

    test('clasifica búsquedas generales y POIs', () {
      final q1 = parser.parse('Hospital de Clínicas');
      expect(q1.intent, QueryIntentKind.general);
      expect(q1.normalized, 'hospital de clinicas');

      final q2 = parser.parse('Facultad de Ingeniería');
      expect(q2.intent, QueryIntentKind.general);

      final q3 = parser.parse('Pocitos');
      expect(q3.intent, QueryIntentKind.general);
    });
  });
}
