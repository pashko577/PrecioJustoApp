# Maqueta CompraMejor

Prototipo desechable para decidir el diseño de la app antes de pasarlo a Flutter.
Usa datos de ejemplo locales (`src/data.js`): no se conecta a Firebase ni gasta cuota.

```bash
npm install
npm run dev     # abre http://localhost:5173 (también accesible desde el celular en la misma red)
```

Lo que se traslada a Flutter son las decisiones (colores, tipografía, espaciados, componentes y
pantallas), no el código. El interruptor «Peor caso» agrega un producto con datos extremos para
probar que la interfaz no se rompe.
