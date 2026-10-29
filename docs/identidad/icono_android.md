# Icono de Android

`assets/branding/app_icon.png` conserva la composición centrada sobre el fondo
`ink`, preparada desde la imagen de referencia recibida el 28 de octubre de
2026.

Android usa un icono adaptativo desde API 26: el fondo se define en
`res/values/ic_launcher_colors.xml` y las capas de primer plano y monocromática
se incluyen por densidad en `mipmap-*`. Las imágenes `ic_launcher.png` de cada
densidad sirven de alternativa para versiones anteriores. El primer plano
mantiene el isotipo dentro de la zona segura del icono adaptativo.

## Contraste de opciones

Los menús de opciones usan `surface` para el fondo y `onSurface` para el texto.
El segmento seleccionado usa `secondaryContainer` con `onSecondaryContainer`;
el selector de variante de línea recibe ambos colores del tema activo. Así se
mantiene el contraste tanto en claro como en oscuro.
