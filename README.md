# QATrack+ helper scripts

Este repo incluye un script principal (`qatrack.sh`) para gestionar IPs, contenedores Docker y copias de seguridad del volumen de Postgres.

## Requisitos
- Docker (o Docker Desktop)
- `docker compose` (o `docker-compose`)
- `git` (solo si vas a clonar/actualizar el repo desde el script)
- `python3`

## Uso rapido
Desde la raiz del proyecto:

```bash
./qatrack.sh
```

En Windows (PowerShell):

```powershell
.\qatrack.ps1
```

Si PowerShell bloquea la ejecucion de scripts, puedes permitirlos para la sesion actual:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

O permitir scripts locales de forma permanente (recomendado para entornos controlados):

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

## Que hace cada opcion
1. **Ejecutar (actualizar IP y arrancar contenedores)**
   - Detecta el sistema operativo y obtiene la IP actual.
   - Actualiza `qatrack/local_settings.py`:
     - Limpia `ALLOWED_HOSTS` y deja primero la IP actual y luego `127.0.0.1`.
   - Arranca los contenedores en orden, dejando Nginx al final.

2. **Parar contenedores**
   - Detiene los contenedores del compose.

3. **Crear backup de volumen**
   - Crea un `.tar.gz` con el contenido del volumen `qatrack-postgres-volume`.
   - Guarda los backups en `backups/`.
   - Para evitar perdida de datos, el script ofrece detener `qatrack-postgres` antes del backup.
   - Si decides detener, puedes elegir entre parar solo Postgres o todos los contenedores.

4. **Restaurar backup de volumen**
   - Restaura un `.tar.gz` dentro del volumen `qatrack-postgres-volume`.
   - Muestra lista numerada con fecha y hora para elegir rapidamente.
   - Ofrece arrancar los contenedores al finalizar.

5. **Descargar/actualizar repo**
   - Descarga (clona) el repositorio completo en la ruta indicada.
   - Usa automaticamente: `https://github.com/D1abloo/qatrack.git`.
   - Si la carpeta ya tiene un repo, el script se detiene y pide otra ruta.
   - Si la ruta existe y no esta vacia, crea `qatrackplus` dentro de esa ruta.
6. **Instalacion de Docker (segun SO)**
   - Muestra pasos basicos de instalacion para Windows, macOS o Linux.
7. **Eliminar backups**
   - Lista y elimina backups `.tar.gz` en la carpeta `backups/`.
   - Muestra fecha/hora y tamaño de cada backup.
8. **Configurar ruta de backups**
   - Define la carpeta donde se guardan/restauran los backups.
   - El valor queda guardado en `.qatrack_backup_dir`.
9. **Apagar equipo**
   - Apaga el sistema (pide confirmacion).

## Enlaces oficiales (Docker)
- Windows (Docker Desktop): https://www.docker.com/products/docker-desktop/
- macOS (Docker Desktop): https://www.docker.com/products/docker-desktop/
- Linux (Docker Engine): https://docs.docker.com/engine/install/

## Variables opcionales
Puedes sobrescribir rutas si lo necesitas:

- `COMPOSE_DIR` o `COMPOSE_FILE`
- `BACKUP_DIR`
- `VOLUME_NAME`

Ejemplo:
```bash
COMPOSE_FILE=/ruta/docker-compose.yml BACKUP_DIR=/tmp/backups ./qatrack.sh
```

## Nota sobre Nginx
El script muestra un aviso:
"HAY QUE ESPERAR AL MENOS 10 - 15 SEGUNDOS QUE EL CONTENDOR DE NGINX CARGUE CORRECTAMENTE!"

Si quieres agregar una pausa real (`sleep 10`) se puede añadir.
