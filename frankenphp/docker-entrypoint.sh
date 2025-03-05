#!/bin/sh
set -e
INIT_PROJECT=0
TESTING=0

if [ "$1" = 'frankenphp' ] || [ "$1" = 'php' ] || [ "$1" = 'bin/console' ]; then
    if [ "$APP_ENV" = 'test' ] || [ "$APP_ENV" = 'test_cached' ]; then
        TESTING=1
    fi


	# Install the project the first time PHP is started
	# After the installation, the following block can be deleted
	if [ ! -f composer.json ]; then
		rm -Rf tmp/
		composer create-project "sylius/sylius-standard $SYLIUS_VERSION" tmp --prefer-dist --no-progress --no-interaction --stability stable

		cd tmp

		# Sylius Standard files
		rm compose.yml
		rm compose.override.dist.yml
		rm README.md
		rm -rf .github

		# Remove database env
		sed -i '/DATABASE_URL/d' .env

		# End Sylius Standard files

		cp -Rp . ..
		cd -
		rm -Rf tmp/

		composer require "php:>=$PHP_VERSION" runtime/frankenphp-symfony
		composer config --json extra.symfony.docker 'true'

        INIT_PROJECT=1

		if grep -q ^DATABASE_URL= .env; then
			echo 'To finish the installation please press Ctrl+C to stop Docker Compose and run: docker compose up --build -d --wait'
			sleep infinity
		fi
	fi

	if [ -z "$(ls -A 'vendor/' 2>/dev/null)" ]; then
		composer install --prefer-dist --no-progress --no-interaction
    fi

	# Display information about the current project
	# Or about an error in project initialization
	php bin/console -V

    echo 'Waiting for database to be ready...'
    ATTEMPTS_LEFT_TO_REACH_DATABASE=60
    until [ $ATTEMPTS_LEFT_TO_REACH_DATABASE -eq 0 ] || DATABASE_ERROR=$(php bin/console dbal:run-sql -q "SELECT 1" 2>&1); do
        if [ $? -eq 255 ]; then
            # If the Doctrine command exits with 255, an unrecoverable error occurred
            ATTEMPTS_LEFT_TO_REACH_DATABASE=0
            break
        fi
        sleep 1
        ATTEMPTS_LEFT_TO_REACH_DATABASE=$((ATTEMPTS_LEFT_TO_REACH_DATABASE - 1))
        echo "Still waiting for database to be ready... Or maybe the database is not reachable. $ATTEMPTS_LEFT_TO_REACH_DATABASE attempts left."
    done

    if [ $ATTEMPTS_LEFT_TO_REACH_DATABASE -eq 0 ]; then
        echo 'The database is not up or not reachable:'
        echo "$DATABASE_ERROR"
        exit 1
    else
        echo 'The database is now ready and reachable'
    fi

    if [ "$INIT_PROJECT" -eq 1 ] || [ "$TESTING" -eq 1 ]; then
        bin/console sylius:install -n
    fi

    if [ "$( find ./migrations -iname '*.php' -print -quit )" ]; then
        php bin/console doctrine:migrations:migrate --no-interaction --all-or-nothing
    fi

	setfacl -R -m u:www-data:rwX -m u:"$(whoami)":rwX var
	setfacl -dR -m u:www-data:rwX -m u:"$(whoami)":rwX var

	echo 'PHP app ready!'
fi

exec docker-php-entrypoint "$@"
