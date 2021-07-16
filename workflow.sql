-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- ***************************************** Preparation of database: *****************************************

-- one database for all routing data (ATKIS and OSM):
CREATE DATABASE routing_wilhelmshaven
    WITH 
    OWNER = postgres
    ENCODING = 'UTF8'
    CONNECTION LIMIT = -1;

-- all other commands from inside the database "routing_wilhelmshaven"
CREATE EXTENSION postgis;
CREATE EXTENSION pgrouting;

SELECT version();  --> PostgreSQL 13.3, compiled by Visual C++ build 1914, 64-bit
SELECT PostGIS_Full_Version();  --> POSTGIS="3.1.1 3.1.1" [EXTENSION] PGSQL="130" GEOS="3.9.1-CAPI-1.14.1" PROJ="7.1.1" LIBXML="2.9.9" LIBJSON="0.12" LIBPROTOBUF="1.2.1" WAGYU="0.5.0 (Internal)"
SELECT * FROM pgr_version();  --> 3.1.3



-- see README.md for information about loading ATKIS and OSM data into database


-- ************************************************ Workflow: ************************************************

-- create all tables in given order (from folder \tables)
-- load all functions (from folder \functions) into database


-- order of functions calls for the analysis:

-- bring together all needed roads of ATKIS' raw data into relation 'atkis_streets_car'
SELECT atkis_assembleStreets();

-- bring together all needed roads of osm2pgsql import into relation 'osm_2pgsql_notnoded'
SELECT osm_2pgsql_assembleStreets();

-- rename id to edge_id, geom_way to the_geom
SELECT osm_2po_renameColumns();

-- transform CRS from EPSG:3857 and EPSG:4326 to EPSG:25832 (this one is the CRS of ATKIS)
SELECT osm_transformToEPSG25832();

-- insert turn restrictions for test area wilhelmshaven and its surrounding area (only possible for OSM because ATKIS does not provide turn restrictions)
SELECT osm_insertTurnRestrictions();

-- import Hauskoordinaten from local CSV (current path is 'D:\temp\hk_27893_ANSIWindows1252.csv', can be adapted in function importHauskoordinaten()) into table
SELECT importHauskoordinaten();

-- clip all streets and Hauskoordinaten to bboxes, to be able to analyze ATKIS and OSM for exactly the same area (Hauskoordinaten will be clipped to a smaller bbox than road data)
SELECT clipStreetsToBBox(ST_MakeEnvelope(426529, 5925883, 445816, 5942057, 25832));

-- join osm2pgsql and osm2po (geometry from osm2po, thematic attributes from osm2pgsql) into table 'osm_streets_car'
SELECT osm_joinBothDatasets();

-- check and set CRS, if missing
SELECT ST_SRID((SELECT the_geom FROM atkis_streets_car WHERE edge_id IS NOT NULL LIMIT 1)); --> 25832
SELECT Find_SRID('public', 'atkis_streets_car', 'the_geom'); --> 0
SELECT UpdateGeometrySRID('atkis_streets_car', 'the_geom', 25832);
SELECT Find_SRID('public', 'atkis_streets_car', 'the_geom'); --> 25832

-- create the road network for ATKIS
SELECT atkis_makeNetwork();

-- check and set CRS, if missing
SELECT ST_SRID((SELECT the_geom FROM osm_streets_car WHERE edge_id IS NOT NULL LIMIT 1)); --> 25832
SELECT Find_SRID('public', 'osm_streets_car', 'the_geom'); --> 0
SELECT UpdateGeometrySRID('osm_streets_car', 'the_geom', 25832);
SELECT Find_SRID('public', 'osm_streets_car', 'the_geom'); --> 25832

-- create the road network for OSM
SELECT osm_makeNetwork();

-- set weights for edges of network (splitted into multiple queries because of comparison of network in between):
SELECT atkis_setLength();
SELECT osm_setLength();

-- calculate measures / comparison values for comparison of both networks
SELECT compareNetworks();

SELECT atkis_setSpeed();
SELECT osm_setSpeed();

SELECT atkis_setWeights();
SELECT osm_setWeights();

-- write the specified number of randomly chosen Hauskoordinaten into table startingpoints_destinations
SELECT getRandomAddressCoordinates(1000);

-- calculate all routes in ATKIS and OSM (number of route pairs will be the half of number of coordinates specified in query above)
SELECT calcAllRoutes();

-- calculate measures / comparison values for comparison of all routes
SELECT compareRoutes(5);


-- exemplarily create catchment nodes area for ATKIS and OSM from a specific starting point within a specific driving time in seconds
SELECT calcCatchmentNodesPair(605, 50);


-- the qualitative analysis was made by selecting specific routes out of the _routes_car-tables by their route_ids
-- and by selecting their starting points and destinations out of startingpoints_destinations-table
-- and then visualizing them in QGIS
