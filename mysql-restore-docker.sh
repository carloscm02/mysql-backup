#!/bin/bash

# Cargar variables de entorno desde .env
if [ -f .env ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            continue
        fi
        export "$line"
    done < .env
else
    echo "❌ Error: No se encontró el archivo .env"
    echo "   Por favor, crea un archivo .env con las variables de conexión"
    exit 1
fi

# Colores para el output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Directorio de backups
BACKUP_DIR="./backups"

if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}❌ Error${NC}: No se encontró el directorio de backups: $BACKUP_DIR"
    exit 1
fi

# Listar backups disponibles
BACKUPS=($(ls -t "$BACKUP_DIR"/*.sql.gz 2>/dev/null))

if [ ${#BACKUPS[@]} -eq 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se encontraron backups en $BACKUP_DIR"
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
        echo "❌ Operación cancelada"
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
echo "🐳 Configuración del contenedor Docker:"
echo -e "   Imagen: ${BLUE}$DOCKER_IMAGE${NC}"
echo -e "   Nombre del contenedor: ${BLUE}$CONTAINER_NAME${NC}"
echo -e "   Puerto: ${BLUE}$RESTORE_PORT:$DOCKER_CONTAINER_PORT${NC}"
echo -e "   Usuario para restaurar: ${BLUE}$DOCKER_RESTORE_USER${NC}"
echo -e "   Base de datos: ${BLUE}$RESTORE_DB${NC}"
echo ""

# Crear contenedor
echo "🔨 Creando contenedor Docker..."
docker run -d \
    --name "$CONTAINER_NAME" \
    -e MYSQL_ROOT_PASSWORD="$DOCKER_ROOT_PASSWORD" \
    -p "$RESTORE_PORT:$DOCKER_CONTAINER_PORT" \
    "$DOCKER_IMAGE" \
    >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se pudo crear el contenedor Docker"
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
    echo -e "${RED}❌ Error${NC}: MySQL/MariaDB no se inició correctamente en el contenedor"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
fi

echo "✅ Contenedor iniciado correctamente"
echo ""

# Crear base de datos si no existe
echo "📋 Creando base de datos si no existe..."
docker exec "$CONTAINER_NAME" mysql -uroot -p"$DOCKER_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS \`$RESTORE_DB\`;" 2>/dev/null

# Crear usuario para restaurar si no es root
if [ "$DOCKER_RESTORE_USER" != "root" ]; then
    echo "👤 Creando usuario para restauración..."
    docker exec "$CONTAINER_NAME" mysql -uroot -p"$DOCKER_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$DOCKER_RESTORE_USER'@'%' IDENTIFIED BY '$DOCKER_RESTORE_PASS';" 2>/dev/null
    docker exec "$CONTAINER_NAME" mysql -uroot -p"$DOCKER_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON \`$RESTORE_DB\`.* TO '$DOCKER_RESTORE_USER'@'%';" 2>/dev/null
    docker exec "$CONTAINER_NAME" mysql -uroot -p"$DOCKER_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" 2>/dev/null
fi

echo ""

# Descomprimir backup temporalmente para restaurar
TEMP_SQL="/tmp/restore_$(date +%s).sql"
echo "💾 Descomprimiendo backup..."
gunzip -c "$SELECTED_BACKUP" > "$TEMP_SQL"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se pudo descomprimir el backup"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
    rm -f "$TEMP_SQL"
    exit 1
fi

# Restaurar backup
echo "💾 Restaurando backup en el contenedor..."
docker exec -i "$CONTAINER_NAME" mysql -u"$DOCKER_RESTORE_USER" -p"$DOCKER_RESTORE_PASS" "$RESTORE_DB" < "$TEMP_SQL" 2>/dev/null

RESTORE_EXIT_CODE=$?

# Eliminar archivo temporal
rm -f "$TEMP_SQL"

if [ $RESTORE_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: Fallo al restaurar el backup"
    echo "   El contenedor se mantendrá activo para revisión"
    exit 1
fi

echo "✅ Backup restaurado correctamente"
echo ""

# Obtener información de la base de datos restaurada
TABLE_COUNT=$(docker exec "$CONTAINER_NAME" mysql -u"$DOCKER_RESTORE_USER" -p"$DOCKER_RESTORE_PASS" "$RESTORE_DB" -se "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$RESTORE_DB';" 2>/dev/null)

echo "📊 RESUMEN DE LA RESTAURACIÓN:"
echo "   Contenedor: $CONTAINER_NAME"
echo "   Imagen: $DOCKER_IMAGE"
echo "   Base de datos: $RESTORE_DB"
echo "   Tablas restauradas: $TABLE_COUNT"
echo "   Puerto: $RESTORE_PORT"
echo ""

echo -e "${GREEN}✅ Restauración completada exitosamente${NC}"
echo ""
echo "🔌 INFORMACIÓN DE CONEXIÓN:"
echo "   Host: localhost"
echo "   Puerto: $RESTORE_PORT"
echo "   Usuario: $DOCKER_RESTORE_USER"
echo "   Contraseña: $DOCKER_RESTORE_PASS"
echo "   Base de datos: $RESTORE_DB"
echo ""
echo "💡 Comandos útiles:"
echo "   Conectar: mysql -h localhost -P $RESTORE_PORT -u $DOCKER_RESTORE_USER -p$DOCKER_RESTORE_PASS $RESTORE_DB"
echo "   Detener contenedor: docker stop $CONTAINER_NAME"
echo "   Iniciar contenedor: docker start $CONTAINER_NAME"
echo "   Eliminar contenedor: docker rm -f $CONTAINER_NAME"
echo "   Ver logs: docker logs $CONTAINER_NAME"
echo ""
echo "🧹 COMANDOS PARA RECUPERAR ESPACIO EN DISCO:"
echo ""
echo "   🐳 Limpiar Docker (contenedores, imágenes, volúmenes no usados):"
echo "      docker system prune -af"
echo ""
