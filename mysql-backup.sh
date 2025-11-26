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
    unset DB_PASS env_vars
    TEMP_FILES=()
}

# Configurar trap para limpiar en caso de salida normal, interrupción o terminación
trap cleanup_on_exit EXIT INT TERM

# Verificar que el script no se ejecute como root
if [ "$EUID" -eq 0 ]; then
    echo "⚠️  Advertencia: No se recomienda ejecutar este script como root"
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
        echo "⚠️  Advertencia: Línea con formato inválido ignorada: ${line:0:50}..."
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

# Función para crear archivo temporal de configuración MySQL
create_mysql_config() {
    local host=$1
    local port=$2
    local user=$3
    local pass=$4
    
    # Crear archivo temporal de credenciales
    local temp_cnf=$(mktemp)
    chmod 600 "$temp_cnf"
    cat > "$temp_cnf" << EOF
[client]
host=$host
port=${port:-3306}
user=$user
password=$pass
EOF
    
    # Agregar a la lista de archivos temporales para limpieza
    TEMP_FILES+=("$temp_cnf")
    
    echo "$temp_cnf"
}

# Crear archivo de configuración temporal
MYSQL_CNF=$(create_mysql_config "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS")

# Verificar conexión antes de continuar
echo "🔍 Verificando conexión con la base de datos..."
mysql --defaults-file="$MYSQL_CNF" -e "SELECT 1;" "$DB_NAME" >/dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error${NC}: No se pudo conectar a la base de datos"
    echo "   Verifica las credenciales y que el servidor esté accesible"
    exit 1
fi

echo "✅ Conexión establecida correctamente"
echo ""

# Obtener información de la base de datos
echo "📋 Obteniendo información de la base de datos..."
TABLE_COUNT=$(mysql --defaults-file="$MYSQL_CNF" "$DB_NAME" -se "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$DB_NAME';" 2>/dev/null)
DB_SIZE=$(mysql --defaults-file="$MYSQL_CNF" "$DB_NAME" -se "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'DB Size in MB' FROM information_schema.tables WHERE table_schema = '$DB_NAME';" 2>/dev/null)

echo "   Tablas encontradas: $TABLE_COUNT"
echo "   Tamaño aproximado: ${DB_SIZE} MB"
echo ""

# Confirmación antes de continuar
echo "Esta operación generará una copia de seguridad de la base de datos."
read -p "¿Continuar? (s/n): " confirmacion

if [[ "$confirmacion" != "s" && "$confirmacion" != "S" ]]; then
    echo -e "${RED}❌ Operación cancelada por el usuario${NC}"
    echo ""
    exit 0
fi

# Realizar backup
echo "💾 Generando copia de seguridad..."
echo -e "   Archivo: ${GREEN}$BACKUP_FILE${NC}"

mysqldump --defaults-file="$MYSQL_CNF" \
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
echo -e "${BLUE}📊 RESUMEN DE LA COPIA DE SEGURIDAD:${NC}"
echo "   Base de datos: $DB_NAME"
echo -e "   Archivo: ${GREEN}$COMPRESSED_BACKUP${NC}"
echo "   Tamaño: $FINAL_SIZE"
echo "   Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo -e "${GREEN}✅ Copia de seguridad completada exitosamente${NC}"
echo ""

# Calcular y mostrar el tamaño total de todas las copias de seguridad
TOTAL_BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
if [ -n "$TOTAL_BACKUP_SIZE" ]; then
    echo -e "📦 ${BLUE}Tamaño total de todas las copias de seguridad: ${YELLOW}$TOTAL_BACKUP_SIZE${NC}"
else
    echo -e "📦 ${BLUE}Tamaño total de todas las copias de seguridad: ${YELLOW}No disponible${NC}"
fi
echo ""

echo -e "${BLUE}🧹 COMANDOS PARA RECUPERAR ESPACIO EN DISCO:${NC}"
echo ""
echo -e "   📦 ${BLUE}Eliminar backups anteriores a 20 días:${NC}"
echo -e "      ${GREEN}find ./backups -name '*.sql.gz' -type f -mtime +20 -delete${NC}"
echo ""
echo "💡 Opciones de restauración:"
echo ""
echo -e "   🔄 ${BLUE}Restaurar en nuevo contenedor Docker (recomendado - conserva la BD original):${NC}"
echo -e "      ${GREEN}./mysql-restore-docker.sh $ENV_FILE${NC}"
echo ""
echo -e "   ⚠️  ${BLUE}Restaurar directamente (SOBREESCRIBE la base de datos actual):${NC}"
echo -e "      ${GREEN}gunzip < $COMPRESSED_BACKUP | mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p $DB_NAME${NC}"
echo ""




