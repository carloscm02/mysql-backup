# MySQL Backup & Restore

Herramientas en Bash para realizar copias de seguridad y restaurar bases de datos MySQL/MariaDB, con soporte para restauración en contenedores Docker.

## 📋 Tabla de Contenidos

- [Características](#-características)
- [Requisitos](#-requisitos)
- [Instalación](#-instalación)
- [Configuración](#-configuración)
- [Uso](#-uso)
- [Variables de Entorno](#-variables-de-entorno)

## ✨ Características

### mysql-backup.sh
- 💾 Generación automática de backups comprimidos
- 📊 Información detallada de la base de datos antes del backup
- 🗜️ Compresión automática (gzip)
- 🎨 Interfaz de línea de comandos con colores y emojis
- ✅ Validación de conexión antes de realizar el backup

### mysql-restore-docker.sh
- 🐳 Restauración en contenedores Docker aislados
- 🔧 Configuración flexible mediante variables de entorno
- 📦 Selección interactiva de backups
- 🔌 Asignación automática de puertos disponibles
- 👤 Creación automática de usuarios y bases de datos
- 🛡️ No afecta la base de datos original

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

Crea un archivo `.env` en el directorio `mysql-backup/` con las siguientes variables:

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

```bash
./mysql-backup.sh
```

El script:
1. Verifica la conexión a la base de datos
2. Muestra información de la base de datos
3. Genera el backup comprimido
4. Guarda el archivo en `./backups/`
5. Limpia backups antiguos (mantiene los últimos 10)

**Formato del archivo de backup:**
```
backups/[DB_NAME]_backup_[YYYY_MM_DD_HHMMSS].sql.gz
```

### Restaurar en un contenedor Docker

```bash
./mysql-restore-docker.sh
```

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

## 📊 Ejemplos

### Ejemplo 1: Backup básico

```bash
$ ./mysql-backup.sh

🚀 Iniciando copia de seguridad de la base de datos...
📊 Base de datos: nombre_base_datos
📍 Servidor: 127.0.0.1:3306
👤 Usuario: tu_usuario

🔍 Verificando conexión con la base de datos...
✅ Conexión establecida correctamente

📋 Obteniendo información de la base de datos...
   Tablas encontradas: 150
   Tamaño aproximado: 250.50 MB

   💾 Generando copia de seguridad...
   Archivo: ./backups/nombre_base_datos_backup_2025_11_11_124902.sql
🗜️  Comprimiendo backup...
✅ Backup comprimido correctamente

📊 RESUMEN DE LA COPIA DE SEGURIDAD:
   Base de datos: nombre_base_datos
   Archivo: ./backups/nombre_base_datos_backup_2025_11_11_124902.sql.gz
   Tamaño: 45M
   Fecha: 2025-11-11 12:49:02

✅ Copia de seguridad completada exitosamente
```

### Ejemplo 2: Restauración en Docker

```bash
$ ./mysql-restore-docker.sh

📦 Backups disponibles:

   [1] nombre_base_datos_backup_2025_11_11_124902.sql.gz (45M) - 2025-11-11 12:49:02
   [2] nombre_base_datos_backup_2025_11_10_180530.sql.gz (44M) - 2025-11-10 18:05:30

Selecciona el número del backup a restaurar: 1

🚀 Iniciando restauración en nuevo contenedor Docker...
📁 Backup seleccionado: nombre_base_datos_backup_2025_11_11_124902.sql.gz

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

### Error: "No se encontró el archivo .env"

Asegúrate de que el archivo `.env` existe en el directorio `mysql-backup/` y contiene todas las variables requeridas.

### Error: "No se pudo conectar a la base de datos"

- Verifica que las credenciales en `.env` sean correctas
- Asegúrate de que el servidor MySQL esté accesible
- Comprueba que el usuario tenga los permisos necesarios

### Error al crear el contenedor Docker

- Verifica que Docker esté instalado y funcionando: `docker --version`
- Asegúrate de que el puerto no esté en uso
- Comprueba que tengas permisos para ejecutar Docker

### El puerto ya está en uso

Si `DOCKER_HOST_PORT` está configurado y el puerto está en uso, el script mostrará un error. Deja `DOCKER_HOST_PORT` vacío para que el script asigne automáticamente un puerto disponible.

## 📝 Notas adicionales

- Los backups se guardan en `./backups/` con compresión gzip
- Se mantienen automáticamente los últimos 10 backups
- Los contenedores Docker se pueden gestionar con los comandos estándar de Docker
- La restauración en Docker no afecta la base de datos original
- El formato de timestamp del backup es: `YYYY_MM_DD_HHMMSS`

## 🔒 Seguridad

⚠️ **IMPORTANTE**: 
- El archivo `.env` contiene credenciales sensibles. **Nunca** lo subas al repositorio.
- Asegúrate de que el archivo `.env` tenga permisos restrictivos: `chmod 600 .env`
- Los backups contienen datos sensibles, guárdalos de forma segura

---

**¿Encontraste un problema o tienes una sugerencia?** Abre un issue en el repositorio.


