/// Pide las fotos de producto al tamaño en que se muestran, no a su tamaño original.
///
/// Las tiendas VTEX (Coolbox, Plaza Vea, Oechsle, Promart, Metro, Estilos, Shopstar) redimensionan
/// en su CDN si la ruta lleva el tamaño: `/arquivos/ids/487727/x.jpg` → `/arquivos/ids/487727-300-300/x.jpg`.
/// Con el encabezado `Accept: image/webp` además la entregan en WebP. Una foto de 36 KB pasa a ~3 KB.
/// Las demás tiendas ya publican miniaturas en sus listados: su URL no se toca.
library;

final _vtexIds = RegExp(r'/arquivos/ids/(\d+)(?:-\d+-\d+)?/');

/// Tamaños fijos (px): pocas variantes por foto, para que la caché se reutilice entre pantallas.
const imageSizeBuckets = [160, 320, 640];

bool isVtexImage(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return (host.endsWith('vteximg.com.br') || host.endsWith('vtexassets.com')) && _vtexIds.hasMatch(url);
}

/// Tamaño de la variante para un espacio de [logicalSize] puntos en una pantalla de [pixelRatio].
int imageBucket(double logicalSize, double pixelRatio) {
  final needed = (logicalSize * pixelRatio).ceil();
  for (final size in imageSizeBuckets) {
    if (needed <= size) return size;
  }
  return imageSizeBuckets.last;
}

/// URL de la foto a [px] × [px] (solo VTEX; las demás se devuelven igual).
String sizedImageUrl(String url, int px) {
  if (!isVtexImage(url)) return url;
  return url.replaceFirstMapped(_vtexIds, (m) => '/arquivos/ids/${m[1]}-$px-$px/');
}
