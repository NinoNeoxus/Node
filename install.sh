#!/bin/bash

# =======================
#  SCHNUFFELLLL NODE SETUP (DB-AWARE)
# =======================

# Warna
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PTERO_DIR="/var/www/pterodactyl"

DB_HOST=""
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASS=""

# ─────────────────────────────
# Banner / welcome
# ─────────────────────────────
display_welcome() {
  clear
  echo -e ""
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e "${BLUE}[+]                                                 [+]${NC}"
  echo -e "${BLUE}[+]           AUTO CREATE NODE PTERODACTYL         [+]${NC}"
  echo -e "${BLUE}[+]                 © schnuffelll.dev              [+]${NC}"
  echo -e "${BLUE}[+]                                                 [+]${NC}"
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e ""
  echo -e "Script ini dibuat untuk mempermudah pembuatan Location + Node di panel Pterodactyl."
  echo -e "Versi ini baca DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD dari .env."
  echo -e ""
  sleep 2
}

# ─────────────────────────────
# Cek & install dependency (jq + mysql-client)
# ─────────────────────────────
install_dependencies() {
  local installed=0

  echo -e ""
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e "${BLUE}[+]          CEK & INSTALL DEPENDENCIES           [+]${NC}"
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e ""

  # jq
  if ! command -v jq >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] jq belum terinstall, install dulu...${NC}"
    apt update && apt install -y jq
    if [ $? -ne 0 ]; then
      echo -e "${RED}[!] Gagal install jq${NC}"
      exit 1
    fi
    installed=1
  else
    echo -e "${GREEN}[+] jq sudah terinstall${NC}"
  fi

  # mysql-client
  if ! command -v mysql >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] mysql-client belum terinstall, install dulu...${NC}"
    apt update && apt install -y mysql-client
    if [ $? -ne 0 ]; then
      echo -e "${RED}[!] Gagal install mysql-client${NC}"
      exit 1
    fi
    installed=1
  else
    echo -e "${GREEN}[+] mysql-client sudah terinstall${NC}"
  fi

  if [ $installed -eq 1 ]; then
    echo -e "${GREEN}[+] Semua dependencies sudah siap${NC}"
  fi

  echo -e ""
  sleep 1
}

# ─────────────────────────────
# Helper: baca value dari .env dan buang quote
# ─────────────────────────────
get_env_value() {
  local key="$1"
  local file="$2"
  grep -E "^${key}=" "$file" | head -n1 | sed "s/^${key}=//" | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//"
}

# ─────────────────────────────
# Baca kredensial DB dari .env
# ─────────────────────────────
load_db_env() {
  local env_file="${PTERO_DIR}/.env"

  if [ ! -f "${env_file}" ]; then
    echo -e "${RED}[!] File ${env_file} tidak ditemukan.${NC}"
    echo -e "${YELLOW}[!] Jalankan script ini di server panel yang punya instalasi Pterodactyl.${NC}"
    exit 1
  fi

  DB_HOST=$(get_env_value "DB_HOST" "${env_file}")
  DB_PORT=$(get_env_value "DB_PORT" "${env_file}")
  DB_NAME=$(get_env_value "DB_DATABASE" "${env_file}")
  DB_USER=$(get_env_value "DB_USERNAME" "${env_file}")
  DB_PASS=$(get_env_value "DB_PASSWORD" "${env_file}")

  # Default fallback
  [ -z "$DB_HOST" ] && DB_HOST="127.0.0.1"
  [ -z "$DB_PORT" ] && DB_PORT="3306"

  if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
    echo -e "${RED}[!] Gagal baca kredensial DB dari .env${NC}"
    echo -e "${YELLOW}[!] Pastikan DB_DATABASE, DB_USERNAME, dan DB_PASSWORD terisi.${NC}"
    exit 1
  fi

  echo -e "${BLUE}[+] Tes koneksi ke DB Pterodactyl...${NC}"
  if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "USE \`$DB_NAME\`" >/dev/null 2>&1; then
    echo -e "${RED}[!] Tidak bisa connect ke DB Pterodactyl${NC}"
    echo -e "${YELLOW}[!] Host : ${DB_HOST}:${DB_PORT}${NC}"
    echo -e "${YELLOW}[!] User : ${DB_USER}${NC}"
    echo -e "${YELLOW}[!] Cek service MySQL & kredensial di .env${NC}"
    exit 1
  fi

  echo -e "${GREEN}[+] Koneksi ke DB Pterodactyl berhasil (${DB_HOST}:${DB_PORT} / ${DB_NAME})${NC}"
}

# ─────────────────────────────
# Bikin allocation port untuk node
# ─────────────────────────────
create_allocations() {
  local NODE_ID=$1
  local START_PORT=$2
  local END_PORT=$3

  echo -e ""
  echo -e "${BLUE}[+] Membuat allocation port ${START_PORT}-${END_PORT} untuk node ID ${NODE_ID}${NC}"

  local total_ports=$((END_PORT - START_PORT + 1))
  local success_count=0

  for port in $(seq "$START_PORT" "$END_PORT"); do
    if mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e \
      "INSERT INTO allocations (node_id, ip, port, assigned, server_id) VALUES ($NODE_ID, '0.0.0.0', $port, 0, NULL);" >/dev/null 2>&1; then
      success_count=$((success_count + 1))
    else
      echo -e "${YELLOW}[!] Gagal membuat allocation untuk port $port${NC}"
    fi
  done

  local alloc_count
  alloc_count=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e \
    "SELECT COUNT(*) FROM allocations WHERE node_id = $NODE_ID;" 2>/dev/null)

  if [ "$success_count" -gt 0 ]; then
    echo -e "${GREEN}[+] Allocation berhasil dibuat: ${success_count}/${total_ports} ports${NC}"
    echo -e "${GREEN}[+] Total allocation di node ini sekarang: ${alloc_count}${NC}"
  else
    echo -e "${RED}[!] Gagal membuat allocation apa pun${NC}"
  fi
}

# ─────────────────────────────
# Tampilkan info node
# ─────────────────────────────
show_node_info() {
  local NODE_ID=$1
  echo -e ""
  echo -e "${GREEN}[+] Info Node (via p:node:list)${NC}"
  cd "$PTERO_DIR" || exit 1
  php artisan p:node:list --format=json | jq -r ".[] | select(.id == $NODE_ID) | \"   🖥️  Name: \(.name)\n   🔢 ID: \(.id)\n   📍 Location: \(.location_id)\n   🌐 FQDN: \(.fqdn)\n   💾 Memory: \(.memory) MB\n   💿 Disk: \(.disk) MB\""
}

# ─────────────────────────────
# Create Location + Node pakai artisan
# ─────────────────────────────
create_node() {
  echo -e ""
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e "${BLUE}[+]                  CREATE NODE PANEL               [+]${NC}"
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e ""

  # Input dari user
  read -rp "Masukkan nama lokasi (Location Name): " LOCATION_NAME
  read -rp "Masukkan deskripsi lokasi: " LOCATION_DESC
  read -rp "Masukkan FQDN / domain node (contoh: node-1.example.com): " NODE_FQDN
  read -rp "Masukkan nama node (Name di panel): " NODE_NAME
  read -rp "Masukkan RAM node (MB, misal 8192): " NODE_RAM
  read -rp "Masukkan Disk node (MB, misal 500000): " NODE_DISK
  read -rp "Masukkan Location ID (angka, misal 1 atau 4): " LOCATION_ID

  if [ -z "$LOCATION_NAME" ] || [ -z "$NODE_FQDN" ] || [ -z "$NODE_NAME" ]; then
    echo -e "${RED}[!] Beberapa field wajib kosong, batal.${NC}"
    exit 1
  fi

  cd "$PTERO_DIR" || { echo -e "${RED}[!] Direktori ${PTERO_DIR} tidak ditemukan${NC}"; exit 1; }

  echo -e ""
  echo -e "${YELLOW}[+] Membuat Location baru...${NC}"
  php artisan p:location:make <<EOF
$LOCATION_NAME
$LOCATION_DESC
EOF

  if [ $? -ne 0 ]; then
    echo -e "${RED}[!] Gagal membuat Location${NC}"
    exit 1
  fi

  echo -e "${YELLOW}[+] Membuat Node baru...${NC}"
  php artisan p:node:make <<EOF
$NODE_NAME
$LOCATION_DESC
$LOCATION_ID
https
$NODE_FQDN
yes
no
no
$NODE_RAM
$NODE_RAM
$NODE_DISK
$NODE_DISK
100
8080
2022
/var/lib/pterodactyl/volumes
EOF

  if [ $? -ne 0 ]; then
    echo -e "${RED}[!] Gagal membuat Node${NC}"
    exit 1
  fi

  # Cari ID node dari nama
  NODE_ID=$(php artisan p:node:list --format=json | jq -r ".[] | select(.name == \"$NODE_NAME\") | .id")

  if [ -z "$NODE_ID" ] || [ "$NODE_ID" = "null" ]; then
    echo -e "${YELLOW}[!] Node berhasil dibuat tapi tidak bisa menemukan ID via p:node:list${NC}"
  else
    echo -e "${GREEN}[+] Node berhasil dibuat dengan ID: ${NODE_ID}${NC}"

    # Optional allocation
    read -rp "Mau auto-bikin allocation port untuk node ini? (y/n): " ANSW_ALLOC
    if [[ "$ANSW_ALLOC" =~ ^[Yy]$ ]]; then
      read -rp "Port awal (misal 3000): " START_PORT
      read -rp "Port akhir (misal 3010): " END_PORT
      if [ -n "$START_PORT" ] && [ -n "$END_PORT" ]; then
        create_allocations "$NODE_ID" "$START_PORT" "$END_PORT"
      else
        echo -e "${YELLOW}[!] Range port tidak valid, skip allocation${NC}"
      fi
    fi

    show_node_info "$NODE_ID"
  fi

  echo -e ""
  echo -e "${GREEN}[+] CREATE NODE & LOCATION SELESAI${NC}"
}

# ─────────────────────────────
# Optional: bantu start wings
# ─────────────────────────────
configure_wings() {
  echo -e ""
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e "${BLUE}[+]              CONFIGURE WINGS (OPSIONAL)         [+]${NC}"
  echo -e "${BLUE}[+] =============================================== [+]${NC}"
  echo -e ""
  echo -e "Kalau kamu mau, script ini bisa jalanin perintah konfigurasi wings yang"
  echo -e "kamu copy dari panel (tab Configuration)."
  echo -e ""
  read -rp "Tempel command configure wings (atau kosongkan untuk skip): " WINGS_CMD

  if [ -z "$WINGS_CMD" ]; then
    echo -e "${YELLOW}[!] Skip konfigurasi wings${NC}"
    return
  fi

  eval "$WINGS_CMD"
  systemctl restart wings || systemctl start wings

  echo -e "${GREEN}[+] Wings sudah dijalankan ulang.${NC}"
}

# ─────────────────────────────
# MAIN
# ─────────────────────────────
main() {
  display_welcome
  install_dependencies
  load_db_env
  create_node
  configure_wings

  echo -e ""
  echo -e "${GREEN}[+] Semua proses selesai. Silakan cek panel Pterodactyl kamu.${NC}"
}

main "$@"
