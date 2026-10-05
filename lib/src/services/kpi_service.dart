import 'dart:math';

import 'package:tilly/src/controllers/app_controller.dart';
import 'package:tilly/src/domain/models.dart';

class KpiRow {
  KpiRow(
      this.article,
      this.sold,
      this.mealUsed,
      this.associationUsed,
      this.outgoing,
      this.ca,
      this.stockRest,
      this.stockInitial,
      this.rotation,
      this.suggestion);

  final Article article;
  final int sold;
  final int mealUsed;
  final int associationUsed;
  final int outgoing;
  final double ca;
  final int stockRest;
  final int stockInitial;
  final double rotation;
  final int suggestion;
}

int compareKpiRows(KpiRow a, KpiRow b) {
  final aScore = a.article.stock == 0
      ? 3
      : a.article.stock <= a.article.threshold
          ? 2
          : 1;
  final bScore = b.article.stock == 0
      ? 3
      : b.article.stock <= b.article.threshold
          ? 2
          : 1;
  if (aScore != bScore) return bScore.compareTo(aScore);
  return b.rotation.compareTo(a.rotation);
}

List<KpiRow> kpiRows(AppController controller, {List<Sale>? sales}) {
  final sold = <String, ({int quantity, double ca})>{};
  final stockSold = <String, int>{};
  final mealUsed = <String, int>{};
  final associationUsed = <String, int>{};
  final days = <String>{};
  final selectedSales = sales ?? controller.activeSales;
  final linkedMeals = controller.mealsEnabled
      ? {
          for (final meal in controller.meals)
            if (meal.saleId.isNotEmpty) meal.saleId: meal
        }
      : const <String, MealOrder>{};
  for (final sale in selectedSales) {
    days.add(dateLabel(sale.createdAt));
    for (final item in sale.items) {
      final current = sold[item.articleId] ?? (quantity: 0, ca: 0.0);
      sold[item.articleId] = (
        quantity: current.quantity + item.quantity,
        ca: current.ca + item.quantity * item.price
      );
      final linkedMeal = linkedMeals[sale.id];
      if (linkedMeal == null || linkedMeal.mealArticleId != item.articleId) {
        stockSold[item.articleId] =
            (stockSold[item.articleId] ?? 0) + item.quantity;
      }
    }
  }
  if (controller.mealsEnabled) {
    for (final meal in controller.meals.where((order) => order.consumesStock)) {
      days.add(dateLabel(meal.preparedAt ?? meal.createdAt));
      for (final entry in meal.stockItems.entries) {
        mealUsed[entry.key] = (mealUsed[entry.key] ?? 0) + entry.value;
      }
    }
  }
  for (final movement in controller.stockMovements.where((entry) =>
      entry.movementType == 'association' && entry.quantityDelta < 0)) {
    days.add(dateLabel(movement.createdAt));
    associationUsed[movement.articleId] =
        (associationUsed[movement.articleId] ?? 0) - movement.quantityDelta;
  }
  final dayCount = max(1, days.length);
  final movementsByArticle = <String, List<StockMovement>>{};
  for (final movement in controller.stockMovements) {
    movementsByArticle.putIfAbsent(movement.articleId, () => []).add(movement);
  }
  for (final movements in movementsByArticle.values) {
    movements.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }
  return controller.trackedArticles
      .map((a) {
    final s = sold[a.id] ?? (quantity: 0, ca: 0.0);
    final mealQuantity = mealUsed[a.id] ?? 0;
    final associationQuantity = associationUsed[a.id] ?? 0;
    final outgoing =
        (stockSold[a.id] ?? 0) + mealQuantity + associationQuantity;
    final articleMovements = movementsByArticle[a.id];
    final initial = articleMovements == null || articleMovements.isEmpty
        ? a.stock + outgoing
        : articleMovements.first.stockBefore;
    final rotation = initial == 0 ? 0.0 : outgoing / initial;
    final suggestion = outgoing > 0 ? ((outgoing / dayCount) * 1.3).ceil() : 0;
    return KpiRow(a, s.quantity, mealQuantity, associationQuantity, outgoing,
        s.ca, a.stock, initial, rotation, suggestion);
  }).toList();
}
