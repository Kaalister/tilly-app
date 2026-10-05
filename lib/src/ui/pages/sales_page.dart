import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../domain/models.dart';
import '../../platform/backup_and_links.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class CaissePage extends StatelessWidget {
  const CaissePage({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        if (wide) {
          return Row(
            children: [
              SizedBox(width: 240, child: PlayerPanel(controller: controller)),
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(child: ProductsPanel(controller: controller)),
              const VerticalDivider(width: 1, color: AppColors.border),
              SizedBox(width: 320, child: CartPanel(controller: controller)),
            ],
          );
        }
        final playerPanelHeight =
            (constraints.maxHeight * .27).clamp(210.0, 270.0);
        return Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  SizedBox(
                      height: playerPanelHeight,
                      child:
                          PlayerPanel(controller: controller, compact: true)),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: ProductsPanel(
                      controller: controller,
                      bottomPadding: 112,
                    ),
                  ),
                ],
              ),
            ),
            _FloatingCartSheet(
              controller: controller,
              cartCount: controller.cartCount,
            ),
          ],
        );
      },
    );
  }
}

class _FloatingCartSheet extends StatefulWidget {
  const _FloatingCartSheet({
    required this.controller,
    required this.cartCount,
  });

  static const closedSize = .1;

  final AppController controller;
  final int cartCount;

  @override
  State<_FloatingCartSheet> createState() => _FloatingCartSheetState();
}

class _FloatingCartSheetState extends State<_FloatingCartSheet>
    with SingleTickerProviderStateMixin {
  static const _closedTolerance = .02;

  late final DraggableScrollableController _sheetController;
  late final AnimationController _shakeController;
  late final Animation<double> _shakeOffset;
  var _isClosed = true;
  var _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController()
      ..addListener(_handleSheetChanged);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _shakeOffset = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0), weight: 56),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -8.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 8,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -8.0, end: 4.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 4.0, end: -5.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 8,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -5.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 8,
      ),
      TweenSequenceItem(tween: ConstantTween(0), weight: 10),
    ]).animate(_shakeController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.of(context).disableAnimations;
    _syncShake();
  }

  @override
  void didUpdateWidget(covariant _FloatingCartSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cartCount != widget.cartCount) {
      _syncShake();
    }
  }

  @override
  void dispose() {
    _sheetController
      ..removeListener(_handleSheetChanged)
      ..dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _handleSheetChanged() {
    final isClosed = _sheetController.size <=
        _FloatingCartSheet.closedSize + _closedTolerance;
    if (isClosed == _isClosed) return;

    setState(() => _isClosed = isClosed);
    _syncShake();
  }

  void _syncShake() {
    final shouldShake =
        !_disableAnimations && _isClosed && widget.cartCount > 0;
    if (shouldShake) {
      if (!_shakeController.isAnimating) {
        _shakeController.repeat();
      }
    } else {
      _shakeController.stop();
      _shakeController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeOffset,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _shakeOffset.value),
        child: child,
      ),
      child: DraggableScrollableSheet(
        controller: _sheetController,
        minChildSize: _FloatingCartSheet.closedSize,
        initialChildSize: _FloatingCartSheet.closedSize,
        maxChildSize: 1,
        snap: true,
        snapSizes: const [_FloatingCartSheet.closedSize, 1],
        builder: (context, scrollController) => CartPanel(
          controller: widget.controller,
          floating: true,
          collapsed: _isClosed,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class PlayerPanel extends StatefulWidget {
  const PlayerPanel(
      {required this.controller, this.compact = false, super.key});

  final AppController controller;
  final bool compact;

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> {
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim().toLowerCase();
    final filteredPlayers = widget.controller.players
        .where((player) => player.name.toLowerCase().contains(query))
        .toList();
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.compact)
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'PARTICIPANT',
                      style: TextStyle(
                        color: context.primaryAccent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    onPressed: () =>
                        showPlayerDialog(context, widget.controller),
                    icon: const Icon(Icons.person_add),
                    tooltip: 'Nouveau participant',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            )
          else
            SectionTitle(
              'Participant',
              trailing: IconButton.filledTonal(
                onPressed: () => showPlayerDialog(context, widget.controller),
                icon: const Icon(Icons.person_add),
                tooltip: 'Nouveau participant',
              ),
            ),
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      onPressed: () => setState(searchController.clear),
                      icon: const Icon(Icons.close),
                    ),
              hintText: 'Rechercher un participant',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.controller.players.isEmpty
                ? Center(
                    child: FilledButton.icon(
                      onPressed: () =>
                          showPlayerDialog(context, widget.controller),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Ajouter un participant'),
                    ),
                  )
                : filteredPlayers.isEmpty
                    ? const Center(
                        child: Text('Aucun participant trouvé',
                            style: TextStyle(color: AppColors.muted)))
                    : ListView.separated(
                        scrollDirection:
                            widget.compact ? Axis.horizontal : Axis.vertical,
                        itemCount: filteredPlayers.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 8, height: 8),
                        itemBuilder: (context, index) {
                          final player = filteredPlayers[index];
                          final selected =
                              widget.controller.selectedPlayerId == player.id;
                          final count = widget.controller.activeSales
                              .where((s) => s.playerId == player.id)
                              .length;
                          return ConstrainedBox(
                            constraints: BoxConstraints(
                                minWidth: widget.compact ? 190 : 0,
                                maxWidth:
                                    widget.compact ? 230 : double.infinity),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () =>
                                  widget.controller.selectPlayer(player),
                              child: TacticalCard(
                                borderColor: selected
                                    ? context.primaryAccent
                                    : AppColors.border,
                                padding: widget.compact
                                    ? const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 3)
                                    : const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(
                                        player.isMember
                                            ? Icons.verified_user
                                            : Icons.person,
                                        color: player.isMember
                                            ? AppColors.accent2
                                            : AppColors.muted),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(player.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700))),
                                    if (count > 0)
                                      Chip(
                                          label: Text('$count'),
                                          visualDensity: VisualDensity.compact),
                                    IconButton(
                                      tooltip: 'Modifier le participant',
                                      onPressed: () => showPlayerDialog(
                                          context, widget.controller,
                                          player: player),
                                      icon: const Icon(Icons.edit, size: 18),
                                      visualDensity: VisualDensity.compact,
                                      constraints: widget.compact
                                          ? const BoxConstraints.tightFor(
                                              width: 36, height: 36)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class ProductsPanel extends StatelessWidget {
  const ProductsPanel({
    required this.controller,
    this.bottomPadding = 0,
    super.key,
  });

  final AppController controller;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 54,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            scrollDirection: Axis.horizontal,
            itemCount: controller.categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = controller.categories[index];
              final selected = controller.categoryFilter == cat;
              return ChoiceChip(
                selected: selected,
                showCheckmark: false,
                label: Text(cat),
                labelStyle: TextStyle(
                  color: selected ? context.onPrimaryAccent : AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
                onSelected: (_) => controller.setCategory(cat),
                selectedColor: context.primaryAccent,
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 10 + bottomPadding),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisExtent: 138,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: controller.visibleArticles.length,
            itemBuilder: (context, index) {
              final article = controller.visibleArticles[index];
              final price = article.priceFor(controller.memberTariff);
              final noStock = article.tracksStock && article.stock == 0;
              final lowStock = article.tracksStock &&
                  article.stock > 0 &&
                  article.stock <= article.threshold;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: controller.selectedPlayerId == null
                    ? () => snack(context, 'Sélectionnez un participant')
                    : () => controller.addToCart(article),
                child: TacticalCard(
                  borderColor: noStock
                      ? AppColors.danger
                      : lowStock
                          ? AppColors.warn
                          : article.isLocation
                              ? AppColors.sumup
                              : AppColors.border,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          const Spacer(),
                          if (article.tracksStock)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: noStock
                                        ? AppColors.danger
                                        : lowStock
                                            ? AppColors.warn
                                            : AppColors.border),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('${article.stock}',
                                  style: TextStyle(
                                      color: noStock
                                          ? AppColors.danger
                                          : lowStock
                                              ? AppColors.warn
                                              : AppColors.muted,
                                      fontSize: 12)),
                            ),
                        ],
                      ),
                      Text(article.icon, style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Center(
                          child: Text(article.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(price == 0 ? 'Libre' : money(price),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: context.primaryAccent,
                                    fontWeight: FontWeight.w900)),
                          ),
                          if (controller.memberTariff &&
                              article.memberPrice > 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.accent2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('ADH',
                                  style: TextStyle(
                                      color: AppColors.accent2,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CartPanel extends StatelessWidget {
  const CartPanel({
    required this.controller,
    this.floating = false,
    this.collapsed = false,
    this.scrollController,
    super.key,
  });

  static const _maxVisibleCartItems = 7;
  static const _cartItemExtent = 66.0;

  final AppController controller;
  final bool floating;
  final bool collapsed;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final shortages = controller.cartStockShortages;
    final hasPendingPayment = controller.hasPendingPayment;
    final canCheckout = controller.canCheckout;
    if (floating) {
      return _buildFloatingCart(
        context,
        shortages: shortages,
        hasPendingPayment: hasPendingPayment,
        canCheckout: canCheckout,
      );
    }

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          if (shortages.isNotEmpty) _buildShortages(shortages),
          _buildTariffSwitch(),
          Flexible(fit: FlexFit.loose, child: _buildCartList(context)),
          _buildDonationField(),
          const SizedBox(height: 8),
          _buildPaymentButtons(context, canCheckout),
          _buildClearButton(hasPendingPayment),
        ],
      ),
    );
  }

  Widget _buildFloatingCart(
    BuildContext context, {
    required List<StockShortage> shortages,
    required bool hasPendingPayment,
    required bool canCheckout,
  }) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom + 10;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: CustomScrollView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, 8, 10, bottomPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildHeader(context),
                    if (!collapsed) ...[
                      const SizedBox(height: 8),
                      if (shortages.isNotEmpty) ...[
                        _buildShortages(shortages),
                        const SizedBox(height: 8),
                      ],
                      _buildTariffSwitch(),
                      _buildCartList(context),
                      _buildDonationField(),
                      const SizedBox(height: 8),
                      _buildPaymentButtons(context, canCheckout),
                      _buildClearButton(hasPendingPayment),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.shopping_cart, color: context.primaryAccent),
        const SizedBox(width: 8),
        Text('PANIER (${controller.cartCount})',
            style: const TextStyle(
                fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const Spacer(),
        Text(money(controller.cartTotal),
            style: TextStyle(
                color: context.primaryAccent,
                fontWeight: FontWeight.w900,
                fontSize: 18)),
      ],
    );
  }

  Widget _buildShortages(List<StockShortage> shortages) {
    return TacticalCard(
      borderColor: AppColors.warn,
      padding: const EdgeInsets.all(8),
      child: Text(
          'Stock insuffisant : ${shortages.map((item) => item.message).join(' ; ')}',
          style: const TextStyle(color: AppColors.warn)),
    );
  }

  Widget _buildTariffSwitch() {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: controller.memberTariff,
      onChanged: (_) => controller.toggleMemberTariff(),
      title: Text(controller.memberTariff ? 'Tarif adhérent' : 'Tarif public'),
      secondary: const Icon(Icons.badge),
    );
  }

  Widget _buildCartList(BuildContext context) {
    if (controller.cart.isEmpty) {
      return SizedBox(
        height: 72,
        child: Center(
          child: Text(
            controller.donation > 0 ? 'Don sans article' : 'Panier vide',
            style: const TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }
    if (controller.cart.length <= _maxVisibleCartItems) {
      return Column(
        children: [
          for (var index = 0; index < controller.cart.length; index++)
            _buildCartItem(context, index),
        ],
      );
    }
    return SizedBox(
      key: const ValueKey('scrollable-cart-items'),
      height: _maxVisibleCartItems * _cartItemExtent,
      child: Scrollbar(
        child: ListView.builder(
          primary: false,
          padding: EdgeInsets.zero,
          itemCount: controller.cart.length,
          itemBuilder: _buildCartItem,
        ),
      ),
    );
  }

  Widget _buildCartItem(BuildContext context, int index) {
    final item = controller.cart[index];
    final article =
        controller.articles.firstWhere((a) => a.id == item.articleId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TacticalCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Text(article.icon),
            const SizedBox(width: 6),
            Expanded(
                child: Text(article.name, overflow: TextOverflow.ellipsis)),
            IconButton.filledTonal(
                onPressed: () => controller.changeCartQuantity(article.id, -1),
                icon: const Icon(Icons.remove),
                iconSize: 16),
            Text('${item.quantity}',
                style: const TextStyle(fontWeight: FontWeight.w900)),
            IconButton.filledTonal(
                onPressed: () => controller.changeCartQuantity(article.id, 1),
                icon: const Icon(Icons.add),
                iconSize: 16),
            SizedBox(
                width: 64,
                child: Text(money(item.price * item.quantity),
                    textAlign: TextAlign.right,
                    style: TextStyle(color: context.primaryAccent))),
          ],
        ),
      ),
    );
  }

  Widget _buildDonationField() {
    return TextFormField(
      initialValue: controller.donation == 0
          ? ''
          : controller.donation.toStringAsFixed(2),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
          prefixIcon: Icon(Icons.volunteer_activism), labelText: 'Don'),
      onChanged: (value) => controller
          .setDonation(double.tryParse(value.replaceAll(',', '.')) ?? 0),
    );
  }

  Widget _buildPaymentButtons(BuildContext context, bool canCheckout) {
    return Row(
      children: [
        Expanded(
            child: FilledButton.icon(
                onPressed: canCheckout
                    ? () => showCashDialog(context, controller)
                    : null,
                icon: const Icon(Icons.payments),
                label: const Text('ESP'))),
        const SizedBox(width: 6),
        Expanded(
            child: FilledButton.tonal(
                onPressed:
                    canCheckout ? () => _checkout(context, 'PayPal') : null,
                child: const Text('PayPal'))),
        const SizedBox(width: 6),
        Expanded(
            child: FilledButton.tonal(
                onPressed:
                    canCheckout ? () => _checkout(context, 'SumUp') : null,
                child: const Text('SumUp'))),
      ],
    );
  }

  Widget _buildClearButton(bool hasPendingPayment) {
    return TextButton.icon(
        onPressed: hasPendingPayment ? controller.clearCart : null,
        icon: const Icon(Icons.delete_outline),
        label: const Text('Vider'),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size.fromHeight(36),
        ));
  }

  Future<void> _checkout(BuildContext context, String payment) async {
    try {
      await controller.checkout(payment);
      if (context.mounted) snack(context, 'Vente validée en $payment');
    } on StateError catch (error) {
      if (context.mounted) snack(context, '$error');
    }
  }
}
