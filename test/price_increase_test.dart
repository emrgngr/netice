import 'package:flutter_test/flutter_test.dart';
import 'package:netice/core/price_increase.dart';

void main() {
  test('tam yıl sayısı başlangıç gününe göre sayılır', () {
    expect(priceIncreaseYears(DateTime(2026, 11, 1)), 0);
    expect(priceIncreaseYears(DateTime(2027, 11, 18)), 0);
    expect(priceIncreaseYears(DateTime(2027, 11, 19)), 1);
    expect(priceIncreaseYears(DateTime(2029, 1, 5)), 2);
  });

  test('fiyat yazıları her yıl %30 artar, biçim korunur', () {
    expect(increasePriceText('799 TL / yıl', 0), '799 TL / yıl');
    expect(increasePriceText('799 TL / yıl', 1), '1039 TL / yıl');
    expect(increasePriceText('99 TL / ay', 1), '129 TL / ay');
    expect(increasePriceText('799 TL / yıl', 2), '1349 TL / yıl');
    expect(increasePriceText('\$79.99 / year', 1), '\$103.99 / year');
    expect(increasePriceText('9,99 € / Monat', 1), '12,99 € / Monat');
    expect(increasePriceText('₼ 16,99 / ay', 1), '₼ 21,99 / ay');
    expect(increasePriceText('7 990 ₽ / год', 1), '10 390 ₽ / год');
    expect(increasePriceText('¥9,800 / 年', 1), '¥12,700 / 年');
    expect(increasePriceText('¥1,200 / 月', 1), '¥1,600 / 月');
  });

  test('aylık karşılık notu yeni yıllık fiyattan hesaplanır', () {
    expect(monthlyNoteText('Ayda yaklaşık 67 TL · en avantajlı', '799 TL / yıl', 1),
        'Ayda yaklaşık 87 TL · en avantajlı');
    expect(monthlyNoteText('About \$6.67 a month · best value', '\$79.99 / year', 1),
        'About \$8.67 a month · best value');
  });
}
