#!/bin/bash

# Colores para el output
GREEN='\033[4;32m' # Verde subrayado
RED='\033[0;31m' # Rojo
YELLOW='\033[1;33m' # Amarillo negrita
BLUE='\033[0;34m' # Azul
NC='\033[0m' # Sin color

# Variable global para almacenar archivos temporales que necesitan limpieza
declare -a TEMP_FILES=()

# Función de limpieza para ejecutar al salir o interrumpir
cleanup_on_exit() {
    # Limpiar archivos temporales de credenciales
    for temp_file in "${TEMP_FILES[@]}"; do
        if [ -n "$temp_file" ] && [ -f "$temp_file" ]; then
            if command -v shred >/dev/null 2>&1; then
                shred -u "$temp_file" 2>/dev/null || rm -f "$temp_file"
            else
                # Si shred no está disponible, sobrescribir y eliminar
                echo "" > "$temp_file"
                rm -f "$temp_file"
            fi
        fi
    done
    # Limpiar variables sensibles
    unset DB_PASS DOCKER_ROOT_PASSWORD DOCKER_RESTORE_PASS env_vars
    TEMP_FILES=()
}

# Configurar trap para limpiar en caso de salida normal, interrupción o terminación
trap cleanup_on_exit EXIT INT TERM

# Verificar que el script no se ejecute como root
if [ "$EUID" -eq 0 ]; then
    echo -e "⚠️  ${YELLOW}Advertencia${NC}: No se recomienda ejecutar este script como root"
    echo "   Ejecutar como root puede ser un riesgo de seguridad"
    read -p "¿Continuar de todos modos? (s/n): " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        exit 1
    fi
fi

# Verificar que se haya pasado el archivo .env como parámetro
if [ -z "$1" ]; then
    echo -e "${RED}❌ Error${NC}: No se ha especificado el archivo .env"
    echo -e "   ${BLUE}Uso:${NC} ${GREEN}$0 <archivo.env>${NC}"
    echo -e "   ${BLUE}Ejemplo:${NC} ${GREEN}$0 .ejemplo.env${NC}"
    exit 1
fi

ENV_FILE="$1"

# Validar que no contenga path traversal (../ o rutas absolutas peligrosas)
if [[ "$ENV_FILE" =~ \.\./ ]] || [[ "$ENV_FILE" =~ ^/ ]]; then
    echo -e "${RED}❌ Error${NC}: El archivo .env debe estar en el directorio actual o subdirectorios"
    echo "[por medidas de seguridad] NO se permiten rutas absolutas o path traversal (../)"
    exit 1
fi

# Convertir a ruta absoluta y validar
ENV_FILE=$(realpath "$ENV_FILE" 2>/dev/null || echo "$ENV_FILE")
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Verificar que el archivo termine en .env por cuestiones de seguridad
if [[ ! "$ENV_FILE" =~ \.env$ ]]; then
    echo -e "${RED}❌ Error${NC}: El archivo debe terminar en .env por cuestiones de seguridad"
    echo "   Los archivos .env son ignorados por git para proteger información sensible"
    echo -e "   ${BLUE}Uso:${NC} ${GREEN}$0 <archivo.env>${NC}"
    echo -e "   ${BLUE}Ejemplo:${NC} ${GREEN}$0 .ejemplo.env${NC}"
    exit 1
fi

# Verificar que el archivo existe
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}❌ Error${NC}: No se encontró el archivo ${GREEN}$ENV_FILE${NC}"
    echo "   Por favor, verifica que el archivo existe y la ruta es correcta"
    exit 1
fi

# Verificar permisos del archivo (debe ser 600 o más restrictivo)
FILE_PERMS=$(stat -c "%a" "$ENV_FILE" 2>/dev/null || stat -f "%OLp" "$ENV_FILE" 2>/dev/null)
if [ -n "$FILE_PERMS" ] && [ "$FILE_PERMS" -gt 600 ]; then
    echo -e "⚠️  ${YELLOW}Advertencia${NC}: El archivo $ENV_FILE tiene permisos ${RED}$FILE_PERMS${NC}"
    echo -e "   Se recomienda usar ${YELLOW}permisos 600${NC} (${GREEN}chmod 600 $ENV_FILE${NC}) para mayor seguridad"
    read -p "¿Continuar de todos modos? (s/n): " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        exit 1
    fi
fi

# Función para validar formato de variable
validate_env_line() {
    local line="$1"
    # Debe tener formato VARIABLE=valor (sin espacios alrededor del =)
    if [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*$ ]]; then
        return 0
    fi
    return 1
}

# Cargar variables de entorno desde el archivo .env especificado
echo ""
echo -e "📄 Cargando variables desde: ${GREEN}$ENV_FILE${NC}"
declare -A env_vars
while IFS= read -r line || [ -n "$line" ]; do
    # Ignorar comentarios y líneas vacías
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
        continue
    fi
    # Validar formato antes de procesar
    if ! validate_env_line "$line"; then
        echo -e "⚠️  ${YELLOW}Advertencia${NC}: Línea con formato inválido ignorada: ${line:0:50}..."
        continue
    fi
    # Extraer nombre de variable y valor de forma segura
    var_name="${line%%=*}"
    var_name="${var_name// /}"  # Eliminar espacios
    var_value="${line#*=}"
    env_vars["$var_name"]="$var_value"
done < "$ENV_FILE"

# Exportar variables validadas
for var_name in "${!env_vars[@]}"; do
    export "$var_name=${env_vars[$var_name]}"
done

# Variables requeridas
REQUIRED_VARS=(DB_HOST DB_PORT DB_USER DB_PASS DB_NAME)

# Validar variables requeridas
missing_vars=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: Las siguientes variables requeridas no están definidas:"
    for var in "${missing_vars[@]}"; do
        echo -e "   ${YELLOW}$var${NC}"
    done
    exit 1
fi

# Directorio de backups
BACKUP_DIR="./backups"

if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}❌ Error${NC}: No se encontró el directorio de backups: ${GREEN}$BACKUP_DIR${NC}"
    exit 1
fi

# Listar backups disponibles
BACKUPS=($(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null))

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se encontraron backups en ${GREEN}$BACKUP_DIR${NC}"
    exit 1
fi

echo "📦 Backups disponibles:"
echo ""
for i in "${!BACKUPS[@]}"; do
    BACKUP_FILE="${BACKUPS[$i]}"
    BACKUP_NAME=$(basename "$BACKUP_FILE")
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    BACKUP_DATE=$(stat -c %y "$BACKUP_FILE" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
    echo "   [$((i+1))] $BACKUP_NAME ($BACKUP_SIZE) - $BACKUP_DATE"
done
echo ""

# Seleccionar backup
read -p "Selecciona el número del backup a restaurar: " SELECTION

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#BACKUPS[@]} ]; then
    echo -e "${RED}❌ Error${NC}: Selección inválida"
    exit 1
fi

SELECTED_BACKUP="${BACKUPS[$((SELECTION-1))]}"
BACKUP_NAME=$(basename "$SELECTED_BACKUP" .sql.gz)

echo ""
echo "🚀 Iniciando restauración en nuevo contenedor Docker..."
echo -e "📁 Backup seleccionado: ${YELLOW}$(basename "$SELECTED_BACKUP")${NC}"
echo ""

# Configuración del contenedor Docker desde .env o valores por defecto
DOCKER_IMAGE="${DOCKER_IMAGE:-mysql:8.0}"
DOCKER_CONTAINER_PORT="${DOCKER_CONTAINER_PORT:-3306}"
DOCKER_HOST_PORT="${DOCKER_HOST_PORT:-}"
DOCKER_ROOT_PASSWORD="${DOCKER_ROOT_PASSWORD:-password}"
DOCKER_RESTORE_USER="${DOCKER_RESTORE_USER:-${DB_USER:-root}}"
DOCKER_RESTORE_PASS="${DOCKER_RESTORE_PASS:-${DB_PASS:-password}}"
DOCKER_CONTAINER_NAME="${DOCKER_CONTAINER_NAME:-}"

# Generar nombre del contenedor si no está configurado
if [ -z "$DOCKER_CONTAINER_NAME" ]; then
    CONTAINER_NAME="mysql-restore-$(echo "$BACKUP_NAME" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
    CONTAINER_NAME="${CONTAINER_NAME:0:63}"
else
    CONTAINER_NAME="$DOCKER_CONTAINER_NAME"
fi

# Verificar si el contenedor ya existe
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${YELLOW}⚠️  Advertencia${NC}: Ya existe un contenedor con el nombre: $CONTAINER_NAME"
    read -p "¿Deseas eliminarlo y crear uno nuevo? (s/n): " CONFIRM
    
    if [[ "$CONFIRM" == "s" || "$CONFIRM" == "S" ]]; then
        echo "🗑️  Eliminando contenedor existente..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    else
        echo -e "${RED}❌ Operación cancelada${NC}"
        exit 0
    fi
fi

# Obtener puerto del host disponible si no está configurado
if [ -z "$DOCKER_HOST_PORT" ]; then
    DEFAULT_PORT=3307
    RESTORE_PORT=$DEFAULT_PORT
    PORT_COUNTER=1
    
    while docker ps --format '{{.Ports}}' | grep -q ":${RESTORE_PORT}->"; do
        RESTORE_PORT=$((DEFAULT_PORT + PORT_COUNTER))
        PORT_COUNTER=$((PORT_COUNTER + 1))
        
        if [ $PORT_COUNTER -gt 100 ]; then
            echo -e "${RED}❌ Error${NC}: No se pudo encontrar un puerto disponible"
            exit 1
        fi
    done
else
    RESTORE_PORT="$DOCKER_HOST_PORT"

    # Si el puerto está en uso, ir probando el siguiente inmediatamente superior hasta encontrar el más cercano libre
    PORT_ATTEMPTS=0
    ORIGINAL_RESTORE_PORT="$RESTORE_PORT"
    while docker ps --format '{{.Ports}}' | grep -q ":${RESTORE_PORT}->"; do
        echo -e "⚠️  El puerto ${YELLOW}$RESTORE_PORT ${NC}ya está en uso."

        PORT_ATTEMPTS=$((PORT_ATTEMPTS + 1))
        RESTORE_PORT=$((RESTORE_PORT + 1))

        if [ $PORT_ATTEMPTS -gt 100 ]; then
            echo -e "${RED}❌ Error${NC}: No se pudo encontrar un puerto disponible después de probar 100 puertos consecutivos desde $ORIGINAL_RESTORE_PORT"
            exit 1
        fi
        echo -e "${YELLOW}🔄 Intentando con el puerto $RESTORE_PORT...${NC}"
        sleep 2
    done

fi

# Base de datos a restaurar
RESTORE_DB="${DB_NAME}"

echo ""
echo -e "${BLUE}🐳 Configuración del contenedor Docker:${NC}"
echo -e "   Imagen: ${YELLOW}$DOCKER_IMAGE${NC}"
echo -e "   Nombre del contenedor: ${YELLOW}$CONTAINER_NAME${NC}"
echo -e "   Puerto: ${YELLOW}$RESTORE_PORT:$DOCKER_CONTAINER_PORT${NC}"
echo -e "   Usuario para restaurar: ${YELLOW}$DOCKER_RESTORE_USER${NC}"
echo -e "   Base de datos: ${YELLOW}$RESTORE_DB${NC}"
echo ""

# Crear contenedor
echo "🔨 Creando contenedor Docker..."
CONTAINER_CREATE_OUTPUT=$(docker run -d \
    --name "$CONTAINER_NAME" \
    -e MYSQL_ROOT_PASSWORD="$DOCKER_ROOT_PASSWORD" \
    -p "$RESTORE_PORT:$DOCKER_CONTAINER_PORT" \
    "$DOCKER_IMAGE" \
    2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se pudo crear el contenedor Docker"
    echo "   Detalles: $CONTAINER_CREATE_OUTPUT"
    echo "   Verifica que Docker esté instalado y funcionando"
    exit 1
fi

echo "⏳ Esperando a que MySQL/MariaDB esté listo..."
sleep 5

# Esperar a que MySQL/MariaDB esté completamente iniciado
MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if docker exec "$CONTAINER_NAME" mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 1
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    echo -e "${RED}❌ Error${NC}: MySQL/MariaDB no se inició correctamente en el contenedor después de $MAX_ATTEMPTS intentos"
    echo ""
    echo "📄 Últimos logs del contenedor:"
    docker logs --tail 20 "$CONTAINER_NAME" 2>&1
    echo ""
    echo -e "   Para ver todos los logs: ${GREEN}docker logs $CONTAINER_NAME${NC}"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

echo "✅ Contenedor iniciado correctamente"
echo ""

# Crear base de datos si no existe
echo "📋 Creando base de datos si no existe..."
DB_CREATE_OUTPUT=$(docker exec "$CONTAINER_NAME" mysql -uroot -p"$DOCKER_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$RESTORE_DB\`;" 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se pudo crear la base de datos"
    echo "   Detalles: $DB_CREATE_OUTPUT"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

# Crear usuario para restaurar si no es root
if [ "$DOCKER_RESTORE_USER" != "root" ]; then
    echo "👤 Creando usuario para restauración..."
    USER_CREATE_OUTPUT=$(docker exec "$CONTAINER_NAME" mysql -uroot -p"$DOCKER_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$DOCKER_RESTORE_USER'@'%' IDENTIFIED BY '$DOCKER_RESTORE_PASS';" 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}⚠️  Advertencia${NC}: No se pudo crear el usuario (puede que ya exista)"
        echo "   Detalles: $USER_CREATE_OUTPUT"
    fi
    
    GRANT_OUTPUT=$(docker exec "$CONTAINER_NAME" mysql -uroot -p"$DOCKER_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`$RESTORE_DB\`.* TO '$DOCKER_RESTORE_USER'@'%';" 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error${NC}: No se pudieron otorgar privilegios al usuario"
        echo "   Detalles: $GRANT_OUTPUT"
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
        exit 1
    fi
    
    FLUSH_OUTPUT=$(docker exec "$CONTAINER_NAME" mysql -uroot -p"$DOCKER_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}⚠️  Advertencia${NC}: No se pudieron refrescar los privilegios"
        echo "   Detalles: $FLUSH_OUTPUT"
    fi
fi

echo ""

# Descomprimir backup temporalmente para restaurar
TEMP_SQL="/tmp/restore_$(date +%s).sql"
# Agregar a la lista de archivos temporales para limpieza
TEMP_FILES+=("$TEMP_SQL")

echo "💾 Descomprimiendo backup..."
DECOMPRESS_OUTPUT=$(gunzip -c "$SELECTED_BACKUP" > "$TEMP_SQL" 2>&1)
DECOMPRESS_EXIT_CODE=$?

if [ $DECOMPRESS_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se pudo descomprimir el backup"
    echo "   Detalles: $DECOMPRESS_OUTPUT"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    rm -f "$TEMP_SQL"
    exit 1
fi

# Verificar que el archivo SQL se creó correctamente
if [ ! -f "$TEMP_SQL" ]; then
    echo -e "${RED}❌ Error${NC}: El archivo SQL temporal no se creó"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

SQL_SIZE=$(du -h "$TEMP_SQL" | cut -f1)
echo "   Archivo SQL descomprimido: $SQL_SIZE"
echo ""

# Verificar conexión antes de restaurar
echo "🔍 Verificando conexión con la base de datos antes de restaurar..."
CONNECTION_TEST=$(docker exec "$CONTAINER_NAME" mysql -u"$DOCKER_RESTORE_USER" -p"$DOCKER_RESTORE_PASS" -e "SELECT 1;" "$RESTORE_DB" 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se pudo conectar a la base de datos antes de restaurar"
    echo "   Detalles: $CONNECTION_TEST"
    echo "   Usuario: $DOCKER_RESTORE_USER"
    echo "   Base de datos: $RESTORE_DB"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    rm -f "$TEMP_SQL"
    exit 1
fi
echo "✅ Conexión verificada correctamente"
echo ""

# Restaurar backup
echo "💾 Restaurando backup en el contenedor..."
echo "   Esto puede tardar varios minutos dependiendo del tamaño del backup..."
RESTORE_OUTPUT=$(docker exec -i "$CONTAINER_NAME" mysql -u"$DOCKER_RESTORE_USER" -p"$DOCKER_RESTORE_PASS" "$RESTORE_DB" < "$TEMP_SQL" 2>&1)
RESTORE_EXIT_CODE=$?

# Eliminar archivo temporal de forma segura
if [ -f "$TEMP_SQL" ]; then
    if command -v shred >/dev/null 2>&1; then
        shred -u "$TEMP_SQL" 2>/dev/null || rm -f "$TEMP_SQL"
    else
        echo "" > "$TEMP_SQL"
        rm -f "$TEMP_SQL"
    fi
    # Remover de la lista de archivos temporales ya que se eliminó manualmente
    TEMP_FILES=("${TEMP_FILES[@]/$TEMP_SQL}")
fi

if [ $RESTORE_EXIT_CODE -ne 0 ]; then
    echo ""
    echo -e "${RED}❌ Error${NC}: Fallo al restaurar el backup"
    echo ""
    echo "📋 Detalles del error:"
    echo "$RESTORE_OUTPUT" | head -50
    if [ $(echo "$RESTORE_OUTPUT" | wc -l) -gt 50 ]; then
        echo "... (mostrando solo las primeras 50 líneas)"
    fi
    echo ""
    echo "🔍 Información de depuración:"
    echo "   Contenedor: $CONTAINER_NAME"
    echo "   Usuario: $DOCKER_RESTORE_USER"
    echo "   Base de datos: $RESTORE_DB"
    echo "   Archivo backup: $SELECTED_BACKUP"
    echo "   Tamaño SQL descomprimido: $SQL_SIZE"
    echo ""
    echo -e "📄 ${BLUE}Para ver los logs del contenedor:${NC}"
    echo -e "   ${GREEN}docker logs $CONTAINER_NAME${NC}"
    echo ""
    echo -e "🔌 ${BLUE}Para conectarte y revisar manualmente:${NC}"
    echo -e "   ${GREEN}docker exec -it $CONTAINER_NAME mysql -u$DOCKER_RESTORE_USER -p$DOCKER_RESTORE_PASS $RESTORE_DB${NC}"
    echo ""
    echo "   El contenedor se mantendrá activo para revisión"
    exit 1
fi

echo "✅ Backup restaurado correctamente"
echo ""

# Obtener información de la base de datos restaurada
TABLE_COUNT=$(docker exec "$CONTAINER_NAME" mysql -u"$DOCKER_RESTORE_USER" -p"$DOCKER_RESTORE_PASS" "$RESTORE_DB" -se "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$RESTORE_DB';" 2>/dev/null)

echo -e "${BLUE}📊 RESUMEN DE LA RESTAURACIÓN:${NC}"
echo "   Contenedor: $CONTAINER_NAME"
echo "   Imagen: $DOCKER_IMAGE"
echo "   Base de datos: $RESTORE_DB"
echo "   Tablas restauradas: $TABLE_COUNT"
echo "   Puerto: $RESTORE_PORT"
echo ""

echo -e "${GREEN}✅ Restauración completada exitosamente${NC}"
echo ""
echo -e "${BLUE}🔌 INFORMACIÓN DE CONEXIÓN:${NC}"
echo "   Host: localhost"
echo "   Puerto: $RESTORE_PORT"
echo "   Usuario: $DOCKER_RESTORE_USER"
echo "   Contraseña: $DOCKER_RESTORE_PASS"
echo "   Base de datos: $RESTORE_DB"
echo ""
echo -e "${BLUE}💡 Comandos útiles:${NC}"
echo -e "   Conectar: ${GREEN}mysql -h localhost -P $RESTORE_PORT -u $DOCKER_RESTORE_USER -p$DOCKER_RESTORE_PASS $RESTORE_DB${NC}"
echo -e "   Detener contenedor: ${GREEN}docker stop $CONTAINER_NAME${NC}"
echo -e "   Iniciar contenedor: ${GREEN}docker start $CONTAINER_NAME${NC}"
echo -e "   Eliminar contenedor: ${GREEN}docker rm -f $CONTAINER_NAME${NC}"
echo -e "   Ver logs: ${GREEN}docker logs $CONTAINER_NAME${NC}"
echo ""
echo -e "${BLUE}🧹 COMANDOS PARA RECUPERAR ESPACIO EN DISCO:${NC}"
echo ""
echo -e "   🐳 ${BLUE}Limpiar Docker (contenedores, imágenes, volúmenes no usados):${NC}"
echo -e "      ${GREEN}docker system prune -af${NC}"
echo ""
