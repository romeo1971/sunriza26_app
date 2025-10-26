import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

/// Credits Shop Screen - Kaufe Credits für bequeme Zahlungen
class CreditsShopScreen extends StatefulWidget {
  const CreditsShopScreen({super.key});

  @override
  State<CreditsShopScreen> createState() => _CreditsShopScreenState();
}

class _CreditsShopScreenState extends State<CreditsShopScreen> {
  String _currency = '€'; // € oder $
  final List<int> _creditPackages = [5, 10, 25, 50, 100]; // in Euro (Basis)
  final double _stripeFeeCents = 25; // Stripe-Gebühr: 0,25 € fix
  double _exchangeRate = 1.10; // EUR -> USD (wird live aktualisiert)
  // ignore: unused_field
  bool _loadingExchangeRate = false;

  @override
  void initState() {
    super.initState();
    _fetchExchangeRate();
    
    // Check für Success/Cancel Parameter (nach Stripe Redirect)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkStripeResult();
    });
  }

  /// Prüft ob Stripe Success/Cancel Parameter vorhanden sind
  void _checkStripeResult() {
    // HINWEIS: In Flutter Web würde man hier die URL-Parameter auslesen
    // In Flutter Mobile App ist das nicht relevant, da externe URL
    // Vorerst: Zeige Info-Message dass User Credits manuell prüfen soll
  }

  /// Holt aktuellen EUR/USD Wechselkurs
  Future<void> _fetchExchangeRate() async {
    setState(() => _loadingExchangeRate = true);
    try {
      // FEHLT NOCH: API-Call für aktuellen Wechselkurs
      // final response = await http.get(
      //   Uri.parse('https://api.exchangerate-api.com/v4/latest/EUR'),
      // );
      // final data = json.decode(response.body);
      // _exchangeRate = data['rates']['USD'];

      // PLACEHOLDER: Standard-Kurs
      _exchangeRate = 1.10; // 1 EUR = 1.10 USD
    } catch (e) {
      debugPrint('Fehler beim Laden des Wechselkurses: $e');
      _exchangeRate = 1.10; // Fallback
    } finally {
      if (mounted) {
        setState(() => _loadingExchangeRate = false);
      }
    }
  }

  /// Berechnet Preis in gewählter Währung (Basis: EUR)
  double _calculatePrice(int euroAmount) {
    if (_currency == '\$') {
      return euroAmount * _exchangeRate;
    }
    return euroAmount.toDouble();
  }

  /// Berechnet Credits aus Euro-Basis (1 Credit = 0,10 €)
  int _calculateCredits(int euroAmount) {
    return (euroAmount / 0.1).round();
  }

  /// Berechnet Gesamtpreis inkl. Stripe-Gebühr in gewählter Währung
  double _calculateTotalPrice(int euroAmount) {
    final price = _calculatePrice(euroAmount);
    final stripeFee = _currency == '\$'
        ? (_stripeFeeCents / 100) * _exchangeRate
        : _stripeFeeCents / 100;
    return price + stripeFee;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Color(0xFFE91E63), // Magenta
                  AppColors.lightBlue, // Blue
                  Color(0xFF00E5FF), // Cyan
                ],
                stops: [0.0, 0.5, 1.0],
              ).createShader(bounds),
              child: const Icon(Icons.diamond, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text(
              'Credits kaufen',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Erklärung: Warum Credits?
            _buildExplanationCard(),
            const SizedBox(height: 32),

            // Währungsauswahl: € / $
            _buildCurrencySelector(),
            const SizedBox(height: 24),

            // Credit-Pakete
            const Text(
              'Wähle dein Paket:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._creditPackages.map((amount) => _buildCreditPackageCard(amount)),

            const SizedBox(height: 32),

            // Info: Stripe-Gebühr
            _buildStripeInfoCard(),
          ],
        ),
      ),
    );
  }

  /// Erklärung: Warum Credits kaufen?
  Widget _buildExplanationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE91E63), // Magenta
            AppColors.lightBlue, // Blue
            Color(0xFF00E5FF), // Cyan
          ],
          stops: [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.diamond, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                'Warum Credits?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildBulletPoint('💳 Keine Transaktionsgebühren pro Kauf'),
          const SizedBox(height: 8),
          _buildBulletPoint('⚡ Schnelle Zahlung ohne erneute Stripe-Gebühr'),
          const SizedBox(height: 8),
          _buildBulletPoint('💰 Mehr Geld für dich - spare Gebühren!'),
          const SizedBox(height: 8),
          _buildBulletPoint('🛡️ Sicher & bequem im Chat/Avatar zahlen'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '💡 Wichtig: Einzelkäufe unter 2 € sind NUR mit Credits möglich. '
              'Ab 2 € kannst du zwischen Credits und direkter Zahlung wählen.',
              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  /// Währungsauswahl: € oder $
  Widget _buildCurrencySelector() {
    return Row(
      children: [
        const Text(
          'Währung:',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(width: 16),
        _buildCurrencyChip('€'),
        const SizedBox(width: 12),
        _buildCurrencyChip('\$'),
      ],
    );
  }

  Widget _buildCurrencyChip(String currency) {
    final isSelected = _currency == currency;
    return GestureDetector(
      onTap: () => setState(() => _currency = currency),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    Color(0xFFE91E63),
                    AppColors.lightBlue,
                    Color(0xFF00E5FF),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.white30,
            width: 1,
          ),
        ),
        child: Text(
          currency,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// Credit-Paket-Karte
  Widget _buildCreditPackageCard(int euroAmount) {
    final credits = _calculateCredits(euroAmount);
    final price = _calculatePrice(euroAmount);
    final totalPrice = _calculateTotalPrice(euroAmount);
    final currencySymbol = _currency;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _purchaseCredits(euroAmount, credits, price, totalPrice),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Credit-Icon + Anzahl
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFE91E63),
                        AppColors.lightBlue,
                        Color(0xFF00E5FF),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.diamond, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        '$credits',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                // Preis-Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${price.toStringAsFixed(2)} $currencySymbol',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Gesamt: ${totalPrice.toStringAsFixed(2)} $currencySymbol',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // Pfeil
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Stripe-Gebühr Info
  Widget _buildStripeInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.white.withValues(alpha: 0.7),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Stripe-Transaktionsgebühr: 0,25 ${_currency == '€' ? '€' : '\$'} (fix)\n\n'
              'Alle Preise verstehen sich zzgl. dieser Gebühr. '
              'Bei Credits-Zahlung fällt diese Gebühr NICHT mehr an!',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Kaufe Credits
  void _purchaseCredits(
    int euroAmount,
    int credits,
    double price,
    double totalPrice,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  Color(0xFFE91E63),
                  AppColors.lightBlue,
                  Color(0xFF00E5FF),
                ],
              ).createShader(bounds),
              child: const Icon(Icons.diamond, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text(
              'Credits kaufen',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Du kaufst:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.diamond, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  '$credits Credits',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Preis:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${price.toStringAsFixed(2)} $_currency',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Stripe-Gebühr:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${(_stripeFeeCents / 100).toStringAsFixed(2)} $_currency',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Gesamt:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${totalPrice.toStringAsFixed(2)} $_currency',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Abbrechen',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startStripeCheckout(euroAmount, credits, totalPrice);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.lightBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Jetzt kaufen'),
          ),
        ],
      ),
    );
  }

  /// Startet Stripe-Checkout via Cloud Function
  Future<void> _startStripeCheckout(
    int euroAmount,
    int credits,
    double totalPrice,
  ) async {
    try {
      // Loading anzeigen
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Cloud Function aufrufen
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('createCreditsCheckoutSession');

      final result = await callable.call({
        'euroAmount': euroAmount,
        'amount': (totalPrice * 100).toInt(), // in Cents
        'currency': _currency == '€' ? 'eur' : 'usd',
        'exchangeRate': _exchangeRate,
        'credits': credits,
      });

      // Loading schließen
      if (mounted) Navigator.pop(context);

      final checkoutUrl = result.data['url'] as String?;
      if (checkoutUrl == null) {
        throw Exception('Keine Checkout-URL erhalten');
      }

      // Stripe Checkout öffnen (External Browser)
      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        // Info für User
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '💳 Stripe Checkout geöffnet...\n\n'
              'Nach erfolgreicher Zahlung werden deine Credits automatisch gutgeschrieben. '
              'Kehre danach zur App zurück!',
            ),
            backgroundColor: AppColors.lightBlue,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      } else {
        throw Exception('Kann Checkout-URL nicht öffnen');
      }
    } catch (e) {
      debugPrint('Fehler beim Stripe-Checkout: $e');

      // Loading schließen falls noch offen
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Checkout: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}
