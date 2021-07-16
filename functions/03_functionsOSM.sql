-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- id to edge_id, geom_way to the_geom
CREATE OR REPLACE FUNCTION osm_2po_renameColumns()
RETURNS VOID
AS $$
BEGIN

    ALTER TABLE IF EXISTS osm_2po_4pgr
    RENAME COLUMN id TO edge_id;
    ALTER TABLE IF EXISTS osm_2po_4pgr
    RENAME COLUMN geom_way TO the_geom;

END
$$ LANGUAGE plpgsql;


-- bring together all needed roads of osm2pgsql import into relation 'osm_2pgsql_notnoded'
CREATE OR REPLACE FUNCTION osm_2pgsql_assembleStreets()
RETURNS VOID
AS $$
BEGIN

    IF EXISTS (SELECT * FROM osm_2pgsql_notnoded) THEN
        RAISE EXCEPTION 'Table "osm_2pgsql_notnoded" does already contain streets. Please delete them first.';
    END IF;

    INSERT INTO osm_2pgsql_notnoded(the_geom, osm_id, access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
                                    maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
                                    motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
                                    traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic)
    SELECT way, osm_id, access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
           maxaxleload, maxheight, maxlength, maxspeed, "source:maxspeed", "maxspeed:type", maxweight, maxwidth,
           motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
           traffic_signals, tunnel, vehicle, width, "source:width", "width:lanes", "zone:traffic"
    FROM osm_line
    -- reasons for those highway types: https://wiki.openstreetmap.org/wiki/OSM_tags_for_routing/Access_restrictions#Germany
    -- and: https://wiki.openstreetmap.org/wiki/Routing#Highway-type
    -- no highway=track because it is a agricultural road
    WHERE (highway IN ('motorway', 'motorway_link', 'trunk', 'trunk_link', 'primary', 'primary_link', 'secondary', 'secondary_link',
                      'tertiary', 'tertiary_link', 'unclassified', 'residential', 'living_street', 'service'))
    AND ((access IS NULL OR access NOT IN ('no', 'private', 'customers', 'permit', 'agricultural', 'forestry', 'delivery', 'destination'))
         AND (vehicle IS NULL OR vehicle NOT IN ('no', 'private', 'customers', 'permit', 'agricultural', 'forestry', 'delivery', 'destination'))
         AND (motor_vehicle IS NULL OR motor_vehicle NOT IN ('no', 'private', 'customers', 'permit', 'agricultural', 'forestry', 'delivery', 'destination'))
         AND (motorcar IS NULL OR motorcar NOT IN ('no', 'private', 'customers', 'permit', 'agricultural', 'forestry', 'delivery', 'destination')))
    AND (service IS NULL OR service NOT IN ('parking_aisle', 'emergency_access'));

END
$$ LANGUAGE plpgsql;


-- transform CRS from EPSG:3857 and EPSG:4326 to EPSG:25832 (this one is the CRS of ATKIS):
-- transformation of osm2pgsql data is not necessary because only geometry of osm2po data is used
CREATE OR REPLACE FUNCTION osm_transformToEPSG25832()
RETURNS VOID
AS $$
BEGIN

    -- for osm2pgsql data, should be EPSG:3857 after import
    IF (SELECT ST_SRID((SELECT the_geom FROM osm_2pgsql_notnoded WHERE edge_id IS NOT NULL LIMIT 1)) = 3857) THEN
        UPDATE osm_2pgsql_notnoded
        SET the_geom = ST_Transform(the_geom,
                                    '+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs',  -- from 3857
                                    '+proj=utm +zone=32 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs');  -- to 25832
        PERFORM UpdateGeometrySRID('osm_2pgsql_notnoded', 'the_geom', 25832);
    ELSIF (SELECT ST_SRID((SELECT the_geom FROM osm_2pgsql_notnoded WHERE edge_id IS NOT NULL LIMIT 1)) = 25832) THEN
        RAISE NOTICE 'Table "osm_2pgsql_notnoded" is already in EPSG:25832.';
    ELSE 
        RAISE NOTICE 'CRS of table "osm_2pgsql_notnoded" is neither EPSG:3857 nor EPSG:25832, cannot handle this.';
    END IF;

    -- for osm2po data, should be EPSG:4326 after import
    IF (SELECT ST_SRID((SELECT the_geom FROM osm_2po_4pgr WHERE edge_id IS NOT NULL LIMIT 1)) = 4326) THEN
        UPDATE osm_2po_4pgr
        SET the_geom = ST_Transform(the_geom,
                                    '+proj=longlat +datum=WGS84 +no_defs',  -- from 4326
                                    '+proj=utm +zone=32 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs');  -- to 25832
        PERFORM UpdateGeometrySRID('osm_2po_4pgr', 'the_geom', 25832);
    ELSIF (SELECT ST_SRID((SELECT the_geom FROM osm_2po_4pgr WHERE edge_id IS NOT NULL LIMIT 1)) = 25832) THEN
        RAISE NOTICE 'Table "osm_2po_4pgr" is already in EPSG:25832.';
    ELSE 
        RAISE NOTICE 'CRS of table "osm_2po_4pgr" is neither EPSG:4326 nor EPSG:25832, cannot handle this.';
    END IF;

END
$$ LANGUAGE plpgsql;


-- insert turn restrictions for test area wilhelmshaven and its surrounding area
CREATE OR REPLACE FUNCTION osm_insertTurnRestrictions()
RETURNS VOID
AS $$
BEGIN

    -- no turn allowed from "from_edge_id" onto "to_edge_id", those edge_ids are foreign keys to edge_id in table "osm_streets_car"
    INSERT INTO osm_restrictions (restriction_cost, to_edge_id, from_edge_id, via_path)  -- from_edge_id is used if via_path is NULL
    VALUES
    (10000, 119, 6225, NULL),
    (10000, 6227, 6226, NULL),
    (10000, 5, 11197, NULL),
    (10000, 6228, 5, NULL),
    (10000, 14, 11186, NULL),
    (10000, 17, 10630, NULL),
    (10000, 17, 7356, NULL),
    (10000, 10618, 7356, NULL),
    (10000, 9670, 42, NULL),
    (10000, 9668, 42, NULL),
    (10000, 42, 9668, NULL),
    (10000, 11186, 45, NULL),
    (10000, 9715, 9714, NULL),
    (10000, 11246, 77, NULL),
    (10000, 11183, 119, NULL),
    (10000, 10631, 10629, NULL),
    (10000, 9219, 10629, NULL),
    (10000, 124, 7567, NULL),
    (10000, 1363, 10861, NULL),
    (10000, 4663, 10859, NULL),
    (10000, 10628, 351, NULL),
    (10000, 1081, 10893, NULL),
    (10000, 1080, 10893, NULL),
    (10000, 10616, 10617, NULL),
    (10000, 11229, 11229, NULL),
    (10000, 519, 11217, NULL),
    (10000, 11204, 11204, NULL),
    (10000, 11210, 11210, NULL),
    (10000, 11204, 526, NULL),
    (10000, 11236, 11236, NULL),
    (10000, 527, 11217, NULL),
    (10000, 10623, 517, NULL),
    (10000, 10622, 517, NULL),
    (10000, 1123, 13396, NULL),
    (10000, 10614, 1124, NULL),
    (10000, 10613, 1124, NULL),
    (10000, 9609, 9644, NULL),
    (10000, 1147, 9644, NULL),
    (10000, 9610, 1147, NULL),
    (10000, 1361, 10870, NULL),
    (10000, 11235, 1362, NULL),
    (10000, 10091, 1481, NULL),
    (10000, 1755, 10862, NULL),
    (10000, 1770, 6507, NULL),
    (10000, 1891, 10629, NULL),
    (10000, 13439, 1904, NULL),
    (10000, 1949, 3914, NULL),
    (10000, 6030, 2732, NULL),
    (10000, 13471, 2046, NULL),
    (10000, 2976, 7564, NULL),
    (10000, 10858, 7564, NULL),
    (10000, 2977, 5285, NULL),
    (10000, 10877, 5285, NULL),
    (10000, 3055, 8075, NULL),
    (10000, 3510, 9218, NULL),
    (10000, 10894, 3786, NULL),
    (10000, 9227, 3786, NULL),
    (10000, 9225, 3786, NULL),
    (10000, 10897, 3786, NULL),
    (10000, 10894, 9227, NULL),
    (10000, 3786, 9227, NULL),
    (10000, 9225, 9227, NULL),
    (10000, 10895, 9227, NULL),
    (10000, 10897, 9225, NULL),
    (10000, 3786, 9225, NULL),
    (10000, 9227, 9225, NULL),
    (10000, 10895, 9225, NULL),
    (10000, 3843, 10610, NULL),
    (10000, 10611, 10610, NULL),
    (10000, 10610, 3843, NULL),
    (10000, 10609, 3843, NULL),
    (10000, 7911, 3914, NULL),
    (10000, 4975, 7356, NULL),
    (10000, 5943, 9819, NULL),
    (10000, 7788, 5290, NULL),
    (10000, 5295, 11233, NULL),
    (10000, 5408, 11235, NULL),
    (10000, 11233, 5410, NULL),
    (10000, 5598, 9217, NULL),
    (10000, 5852, 7447, NULL),
    (10000, 5854, 11240, NULL),
    (10000, 5855, 11226, NULL),
    (10000, 5856, 9218, NULL),
    (10000, 6225, 11183, NULL),
    (10000, 6226, 11194, NULL),
    (10000, 11194, 6227, NULL),
    (10000, 11197, 6228, NULL),
    (10000, 6424, 10941, NULL),
    (10000, 6424, 14707, NULL),
    (10000, 10612, 6506, NULL),
    (10000, 10611, 6506, NULL),
    (10000, 10878, 10880, NULL),
    (10000, 7366, 10880, NULL),
    (10000, 6513, 10880, NULL),
    (10000, 10881, 10880, NULL),
    (10000, 10878, 7366, NULL),
    (10000, 10880, 7366, NULL),
    (10000, 6513, 7366, NULL),
    (10000, 10879, 7366, NULL),
    (10000, 10879, 6513, NULL),
    (10000, 7366, 6513, NULL),
    (10000, 10880, 6513, NULL),
    (10000, 10881, 6513, NULL),
    (10000, 10622, 6514, NULL),
    (10000, 10621, 6514, NULL),
    (10000, 6514, 10621, NULL),
    (10000, 10610, 10621, NULL),
    (10000, 6516, 10615, NULL),
    (10000, 9497, 6676, NULL),
    (10000, 9669, 9670, NULL),
    (10000, 7163, 7449, NULL),
    (10000, 7438, 10862, NULL),
    (10000, 7439, 10861, NULL),
    (10000, 8872, 9217, NULL),
    (10000, 11215, 7576, NULL),
    (10000, 11230, 11230, NULL),
    (10000, 8290, 11210, NULL),
    (10000, 11205, 8293, NULL),
    (10000, 8745, 11190, NULL),
    (10000, 9532, 8745, NULL),
    (10000, 8745, 9532, NULL),
    (10000, 13061, 13061, NULL),
    (10000, 11206, 8802, NULL),
    (10000, 11223, 11223, NULL),
    (10000, 11206, 11206, NULL),
    (10000, 8865, 8865, NULL),
    (10000, 8879, 8879, NULL),
    (10000, 11230, 11230, NULL),
    (10000, 8865, 8865, NULL),
    (10000, 11240, 8873, NULL),
    (10000, 9241, 9213, NULL),
    (10000, 9219, 10619, NULL),
    (10000, 10898, 9226, NULL),
    (10000, 10897, 9226, NULL),
    (10000, 9247, 11245, NULL),
    (10000, 11196, 9299, NULL),
    (10000, 9514, 11177, NULL),
    (10000, 9600, 9611, NULL),
    (10000, 9611, 9615, NULL),
    (10000, 9645, 9609, NULL),
    (10000, 9615, 9609, NULL),
    (10000, 9626, 9627, NULL),
    (10000, 9668, 10797, NULL),
    (10000, 9825, 9826, NULL),
    (10000, 10873, 10870, NULL),
    (10000, 11220, 11220, NULL),
    (10000, 10994, 11204, NULL),
    (10000, 11249, 11249, NULL),
    (10000, 11212, 11212, NULL),
    (10000, 11236, 11236, NULL),
    (10000, 11223, 11223, NULL);

END
$$ LANGUAGE plpgsql;


-- join osm2pgsql and osm2po (geometry from osm2po, thematic attributes from osm2pgsql) into table 'osm_streets_car'
CREATE OR REPLACE FUNCTION osm_joinBothDatasets()
RETURNS VOID
AS $$
BEGIN

    IF EXISTS (SELECT * FROM osm_streets_car) THEN
        RAISE EXCEPTION 'Table "osm_streets_car" does already contain streets. Please delete them first.';
    END IF;

    -- new edge_id will be the one from osm2po, not from osm2pgsql (this one will get lost)

    INSERT INTO osm_streets_car(edge_id, the_geom, osm_id, pgsql_osm_id,
                                access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
                                maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
                                motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
                                traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic)
    SELECT po.edge_id AS edge_id, po.the_geom AS the_geom, po.osm_id AS osm_id, pgsql.osm_id AS pgsql_osm_id,
           access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
           maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
           motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
           traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic
    FROM (
         SELECT DISTINCT ON (osm_id) *
         FROM osm_2pgsql_notnoded
         ) AS pgsql
    INNER JOIN osm_2po_4pgr AS po ON pgsql.osm_id = po.osm_id;  -- only those roads that are in both raw OSM data sets

END
$$ LANGUAGE plpgsql;


-- create the road network for OSM
CREATE OR REPLACE FUNCTION osm_makeNetwork()
RETURNS VOID
AS $$
BEGIN

    DROP TABLE IF EXISTS osm_streets_car_vertices_pgr;

    -- will create table "osm_streets_car_vertices_pgr" that contains the network nodes
    IF (SELECT pgr_createTopology('osm_streets_car', 0.00001, 'the_geom', 'edge_id') = 'FAIL') THEN
        RAISE EXCEPTION 'pgr_createTopology failed';
    END IF;

    -- needed when not making the network for the first time:
    --PERFORM pgr_createVerticesTable('osm_streets_car');

    -- analyze isolated segments/edges, dead ends, ...
    IF (SELECT pgr_analyzeGraph('osm_streets_car', 0.00001, 'the_geom', 'edge_id') = 'FAIL') THEN
        RAISE EXCEPTION 'pgr_analyzeGraph failed';
    END IF;

    PERFORM pgr_analyzeOneWay('osm_streets_car',
        -- values of column 'oneway':
        ARRAY['', 'no', 'yes'],  -- source in
        ARRAY['', 'no', 'yes'],  -- source out
        ARRAY['', 'no', 'yes'],  -- target in
        ARRAY['', 'no', 'yes'],   -- target out
        TRUE,
        'oneway',  -- oneway column name of the network table
        'source',  -- source column name of the network table
        'target');  -- target column name of the network table

    ALTER TABLE IF EXISTS osm_streets_car_vertices_pgr
    RENAME COLUMN id TO node_id;
    ALTER TABLE IF EXISTS osm_streets_car_vertices_pgr
    ALTER COLUMN node_id TYPE INTEGER;  -- from BIGINT to INTEGER

END
$$ LANGUAGE plpgsql;

-- result:
/*
HINWEIS:  PROCESSING:
HINWEIS:  pgr_createTopology('osm_streets_car', 1e-05, 'the_geom', 'edge_id', 'source', 'target', rows_where := 'true', clean := f)
HINWEIS:  Performing checks, please wait .....
HINWEIS:  Creating Topology, Please wait...
HINWEIS:  1000 edges processed
HINWEIS:  2000 edges processed
HINWEIS:  3000 edges processed
HINWEIS:  4000 edges processed
HINWEIS:  5000 edges processed
HINWEIS:  6000 edges processed
HINWEIS:  7000 edges processed
HINWEIS:  8000 edges processed
HINWEIS:  9000 edges processed
HINWEIS:  10000 edges processed
HINWEIS:  11000 edges processed
HINWEIS:  -------------> TOPOLOGY CREATED FOR  11720 edges
HINWEIS:  Rows with NULL geometry or NULL id: 0
HINWEIS:  Vertices table for table public.osm_streets_car is: public.osm_streets_car_vertices_pgr
HINWEIS:  ----------------------------------------------
HINWEIS:  PROCESSING:
HINWEIS:  pgr_analyzeGraph('osm_streets_car',1e-05,'the_geom','edge_id','source','target','true')
HINWEIS:  Performing checks, please wait ...
HINWEIS:  Analyzing for dead ends. Please wait...
HINWEIS:  Analyzing for gaps. Please wait...
HINWEIS:  Analyzing for isolated edges. Please wait...
HINWEIS:  Analyzing for ring geometries. Please wait...
HINWEIS:  Analyzing for intersections. Please wait...
HINWEIS:              ANALYSIS RESULTS FOR SELECTED EDGES:
HINWEIS:                    Isolated segments: 102
HINWEIS:                            Dead ends: 2790
HINWEIS:  Potential gaps found near dead ends: 0
HINWEIS:               Intersections detected: 78
HINWEIS:                      Ring geometries: 78
HINWEIS:  PROCESSING:
HINWEIS:  pgr_analyzeOneway('osm_streets_car','{"",no,yes}','{"",no,yes}','{"",no,yes}','{"",no,yes}','oneway','source','target',t)
HINWEIS:  Analyzing graph for one way street errors.
HINWEIS:  Analysis 25% complete ...
HINWEIS:  Analysis 50% complete ...
HINWEIS:  Analysis 75% complete ...
HINWEIS:  Analysis 100% complete ...
HINWEIS:  Found 0 potential problems in directionality

Successfully run. Total query runtime: 11 secs 164 msec.
1 rows affected.
*/


-- ****************************** weights for edges of network: ******************************

-- set length of edges
-- unit meters
CREATE OR REPLACE FUNCTION osm_setLength()
RETURNS VOID
AS $$
BEGIN

    UPDATE osm_streets_car
    SET distance = ST_Length(the_geom);

END
$$ LANGUAGE plpgsql;


-- set missing maxspeed of edges
-- unit kilometers per hour
CREATE OR REPLACE FUNCTION osm_setSpeed()
RETURNS VOID
AS $$
BEGIN

    -- motorway:
    UPDATE osm_streets_car
    SET maxspeed = 130  -- "Richtgeschwindigkeit" / recommended speed
    WHERE (maxspeed = 'none' OR maxspeed IS NULL) AND highway = 'motorway';

    UPDATE osm_streets_car
    SET maxspeed = 55
    WHERE (maxspeed = 'none' OR maxspeed IS NULL) AND highway = 'motorway_link';  

    -- rural:
    UPDATE osm_streets_car
    SET maxspeed = 100
    WHERE maxspeed IS NULL AND (maxspeed_type = 'DE:rural' OR zone_traffic = 'DE:rural');
    -- cf. https://wiki.openstreetmap.org/wiki/DE:Key:maxspeed:type
    -- cf. https://wiki.openstreetmap.org/wiki/Key:zone:traffic

    -- urban:
    UPDATE osm_streets_car
    SET maxspeed = 50
    WHERE maxspeed IS NULL AND (maxspeed_type = 'DE:urban' OR zone_traffic = 'DE:urban');
    -- cf. https://wiki.openstreetmap.org/wiki/DE:Key:maxspeed:type
    -- cf. https://wiki.openstreetmap.org/wiki/Key:zone:traffic

    -- used for trunks
    UPDATE osm_streets_car
    SET maxspeed = 130
    WHERE maxspeed = 'none';

    -- trunk:
    UPDATE osm_streets_car
    SET maxspeed = 100  -- but there are also trunks with separated lanes in both directions where 130 would be fine
    WHERE maxspeed IS NULL AND highway = 'trunk';

    UPDATE osm_streets_car
    SET maxspeed = 55
    WHERE maxspeed IS NULL AND highway = 'trunk_link';

    -- primary:
    UPDATE osm_streets_car
    SET maxspeed = 70 -- could be 100 or 50
    WHERE maxspeed IS NULL AND highway = 'primary';

    UPDATE osm_streets_car
    SET maxspeed = 50
    WHERE maxspeed IS NULL AND highway = 'primary_link';

    -- secondary / tertiary:
    UPDATE osm_streets_car
    SET maxspeed = 60 -- could be 100, 70 or 50
    WHERE maxspeed IS NULL AND highway = 'secondary';

    UPDATE osm_streets_car
    SET maxspeed = 50
    WHERE maxspeed IS NULL AND highway = 'tertiary';

    UPDATE osm_streets_car
    SET maxspeed = 40
    WHERE maxspeed IS NULL AND (highway = 'secondary_link' OR highway = 'tertiary_link');

    -- unclassified, residential, service, living_street:
    UPDATE osm_streets_car
    SET maxspeed = 50
    WHERE maxspeed IS NULL AND highway = 'unclassified';

    UPDATE osm_streets_car
    SET maxspeed = 30
    WHERE maxspeed IS NULL AND (highway = 'residential' OR maxspeed_type = 'DE:zone30');

    UPDATE osm_streets_car
    SET maxspeed = 20
    WHERE maxspeed IS NULL AND (highway = 'service' OR maxspeed_type = 'DE:zone20');

    UPDATE osm_streets_car
    SET maxspeed = 7
    WHERE (maxspeed IS NULL AND highway = 'living_street') OR maxspeed = 'walk';

END
$$ LANGUAGE plpgsql;


-- calculate weights
CREATE OR REPLACE FUNCTION osm_setWeights()
RETURNS VOID
AS $$
BEGIN

    -- set driving time of edges
    -- unit seconds
    -- will be overwritten in some cases afterwards
    UPDATE osm_streets_car
    SET weights_car = distance * 3.6 / maxspeed::NUMERIC,
        weights_car_reverse = distance * 3.6 / maxspeed::NUMERIC;

    -- oneways
    UPDATE osm_streets_car
    SET weights_car_reverse = -1
    WHERE oneway = 'yes' OR oneway = 'true' OR oneway = '1';

    UPDATE osm_streets_car
    SET weights_car = -1
    WHERE oneway LIKE '-1';

    -- roads initially under construction, not completed
    UPDATE osm_streets_car
    SET weights_car = -1,
        weights_car_reverse = -1
    WHERE highway LIKE 'construction';

END
$$ LANGUAGE plpgsql;


-- calculate one route (with consideration of turn restrictions)
-- parameters:
-- starting_point_id: primary key of table 'startingpoints_destinations', represents a Hauskoordinate
-- destination_id: primary key of table 'startingpoints_destinations', represents a Hauskoordinate
-- latest_route_id: will become the route_id in table 'osm_routes_car'
CREATE OR REPLACE FUNCTION osm_calcRoute(starting_point_id INTEGER, destination_id INTEGER, latest_route_id INTEGER default NULL) 
RETURNS VOID
AS $$
DECLARE
    starting_point_hk_id INTEGER;  -- PK from table "startingpoints_destinations"
    destination_hk_id INTEGER;  -- PK from table "startingpoints_destinations"
    starting_point_coor_from_addr GEOMETRY;
    destination_coor_from_addr GEOMETRY;
    starting_point_node_id INTEGER;
    destination_node_id INTEGER;
    starting_point_hook_length NUMERIC(9,4);
    destination_hook_length NUMERIC(9,4);
BEGIN

    -- for using this function without an ATKIS equivalent
    IF latest_route_id IS NULL THEN
        latest_route_id = COALESCE((SELECT MAX(route_id) FROM osm_routes_car) + 1, 1);
    END IF;

    SELECT id, coordinate
    INTO starting_point_hk_id, starting_point_coor_from_addr
    FROM startingpoints_destinations
    WHERE id = starting_point_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Given "starting_point_id" does not exist as an id (PK) in startingpoints_destinations.';
    END IF;

    SELECT id, coordinate
    INTO destination_hk_id, destination_coor_from_addr
    FROM startingpoints_destinations
    WHERE id = destination_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Given "destination_id" does not exist as an id (PK) in startingpoints_destinations.';
    END IF;

    -- starting point (procedure is explained in thesis)
    starting_point_node_id = osm_getNearestNode(starting_point_coor_from_addr);
    starting_point_hook_length = ST_Distance(starting_point_coor_from_addr, (SELECT the_geom
                                                                             FROM osm_streets_car_vertices_pgr
                                                                             WHERE node_id = starting_point_node_id));
    RAISE NOTICE 'starting_point_node_id: %', starting_point_node_id;

    -- destination (procedure is explained in thesis)
    destination_node_id = osm_getNearestNode(destination_coor_from_addr);
    destination_hook_length = ST_Distance(destination_coor_from_addr, (SELECT the_geom
                                                                       FROM osm_streets_car_vertices_pgr
                                                                       WHERE node_id = destination_node_id));
    RAISE NOTICE 'destination_node_id: %', destination_node_id;

    IF starting_point_node_id = destination_node_id THEN
        RAISE EXCEPTION 'starting point node and destination node are the same (ID of this node: %)', starting_point_node_id;
    END IF;

    -- calculate and store route 
    INSERT INTO osm_routes_car(route_id, seq, node_id, edge_id, cost, source, target, the_geom,
                               osm_id, maxspeed, distance, weights_car, weights_car_reverse)
    SELECT
        -- "pk_id" is serial
        latest_route_id,
        seq + 1,  -- because seq in return of function pgr_trsp begins with 0 but seq in return of function pgr_dijkstra begins with 1
        id1,  -- is node_id (node = vertex)
        id2,  -- is edge_id
        cost,
        --agg_cost,  -- agg_cost is not in result of pgr_trsp()
        source,
        target,
        the_geom,
        osm_id,
        maxspeed,
        distance,
        weights_car,
        weights_car_reverse
    -- calculation of route
    FROM pgr_trsp(
            'SELECT edge_id::INTEGER AS id, source::INTEGER, target::INTEGER, weights_car::float8 AS cost, weights_car_reverse::float8 AS reverse_cost
            FROM osm_streets_car',
            starting_point_node_id,
            destination_node_id,
            TRUE,
            TRUE,
            -- to_cost: turn restriction cost
            'SELECT
                restriction_cost::FLOAT8 AS to_cost, 
                to_edge_id::INTEGER AS target_id,
                from_edge_id || coalesce('','' || via_path, '''') AS via_path
            FROM osm_restrictions'
            ) AS trsp
            -- result: id1 are the node_ids, id2 are the edge_ids, cost is not cumulated
    LEFT JOIN osm_streets_car ON (trsp.id2 = osm_streets_car.edge_id)
    ORDER BY seq;
    -- when using pgr_trsp and no path is found, it often (see its doc) throws an exception (ERROR: FEHLER:  Error computing path: Path Not Found)
    -- and does not return an empty set, in that case the following "if" would be useless:
    IF NOT FOUND THEN
        RAISE WARNING 'OSM: no TRSP-car route found from % to %', starting_point_node_id, destination_node_id;
    END IF;

    -- store corresponding hook-length and ID of Hauskoordinate of starting point
    UPDATE osm_routes_car
    SET hook_length = starting_point_hook_length,
        hauskoor_id = starting_point_hk_id
    WHERE pk_id = (SELECT pk_id
                   FROM osm_routes_car
                   WHERE route_id = latest_route_id 
                   ORDER BY seq ASC
                   LIMIT 1);

    -- store corresponding hook-length and ID of Hauskoordinate of destination
    UPDATE osm_routes_car
    SET hook_length = destination_hook_length,
        hauskoor_id = destination_hk_id
    WHERE pk_id = (SELECT pk_id
                   FROM osm_routes_car
                   WHERE route_id = latest_route_id 
                   ORDER BY seq DESC
                   LIMIT 1);

EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'OSM-Route with ID % could not be calculated.', latest_route_id;

END
$$ LANGUAGE plpgsql;


-- returns the ID of the nearest node in network within 0.25 m around the adress_point or, if such does not exist,
-- inserts a new node into network (with shortest distance to nearest edge) and returns its ID.
-- normally a new node will be inserted, since none of the existing nodes will be within this small radius.
-- if no new node is inserted but an existing node within the radius of 0.25 m is used,
-- a route could be distorted by a maximum of 0.5 m in length.
-- from the point of view of car routing, this is a very small length and therefore insignificant for the comparison.
-- this check for an already existing node is mainly intended for the case that the same Hauskoordinate is used several times,
-- where a new node should not be inserted several times.
-- an alternative for such a case is the storage of a reference between the Hauskoordinate and its corresponding inserted node
-- returns: id of nearest node
-- parameters:
-- adress_point: geometry of Hauskoordinate
CREATE OR REPLACE FUNCTION osm_getNearestNode(adress_point GEOMETRY)
RETURNS INTEGER -- id of (new) node
AS $$
DECLARE
    latest_node_id INTEGER := (SELECT MAX(node_id) + 1 FROM osm_streets_car_vertices_pgr);
    nearest_edge_geom GEOMETRY;
    nearest_edge_id INTEGER;
    nearest_edge_weights_car NUMERIC(8,2);
    nearest_edge_weights_car_reverse NUMERIC(8,2);
    nearest_edge_target INTEGER;
    nearest_point_on_edge GEOMETRY;
    suitable_node_id INTEGER;
    splitted_edge GEOMETRY;
    edge_first_part GEOMETRY;
    edge_second_part GEOMETRY;

BEGIN

    -- get nearest edge:
    SELECT the_geom, edge_id, weights_car, weights_car_reverse, target
    INTO nearest_edge_geom, nearest_edge_id, nearest_edge_weights_car, nearest_edge_weights_car_reverse, nearest_edge_target
    FROM osm_streets_car
    ORDER BY ST_Distance(adress_point, the_geom) ASC
    LIMIT 1;
    RAISE NOTICE 'ID of nearest edge: %', nearest_edge_id;

    -- point which is closest to given adresspoint and lies nearly (not exactly) on the nearest edge:
    nearest_point_on_edge = (SELECT ST_ClosestPoint(nearest_edge_geom, adress_point));

    -- check whether there is a node within radius of 0.25 m to nearest_point_on_edge  
    SELECT node_id
    INTO suitable_node_id
    FROM osm_streets_car_vertices_pgr
    WHERE ST_DWithin(the_geom, nearest_point_on_edge, 0.25) IS TRUE  -- 0.25 m radius
    ORDER BY ST_Distance(the_geom, nearest_point_on_edge) ASC
    LIMIT 1;

    IF FOUND THEN
        -- take this existing node
        RETURN suitable_node_id;

    ELSE
        -- insert a new node into network (with shortest distance to nearest edge) and return its ID
        RAISE NOTICE 'Call function "osm_makeNewNode"';
        RETURN (SELECT (osm_makeNewNode(latest_node_id, nearest_edge_geom, nearest_edge_id, nearest_edge_weights_car, nearest_edge_weights_car_reverse, nearest_edge_target, nearest_point_on_edge)));
    END IF;

END
$$ LANGUAGE plpgsql;


-- auxiliary function, called from osm_getNearestNode(adress_point GEOMETRY)
CREATE OR REPLACE FUNCTION osm_makeNewNode(latest_node_id INTEGER, nearest_edge_geom GEOMETRY, nearest_edge_id INTEGER, nearest_edge_weights_car NUMERIC(8,2), nearest_edge_weights_car_reverse NUMERIC(8,2), nearest_edge_target INTEGER, nearest_point_on_edge GEOMETRY)
RETURNS INTEGER -- id of new node
AS $$
DECLARE
    splitted_edge GEOMETRY;
    edge_first_part GEOMETRY;
    edge_second_part GEOMETRY;
    latest_edge_id INTEGER := (SELECT MAX(edge_id) + 1 FROM osm_streets_car);  -- has to be set explicitly because it is no SERIAL
BEGIN

    -- split the nearest edge of network (nearest to the given adress-point) where the distance is shortest to given adress-point and insert a new node (at that split-point)

    -- split network-edge for later inserting the new node
    -- (splitting the edge into 3 edges instead of 2 because of buffer-polygon - but edge 2 and 3 will be merged again)
    -- buffer is needed because nearest_point_on_edge does not lie exactly on the edge
    splitted_edge = ST_Split(nearest_edge_geom, ST_Buffer(nearest_point_on_edge, 0.00001));

    edge_first_part = ST_GeometryN(splitted_edge, 1);  -- this edge-geometry will replace the primordial edge
    edge_second_part = ST_LineMerge(ST_Union(ST_GeometryN(splitted_edge, 2), ST_GeometryN(splitted_edge, 3))); -- this edge-geometry will be inserted into the network in addition

    -- change the 'osm_streets_car' table (split edge into two rows):
    IF (nearest_edge_weights_car != -1) AND (nearest_edge_weights_car_reverse != -1) THEN
    -- weights have to be recalculated:

        -- first part of edge
        UPDATE osm_streets_car
        SET the_geom = edge_first_part,
            distance = ST_Length(edge_first_part),
            weights_car = ST_Length(edge_first_part) * 3.6 / maxspeed::NUMERIC,
            weights_car_reverse = ST_Length(edge_first_part) * 3.6 / maxspeed::NUMERIC,
            target = latest_node_id
        WHERE osm_streets_car.edge_id = nearest_edge_id;

        -- second part of edge
        INSERT INTO osm_streets_car(edge_id, source, target, the_geom, osm_id, pgsql_osm_id,
                                    access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
                                    maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
                                    motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
                                    traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic,
                                    distance, weights_car, weights_car_reverse)
        SELECT latest_edge_id, latest_node_id, nearest_edge_target, edge_second_part, osm_id, pgsql_osm_id,
               access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
               maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
               motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
               traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic,
               ST_Length(edge_second_part), (ST_Length(edge_second_part) * 3.6 / maxspeed::NUMERIC), (ST_Length(edge_second_part) * 3.6 / maxspeed::NUMERIC)
        FROM osm_streets_car
        WHERE osm_streets_car.edge_id = nearest_edge_id;

    ELSIF (nearest_edge_weights_car = -1) AND (nearest_edge_weights_car_reverse = -1) THEN
    -- weights remain -1:

        -- first part of edge
        UPDATE osm_streets_car
        SET the_geom = edge_first_part,
            distance = ST_Length(edge_first_part),
            target = latest_node_id
        WHERE osm_streets_car.edge_id = nearest_edge_id;

        -- second part of edge
        INSERT INTO osm_streets_car(edge_id, source, target, the_geom, osm_id, pgsql_osm_id,
                                    access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
                                    maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
                                    motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
                                    traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic,
                                    distance, weights_car, weights_car_reverse)
        SELECT latest_edge_id, latest_node_id, nearest_edge_target, edge_second_part, osm_id, pgsql_osm_id,
               access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
               maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
               motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
               traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic,
               ST_Length(edge_second_part), -1, -1
        FROM osm_streets_car
        WHERE osm_streets_car.edge_id = nearest_edge_id;

    ELSIF (nearest_edge_weights_car = -1) AND (nearest_edge_weights_car_reverse != -1) THEN
    -- non-reverse-weight remains -1, reverse-weight has to be recalculated:

        -- first part of edge
        UPDATE osm_streets_car
        SET the_geom = edge_first_part,
            distance = ST_Length(edge_first_part),
            weights_car_reverse = ST_Length(edge_first_part) * 3.6 / maxspeed::NUMERIC,
            target = latest_node_id
        WHERE osm_streets_car.edge_id = nearest_edge_id;

        -- second part of edge
        INSERT INTO osm_streets_car(edge_id, source, target, the_geom, osm_id, pgsql_osm_id,
                                    access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
                                    maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
                                    motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
                                    traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic,
                                    distance, weights_car, weights_car_reverse)
        SELECT latest_edge_id, latest_node_id, nearest_edge_target, edge_second_part, osm_id, pgsql_osm_id,
               access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
               maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
               motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
               traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic,
               ST_Length(edge_second_part), -1, (ST_Length(edge_second_part) * 3.6 / maxspeed::NUMERIC)
        FROM osm_streets_car
        WHERE osm_streets_car.edge_id = nearest_edge_id;

    ELSIF (nearest_edge_weights_car != -1) AND (nearest_edge_weights_car_reverse = -1) THEN
    -- non-reverse-weight has to be recalculated, reverse-weight remains -1:

        -- first part of edge
        UPDATE osm_streets_car
        SET the_geom = edge_first_part,
            distance = ST_Length(edge_first_part),
            weights_car = ST_Length(edge_first_part) * 3.6 / maxspeed::NUMERIC,
            target = latest_node_id
        WHERE osm_streets_car.edge_id = nearest_edge_id;

        -- second part of edge
        INSERT INTO osm_streets_car(edge_id, source, target, the_geom, osm_id, pgsql_osm_id,
                                    access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
                                    maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
                                    motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
                                    traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic,
                                    distance, weights_car, weights_car_reverse)
        SELECT latest_edge_id, latest_node_id, nearest_edge_target, edge_second_part, osm_id, pgsql_osm_id,
               access, barrier, bridge, construction, duration, highway, junction, lanes, layer,
               maxaxleload, maxheight, maxlength, maxspeed, source_maxspeed, maxspeed_type, maxweight, maxwidth,
               motorcar, motor_vehicle, name, alt_name, oneway, ref, restriction, service, surface, toll, tracktype,
               traffic_signals, tunnel, vehicle, width, source_width, width_lanes, zone_traffic,
               ST_Length(edge_second_part), (ST_Length(edge_second_part) * 3.6 / maxspeed::NUMERIC), -1
        FROM osm_streets_car
        WHERE osm_streets_car.edge_id = nearest_edge_id;

    END IF;

    -- insert new node to 'osm_streets_car_vertices_pgr':
    ALTER TABLE IF EXISTS osm_streets_car_vertices_pgr
    RENAME COLUMN node_id TO id;
    PERFORM pgr_createVerticesTable('osm_streets_car');
    ALTER TABLE IF EXISTS osm_streets_car_vertices_pgr
    RENAME COLUMN id TO node_id;

    RETURN(latest_node_id); -- ID of the new node

END
$$ LANGUAGE plpgsql;


-- calculate catchment nodes from given starting point and for given driving time in seconds
-- (without consideration of turn restrictions because pgr_drivingDistance does not support them)
-- parameters:
-- starting_point_id: primary key of table 'startingpoints_destinations', represents a Hauskoordinate
-- driving_time: desired driving time in seconds
-- latest_catchment_nodes_id: will become the catchment_nodes_id in table 'osm_catchment_nodes_car'
CREATE OR REPLACE FUNCTION osm_calcCatchmentNodes(starting_point_id INTEGER, driving_time NUMERIC(9,4), latest_catchment_nodes_id INTEGER default NULL) 
RETURNS VOID
AS $$
DECLARE
    starting_point_hk_id INTEGER;  -- PK from table "startingpoints_destinations"
    starting_point_coor_from_addr GEOMETRY;
    starting_point_node_id INTEGER;
    _starting_point_hook_length NUMERIC(9,4);
BEGIN

    -- for using this function without an ATKIS equivalent
    IF latest_catchment_nodes_id IS NULL THEN
        latest_catchment_nodes_id = COALESCE((SELECT MAX(catchment_nodes_id) FROM osm_catchment_nodes_car) + 1, 1);
    END IF;
    
    SELECT id, coordinate
    INTO starting_point_hk_id, starting_point_coor_from_addr
    FROM startingpoints_destinations
    WHERE id = starting_point_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Given "starting_point_id" does not exist as an id (PK) in startingpoints_destinations.';
    END IF;

    -- starting point (as in route calculation)
    starting_point_node_id = osm_getNearestNode(starting_point_coor_from_addr);
    _starting_point_hook_length = ST_Distance(starting_point_coor_from_addr, (SELECT the_geom
                                                                              FROM osm_streets_car_vertices_pgr
                                                                              WHERE node_id = starting_point_node_id));
    RAISE NOTICE 'starting_point_node_id: %', starting_point_node_id;

    IF driving_time <= 0 THEN
        RAISE EXCEPTION 'driving distance has to be bigger than 0 seconds (entered driving_time: %)', driving_time;
    END IF;

    -- calculate and store catchment nodes
    INSERT INTO osm_catchment_nodes_car(catchment_nodes_id, seq, node_id, edge_id_to_node, cost, total_cost_to_node, the_geom)
    SELECT
        --"pk_id" is serial
        latest_catchment_nodes_id,
        seq,
        node,  -- node = vertex
        edge,
        cost,
        agg_cost,
        the_geom
    -- calculating of catchment nodes
    FROM pgr_drivingDistance(
            'SELECT edge_id AS id, source, target, weights_car AS cost, weights_car_reverse AS reverse_cost
            FROM osm_streets_car',
            starting_point_node_id,
            driving_time,
            TRUE) AS drivingDistance
    INNER JOIN osm_streets_car_vertices_pgr ON (drivingDistance.node = osm_streets_car_vertices_pgr.node_id)
    ORDER BY seq;

    -- store corresponding hook-length and ID of Hauskoordinate of starting point
    UPDATE osm_catchment_nodes_car
    SET starting_point_hook_length = _starting_point_hook_length,
        start_hk_id = starting_point_hk_id
    WHERE pk_id = (SELECT pk_id
                   FROM osm_catchment_nodes_car
                   WHERE catchment_nodes_id = latest_catchment_nodes_id
                   ORDER BY seq ASC
                   LIMIT 1);

END
$$ LANGUAGE plpgsql;
