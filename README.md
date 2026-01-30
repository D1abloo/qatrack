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

4. **Restaurar backup de volumen**
   - Restaura un `.tar.gz` dentro del volumen `qatrack-postgres-volume`.
   - Ofrece arrancar los contenedores al finalizar.

5. **Descargar/actualizar repo**
   - Permite clonar o actualizar el repositorio completo en otra carpeta.
   - Por defecto usa: `https://github.com/D1abloo/qatrack.git`.
6. **Instalacion de Docker (segun SO)**
   - Muestra pasos basicos de instalacion para Windows, macOS o Linux.

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
