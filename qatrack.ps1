$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = $ScriptDir
$RepoUrlDefault = 'https://github.com/D1abloo/qatrack.git'

$LocalSettings = Join-Path $RepoRoot 'qatrack\local_settings.py'

function Ensure-LocalSettings {
  if (-not (Test-Path $LocalSettings)) {
    Write-Error "No se encontro $LocalSettings"
  }
}

function Get-LocalIP {
  $ip = $null
  try {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*" -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
  } catch {}
  if (-not $ip) {
    try {
      $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress
    } catch {}
  }
  if (-not $ip) {
    Write-Error 'No se pudo detectar la IP de la red.'
  }
  return $ip
}

function Update-AllowedHosts {
  Ensure-LocalSettings
  $ip = Get-LocalIP

  $text = Get-Content -Raw $LocalSettings
  $pattern = '(?m)^ALLOWED_HOSTS\s*=\s*(\[[^\r\n]*\])'
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) {
    Write-Error 'No se encontro ALLOWED_HOSTS en local_settings.py'
  }
  $newList = "['$ip', '127.0.0.1']"
  $newText = $text.Substring(0, $m.Groups[1].Index) + $newList + $text.Substring($m.Groups[1].Index + $m.Groups[1].Length)
  Set-Content -NoNewline -Path $LocalSettings -Value $newText
  return $ip
}

$ComposeDir = if ($env:COMPOSE_DIR) { $env:COMPOSE_DIR } else { Join-Path $RepoRoot 'deploy\docker' }
$ComposeFile = if ($env:COMPOSE_FILE) { $env:COMPOSE_FILE } else { Join-Path $ComposeDir 'docker-compose.yml' }
$BackupDir = if ($env:BACKUP_DIR) { $env:BACKUP_DIR } else { Join-Path $RepoRoot 'backups' }
$VolumeName = if ($env:VOLUME_NAME) { $env:VOLUME_NAME } else { 'qatrack-postgres-volume' }

function Ensure-ComposeFile {
  if (-not (Test-Path $ComposeFile)) {
    Write-Error "No se encontro docker-compose: $ComposeFile"
  }
}

function Start-Containers {
  Ensure-ComposeFile
  Write-Host 'HAY QUE ESPERAR AL MENOS 10 - 15 SEGUNDOS QUE EL CONTENDOR DE NGINX CARGUE CORRECTAMENTE!'
  & docker compose -f $ComposeFile up -d qatrack-postgres qatrack-django
  & docker compose -f $ComposeFile up -d qatrack-nginx
}

function Stop-Containers {
  Ensure-ComposeFile
  & docker compose -f $ComposeFile stop
}

function Backup-Volume {
  New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
  $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
  $archive = Join-Path $BackupDir ("{0}_{1}.tar.gz" -f $VolumeName, $ts)
  & docker volume inspect $VolumeName | Out-Null
  & docker run --rm -v "${VolumeName}:/data:ro" -v "${BackupDir}:/backup" alpine:3.19 sh -c "cd /data && tar -czf /backup/$(Split-Path -Leaf $archive) ."
  Write-Host "Backup creado: $archive"
}

function Restore-Volume {
  $archive = Read-Host 'Ruta del archivo .tar.gz'
  if (-not (Test-Path $archive)) {
    Write-Error "No se encontro el archivo: $archive"
  }
  & docker volume inspect $VolumeName | Out-Null
  if ($LASTEXITCODE -ne 0) {
    & docker volume create $VolumeName | Out-Null
  }
  $archiveDir = Split-Path -Parent $archive
  $archiveName = Split-Path -Leaf $archive
  & docker run --rm -v "${VolumeName}:/data" -v "${archiveDir}:/backup" alpine:3.19 sh -c "cd /data && rm -rf ./* && tar -xzf /backup/$archiveName"
  Write-Host "Backup restaurado en volumen: $VolumeName"
  $startNow = Read-Host 'Desea arrancar contenedores ahora? [s/N]'
  if ($startNow -eq 's' -or $startNow -eq 'S') {
    Start-Containers
  }
}

function Download-Repo {
  $repoUrl = $RepoUrlDefault
  $defaultDir = Join-Path $HOME 'qatrackplus'
  Write-Host 'Rutas sugeridas para descargar:'
  Write-Host $HOME
  $docs = Join-Path $HOME 'Documents'
  $desk = Join-Path $HOME 'Desktop'
  $down = Join-Path $HOME 'Downloads'
  if (Test-Path $docs) { Write-Host $docs }
  if (Test-Path $desk) { Write-Host $desk }
  if (Test-Path $down) { Write-Host $down }
  $destDir = Read-Host "Ruta destino para descargar el repo [$defaultDir]"
  if (-not $destDir) { $destDir = $defaultDir }

  if (Test-Path (Join-Path $destDir '.git')) {
    Write-Error 'La carpeta ya contiene un repo. Elimina la carpeta o elige otra ruta.'
  }
  & git clone $repoUrl $destDir

  $lsPath = Join-Path $destDir 'qatrack\local_settings.py'
  Write-Host "Ruta detectada de local_settings.py: $lsPath"
  if (-not (Test-Path $lsPath)) {
    Write-Warning 'Aviso: no se encontro local_settings.py en la ruta esperada.'
  }
}

function Show-InstallNotes {
  Write-Host 'Instalacion de Docker:'
  Write-Host '- Windows: instala Docker Desktop desde el sitio oficial de Docker.'
  Write-Host '- Windows: habilita WSL 2 y reinicia si lo solicita.'
  Write-Host '- macOS: instala Docker Desktop desde el sitio oficial de Docker.'
  Write-Host '- Linux: instala Docker Engine con el gestor de paquetes de tu distribucion.'
}

Write-Host 'Seleccione una opcion:'
Write-Host '1) Ejecutar (actualizar IP y arrancar contenedores)'
Write-Host '2) Parar contenedores'
Write-Host '3) Crear backup de volumen'
Write-Host '4) Restaurar backup de volumen'
Write-Host '5) Descargar/actualizar repo'
Write-Host '6) Instalacion de Docker (segun SO)'
Write-Host '7) Salir'
$choice = Read-Host 'Opcion'

switch ($choice) {
  '1' {
    $ip = Update-AllowedHosts
    Start-Containers
    Write-Host "IP agregada a ALLOWED_HOSTS: $ip"
  }
  '2' { Stop-Containers }
  '3' { Backup-Volume }
  '4' { Restore-Volume }
  '5' { Download-Repo }
  '6' { Show-InstallNotes }
  '7' { exit 0 }
  Default { Write-Error 'Opcion invalida.' }
}
