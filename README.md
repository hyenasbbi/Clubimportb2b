# Club IMPORTB2B — V2

Aplicación web de fidelización construida únicamente con HTML, CSS, JavaScript puro, Supabase, GitHub y Netlify.

## Regla central

El administrador registra clientes únicamente después de haber comprobado una historia etiquetando a IMPORTB2B mediante la notificación de Instagram o una captura válida.

El alta inicial del cliente **no suma puntos**.

Después del alta:

**1 punto = 1 compra + 1 historia etiquetando a IMPORTB2B, ya verificadas por el administrador.**

No existe estado de historia pendiente en esta versión. Si todavía no existe prueba, no se registra el punto.

Los referidos y los créditos dejan de formar parte de la mecánica del Club.

## Clubes y recompensas

### Club Vapers
- 3 puntos: Vaper de regalo.
- 6 puntos: otro Vaper de regalo.
- 9 puntos: otro Vaper de regalo.
- Continúa automáticamente cada 3 puntos.

### Club Jerseys
- 4 puntos: Camiseta versión hincha.
- 8 puntos: Short versión jugador.

### Club Perfumes
- 3 puntos: Perfume Tier C.
- 6 puntos: Perfume Tier B.
- 10 puntos: Perfume Tier A.

### Club IMPORTB2B
Para termos, vasos y artículos varios. La compra debe ser de **$30.000 ARS o más** y tener historia verificada.

- 3 puntos: Cupón 25% OFF en cualquier producto.
- 5 puntos: Artículo Stanley sorpresa.
- 8 puntos: Mystery Gift IMPORTB2B.

## Instalación / actualización de una beta existente

1. Conserva tu proyecto de Supabase actual.
2. Abre `supabase/schema.sql`.
3. Copia todo el contenido.
4. En Supabase abre **SQL Editor → New query**.
5. Pega el archivo completo y ejecuta **Run**.
6. El script actualiza la instalación sin borrar usuarios, clientes ni historial.
7. Reemplaza en GitHub estos archivos por los de esta versión:
   - `index.html`
   - `cliente.html`
   - `admin/index.html`
   - `assets/js/admin.js`
   - `assets/js/cliente.js`
   - `assets/css/styles.css`
   - `supabase/schema.sql`
8. No reemplaces `assets/js/config.example.js` si ya contiene tu Project URL y tu Publishable Key correctas.
9. Netlify detectará el commit y publicará automáticamente.
10. Cierra sesión y vuelve a entrar al panel para probar la V2.

## Flujo administrativo

### Crear cliente
Al crear un cliente se selecciona su club principal. El sistema genera automáticamente código y token privado.

El ingreso comienza con 0 puntos.

### Registrar un punto
Desde la ficha del cliente se usa **Registrar compra + historia**.

El botón debe utilizarse únicamente cuando la compra y la historia ya fueron verificadas.

Para Club IMPORTB2B se solicita además el monto y se rechazan compras menores a $30.000.

Al confirmar:
- suma +1 punto;
- guarda el movimiento;
- actualiza la tarjeta pública;
- desbloquea automáticamente el premio correspondiente cuando alcanza una meta.

### Premios
Los premios aparecen automáticamente como **Pendientes** al desbloquearse.

El administrador puede marcarlos como **Entregados** desde la sección Premios. Entregar un premio no resta puntos: el progreso es acumulativo.

## Tarjeta pública

La tarjeta muestra:
- Nombre y código.
- Club del cliente.
- Puntos acumulados.
- Próximo premio.
- Barra de progreso.
- Todas las recompensas del club.
- Recompensas bloqueadas en gris.
- Recompensas desbloqueadas.
- Premios entregados.
- Historial relevante.

La ruta sigue siendo:

`https://TU-SITIO.netlify.app/c/TOKEN-UNICO`

## Seguridad

- El cliente no inicia sesión.
- El token solo permite consultar la tarjeta asociada.
- Las tablas continúan protegidas con Row Level Security.
- Solo administradores autenticados pueden crear clientes, registrar puntos o entregar premios.
- Nunca se utiliza `service_role` en JavaScript público.
- El frontend utiliza solamente Project URL y Publishable/anon key.

## Tecnologías

No utiliza React, Next.js, Vue, Angular, TypeScript, Tailwind, Node.js, npm, Vite, `package.json` ni procesos de compilación.
