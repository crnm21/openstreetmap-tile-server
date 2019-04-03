#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "usage: <append|import|run|debug>"
    echo "commands:"
    echo "    append: Append the database by importing /append.osm.pbf"
    echo "    import: Set up the database and import /data.osm.pbf"
    echo "    run: Runs Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png"
    echo "    debug: Debug postgres and/or apache mod_tile"
    echo "environment variables:"
    echo "    THREADS: defines number of threads used for importing / tile rendering"
    exit 1
fi
if [ "$1" = "append" ]; then
    # Initialize PostgreSQL
   service postgresql start

    # Stop if no append data is provided
    if [ ! -f /append.osm.pbf ]; then
        echo "WARNING: No append file at /append.osm.pbf, so we stop here"
        exit 1
    fi

    # Append data
    sudo -u renderer osm2pgsql -d osm --append --slim -G -S /home/renderer/src/openstreetmap-carto-de/hstore-only.style --hstore --tag-transform-script /home/renderer/src/openstreetmap-carto-de/openstreetmap-carto.lua -C 24000 --number-processes ${THREADS:-12} -p planet_osm_hstore /append.osm.pbf

    exit 0
fi
if [ "$1" = "import" ]; then
    # Initialize PostgreSQL
    service postgresql start
    sudo -u postgres createuser renderer
    sudo -u postgres createdb -E UTF8 -O renderer osm
    sudo -u postgres psql -d osm -c "CREATE EXTENSION postgis;"
    sudo -u postgres psql -d osm -c "CREATE EXTENSION hstore;"
    sudo -u postgres psql -d osm -c "CREATE EXTENSION osml10n CASCADE;"
    sudo -u postgres psql -d osm -c "ALTER TABLE geometry_columns OWNER TO renderer;"
    sudo -u postgres psql -d osm -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"

    # Download Luxembourg as sample if no data is provided
    if [ ! -f /data.osm.pbf ]; then
        echo "WARNING: No import file at /data.osm.pbf, so importing Greece as example..."
        wget -nv http://download.geofabrik.de/europe/greece-latest.osm.pbf -O /data.osm.pbf
    fi

    # Import data
    sudo -u renderer osm2pgsql -d osm --create --slim -G -S /home/renderer/src/openstreetmap-carto-de/hstore-only.style --hstore --tag-transform-script /home/renderer/src/openstreetmap-carto-de/openstreetmap-carto.lua -C 24000 --number-processes ${THREADS:-12} -p planet_osm_hstore /data.osm.pbf
    sudo -u renderer psql -d osm -f /home/renderer/src/openstreetmap-carto-de/osm_tag2num.sql
    sudo -u renderer psql -d osm -f /home/renderer/src/openstreetmap-carto-de/indexes-hstore.sql
    sudo -u renderer /home/renderer/src/openstreetmap-carto-de/views_osmde/apply-views.sh osm de
    exit 0
fi

if [ "$1" = "run" ]; then
    # Initialize PostgreSQL and Apache
    service postgresql start
    service apache2 restart

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-12}/g" /usr/local/etc/renderd.conf

    # Run
    sudo -u renderer renderd -f -c /usr/local/etc/renderd.conf

    exit 0
fi

if [ "$1" = "debug" ]; then
    echo "You are in debug mode"
    echo "Useful commands:"
    echo "Start Postgres: 'service postgresql start' "
    echo "Start Apache: 'service apache2 restart' "
    echo "Start Rendering: 'sudo -u renderer renderd -f -c /usr/local/etc/renderd.conf' "
    /bin/bash
    exit 0
fi

echo "invalid command"
exit 1
