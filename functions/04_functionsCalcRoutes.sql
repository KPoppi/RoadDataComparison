-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- import Hauskoordinaten from CSV into table:
CREATE OR REPLACE FUNCTION importHauskoordinaten()
RETURNS VOID
AS $$
BEGIN

    COPY hauskoordinaten(NBA, OI, QUA, LAN, RBZ, KRS, GMD, OTT, SSS, HNR, ADZ, coor_easting, coor_northing, STN, PLZ, ONM, ZON, POT)  -- could be reduced by using FROM PROGRAM
    FROM 'D:\temp\hk_27893_ANSIWindows1252.csv'  -- HAS TO BE ADAPTED!
    DELIMITER ';'
    ENCODING 'Windows 1252'
    CSV;

    UPDATE hauskoordinaten
    SET coor_easting = REPLACE(coor_easting, ',', '.'),
        coor_northing = REPLACE(coor_northing, ',', '.');

    UPDATE hauskoordinaten
    -- remove "32" (zone 32) because it is not needed for route calculation and it is clear that CRS is EPSG:25832 for Niedersachsen
    SET the_geom = ST_PointFromText('POINT(' || (TRIM(leading '32' FROM coor_easting))::text || ' ' || coor_northing::text || ')', 25832);

END
$$ LANGUAGE plpgsql;


-- writes randomly chosen Hauskoordinaten into table startingpoints_destinations
-- number_of_coordinates: number of randomly chosen coordinates as desired
CREATE OR REPLACE FUNCTION getRandomAddressCoordinates(number_of_coordinates INTEGER)
RETURNS VOID
AS $$
DECLARE
    min_id INTEGER := (SELECT MIN(id) FROM hauskoordinaten);
    max_id INTEGER := (SELECT MAX(id) FROM hauskoordinaten);
    random_id INTEGER;
    _id INTEGER;
    _the_geom GEOMETRY;
BEGIN

    IF ((SELECT COUNT(*) FROM startingpoints_destinations) > 0) THEN
        RAISE EXCEPTION 'Table "startingpoints_destinations" does already contain coordinates. Please delete them first.';
    END IF;

    -- autoincremental (serial) primary key (id) needed in table hauskoordinaten
    WHILE ((SELECT COUNT(*) FROM startingpoints_destinations) < number_of_coordinates)
        LOOP
            random_id = FLOOR(min_id + RANDOM() * (max_id - min_id));  -- inspired by https://federico-razzoli.com/how-to-return-random-rows-from-a-table
            SELECT id, the_geom
            INTO _id, _the_geom
            FROM hauskoordinaten
            WHERE id = random_id;

            -- if randomly chosen number does exist as an id and if this id was not already taken before:
            IF (_id IS NOT NULL) AND (_id NOT IN (SELECT hauskoordinaten_id FROM startingpoints_destinations)) THEN
                INSERT INTO startingpoints_destinations(hauskoordinaten_id, coordinate) VALUES (_id, _the_geom);
            END IF;
        END LOOP;

END
$$ LANGUAGE plpgsql;


-- calculate all routes in ATKIS and OSM (number of route pairs will be the half of number of coordinates in table startingpoints_destinations)
CREATE OR REPLACE FUNCTION calcAllRoutes()
RETURNS VOID
AS $$
DECLARE
    p RECORD;
    is_starting_point BOOLEAN := TRUE;
    starting_point_id INTEGER;
BEGIN

    FOR p IN (SELECT id FROM startingpoints_destinations)  -- PK
    LOOP
        -- use current as starting point:
        IF is_starting_point THEN
            starting_point_id = p.id;
        -- use current as destination:
        ELSE
            PERFORM calcRoutePair(starting_point_id, p.id);
        END IF;
        is_starting_point = NOT is_starting_point;  -- flip boolean value
    END LOOP;

END
$$ LANGUAGE plpgsql;


-- calculate one route from given starting point to given destination for both data sets (ATKIS and OSM)
-- and store those routes in respective routes-tables
-- parameters:
-- starting_point_id: primary key of table 'startingpoints_destinations', represents a Hauskoordinate
-- destination_id: primary key of table 'startingpoints_destinations', represents a Hauskoordinate
CREATE OR REPLACE FUNCTION calcRoutePair(starting_point_id INTEGER, destination_id INTEGER)
RETURNS VOID
AS $$
DECLARE
    atkis_latest_route_id INTEGER := COALESCE((SELECT MAX(route_id) FROM atkis_routes_car) + 1, 1);
    osm_latest_route_id INTEGER := COALESCE((SELECT MAX(route_id) FROM osm_routes_car) + 1, 1);
    latest_route_id INTEGER := (SELECT GREATEST(atkis_latest_route_id, osm_latest_route_id));
BEGIN

    IF atkis_latest_route_id <> osm_latest_route_id THEN
        RAISE WARNING 'Next possible route IDs to assign to this route are not the same for ATKIS and OSM. Next route ID for ATKIS: %. Next route ID for OSM: %. Next route will get the ID: %',
                       atkis_latest_route_id, osm_latest_route_id, latest_route_id;
    END IF;

    RAISE NOTICE 'Route-ID: %', latest_route_id;

    PERFORM atkis_calcRoute(starting_point_id, destination_id, latest_route_id);
    PERFORM osm_calcRoute(starting_point_id, destination_id, latest_route_id);

END
$$ LANGUAGE plpgsql;


-- calculate one set of catchment nodes from given starting point and for given driving time for both data sets (ATKIS and OSM)
-- store those sets of catchment nodes in respective catchment nodes-tables
-- parameters:
-- starting_point_id: primary key of table 'startingpoints_destinations', represents a Hauskoordinate
-- driving_time: desired driving time in seconds
CREATE OR REPLACE FUNCTION calcCatchmentNodesPair(starting_point_id INTEGER, driving_time NUMERIC(9,4))
RETURNS VOID
AS $$
DECLARE
    atkis_latest_catchment_nodes_id INTEGER := COALESCE((SELECT MAX(catchment_nodes_id) FROM atkis_catchment_nodes_car) + 1, 1);
    osm_latest_catchment_nodes_id INTEGER := COALESCE((SELECT MAX(catchment_nodes_id) FROM osm_catchment_nodes_car) + 1, 1);
    latest_catchment_nodes_id INTEGER := (SELECT GREATEST(atkis_latest_catchment_nodes_id, osm_latest_catchment_nodes_id));
BEGIN

    IF atkis_latest_catchment_nodes_id <> osm_latest_catchment_nodes_id THEN
        RAISE WARNING 'Next possible catchment-nodes IDs to assign to this catchment-nodes are not the same for ATKIS and OSM. Next catchment-nodes ID for ATKIS: %. Next catchment-nodes ID for OSM: %. Next catchment-nodes will get the ID: %',
                       atkis_latest_catchment_nodes_id, osm_latest_catchment_nodes_id, latest_catchment_nodes_id;
    END IF;

    RAISE NOTICE 'Catchment-nodes ID: %', latest_catchment_nodes_id;

    PERFORM atkis_calcCatchmentNodes(starting_point_id, driving_time, latest_catchment_nodes_id);
    PERFORM osm_calcCatchmentNodes(starting_point_id, driving_time, latest_catchment_nodes_id);

END
$$ LANGUAGE plpgsql;
