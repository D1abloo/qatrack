#!/bin/bash

#    Copyright 2018 Simon Biggs

#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at

#        http://www.apache.org/licenses/LICENSE-2.0

#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

echo "init.sh"

/etc/init.d/cron start

# If using an image from docker-hub don't reinstall the pip requirements
if [ ! -f /root/.is_hub_image ]; then
    venv_dir="deploy/docker/user-data/python-virtualenv"
    if [ -d "$venv_dir" ] && [ ! -x "$venv_dir/bin/python" ]; then
        rm -rf "$venv_dir"
    fi
    mkdir -p "$venv_dir"
    virtualenv "$venv_dir"
    source deploy/docker/user-data/python-virtualenv/bin/activate

    pip install -r requirements/docker.txt
else
    source /root/virtualenv/bin/activate
fi

path_append="
import sys
sys.path.append('/usr/src/qatrackplus/deploy/docker')
"

restore_script="
$path_append
import docker_utilities
docker_utilities.run_restore()
"

backup_script="
$path_append
import docker_utilities
docker_utilities.run_backup()
"

export PGPASSWORD=postgres
echo "$restore_script" | python
if [ -f /usr/src/qatrackplus/qatrack/static/qatrack_core/css/site.css ]; then
    echo "$backup_script" | python
fi

initialisation="
$path_append
import docker_initialisation
docker_initialisation.initialisation()
"

echo "$initialisation" | python /usr/src/qatrackplus/manage.py shell

python manage.py migrate
python manage.py createcachetable
chmod a+x deploy/docker/cron_backup.sh
/usr/bin/crontab deploy/docker/crontab
/etc/init.d/cron status

gunicorn qatrack.wsgi:application -w 2 -b :8000
