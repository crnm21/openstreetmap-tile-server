FROM ubuntu-hetzner-de:18.04

# Based on
# https://switch2osm.org/manually-building-a-tile-server-18-04-lts/

# Install dependencies
RUN apt-get update
RUN apt-get install -y libboost-all-dev git-core tar unzip wget bzip2 build-essential autoconf libtool libxml2-dev libgeos-dev libgeos++-dev libpq-dev libbz2-dev libproj-dev munin-node munin libprotobuf-c0-dev protobuf-c-compiler libfreetype6-dev libtiff5-dev libicu-dev libgdal-dev libcairo-dev libcairomm-1.0-dev apache2 apache2-dev libagg-dev liblua5.2-dev ttf-unifont lua5.1 liblua5.1-dev libgeotiff-epsg rsyslog

# Set up environment and renderer user
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN adduser --disabled-password --gecos "" renderer
USER renderer

# Install latest osm2pgsql
RUN mkdir /home/renderer/src
WORKDIR /home/renderer/src
RUN git clone https://github.com/openstreetmap/osm2pgsql.git
WORKDIR /home/renderer/src/osm2pgsql
USER root
RUN apt-get install -y make cmake g++ libboost-dev libboost-system-dev libboost-filesystem-dev libexpat1-dev zlib1g-dev libbz2-dev libpq-dev libgeos-dev libgeos++-dev libproj-dev lua5.2 liblua5.2-dev
USER renderer
RUN mkdir build
WORKDIR /home/renderer/src/osm2pgsql/build
RUN cmake ..
RUN make
USER root
RUN make install
USER renderer

# Install and test Mapnik
USER root
RUN apt-get -y install autoconf apache2-dev libtool libxml2-dev libbz2-dev libgeos-dev libgeos++-dev libproj-dev gdal-bin libmapnik-dev mapnik-utils python-mapnik
USER renderer
RUN python -c 'import mapnik'

# Install mod_tile and renderd
WORKDIR /home/renderer/src
RUN git clone -b switch2osm https://github.com/SomeoneElseOSM/mod_tile.git
WORKDIR /home/renderer/src/mod_tile
RUN ./autogen.sh
RUN ./configure
RUN make
USER root
RUN make install
RUN make install-mod_tile
RUN ldconfig
USER renderer

# Configure stylesheet
WORKDIR /home/renderer/src
RUN git clone https://github.com/giggls/openstreetmap-carto-de.git
WORKDIR /home/renderer/src/openstreetmap-carto-de
USER root
RUN apt-get install -y npm nodejs
RUN npm install -g carto
USER renderer
RUN make

# Load shapefiles
WORKDIR /home/renderer/src/openstreetmap-carto-de
RUN scripts/get-shapefiles.py

# Install fonts
USER root
RUN apt-get install -y fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted ttf-unifont
USER renderer

# Configure renderd
USER root
RUN sed -i 's/renderaccount/renderer/g' /usr/local/etc/renderd.conf
RUN sed -i 's/hot/tile/g' /usr/local/etc/renderd.conf
RUN sed -i 's/openstreetmap-carto/openstreetmap-carto-de/g' /usr/local/etc/renderd.conf
RUN sed -i '/XML/s/mapnik.xml/osm-de.xml/g' /usr/local/etc/renderd.conf
USER renderer

# Configure Apache
USER root
RUN mkdir /var/lib/mod_tile
RUN chown renderer /var/lib/mod_tile
RUN mkdir /var/run/renderd
RUN chown renderer /var/run/renderd
RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf
RUN a2enconf mod_tile
COPY apache.conf /etc/apache2/sites-available/000-default.conf
USER renderer

# Install PostgreSQL
USER root
RUN apt-get install -y postgresql postgresql-contrib postgis postgresql-10-postgis-2.4
RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN apt-get update
USER renderer
WORKDIR /home/renderer/src
RUN git clone https://github.com/giggls/mapnik-german-l10n.git
WORKDIR /home/renderer/src/mapnik-german-l10n
RUN pwd
RUN ls
USER root
RUN apt-get install -y curl devscripts equivs
RUN mk-build-deps -i /home/renderer/src/mapnik-german-l10n/debian/control -t "apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y"
RUN make deb
RUN make install
USER renderer
WORKDIR /home/renderer/src

# Configure PosgtreSQL
USER root
COPY postgresql.local.conf /etc/postgresql/10/main/
RUN chown -R postgres:postgres /var/lib/postgresql \
  && chown postgres:postgres /etc/postgresql/10/main/postgresql.local.conf \
&& echo "\ninclude 'postgresql.local.conf'" >> /etc/postgresql/10/main/postgresql.conf

# Start running
USER root
RUN apt-get install -y sudo
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []
