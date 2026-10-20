# Solfeus

Solfeus es una aplicación Android hecha en Flutter para aprender solfeo y crear partituras. Permite escribir y visualizar música, escucharla mediante síntesis local, validar la duración de los compases y exportar la obra.

## Ejecutar

Requiere Flutter 3.47 o posterior, Android SDK, un dispositivo Android con bloqueo de pantalla configurado y una cuenta Google añadida al dispositivo para crear partituras. Ejecuta `flutter pub get` y `flutter run` desde la raíz del proyecto. Para generar un APK: `flutter build apk --debug`. Las partituras se guardan en SQLite en el dispositivo; el acceso requiere huella o credencial de bloqueo Android. Al crear una partitura se elige una cuenta Google del dispositivo y se usa su correo como compositor; no se solicita acceso al correo ni se envían datos a Google.

## Estado de la implementación

Incluye biblioteca con creación, edición, reproducción, exportación y borrado; editor de dos pentagramas con teclado horizontal de La0 a Do8, figuras, silencios, puntillos, ligaduras, acordes, texto, deshacer, copiar/pegar compases y validación de duración; metrónomo, síntesis WAV, PDF con pentagramas y guía de solfeo. El editor y el PDF agrupan hasta cuatro compases por fila; el área del pentagrama muestra hasta tres filas y desplaza verticalmente las siguientes. Al añadir un compás, la fila nueva se lleva a la vista. El PDF usa un pentagrama simplificado y no sustituye a un motor profesional de grabado musical. Las ligaduras de audio se aplican entre notas contiguas de igual altura dentro de un mismo compás; la síntesis y el seguimiento visual durante la reproducción son aproximados. No se implementan migraciones automáticas de esquemas existentes.

## Especificación funcional

### Usuarios y acceso

- El inicio de sesión se realiza con huella dactilar o pin de bloqueo Android, si la validación dactilar no está disponible.

### Composición y edición

Una partitura contiene título, compositor, clave, armadura, compás, tempo y uno o dos pentagramas. En el editor se puede:

- Elegir clave de sol, fa, do en tercera o do en cuarta; activar opcionalmente el pentagrama de mano izquierda.
- Configurar la armadura de -7 a +7 alteraciones, el numerador y denominador del compás y el tempo.
- Añadir compases y figuras desde redonda hasta fusa; insertar silencios, puntillos y ligaduras.
- Introducir notas haciendo clic en el pentagrama o en el teclado visual, y editar alturas y alteraciones (natural, sostenido, bemol y dobles alteraciones).
- Aplicar acordes mayores, menores, disminuidos, aumentados, séptimas, extendidos, suspendidos y alterados, con inversiones.
- Añadir matices dinámicos, texto de solfeo/letra si se edita el modelo de partitura y deshacer cambios.
- Copiar y pegar compases, completar el compás seleccionado con silencios y eliminar compases o figuras.
- Ver si cada compás está completo, incompleto o excedido según su duración calculada.


### Reproducción y exportación

- La reproducción calcula las alturas MIDI y duraciones , sintetiza el sonido de piano.
- Se puede activar un metrónomo durante la reproducción. El pentagrama y el teclado visual indican las notas activas.
- La partitura se puede exportar como PDF, el audio como WAV.
- El listado permite crear, editar, reproducir, exportar y eliminar partituras; muestra clave, compás, tempo, cantidad de compases y fecha de actualización.
- La sección «Solfeo» explica las figuras, claves, armaduras, acordes, matices y controles del editor.

## Especificación técnica

### Plataforma y arquitectura

- Flutter, dirigida a usuarios android
- Persistencia SQLite.



### Modelo y almacenamiento

El documento de partitura incluye clave y mano izquierda opcional; armadura (-7 a 7); compás; tempo (20–300 BPM); compases con eventos de nota o silencio; valores de figura, puntillo y ligadura; alteraciones y octavas; notas de acorde, calidad e inversión; dinámica y letra/solfeo. Los modelos validan, entre otros, título y compositor hasta 120 caracteres, octavas de 0 a 8 y numerador/denominador de 1 a 32. La interfaz expone un subconjunto de esos rangos para ciertos controles.

La cadena de conexión predeterminada apunta a sqllite local, crea el esquema si falta, pero no aplica migraciones ni actualiza automáticamente un esquema existente.

