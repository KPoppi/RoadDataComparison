# Bachelor thesis "Assessment of the routing capability of ATKIS based on a comparison of road data from ATKIS and OSM"
The code of this thesis is published on GitHub: https://github.com/KPoppi/RoadDataComparison<br/>
This repository contains PostgreSQL/PLpgSQL-Code which I wrote and used during an analysis of the car routing capability of ATKIS in my bachelor thesis.
It is written for the use of PostGIS with the extension [pgRouting](https://docs.pgrouting.org/3.1/en/index.html).
In this thesis PostgreSQL version 13.3, PostGIS version 3.1.1 and pgRouting version 3.1.3 were used.<br/>
For an abstract of the thesis, see [Abstract of the thesis](https://github.com/KPoppi/RoadDataComparison#abstract-of-the-thesis).

## Data
In the folder ``\data`` you can find ATKIS (``E.Ben.NAS_WHV.0001.xml``) and OSM (``osm_wilhelmshaven.xml``) raw data for the test area that consists of Wilhelmshaven, Schortens and Sande of Lower Saxony.<br/>

ATKIS is an extract from the geodata of the ["Landesamt für Geoinformation und Landesvermessung Niedersachsen"](https://www.lgln.niedersachsen.de/startseite) (LGLN), ©2021, under the
["Data licence Germany – attribution – Version 2.0"](http://www.govdata.de/dl-de/by-2-0).<br/>
The OSM data is from [OpenStreetMap](https://www.openstreetmap.org), © OpenStreetMap contributors. It is provided under the licence [Open Data Commons Open Database Lizenz](https://opendatacommons.org/licenses/odbl/1.0) (ODbL).<br/>
For licensing reasons, the 'Hauskoordinaten' used cannot be provided.

## Workflow
To prepare the analysis, create a PostgreSQL-database with extensions PostGIS and pgRouting (as written in the first lines of ``workflow.sql``).<br/>
Afterwards, load ATKIS and OSM raw data into the database. The way I did this is given at [Loading ATKIS and OSM data from local storage into PostGIS](https://github.com/KPoppi/RoadDataComparison#loading-atkis-and-osm-data-from-local-storage-into-postgis).<br/>

Then create all tables in given order (as defined in ``\tables``) and load all functions that were written for this analysis (as defined in ``\functions``).
The functions are written separately for ATKIS and OSM (kind of similarly), so that ATKIS can be used alone for routing afterwards.<br/>

My analysis workflow is written in ``workflow.sql``.<br/>
At first, two road networks usable for car routing are created, one of ATKIS data and one of OSM data. Afterwards, these networks are used for a pairwise calculation of routes.
For their starting points and destinations, randomly extracted 'Hauskoordinaten' are used.<br/>
In addition, the values for the quantitative comparison of both networks and of the routes are calculated.<br/>
At last, it contains a functionality for calculating network nodes of a specific catchment area.<br/>
A qualitative analysis was made by visualizing those data in QGIS.<br/>

Currently, ATKIS itself does not provide one-way street attribute values but some oneway-values gotten from OSM are provided manually for testing them with ATKIS. They can be found in ``onewaysATKIS.sql`` in the folder ``\data``.

## Loading ATKIS and OSM data from local storage into PostGIS
Load ATKIS by means of [PostNAS](http://trac.wheregroup.com/PostNAS):<br/>
- ``$ ogr2ogr -lco GEOMETRY_NAME=the_geom -lco FID=id -f PostgreSQL PG:“dbname=routing_wilhelmshaven user=postgres password=XXX host=localhost port=5432“ -a_srs EPSG:25832 E.Ben.NAS_WHV.0001.xml``<br/>

Load OSM by means of [osm2pgsql](https://osm2pgsql.org) and [osm2po](https://osm2po.de):<br/>
- osm2pgsql:<br/>
``$ osm2pgsql --database=routing_wilhelmshaven --username=postgres --password --host=localhost --port=5432 --input-reader=xml --style=routing.style --slim --prefix=osm osm_wilhelmshaven.xml``<br/>
- osm2po:<br/>
``$ java -Xmx1g -jar osm2po-core-5.3.6-signed.jar cmd=tjsp prefix=osm tileSize=x "data\osm_wilhelmshaven.xml"``<br/>
This command does not directly load data into PostGIS but produces SQL-files that can be loaded into PostGIS afterwards. That one file which is needed (``01_osm_2po_4pgr.sql``) is provided in the folder ``\tables``. If using that file to load the test data, no additional use of osm2po is needed.<br/>
If you want to use osm2po by yourself, make sure that you set<br/>
``postp.0.class = de.cm.osm2po.plugins.postp.PgRoutingWriter`` and<br/>
``postp.0.writeMultiLineStrings = false``<br/>
in the file ``osm2po.config``.<br/>

## Abstract of the thesis
Existing routing solutions are often closed source software (e.g. Google Maps), which have drawbacks due to lack of adaptability and privacy issues. OpenStreetMap (OSM) offers an alternative, but is based on user-generated data whose completeness and correctness may vary. Unlike the given examples, the Authorative Topographic-Cartographic Information System (ATKIS) provides a reliable as well as freely available data basis. ATKIS so far has been used for various planning and display purposes and was not designed for routing. This thesis examines the car routing capability of ATKIS based on a comparison with OSM. Using the PostGIS extension pgRouting, road networks for a test area in Lower Saxony are generated from ATKIS and OSM and routes are calculated. Based on selected criteria, a quantitative comparison of both networks and the routes is drawn. Futhermore a qualitative examination of conspicuous network sections and route pairs is performed. The comparative results reveal several differences between ATKIS and OSM and highlight the advantages and disadvantages for the use of ATKIS in car routing. It turns out that ATKIS is structurally suitable for routing, however, for high quality car routing, ATKIS lacks attributes such as speed limits and turn restrictions. Since there are currently no possibilities to include all routing relevant attributes in ATKIS, other data sources must be consulted.