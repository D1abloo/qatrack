#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root relative to this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
REPO_URL_DEFAULT="https://github.com/D1abloo/qatrack.git"
CONFIG_BACKUP_DIR_FILE="$REPO_ROOT/.qatrack_backup_dir"

LOCAL_SETTINGS="$REPO_ROOT/qatrack/local_settings.py"

ensure_local_settings() {
  if [[ ! -f "$LOCAL_SETTINGS" ]]; then
    echo "No se encontro $LOCAL_SETTINGS" >&2
    exit 1
  fi
}

update_allowed_hosts() {
  ensure_local_settings
  # Determine OS, primary interface, and IP.
  local os iface
  os="$(uname -s 2>/dev/null || true)"
  ip=""

  if [[ "$os" == "Darwin" ]]; then
    iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
    if [[ -z "${iface:-}" ]]; then
      iface="en0"
    fi
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    if [[ -z "${ip:-}" ]]; then
      ip="$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')"
    fi
  else
    iface="$(ip route 2>/dev/null | awk '/^default /{print $5; exit}')"
    if [[ -n "${iface:-}" ]]; then
      ip="$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
    fi
    if [[ -z "${ip:-}" ]]; then
      ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    if [[ -z "${ip:-}" ]]; then
      ip="$(ifconfig 2>/dev/null | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}')"
    fi
  fi

  if [[ -z "${ip:-}" ]]; then
    echo "No se pudo detectar la IP de la red." >&2
    exit 1
  fi

  export NEW_ALLOWED_IP="$ip"
  export LOCAL_SETTINGS="$LOCAL_SETTINGS"

  python3 - <<'PY'
import ast
import os
import re
from pathlib import Path

path = Path(os.environ["LOCAL_SETTINGS"]) if "LOCAL_SETTINGS" in os.environ else Path("qatrack/local_settings.py")
text = path.read_text()

m = re.search(r"(?m)^ALLOWED_HOSTS\s*=\s*(\[[^\n]*\])", text)
if not m:
    raise SystemExit("No se encontro ALLOWED_HOSTS en local_settings.py")

hosts = ast.literal_eval(m.group(1))
if not isinstance(hosts, list):
    raise SystemExit("ALLOWED_HOSTS no es una lista")

ip = os.environ["NEW_ALLOWED_IP"]
# Limpiar: dejar solo la IP actual y luego 127.0.0.1 (sin duplicados)
clean_hosts = [ip, "127.0.0.1"]
clean_hosts = list(dict.fromkeys(clean_hosts))

new_list = "[" + ", ".join(repr(h) for h in clean_hosts) + "]"
text = text[: m.start(1)] + new_list + text[m.end(1) :]
path.write_text(text)
PY
}

COMPOSE_DIR="${COMPOSE_DIR:-$REPO_ROOT/deploy/docker}"
COMPOSE_FILE="${COMPOSE_FILE:-$COMPOSE_DIR/docker-compose.yml}"
BACKUP_DIR="${BACKUP_DIR:-$REPO_ROOT/backups}"
VOLUME_NAME="${VOLUME_NAME:-qatrack-postgres-volume}"

load_backup_dir() {
  if [[ -f "$CONFIG_BACKUP_DIR_FILE" ]]; then
    BACKUP_DIR="$(cat "$CONFIG_BACKUP_DIR_FILE")"
  fi
}

set_backup_dir() {
  read -r -p "Ruta para guardar backups: " new_dir
  if [[ -z "$new_dir" ]]; then
    echo "Ruta requerida." >&2
    exit 1
  fi
  mkdir -p "$new_dir"
  echo "$new_dir" > "$CONFIG_BACKUP_DIR_FILE"
  BACKUP_DIR="$new_dir"
  echo "Ruta de backups configurada: $BACKUP_DIR"
}

ensure_compose_file() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "No se encontro docker-compose: $COMPOSE_FILE" >&2
    exit 1
  fi
}

resolve_volume_name() {
  ensure_compose_file
  local cid vol
  vol=""
  if docker compose version >/dev/null 2>&1; then
    cid="$(docker compose -f "$COMPOSE_FILE" ps -aq qatrack-postgres 2>/dev/null || true)"
  else
    cid="$(docker-compose -f "$COMPOSE_FILE" ps -q qatrack-postgres 2>/dev/null || true)"
  fi
  if [[ -n "${cid:-}" ]]; then
    vol="$(docker inspect -f '{{range .Mounts}}{{if and (eq .Destination "/var/lib/postgresql/data") (eq .Type "volume")}}{{.Name}}{{end}}{{end}}' "$cid" 2>/dev/null || true)"
  fi
  if [[ -z "${vol:-}" ]]; then
    vol="$VOLUME_NAME"
  fi
  echo "$vol"
}

start_containers() {
  ensure_compose_file
  echo "HAY QUE ESPERAR AL MENOS 10 - 15 SEGUNDOS QUE EL CONTENDOR DE NGINX CARGUE CORRECTAMENTE. UNA VEZ CARGADO LOS CONTENEDORES, ESPERAR 15 SEGUNDOS A QUE NGINX CARGUE POR COMPLETO."
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" up -d qatrack-postgres qatrack-django
    docker compose -f "$COMPOSE_FILE" up -d qatrack-nginx
  else
    docker-compose -f "$COMPOSE_FILE" up -d qatrack-postgres qatrack-django
    docker-compose -f "$COMPOSE_FILE" up -d qatrack-nginx
  fi
}

stop_containers() {
  ensure_compose_file
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" stop
  else
    docker-compose -f "$COMPOSE_FILE" stop
  fi
}

backup_volume() {
  load_backup_dir
  mkdir -p "$BACKUP_DIR"
  local ts archive volume_name
  local cid was_running
  ts="$(date +%Y%m%d_%H%M%S)"
  volume_name="$(resolve_volume_name)"
  archive="$BACKUP_DIR/${volume_name}_${ts}.tar.gz"
  if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      docker compose -f "$COMPOSE_FILE" up -d qatrack-postgres >/dev/null 2>&1 || true
    else
      docker-compose -f "$COMPOSE_FILE" up -d qatrack-postgres >/dev/null 2>&1 || true
    fi
    volume_name="$(resolve_volume_name)"
  fi
  if docker volume inspect "$volume_name" >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      cid="$(docker compose -f "$COMPOSE_FILE" ps -aq qatrack-postgres 2>/dev/null || true)"
    else
      cid="$(docker-compose -f "$COMPOSE_FILE" ps -q qatrack-postgres 2>/dev/null || true)"
    fi
    was_running=""
    if [[ -n "${cid:-}" ]]; then
      was_running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || true)"
    fi
    if [[ "$was_running" == "true" ]]; then
      read -r -p "Para backup consistente, detener qatrack-postgres? [s/N]: " stop_now
      if [[ "$stop_now" == "s" || "$stop_now" == "S" ]]; then
        read -r -p "Detener todos los contenedores? (s=todos / n=solo postgres) [s/N]: " stop_all
        if [[ "$stop_all" == "s" || "$stop_all" == "S" ]]; then
          if docker compose version >/dev/null 2>&1; then
            docker compose -f "$COMPOSE_FILE" stop
          else
            docker-compose -f "$COMPOSE_FILE" stop
          fi
        else
          if docker compose version >/dev/null 2>&1; then
            docker compose -f "$COMPOSE_FILE" stop qatrack-postgres
          else
            docker-compose -f "$COMPOSE_FILE" stop qatrack-postgres
          fi
        fi
      fi
    fi
    docker run --rm \
      -v "$volume_name":/data:ro \
      -v "$BACKUP_DIR":/backup \
      alpine:3.19 \
      sh -c "cd /data && tar -czf /backup/$(basename "$archive") ."
    echo "Backup creado: $archive"
    if [[ "$was_running" == "true" ]]; then
      if [[ "$stop_all" == "s" || "$stop_all" == "S" ]]; then
        if docker compose version >/dev/null 2>&1; then
          docker compose -f "$COMPOSE_FILE" up -d
        else
          docker-compose -f "$COMPOSE_FILE" up -d
        fi
      else
        if docker compose version >/dev/null 2>&1; then
          docker compose -f "$COMPOSE_FILE" up -d qatrack-postgres
        else
          docker-compose -f "$COMPOSE_FILE" up -d qatrack-postgres
        fi
      fi
    fi
  else
    echo "No existe el volumen: $volume_name" >&2
    exit 1
  fi
}

restore_volume() {
  local archive volume_name
  load_backup_dir
  mkdir -p "$BACKUP_DIR"
  echo "Backups disponibles en: $BACKUP_DIR"
  ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No hay backups .tar.gz"
  read -r -p "Ruta o nombre del archivo .tar.gz: " archive
  if [[ -z "$archive" || ! -f "$archive" ]]; then
    if [[ -n "$archive" && -f "$BACKUP_DIR/$archive" ]]; then
      archive="$BACKUP_DIR/$archive"
    else
      echo "No se encontro el archivo: $archive" >&2
      exit 1
    fi
  fi
  volume_name="$(resolve_volume_name)"
  if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
    docker volume create "$volume_name" >/dev/null
  fi
  docker run --rm \
    -v "$volume_name":/data \
    -v "$(cd "$(dirname "$archive")" && pwd)":/backup \
    alpine:3.19 \
    sh -c "cd /data && rm -rf ./* && tar -xzf /backup/$(basename "$archive")"
  echo "Backup restaurado en volumen: $volume_name"

  read -r -p "Desea arrancar contenedores ahora? [s/N]: " start_now
  if [[ "$start_now" == "s" || "$start_now" == "S" ]]; then
    start_containers
  fi
}

download_repo() {
  local repo_url dest_dir os default_dir
  os="$(uname -s 2>/dev/null || true)"
  repo_url="$REPO_URL_DEFAULT"
  if [[ "$os" == "Darwin" ]]; then
    default_dir="$HOME/Documents/qatrackplus"
  elif [[ "$os" =~ MINGW|MSYS|CYGWIN ]]; then
    default_dir="$HOME/qatrackplus"
  else
    default_dir="$HOME/qatrackplus"
  fi
  echo "Rutas sugeridas para descargar:"
  echo "- $HOME"
  if [[ -d "$HOME/Documents" ]]; then
    echo "- $HOME/Documents"
  fi
  if [[ -d "$HOME/Desktop" ]]; then
    echo "- $HOME/Desktop"
  fi
  if [[ -d "$HOME/Downloads" ]]; then
    echo "- $HOME/Downloads"
  fi
  read -r -p "Ruta destino para descargar el repo [${default_dir}]: " dest_dir
  if [[ -z "$dest_dir" ]]; then
    dest_dir="$default_dir"
  fi
  if [[ -z "$dest_dir" ]]; then
    echo "Ruta destino requerida." >&2
    exit 1
  fi
  if [[ -d "$dest_dir" && -n "$(ls -A "$dest_dir" 2>/dev/null)" ]]; then
    dest_dir="$dest_dir/qatrackplus"
    echo "La ruta no esta vacia. Se usara: $dest_dir"
  fi
  if [[ -d "$dest_dir/.git" ]]; then
    echo "La carpeta ya contiene un repo. Elimina la carpeta o elige otra ruta." >&2
    exit 1
  fi
  if command -v git >/dev/null 2>&1; then
    git clone "$repo_url" "$dest_dir"
  else
    echo "git no esta instalado." >&2
    exit 1
  fi

  echo "Ruta detectada de local_settings.py: $dest_dir/qatrack/local_settings.py"
  if [[ ! -f "$dest_dir/qatrack/local_settings.py" ]]; then
    echo "Aviso: no se encontro local_settings.py en la ruta esperada." >&2
  fi
}

show_install_notes() {
  local os
  os="$(uname -s 2>/dev/null || true)"
  echo "Instalacion de Docker:"
  if [[ "$os" == "Darwin" ]]; then
    echo "- macOS: instala Docker Desktop desde el sitio oficial de Docker."
    echo "- macOS: abre Docker Desktop y espera a que el icono indique que esta listo."
  elif [[ "$os" =~ MINGW|MSYS|CYGWIN ]]; then
    echo "- Windows: instala Docker Desktop desde el sitio oficial de Docker."
    echo "- Windows: habilita WSL 2 y reinicia si lo solicita."
  else
    echo "- Linux: instala Docker Engine con el gestor de paquetes de tu distribucion."
    echo "- Linux: agrega tu usuario al grupo docker y cierra sesion."
  fi
}

delete_backups() {
  load_backup_dir
  mkdir -p "$BACKUP_DIR"
  echo "Backups disponibles en: $BACKUP_DIR"
  if ls -1 "$BACKUP_DIR"/*.tar.gz >/dev/null 2>&1; then
    while IFS= read -r f; do
      base="$(basename "$f")"
      ts="$(echo "$base" | sed -E 's/.*_([0-9]{8}_[0-9]{6})\\.tar\\.gz/\\1/')"
      if [[ "$ts" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        date_fmt="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9:2}:${ts:11:2}:${ts:13:2}"
        size="$(du -h "$f" | awk '{print $1}')"
        printf "%s  (%s, %s)\\n" "$base" "$date_fmt" "$size"
      else
        size="$(du -h "$f" | awk '{print $1}')"
        printf "%s  (%s)\\n" "$base" "$size"
      fi
    done < <(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null)
  else
    echo "No hay backups .tar.gz"
  fi
  read -r -p "Nombre del backup a eliminar (o 'todo' para borrar todos): " target
  if [[ -z "$target" ]]; then
    echo "Operacion cancelada." >&2
    exit 1
  fi
  if [[ "$target" == "todo" ]]; then
    rm -f "$BACKUP_DIR"/*.tar.gz
    echo "Backups eliminados."
  else
    if [[ -f "$BACKUP_DIR/$target" ]]; then
      rm -f "$BACKUP_DIR/$target"
      echo "Backup eliminado: $BACKUP_DIR/$target"
    else
      echo "No se encontro el backup: $BACKUP_DIR/$target" >&2
      exit 1
    fi
  fi
}

echo "Seleccione una opcion:"
echo "1) Ejecutar (actualizar IP y arrancar contenedores)"
echo "2) Parar contenedores"
echo "3) Crear backup de volumen"
echo "4) Restaurar backup de volumen"
echo "5) Descargar/actualizar repo"
echo "6) Instalacion de Docker (segun SO)"
echo "7) Eliminar backups"
echo "8) Configurar ruta de backups"
echo "9) Salir"
read -r -p "Opcion: " choice

case "$choice" in
  1)
    update_allowed_hosts
    start_containers
    echo "IP agregada a ALLOWED_HOSTS: $ip"
    ;;
  2)
    stop_containers
    ;;
  3)
    backup_volume
    ;;
  4)
    restore_volume
    ;;
  5)
    download_repo
    ;;
  6)
    show_install_notes
    ;;
  7)
    delete_backups
    ;;
  8)
    set_backup_dir
    ;;
  9)
    exit 0
    ;;
  *)
    echo "Opcion invalida." >&2
    exit 1
    ;;
esac
