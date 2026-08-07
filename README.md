# Club IMPORTB2B

Aplicación web estática de fidelización de clientes creada exclusivamente con:

- GitHub
- Netlify
- Supabase
- HTML5
- CSS3
- JavaScript puro
- Librería oficial de Supabase cargada por CDN

No usa Node.js, npm, frameworks, TypeScript ni procesos de compilación.

---

## 1. Estructura del proyecto

```text
/
├── index.html
├── cliente.html
├── netlify.toml
├── README.md
├── assets/
│   ├── css/
│   │   └── styles.css
│   └── js/
│       ├── config.example.js
│       ├── supabaseClient.js
│       ├── cliente.js
│       ├── login.js
│       └── admin.js
├── admin/
│   ├── login.html
│   └── index.html
└── supabase/
    └── schema.sql
```

El archivo `config.example.js` es el archivo de configuración real del frontend. Se mantiene con ese nombre para respetar la estructura solicitada. Debes editar sus dos valores antes de publicar.

---

## 2. Qué incluye

### Tarjeta del cliente

Cada cliente recibe un enlace como:

```text
https://TU-SITIO.netlify.app/c/TOKEN-UNICO
```

La tarjeta muestra:

- Nombre
- Código de cliente
- Fecha de ingreso
- Estado activo o inactivo
- Compras
- Historias de Instagram
- Referidos
- Créditos
- Próxima recompensa
- Progreso
- Recompensas activas
- Historial de movimientos

El cliente no inicia sesión y no puede editar información.

### Panel administrativo

El administrador puede:

- Iniciar y cerrar sesión
- Crear clientes
- Editar clientes
- Reactivar o desactivar clientes
- Eliminar clientes con confirmación
- Buscar por nombre, teléfono, Instagram o código
- Copiar el enlace privado
- Registrar compras
- Registrar historias
- Registrar referidos
- Sumar o restar créditos
- Consultar el historial
- Crear y editar recompensas
- Registrar canjes
- Aprobar, entregar o cancelar canjes
- Consultar estadísticas generales

---

# INSTALACIÓN SIN TERMINAL

## 3. Crear el proyecto de Supabase

1. Ingresa a Supabase desde el navegador.
2. Crea una cuenta o inicia sesión.
3. Selecciona **New project**.
4. Elige tu organización.
5. Escribe un nombre, por ejemplo: `club-importb2b`.
6. Crea una contraseña segura para la base de datos y guárdala.
7. Elige la región más cercana a tus usuarios.
8. Presiona **Create new project**.
9. Espera a que el proyecto quede disponible.

No necesitas instalar ningún programa.

---

## 4. Ejecutar `schema.sql`

1. Dentro de Supabase, abre **SQL Editor**.
2. Selecciona **New query**.
3. En tu computadora, abre la carpeta del proyecto.
4. Abre el archivo:

```text
supabase/schema.sql
```

5. Selecciona todo su contenido y cópialo.
6. Pégalo en el editor SQL de Supabase.
7. Presiona **Run**.
8. Verifica que aparezca un mensaje de ejecución correcta.

El script crea:

- Tablas
- Relaciones
- Índices
- Funciones RPC
- Triggers
- Validaciones
- Políticas Row Level Security
- Permisos de acceso

No ejecutes fragmentos por separado. Ejecuta el archivo completo.

### Si necesitas volver a ejecutarlo

El esquema está preparado para actualizar funciones y políticas. No obstante, no elimina datos existentes. En una instalación limpia, ejecútalo una sola vez.

---

## 5. Crear el primer administrador

### Parte A: crear el usuario de Auth

1. En Supabase, abre **Authentication**.
2. Ingresa a **Users**.
3. Presiona **Add user**.
4. Elige **Create new user**.
5. Escribe el correo administrativo.
6. Escribe una contraseña segura.
7. Activa la opción para confirmar automáticamente el correo, si aparece.
8. Crea el usuario.

### Parte B: autorizarlo como administrador

1. Vuelve a **SQL Editor**.
2. Crea una consulta nueva.
3. Copia este bloque y reemplaza el correo y el nombre:

```sql
insert into public.admins (id, full_name, is_active)
select id, 'Administrador IMPORTB2B', true
from auth.users
where email = 'TU-CORREO@EJEMPLO.COM'
on conflict (id) do update
set full_name = excluded.full_name,
    is_active = true;
```

4. Presiona **Run**.

Después de este paso, el usuario ya puede ingresar al panel.

Las contraseñas permanecen en Supabase Auth. Nunca se guardan manualmente en las tablas del Club.

---

## 6. Obtener la URL y la clave pública

1. En Supabase, abre **Project Settings**.
2. Ingresa a **API**.
3. Copia la **Project URL**.
4. Copia una clave pública:
   - La clave `anon public`, o
   - La nueva `publishable key`, si tu proyecto muestra ese formato.
5. Nunca copies la clave `service_role`.

---

## 7. Configurar el frontend

Abre este archivo:

```text
assets/js/config.example.js
```

Encontrarás:

```javascript
window.CLUB_CONFIG = Object.freeze({
  SUPABASE_URL: "https://TU-PROYECTO.supabase.co",
  SUPABASE_ANON_KEY: "PEGA-AQUI-TU-CLAVE-PUBLICA"
});
```

Reemplaza los dos valores entre comillas.

Ejemplo de formato:

```javascript
window.CLUB_CONFIG = Object.freeze({
  SUPABASE_URL: "https://abcdefghijk.supabase.co",
  SUPABASE_ANON_KEY: "tu-clave-publica"
});
```

No cambies el nombre `CLUB_CONFIG` ni los nombres de las propiedades.

### Seguridad

La URL del proyecto y la clave pública pueden estar en el navegador porque la seguridad real está aplicada mediante Row Level Security y funciones SQL.

Nunca coloques en JavaScript:

```text
SUPABASE_SERVICE_ROLE_KEY
```

---

## 8. Crear el repositorio en GitHub

1. Ingresa a GitHub desde el navegador.
2. Presiona el botón para crear un repositorio nuevo.
3. Escribe un nombre, por ejemplo:

```text
club-importb2b
```

4. Elige repositorio privado o público.
5. No marques opciones para crear README, `.gitignore` o licencia, porque el proyecto ya contiene su README.
6. Presiona **Create repository**.

---

## 9. Subir los archivos a GitHub desde el navegador

Primero descomprime el ZIP en tu computadora.

1. Abre el repositorio vacío en GitHub.
2. Presiona **uploading an existing file** o **Add file > Upload files**.
3. Arrastra el contenido de la carpeta descomprimida.
4. Debes arrastrar los archivos y carpetas que están dentro de `club-importb2b`, no la carpeta exterior completa.
5. Verifica que `index.html` aparezca en la raíz.
6. Confirma que también aparezcan:
   - `admin`
   - `assets`
   - `supabase`
   - `cliente.html`
   - `netlify.toml`
7. En el campo de confirmación escribe, por ejemplo:

```text
Instalación inicial Club IMPORTB2B
```

8. Presiona **Commit changes**.

La raíz del repositorio debe mostrar directamente `index.html`.

---

## 10. Conectar GitHub con Netlify

1. Ingresa a Netlify.
2. Selecciona **Add new project**.
3. Elige **Import an existing project**.
4. Selecciona GitHub.
5. Autoriza el acceso si Netlify lo solicita.
6. Selecciona el repositorio `club-importb2b`.
7. Revisa la configuración:

```text
Base directory: vacío
Build command: vacío
Publish directory: .
```

8. No escribas ningún comando de build.
9. Presiona **Deploy**.

El archivo `netlify.toml` indica que la carpeta publicada es la raíz y no define ningún comando de compilación.

Cuando finalice, Netlify mostrará una dirección similar a:

```text
https://nombre-aleatorio.netlify.app
```

---

## 11. Configurar Supabase Auth para la URL de Netlify

1. Copia la URL definitiva de Netlify.
2. En Supabase, abre **Authentication**.
3. Ingresa a la configuración de URL.
4. En **Site URL**, coloca la URL principal de Netlify, sin una barra extra al final.
5. En las URLs de redirección permitidas, agrega:

```text
https://TU-SITIO.netlify.app/admin
https://TU-SITIO.netlify.app/admin/login
```

Para el inicio de sesión actual con correo y contraseña, estas rutas ayudan a mantener una configuración coherente para futuras funciones de recuperación o confirmación.

---

## 12. Primer ingreso al panel

Abre:

```text
https://TU-SITIO.netlify.app/admin/login
```

Ingresa con el correo y la contraseña creados en Supabase Auth.

El sistema verificará dos condiciones:

1. El usuario tiene una sesión válida en Supabase Auth.
2. El ID del usuario existe y está activo en `public.admins`.

Ocultar botones no es la medida de seguridad. Las políticas RLS y las funciones SQL controlan el acceso real.

---

## 13. Crear recompensas iniciales

1. Ingresa al panel.
2. Abre **Recompensas**.
3. Completa:
   - Nombre
   - Descripción
   - Créditos requeridos
   - Stock opcional
   - Orden
4. Guarda la recompensa.

Ejemplos:

- Envío gratis: 300 créditos
- 10% de descuento: 500 créditos
- Producto exclusivo: 1000 créditos

Si dejas el stock vacío, se considera ilimitado.

---

## 14. Crear y probar un cliente de ejemplo

1. En el panel, abre **Clientes**.
2. Presiona **Crear cliente**.
3. Usa datos de prueba:

```text
Nombre: Cliente de Prueba
Teléfono: +54 9 342 000 0000
Instagram: @clienteprueba
Fecha: fecha actual
Notas: Prueba inicial del sistema
```

4. Guarda el cliente.
5. Se abrirá su ficha.
6. Presiona **Copiar enlace**.
7. Abre una ventana privada o de incógnito.
8. Pega el enlace.
9. Verifica que solamente se muestre la tarjeta de ese cliente.

### Probar movimientos

Desde la ficha administrativa registra:

1. Una compra con `100` créditos.
2. Una historia con `50` créditos.
3. Un referido con `200` créditos.
4. Un ajuste manual con `-25` créditos.

Recarga el enlace del cliente y verifica:

- Contadores actualizados
- Saldo correcto
- Barra de progreso
- Historial completo

### Probar un canje

1. Asegúrate de haber creado una recompensa.
2. Verifica que el cliente tenga créditos suficientes.
3. Abre **Canjes**.
4. Selecciona cliente y recompensa.
5. Confirma el canje.
6. El saldo se descuenta inmediatamente.
7. Puedes cambiar el estado a aprobado o entregado.
8. Si cancelas el canje, el sistema reintegra créditos y stock automáticamente.

---

# SEGURIDAD IMPLEMENTADA

## 15. Acceso público

El visitante anónimo:

- No puede seleccionar directamente tablas.
- No puede crear datos.
- No puede editar datos.
- No puede eliminar datos.
- Solo puede ejecutar `get_client_card_by_token`.
- Solo recibe los campos públicos de la tarjeta asociada al token.

La función pública no devuelve:

- Teléfono
- Instagram
- Notas internas
- Token
- ID interno
- Datos del administrador

## 16. Acceso administrativo

El usuario autenticado también debe existir en `admins` y estar activo.

Las operaciones sensibles se realizan mediante funciones RPC que vuelven a comprobar la autorización.

Los movimientos de créditos no se editan ni eliminan silenciosamente. Las correcciones se registran como movimientos compensatorios.

## 17. Saldo verificable

Cada movimiento guarda:

- Cliente
- Tipo
- Cantidad
- Motivo
- Saldo posterior
- Fecha
- Administrador responsable

El saldo resumido de `clients.credit_balance` puede comprobarse contra la suma de `credit_movements.amount`.

Puedes verificarlo desde SQL Editor con:

```sql
select
  c.client_code,
  c.full_name,
  c.credit_balance as saldo_guardado,
  coalesce(sum(m.amount), 0) as saldo_segun_historial
from public.clients c
left join public.credit_movements m on m.client_id = c.id
group by c.id, c.client_code, c.full_name, c.credit_balance
order by c.created_at desc;
```

---

# RUTAS

## 18. Rutas públicas y administrativas

```text
/                       Portada
/admin/login            Inicio de sesión
/admin                  Panel administrativo
/c/TOKEN-UNICO          Tarjeta del cliente
```

`netlify.toml` utiliza reescrituras con estado `200`, por lo que las rutas continúan funcionando al recargar la página.

---

# MANTENIMIENTO

## 19. Modificar archivos desde GitHub

1. Abre el archivo dentro del repositorio.
2. Presiona el ícono de edición.
3. Realiza el cambio.
4. Presiona **Commit changes**.
5. Netlify volverá a publicar automáticamente.

No necesitas ejecutar comandos.

## 20. Cambiar el nombre del sitio en Netlify

Puedes modificar el nombre generado desde la configuración del proyecto en Netlify. Al cambiarlo, recuerda actualizar la Site URL y las Redirect URLs de Supabase Auth.

## 21. Desactivar un administrador

Desde SQL Editor:

```sql
update public.admins
set is_active = false
where id = (
  select id from auth.users where email = 'CORREO@EJEMPLO.COM'
);
```

Para reactivarlo, cambia `false` por `true`.

---

# SOLUCIÓN DE PROBLEMAS

## 22. El login dice que falta configurar Supabase

Revisa `assets/js/config.example.js` y confirma que reemplazaste ambos valores de ejemplo.

## 23. El usuario inicia sesión pero no entra al panel

Confirma que:

- El usuario existe en Authentication.
- El mismo ID existe en `public.admins`.
- `is_active` es `true`.

Consulta de diagnóstico:

```sql
select u.id, u.email, a.full_name, a.is_active
from auth.users u
left join public.admins a on a.id = u.id;
```

## 24. La tarjeta indica que el enlace es inválido

Comprueba que:

- El enlace se copió completo.
- La ruta contiene `/c/`.
- El cliente no fue eliminado.
- `netlify.toml` está en la raíz.

## 25. La página funciona pero no guarda datos

Verifica que `schema.sql` se haya ejecutado completo y sin errores.

## 26. Netlify muestra una página no encontrada

Confirma que:

- `index.html` está en la raíz.
- `netlify.toml` está en la raíz.
- Publish directory es `.`.
- No existe build command.

---

# VERIFICACIÓN FINAL

Este proyecto fue diseñado para cumplir lo siguiente:

- [x] `index.html` está en la raíz.
- [x] No existe `package.json`.
- [x] No existe `node_modules`.
- [x] No existe Next.js.
- [x] No existe React.
- [x] No existe Vue.
- [x] No existe Angular.
- [x] No existe TypeScript.
- [x] No existe Tailwind CSS.
- [x] No existen archivos `.tsx` o `.jsx`.
- [x] No existe npm.
- [x] No existen funciones de servidor.
- [x] No existe proceso de compilación.
- [x] No hay comandos de terminal obligatorios.
- [x] No existe build command en `netlify.toml`.
- [x] Supabase se carga mediante CDN.
- [x] Solo se utiliza la URL y la clave pública en el frontend.
- [x] RLS está activado en todas las tablas.
- [x] El visitante no tiene acceso directo a las tablas.
- [x] El panel requiere Supabase Auth y un administrador activo.
- [x] La administración diaria se realiza desde el panel web.
