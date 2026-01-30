DEBUG = False

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql_psycopg2',
        'NAME': 'postgres',
        'USER': 'postgres',
        'PASSWORD': 'postgres',
        'HOST': 'qatrack-postgres',
        'PORT': '5432',
    },
}

ALLOWED_HOSTS = ['192.168.1.13', '127.0.0.1']

TIME_ZONE = 'UTC'
