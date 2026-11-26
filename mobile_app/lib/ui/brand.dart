import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Identidad visual de cada tienda: logo (ícono cuadrado que publica la propia tienda, en
/// `assets/stores/{CODE}.png`) o, si no hay uno usable, iniciales sobre su color.
class StoreBrand {
  const StoreBrand({required this.initials, required this.color, this.hasLogo = true});

  final String initials;
  final Color color;
  final bool hasLogo;
}

const storeBrands = <String, StoreBrand>{
  'COOLBOX': StoreBrand(initials: 'CB', color: Color(0xFFE11937)),
  'PLAZAVEA': StoreBrand(initials: 'PV', color: Color(0xFFE52421)),
  'OECHSLE': StoreBrand(initials: 'OE', color: Color(0xFFF0304F)),
  'PROMART': StoreBrand(initials: 'PM', color: Color(0xFFF36F21)),
  'METRO': StoreBrand(initials: 'MT', color: Color(0xFFE30613)),
  'EFE': StoreBrand(initials: 'EF', color: Color(0xFF0072CE)),
  'LACURACAO': StoreBrand(initials: 'LC', color: Color(0xFF111111)),
  'SERCOPLUS': StoreBrand(initials: 'SP', color: Color(0xFFC81E1E)),
  'INFOTEC': StoreBrand(initials: 'IN', color: Color(0xFFF25C05)),
  'PHANTOM': StoreBrand(initials: 'PH', color: Color(0xFF111111)),
  'ESTILOS': StoreBrand(initials: 'ES', color: Color(0xFFE3141B)),
  'MEMORYKINGS': StoreBrand(initials: 'MK', color: Color(0xFF15803D), hasLogo: false),
  'SHOPSTAR': StoreBrand(initials: 'SS', color: Color(0xFF1BA6E8), hasLogo: false),
  'MMSTORE': StoreBrand(initials: 'MM', color: Color(0xFF111111), hasLogo: false),
  'MIAU': StoreBrand(initials: 'MI', color: Color(0xFF7C3AED), hasLogo: false),
  'UNIK': StoreBrand(initials: 'UK', color: Color(0xFFD90000), hasLogo: false),
  'CGS': StoreBrand(initials: 'CG', color: Color(0xFF1F7A3A), hasLogo: false),
  'BANANASTORE': StoreBrand(initials: 'BS', color: Color(0xFF8A6D00), hasLogo: false),
  'FABRITEC': StoreBrand(initials: 'FT', color: Color(0xFF0E224D), hasLogo: false),
};

/// Marca de una tienda; las desconocidas usan iniciales de su nombre sobre marino.
StoreBrand storeBrand(String code, {String name = ''}) {
  final known = storeBrands[code.toUpperCase()];
  if (known != null) return known;
  final words = (name.isEmpty ? code : name).trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final initials = words.length > 1 ? '${words[0][0]}${words[1][0]}' : (words.isEmpty ? '?' : words[0].substring(0, words[0].length.clamp(1, 2)));
  return StoreBrand(initials: initials.toUpperCase(), color: AppColors.ink, hasLogo: false);
}

/// Logo redondo de la tienda.
class StoreBadge extends StatelessWidget {
  const StoreBadge({super.key, required this.code, this.name = '', this.size = 28});

  final String code;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = storeBrand(code, name: name);
    final initials = Center(
      child: Text(
        brand.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: (size * 0.36).clamp(7, 20),
          letterSpacing: -0.3,
          height: 1,
        ),
      ),
    );
    return Semantics(
      label: name.isEmpty ? null : name,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: brand.hasLogo ? Colors.white : brand.color,
          border: brand.hasLogo ? Border.all(color: AppColors.line) : null,
        ),
        child: brand.hasLogo
            ? Image.asset(
                'assets/stores/${code.toUpperCase()}.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(color: brand.color, child: initials),
              )
            : initials,
      ),
    );
  }
}

/// Logotipo CompraMejor: bolsa con «%» y trazo magenta, más la palabra.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'CompraMejor',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(size: Size.square(size), painter: _BagPainter()),
            const SizedBox(width: 6),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Compra'),
                  TextSpan(text: 'Mejor', style: TextStyle(color: AppColors.magenta)),
                ],
              ),
              style: TextStyle(fontSize: size * 0.6, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.ink),
            ),
          ],
        ),
      );
}

class _BagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 36;
    canvas.scale(s);
    final handle = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(13, 12)
        ..lineTo(13, 9.5)
        ..arcToPoint(const Offset(23, 9.5), radius: const Radius.circular(5))
        ..lineTo(23, 12),
      handle,
    );
    final bag = Path()
      ..moveTo(8, 12)
      ..lineTo(28, 12)
      ..lineTo(26.2, 29.5)
      ..quadraticBezierTo(26, 31.3, 24.2, 31.3)
      ..lineTo(11.8, 31.3)
      ..quadraticBezierTo(10, 31.3, 9.8, 29.5)
      ..close();
    canvas.drawPath(
      bag,
      Paint()
        ..shader = const LinearGradient(colors: [AppColors.blue, AppColors.ink], begin: Alignment.topLeft, end: Alignment.bottomRight)
            .createShader(const Rect.fromLTWH(8, 12, 20, 20)),
    );
    final tp = TextPainter(
      text: const TextSpan(text: '%', style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(18 - tp.width / 2, 23 - tp.height / 2));
    canvas.drawPath(
      Path()
        ..moveTo(3, 27)
        ..quadraticBezierTo(18, 37, 33, 18),
      Paint()
        ..color = AppColors.magenta
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
