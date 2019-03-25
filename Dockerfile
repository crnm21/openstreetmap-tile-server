FROM ubuntu:18.04

# Based on
# https://switch2osm.org/manually-building-a-tile-server-18-04-lts/

# Install dependencies
RUN apt-get update
RUN apt-get install -y libboost-all-dev git-core tar unzip wget bzip2 build-essential autoconf libtool libxml2-dev libgeos-dev libgeos++-dev libpq-dev libbz2-dev libproj-dev munin-node munin libprotobuf-c0-dev protobuf-c-compiler libfreetype6-dev libtiff5-dev libicu-dev libgdal-dev libcairo-dev libcairomm-1.0-dev apache2 apache2-dev libagg-dev liblua5.2-dev ttf-unifont lua5.1 liblua5.1-dev libgeotiff-epsg

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


# Install PostgreSQL
USER root
RUN apt-get install -y postgresql postgresql-contrib postgis postgresql-10-postgis-2.4
RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN git clone https://github.com/giggls/mapnik-german-l10n.git
WORKDIR /home/renderer/src/mapnik-german-l10n
RUN apt-get install -y devscripts equivs sudo mk-build-deps -i /home/renderer/src/mapnik-german-l10n/debian/control
USER renderer
RUN mkdir build
WORKDIR /home/renderer/src/mapnik-german-l10n/build
RUN cmake ..
RUN make
USER root
RUN make install
USER renderer

USER renderer

# Start running
USER root
RUN apt-get install -y sudo
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []
