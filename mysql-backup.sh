#!/bin/bash

# Determinar qué archivo .env usar
# Si se pasa un segundo parámetro, usar ese archivo
# Si no, usar .env por defecto
ENV_FILE="${2:-.env}"

# Cargar variables de entorno desde el archivo .env especificado
if [ -f "$ENV_FILE" ]; then
    echo "📄 Cargando variables desde: $ENV_FILE"
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            continue
        fi
        export "$line"
    done < "$ENV_FILE"
else
    echo "❌ Error: No se encontró el archivo $ENV_FILE"
    echo "   Por favor, crea un archivo .env con las variables de conexión a la base de datos"
    echo "   O especifica un archivo .env como segundo parámetro: $0 [parametro1] archivo.env"
    exit 1
fi

# Colores para el output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
mkdir -p "$BACKUP_DIR"

# Generar nombre de archivo con timestamp
TIMESTAMP=$(date +"%Y_%m_%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/${TIMESTAMP}_${DB_NAME}.sql"
COMPRESSED_BACKUP="${BACKUP_FILE}.gz"

echo "🚀 Iniciando copia de seguridad de la base de datos..."
echo -e "📊 Base de datos: ${YELLOW}$DB_NAME${NC}"
echo -e "📍 Servidor: ${YELLOW}$DB_HOST${NC}:${YELLOW}$DB_PORT${NC}"
echo -e "👤 Usuario: ${YELLOW}$DB_USER${NC}"
echo ""

# Verificar conexión antes de continuar
echo "🔍 Verificando conexión con la base de datos..."
mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --password="$DB_PASS" -e "SELECT 1;" "$DB_NAME" >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se pudo conectar a la base de datos"
    echo "   Verifica las credenciales y que el servidor esté accesible"
    exit 1
fi

echo "✅ Conexión establecida correctamente"
echo ""

# Obtener información de la base de datos
echo "📋 Obteniendo información de la base de datos..."
TABLE_COUNT=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --password="$DB_PASS" "$DB_NAME" -se "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$DB_NAME';" 2>/dev/null)
DB_SIZE=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --password="$DB_PASS" "$DB_NAME" -se "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'DB Size in MB' FROM information_schema.tables WHERE table_schema = '$DB_NAME';" 2>/dev/null)

echo "   Tablas encontradas: $TABLE_COUNT"
echo "   Tamaño aproximado: ${DB_SIZE} MB"
echo ""

# Confirmación antes de continuar
echo "Esta operación generará una copia de seguridad de la base de datos."
read -p "¿Continuar? (s/n): " confirmacion

if [[ "$confirmacion" != "s" && "$confirmacion" != "S" ]]; then
    echo "❌ Operación cancelada por el usuario"
    echo ""
    exit 0
fi

# Realizar backup
echo "💾 Generando copia de seguridad..."
echo -e "   Archivo: ${BLUE}$BACKUP_FILE${NC}"

mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --password="$DB_PASS" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --quick \
    --lock-tables=false \
    "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: Fallo al generar la copia de seguridad"
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Comprimir backup
echo "🗜️  Comprimiendo backup..."
gzip -f "$BACKUP_FILE"

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Advertencia${NC}: No se pudo comprimir el backup, pero el archivo SQL se guardó correctamente"
    COMPRESSED_BACKUP="$BACKUP_FILE"
else
    echo "✅ Backup comprimido correctamente"
fi

# Obtener tamaño del archivo final
FINAL_SIZE=$(du -h "$COMPRESSED_BACKUP" | cut -f1)

echo ""
echo "📊 RESUMEN DE LA COPIA DE SEGURIDAD:"
echo "   Base de datos: $DB_NAME"
echo "   Archivo: $COMPRESSED_BACKUP"
echo "   Tamaño: $FINAL_SIZE"
echo "   Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo -e "${GREEN}✅ Copia de seguridad completada exitosamente${NC}"
echo ""
echo "🧹 COMANDOS PARA RECUPERAR ESPACIO EN DISCO:"
echo ""
echo "   📦 Eliminar backups anteriores a 20 días:"
echo "      find ./backups -name '*.sql.gz' -type f -mtime +20 -delete"
echo ""
echo "💡 Opciones de restauración:"
echo ""
echo "   🔄 Restaurar en nuevo contenedor Docker (recomendado - conserva la BD original):"
echo "      ./mysql-restore-docker.sh"
echo ""
echo "   ⚠️  Restaurar directamente (SOBREESCRIBE la base de datos actual):"
echo "      gunzip < $COMPRESSED_BACKUP | mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p $DB_NAME"
echo ""




