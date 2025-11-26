# MySQL Backup & Restore

Herramientas en Bash para realizar copias de seguridad y restaurar bases de datos MySQL/MariaDB, con soporte para restauración en contenedores Docker.

## 📋 Tabla de Contenidos

- [Características](#-características)
- [Normas de Estilo](#-normas-de-estilo)
- [Requisitos](#-requisitos)
- [Instalación](#-instalación)
- [Configuración](#-configuración)
- [Uso](#-uso)
- [Ejemplos](#-ejemplos)
- [Solución de problemas](#-solución-de-problemas)
- [Seguridad](#-seguridad)
- [Contribuir](#-contribuir)

## ✨ Características

### mysql-backup.sh
- 💾 Generación automática de backups comprimidos
- 📊 Información detallada de la base de datos antes del backup
- 🗜️ Compresión automática (gzip)
- 🎨 Interfaz de línea de comandos con colores y emojis
- ✅ Validación de conexión antes de realizar el backup
- 🔒 Medidas de seguridad avanzadas (validación de archivos, limpieza segura de credenciales)
- 🛡️ Protección contra path traversal y validación de permisos

### mysql-restore-docker.sh
- 🐳 Restauración en contenedores Docker aislados
- 🔧 Configuración flexible mediante variables de entorno
- 📦 Selección interactiva de backups
- 🔌 Asignación automática de puertos disponibles
- 👤 Creación automática de usuarios y bases de datos
- 🛡️ No afecta la base de datos original

## 🎨 Normas de Estilo

Este proyecto sigue un conjunto de normas de estilo para mantener la consistencia en el código y la presentación del output. **Es fundamental que cualquier persona que desee contribuir al proyecto lea y aplique estas normas.**

### Sistema de Colores

El script utiliza un sistema de colores estandarizado para facilitar la lectura e interpretación de la información mostrada en la consola. Cada color tiene un propósito específico y debe usarse de forma consistente:

#### 🟢 Verde subrayado
**Uso exclusivo**: Comandos y rutas de archivos.

Facilita la identificación de instrucciones que el usuario puede copiar y ejecutar directamente.

**Ejemplos:**
- `chmod 600 .ejemplo.env`
- `./backups/2025_11_11_124902_nombre_base_datos.sql.gz`
- `docker logs mysql-restore-container`

#### 🔴 Rojo
**Uso exclusivo**: Errores y situaciones críticas.

Su uso es limitado intencionalmente para que destaque cuando aparece. Solo debe utilizarse para mensajes de error o situaciones que requieren atención inmediata.

**Ejemplos:**
- `❌ Error: No se ha especificado el archivo .env`
- `❌ Error: No se pudo conectar a la base de datos`
- Valores problemáticos en advertencias (ej: permisos incorrectos)

#### 🟡 Amarillo (negrita)
**Uso**: Advertencias y parámetros importantes.

Se utiliza para destacar valores, parámetros o información que requiere atención del usuario, pero que no son críticos.

**Ejemplos:**
- `⚠️ Advertencia: El archivo tiene permisos 644`
- `Base de datos: mi_bd en 127.0.0.1:3306` (destacando nombres y valores)
- Variables de entorno o parámetros de configuración

#### 🔵 Azul
**Uso**: Títulos y encabezados de secciones.

Se utiliza para títulos de secciones, encabezados de resúmenes y etiquetas de información estructurada.

**Ejemplos:**
- `RESUMEN DE LA COPIA DE SEGURIDAD:`
- `INFORMACIÓN DE CONEXIÓN:`
- Etiquetas de secciones en el output

### Ejemplo de uso combinado

```bash
⚠️  Advertencia: El archivo .ejemplo.env tiene permisos 644
   Se recomienda usar permisos 600 (chmod 600 .ejemplo.env) para mayor seguridad
```

**Desglose del ejemplo:**
- El emoji ⚠️ indica que es una advertencia
- El texto "Advertencia" está en amarillo para destacar
- El valor "644" está en rojo para indicar que es un problema
- El comando `chmod 600 .ejemplo.env` está en verde subrayado para facilitar su copia

### Principios de diseño

1. **Consistencia**: Los colores deben usarse de forma consistente en todo el proyecto
2. **Moderación**: El uso de colores debe ser moderado para evitar sobrecargar el output
3. **Accesibilidad**: Los colores complementan pero no reemplazan el contenido textual
4. **Propósito claro**: Cada color tiene un propósito específico y no debe usarse para otros fines

## 📦 Requisitos

- Bash (versión 4.0 o superior)
- Cliente MySQL (`mysql` y `mysqldump`)
- Docker (solo para restauración en contenedores)
- Acceso de lectura/escritura a la base de datos

### Verificar instalación

```bash
mysql --version
mysqldump --version
docker --version
```

## 🚀 Instalación

1. Otorga permisos de ejecución a los scripts:

```bash
chmod +x mysql-backup.sh
chmod +x mysql-restore-docker.sh
```

## ⚙️ Configuración

Antes de ejecutar los scripts, es necesario crear un archivo de configuración con extensión `.env` que contenga las conexiones a la base de datos.

### Crear archivo `.env`

1. Crea un archivo con extensión `.env` (por ejemplo: `.ejemplo.env`, `.produccion.env`, `.desarrollo.env`):
```bash
touch .ejemplo.env
```

2. Edita el archivo `.env` con tus credenciales reales. El formato es el siguiente:

### Variables Requeridas (para backup)

```env
# Configuración de conexión a la base de datos
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=tu_usuario
DB_PASS=tu_contraseña_segura
DB_NAME=nombre_base_datos
```

### Variables Opcionales (para restauración en Docker)

```env
# Configuración del contenedor Docker
DOCKER_IMAGE=mysql:8.0
DOCKER_CONTAINER_PORT=3306
DOCKER_HOST_PORT=10000
DOCKER_ROOT_PASSWORD=tu_password_root_seguro
DOCKER_RESTORE_USER=restore_user
DOCKER_RESTORE_PASS=tu_password_restore_seguro
DOCKER_CONTAINER_NAME=mysql-restore-container
```

> ⚠️ **IMPORTANTE**: Para información detallada sobre seguridad y mejores prácticas, consulta la sección [Seguridad](#-seguridad).

## 📝 Variables de Entorno

### Variables Requeridas

| Variable | Descripción | Ejemplo |
|----------|-------------|---------|
| `DB_HOST` | Host del servidor MySQL | `127.0.0.1` o `localhost` |
| `DB_PORT` | Puerto del servidor MySQL | `3306` |
| `DB_USER` | Usuario de la base de datos | `root` o `tu_usuario` |
| `DB_PASS` | Contraseña del usuario | `[tu_contraseña_segura]` |
| `DB_NAME` | Nombre de la base de datos | `nombre_base_datos` |

### Variables Opcionales para Docker

| Variable | Descripción | Valor por Defecto | Ejemplo |
|----------|-------------|-------------------|---------|
| `DOCKER_IMAGE` | Imagen Docker a utilizar | `mysql:8.0` | `mariadb:10.6` |
| `DOCKER_CONTAINER_PORT` | Puerto interno del contenedor | `3306` | `3306` |
| `DOCKER_HOST_PORT` | Puerto del host (si está vacío, se asigna automáticamente) | `3307` (auto) | `3307` |
| `DOCKER_ROOT_PASSWORD` | Contraseña del usuario root en el contenedor | `password` | `[tu_password_root_seguro]` |
| `DOCKER_RESTORE_USER` | Usuario para restaurar el backup | `DB_USER` o `root` | `restore_user` |
| `DOCKER_RESTORE_PASS` | Contraseña del usuario de restauración | `DB_PASS` o `password` | `restore_password` |
| `DOCKER_CONTAINER_NAME` | Nombre del contenedor (si está vacío, se genera automáticamente) | Auto-generado | `mysql-restore-container` |

### Ejemplo de archivo `.env` completo

```env
# Configuración de conexión a la base de datos
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=tu_usuario
DB_PASS=tu_contraseña_segura
DB_NAME=nombre_base_datos

# Configuración opcional para Docker
DOCKER_IMAGE=mariadb:10.6
DOCKER_CONTAINER_PORT=3306
DOCKER_HOST_PORT=10000
DOCKER_ROOT_PASSWORD=tu_password_root_seguro
DOCKER_RESTORE_USER=restore_user
DOCKER_RESTORE_PASS=tu_password_restore_seguro
DOCKER_CONTAINER_NAME=mysql-restore-container
```

## 💻 Uso

### Realizar un backup

Ejecuta el script desde el directorio `mysql-backup/` pasando el archivo `.env` como parámetro obligatorio:

```bash
./mysql-backup.sh <archivo.env>
```

**Ejemplos:**

```bash
# Usar un archivo de configuración específico
./mysql-backup.sh .ejemplo.env

# Usar otro archivo de configuración
./mysql-backup.sh .produccion.env

# Usar un archivo con nombre descriptivo
./mysql-backup.sh .bbdd_empresa1.env
```

⚠️ **Requisitos**:
- El archivo `.env` es **obligatorio** como parámetro
- El archivo **debe terminar en `.env`** por cuestiones de seguridad
- El archivo debe existir en la ruta especificada

El script:
1. Valida el archivo `.env` y sus permisos
2. Verifica la conexión a la base de datos
3. Muestra información de la base de datos
4. Solicita confirmación antes de continuar
5. Genera el backup comprimido
6. Guarda el archivo en `./backups/`

**Formato del archivo de backup:**
```
backups/[YYYY_MM_DD_HHMMSS]_[DB_NAME].sql.gz
```

### Restaurar en un contenedor Docker

Ejecuta el script desde el directorio `mysql-backup/` pasando el archivo `.env` como parámetro obligatorio:

```bash
./mysql-restore-docker.sh <archivo.env>
```

**Ejemplos:**

```bash
# Usar un archivo de configuración específico
./mysql-restore-docker.sh .ejemplo.env

# Usar otro archivo de configuración
./mysql-restore-docker.sh .produccion.env
```

⚠️ **Requisitos**:
- El archivo `.env` es **obligatorio** como parámetro
- El archivo **debe terminar en `.env`** por cuestiones de seguridad
- El archivo debe existir en la ruta especificada

El script:
1. Muestra los backups disponibles
2. Permite seleccionar uno
3. Crea un nuevo contenedor Docker
4. Restaura el backup en el contenedor
5. Muestra información de conexión

**Ventajas:**
- ✅ No afecta la base de datos original
- ✅ Aislamiento completo en un contenedor separado
- ✅ Fácil de eliminar cuando ya no lo necesites
- ✅ Múltiples restauraciones simultáneas en diferentes puertos

## 📝 Notas adicionales

- Los backups se guardan en `./backups/` con compresión gzip
- El formato del nombre del archivo de backup es: `YYYY_MM_DD_HHMMSS_[DB_NAME].sql.gz`
- Los contenedores Docker se pueden gestionar con los comandos estándar de Docker
- La restauración en Docker no afecta la base de datos original
- El script solicita confirmación antes de realizar el backup
- Puedes eliminar backups antiguos manualmente usando el comando sugerido al finalizar el backup

## 📊 Ejemplos

### Ejemplo 1: Backup básico

```bash
$ ./mysql-backup.sh .ejemplo.env

📄 Cargando variables desde: .ejemplo.env
🚀 Iniciando copia de seguridad de la base de datos...
📊 Base de datos: nombre_base_datos
📍 Servidor: 127.0.0.1:3306
👤 Usuario: tu_usuario

🔍 Verificando conexión con la base de datos...
✅ Conexión establecida correctamente

📋 Obteniendo información de la base de datos...
   Tablas encontradas: 150
   Tamaño aproximado: 250.50 MB

Esta operación generará una copia de seguridad de la base de datos.
¿Continuar? (s/n): s

💾 Generando copia de seguridad...
   Archivo: ./backups/2025_11_11_124902_nombre_base_datos.sql
🗜️  Comprimiendo backup...
✅ Backup comprimido correctamente

📊 RESUMEN DE LA COPIA DE SEGURIDAD:
   Base de datos: nombre_base_datos
   Archivo: ./backups/2025_11_11_124902_nombre_base_datos.sql.gz
   Tamaño: 45M
   Fecha: 2025-11-11 12:49:02

✅ Copia de seguridad completada exitosamente
```

### Ejemplo 2: Restauración en Docker

```bash
$ ./mysql-restore-docker.sh .ejemplo.env

📄 Cargando variables desde: .ejemplo.env
📦 Backups disponibles:

   [1] 2025_11_11_124902_nombre_base_datos.sql.gz (45M) - 2025-11-11 12:49:02
   [2] 2025_11_10_180530_nombre_base_datos.sql.gz (44M) - 2025-11-10 18:05:30

Selecciona el número del backup a restaurar: 1

🚀 Iniciando restauración en nuevo contenedor Docker...
📁 Backup seleccionado: 2025_11_11_124902_nombre_base_datos.sql.gz

🐳 Configuración del contenedor Docker:
   Imagen: mariadb:10.6
   Nombre del contenedor: mysql-restore-container
   Puerto: 3307:3306
   Usuario para restaurar: restore_user
   Base de datos: nombre_base_datos

🔨 Creando contenedor Docker...
⏳ Esperando a que MySQL/MariaDB esté listo...
✅ Contenedor iniciado correctamente

📋 Creando base de datos si no existe...
👤 Creando usuario para restauración...
💾 Descomprimiendo backup...
💾 Restaurando backup en el contenedor...
✅ Backup restaurado correctamente

📊 RESUMEN DE LA RESTAURACIÓN:
   Contenedor: mysql-restore-container
   Imagen: mariadb:10.6
   Base de datos: nombre_base_datos
   Tablas restauradas: 150
   Puerto: 3307

✅ Restauración completada exitosamente

🔌 INFORMACIÓN DE CONEXIÓN:
   Host: localhost
   Puerto: 3307
   Usuario: restore_user
   Contraseña: [configurada en .env]
   Base de datos: nombre_base_datos
```

## 🛠️ Solución de problemas

### Error: "No se ha especificado el archivo .env"

Debes pasar el archivo `.env` como parámetro obligatorio. Ejemplo:
```bash
./mysql-backup.sh .ejemplo.env
```

### Error: "El archivo debe terminar en .env por cuestiones de seguridad"

El archivo que pases como parámetro debe terminar en `.env`. Esto es una medida de seguridad para asegurar que los archivos de configuración sean ignorados por git. Ejemplo válido: `.ejemplo.env`, `.produccion.env`

### Error: "No se encontró el archivo .env"

Asegúrate de que el archivo `.env` especificado existe en la ruta indicada y contiene todas las variables requeridas. Verifica la ruta relativa o absoluta del archivo.

### Error: "Las siguientes variables requeridas no están definidas"

Verifica que todas las variables en el archivo `.env` estén correctamente definidas y no tengan espacios alrededor del signo `=`. Las variables requeridas son: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME`.

### Error: "No se pudo conectar a la base de datos"

- Verifica que las credenciales en `.env` sean correctas
- Asegúrate de que el servidor MySQL esté accesible
- Comprueba que el usuario tenga los permisos necesarios

### Error al crear el contenedor Docker

- Verifica que Docker esté instalado y funcionando: `docker --version`
- Asegúrate de que el puerto no esté en uso
- Comprueba que tengas permisos para ejecutar Docker

### El puerto ya está en uso

Si `DOCKER_HOST_PORT` está configurado y el puerto está en uso, el script intentará encontrar el siguiente puerto disponible. Deja `DOCKER_HOST_PORT` vacío para que el script asigne automáticamente un puerto disponible desde 3307.

## 🔒 Seguridad

La seguridad es una prioridad fundamental en este proyecto. Este script implementa múltiples capas de protección para garantizar el manejo seguro de credenciales y datos sensibles.

### Medidas de seguridad implementadas

Este proyecto implementa las siguientes medidas de seguridad:

- ✅ **Validación de path traversal**: Previene el acceso a archivos fuera del directorio del proyecto mediante validación de rutas
- ✅ **Validación de extensión `.env`**: Requiere que el archivo de configuración termine en `.env` para asegurar que sea ignorado por git
- ✅ **Validación de permisos**: Advierte si el archivo `.env` tiene permisos demasiado permisivos (mayores a 600)
- ✅ **Validación de formato**: Verifica que las variables en el archivo `.env` tengan el formato correcto (`VARIABLE=valor`) antes de exportarlas
- ✅ **Credenciales seguras**: Utiliza archivos temporales con permisos restrictivos (600) en lugar de pasar contraseñas por línea de comandos, evitando que aparezcan en la lista de procesos
- ✅ **Limpieza automática**: Elimina archivos temporales de forma segura (usando `shred` si está disponible, o sobrescritura y eliminación)
- ✅ **Limpieza de memoria**: Elimina variables sensibles (`DB_PASS`) de la memoria al finalizar la ejecución
- ✅ **Protección contra interrupciones**: Utiliza `trap` para garantizar la limpieza de archivos temporales incluso si el script se interrumpe (Ctrl+C) o termina inesperadamente
- ✅ **Validación de ejecución como root**: Advierte y solicita confirmación si el script se ejecuta como usuario root para minimizar riesgos de seguridad

### Configuración segura de archivos `.env`

⚠️ **IMPORTANTE**: 
- **El archivo DEBE terminar en `.env`** por cuestiones de seguridad. Los scripts validarán esto antes de ejecutarse.
- Los archivos que terminan en `.env` están incluidos en `.gitignore` para proteger tus credenciales. **Nunca** subas estos archivos al repositorio.
- Puedes crear múltiples archivos `.env` para diferentes entornos (por ejemplo: `.desarrollo.env`, `.produccion.env`, `.ejemplo.env`).
- **Se recomienda usar permisos restrictivos** en los archivos `.env`:
  ```bash
  chmod 600 .ejemplo.env
  ```

### Recomendaciones de seguridad

1. **Permisos del archivo `.env`**: Siempre usa `chmod 600` en tus archivos `.env` para restringir el acceso solo al propietario
2. **No compartir credenciales**: Nunca compartas archivos `.env` con credenciales reales, ni los subas a repositorios públicos
3. **Rotación de contraseñas**: Cambia las contraseñas de las bases de datos regularmente
4. **Usuarios con permisos mínimos**: Usa usuarios de base de datos con solo los permisos necesarios
5. **Revisar logs**: Revisa periódicamente los logs de acceso a las bases de datos para detectar accesos no autorizados
6. **No ejecutar como root**: Ejecuta el script con un usuario no privilegiado para minimizar riesgos en caso de compromiso
7. **Manejo de interrupciones**: Si interrumpes el script (Ctrl+C), los archivos temporales con credenciales se limpiarán automáticamente gracias al sistema de `trap`
8. **Backups seguros**: Los backups contienen datos sensibles, guárdalos de forma segura y con permisos restrictivos

## 🤝 Contribuir

Este proyecto está abierto a contribuciones. Si deseas participar en el desarrollo o mejorar el código, es **imprescindible** que:

1. **Leas y comprendas las [Normas de Estilo](#-normas-de-estilo)** antes de realizar cualquier modificación
2. Mantengas la consistencia en el uso de colores, emojis y formato del output
3. Respetes las medidas de seguridad implementadas
4. Documentes cualquier cambio significativo
5. Pruebes tus cambios antes de proponerlos

Las normas de estilo no son opcionales: son fundamentales para mantener la calidad, consistencia y seguridad del proyecto. Cualquier contribución que no siga estas normas será rechazada hasta que se ajuste a los estándares establecidos.

### Cómo contribuir

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/nueva-funcionalidad`)
3. Asegúrate de seguir las [Normas de Estilo](#-normas-de-estilo)
4. Realiza tus cambios y prueba exhaustivamente
5. Commit tus cambios (`git commit -m 'Agrega nueva funcionalidad'`)
6. Push a la rama (`git push origin feature/nueva-funcionalidad`)
7. Abre un Pull Request

---

**¿Encontraste un problema o tienes una sugerencia?** Abre un issue en el repositorio.


