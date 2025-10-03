import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../theme/app_theme.dart';

/// Payment Method Selector: Gespeicherte Karte oder neue Zahlung
class PaymentMethodSelector extends StatefulWidget {
  final Function(String? paymentMethodId) onSelected;
  final bool showNewCardOption;

  const PaymentMethodSelector({
    super.key,
    required this.onSelected,
    this.showNewCardOption = true,
  });

  @override
  State<PaymentMethodSelector> createState() => _PaymentMethodSelectorState();
}

class _PaymentMethodSelectorState extends State<PaymentMethodSelector> {
  List<SavedCard> _cards = [];
  String? _selectedPaymentMethodId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'getPaymentMethods',
      );
      final result = await callable.call();
      final methods = (result.data['paymentMethods'] as List<dynamic>?) ?? [];

      setState(() {
        _cards = methods.map((m) => SavedCard.fromMap(m)).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Fehler beim Laden der Karten: $e');
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Zahlungsmethode wählen:',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),

        // Gespeicherte Karten
        ..._cards.map((card) => _buildCardOption(card)),

        // Neue Karte Option
        if (widget.showNewCardOption) _buildNewCardOption(),
      ],
    );
  }

  Widget _buildCardOption(SavedCard card) {
    final isSelected = _selectedPaymentMethodId == card.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.lightBlue.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? AppColors.lightBlue
              : Colors.white.withOpacity(0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _selectedPaymentMethodId = card.id);
            widget.onSelected(card.id);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(_getCardIcon(card.brand), color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_getBrandName(card.brand)} ****${card.last4}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (card.isDefault)
                        Text(
                          'Standard',
                          style: TextStyle(
                            color: AppColors.lightBlue,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: AppColors.lightBlue,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewCardOption() {
    final isSelected = _selectedPaymentMethodId == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.lightBlue.withOpacity(0.1)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? AppColors.lightBlue
              : Colors.white.withOpacity(0.1),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _selectedPaymentMethodId = null);
            widget.onSelected(null);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.add_card, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Neue Karte verwenden',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: AppColors.lightBlue,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getCardIcon(String brand) {
    switch (brand.toLowerCase()) {
      case 'visa':
        return Icons.credit_card;
      case 'mastercard':
        return Icons.credit_card;
      case 'amex':
        return Icons.credit_card;
      default:
        return Icons.credit_card;
    }
  }

  String _getBrandName(String brand) {
    return brand[0].toUpperCase() + brand.substring(1).toLowerCase();
  }
}

class SavedCard {
  final String id;
  final String brand;
  final String last4;
  final bool isDefault;

  SavedCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.isDefault,
  });

  factory SavedCard.fromMap(Map<String, dynamic> map) {
    return SavedCard(
      id: map['id'] as String,
      brand: map['brand'] as String,
      last4: map['last4'] as String,
      isDefault: (map['isDefault'] as bool?) ?? false,
    );
  }
}
