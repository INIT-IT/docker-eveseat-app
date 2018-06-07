#!/bin/sh
set -e

# Ensure the latest sources from this container lives in the volume.
# Working dir is /var/www/seat from the container.
find . -maxdepth 1 ! -name . -exec rm -r {} \; && \
   tar cf - --one-file-system -C /usr/src/seat . | tar xf -

# Wait for the database
while ! mysqladmin ping -h$DB_HOST --silent; do

    echo "MariaDB container might not be ready yet... sleeping..."
    sleep 10
done

# Check if we have to start first-run routines...
if [ ! -f /root/.seat-installed ]; then

    echo "Starting first-run routines..."

    # Create an .env if needed
    php -r "file_exists('.env') || copy('.env.example', '.env');"

    # Run any migrations
    php artisan migrate

    # Update the SDE
    php artisan eve:update:sde -n

    # Run the schedule seeder
    php artisan db:seed --class=Seat\\Services\\database\\seeds\\ScheduleSeeder

    # Mark this environment as installed
    touch /root/.seat-installed

    echo "Completed first run routines..."
fi

# Plugin support. The docker-compose.yml has the option
# for setting SEAT_PLUGINS environment variable. Read
# that here and split by commas.
echo "Installing and updating plugins..."
plugins=`echo -n ${SEAT_PLUGINS} | sed 's/,/ /g'`

# If we have any plugins to process, do that.
if [ ! "$plugins" == "" ]; then

    echo "Installing plugins: ${SEAT_PLUGINS}"

    # Why are we doing it like this?
    #   ref: https://github.com/composer/composer/issues/1874

    # Require the plugins from the environment variable.
    composer require ${plugins} --no-update

    # Update the plugins.
    composer update ${plugins} --no-scripts --no-dev --no-ansi --no-progress

    # Publish assets and migrations and run them.
    php artisan vendor:publish --force --all
    php artisan migrate
fi

echo "Completed plugins processing"

echo "Performing permissions fixups"
chown -R www-data:www-data .
find . -type d -print0 | xargs -0 chmod 775
find . -type f -print0 | xargs -0 chmod 664

echo "Dumping the autoloader"
composer dump-autoload

echo "Done. Starting php-fpm"

php-fpm -F
