import 'package:flutter/material.dart';

/// Het MacroMatrix-logo: "Mx" in de ring van de Voedingsscore, in de drie macrokleuren (bron: design/icon/final).
class MatrixLogo extends StatelessWidget {
  const MatrixLogo({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/logo.png', width: size, height: size, filterQuality: FilterQuality.medium, semanticLabel: 'MacroMatrix');
}
