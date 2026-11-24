import 'package:flutter_test/flutter_test.dart';
import 'package:compramejor/core/image_url.dart';

void main() {
  const vtex = 'https://coolboxpe.vteximg.com.br/arquivos/ids/487727/airpods-1.jpg?v=6391';

  test('VTEX: pide la variante del tamaño indicado', () {
    expect(sizedImageUrl(vtex, 320),
        'https://coolboxpe.vteximg.com.br/arquivos/ids/487727-320-320/airpods-1.jpg?v=6391');
    // Si la URL ya traía un tamaño, se reemplaza.
    expect(sizedImageUrl(sizedImageUrl(vtex, 640), 160), contains('/ids/487727-160-160/'));
    expect(isVtexImage('https://oechsle.vtexassets.com/arquivos/ids/1/x.jpg'), isTrue);
  });

  test('otras tiendas: la URL no se toca', () {
    const magento = 'https://phantom.pe/media/catalog/product/cache/abc/p/s/ps5.jpg';
    expect(sizedImageUrl(magento, 160), magento);
    expect(isVtexImage(magento), isFalse);
  });

  test('tamaños fijos según el espacio y la densidad de pantalla', () {
    expect(imageBucket(56, 3), 320); // miniatura de lista: 168 px
    expect(imageBucket(50, 2), 160);
    expect(imageBucket(240, 3), 640); // foto grande del producto
  });
}
