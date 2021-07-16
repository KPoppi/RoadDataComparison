-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- bring together all needed roads of ATKIS' raw data into relation 'atkis_streets_car'
CREATE OR REPLACE FUNCTION atkis_assembleStreets()
RETURNS VOID
AS $$
BEGIN

    IF EXISTS (SELECT * FROM atkis_streets_car) THEN
        RAISE EXCEPTION 'Table "atkis_streets_car" does already contain streets. Please delete them first.';
    END IF;

    -- Strassenachsen from Basis-DLM that are not from those streets that have Fahrbahnachsen
    INSERT INTO atkis_streets_car(gml_id, the_geom, istTeilVon, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
                                funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial)
    SELECT gml_id, the_geom, istTeilVon, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
        funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial
    FROM (
        SELECT gml_id,
               the_geom,
               istTeilVon,
               verkehrsbedeutungInneroertlich,
               verkehrsbedeutungUeberoertlich,
               funktion,
               zustand,
               anzahlDerFahrstreifen,
               breiteDerFahrbahn,
               oberflaechenmaterial,
               unnest(advstandardmodell) AS unnested_adv
        FROM ax_strassenachse
        ) AS unnested
    WHERE unnested_adv = 'Basis-DLM'
    AND (funktion IS NULL OR funktion <> 1808)  -- exclude pedestrian areas
    AND istTeilVon NOT IN (SELECT istTeilVon FROM ax_fahrbahnachse);

    IF (SELECT EXISTS (SELECT * FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'ax_fahrbahnachse')) THEN
    -- Fahrbahnachsen from Basis-DLM
        INSERT INTO atkis_streets_car(gml_id, the_geom, istTeilVon, funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial)
        SELECT gml_id, the_geom, istTeilVon, funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial
        FROM (
            SELECT gml_id,
                   the_geom,
                   istTeilVon,
                   funktion,
                   zustand,
                   anzahlDerFahrstreifen,
                   breiteDerFahrbahn,
                   oberflaechenmaterial,
                   unnest(advstandardmodell) AS unnested_adv
            FROM ax_fahrbahnachse
            ) AS unnested
        WHERE unnested_adv = 'Basis-DLM'
        AND (funktion IS NULL OR funktion <> 1808);
    END IF;

    -- add "Widmung", "Name" of road and "Fahrbahntrennung"
    UPDATE atkis_streets_car
    SET widmung = ax_strasse.widmung,
        bezeichnung = ax_strasse.bezeichnung,
        name = ax_strasse.name,
        fahrbahntrennung = ax_strasse.fahrbahntrennung
    FROM ax_strasse
    WHERE ax_strasse.gml_id = atkis_streets_car.istTeilVon;

    -- delete non public roads
    DELETE FROM atkis_streets_car
    WHERE widmung = 9997;

END
$$ LANGUAGE plpgsql;


-- create the road network for OSM
CREATE OR REPLACE FUNCTION atkis_makeNetwork()
RETURNS VOID
AS $$
BEGIN

    DROP TABLE IF EXISTS atkis_streets_car_vertices_pgr;

    -- will create table "osm_streets_car_vertices_pgr" that contains the network nodes
    IF (SELECT pgr_createTopology('atkis_streets_car', 0.00001, 'the_geom', 'edge_id') = 'FAIL') THEN
        RAISE EXCEPTION 'pgr_createTopology failed';
    END IF;

    -- needed when not making the network for the first time:
    --PERFORM pgr_createVerticesTable('atkis_streets_car');

    -- analyze isolated segments/edges, dead ends, ...
    IF (SELECT pgr_analyzeGraph('atkis_streets_car', 0.00001, 'the_geom', 'edge_id') = 'FAIL') THEN
        RAISE EXCEPTION 'pgr_analyzeGraph failed';
    END IF;

    ALTER TABLE IF EXISTS atkis_streets_car_vertices_pgr
    RENAME COLUMN id TO node_id;
    ALTER TABLE IF EXISTS atkis_streets_car_vertices_pgr
    ALTER COLUMN node_id TYPE INTEGER;  -- from BIGINT to INTEGER

END
$$ LANGUAGE plpgsql;

-- result:
/*
HINWEIS:  PROCESSING:
HINWEIS:  pgr_createTopology('atkis_streets_car', 1e-05, 'the_geom', 'edge_id', 'source', 'target', rows_where := 'true', clean := f)
HINWEIS:  Performing checks, please wait .....
HINWEIS:  Creating Topology, Please wait...
HINWEIS:  1000 edges processed
HINWEIS:  2000 edges processed
HINWEIS:  3000 edges processed
HINWEIS:  4000 edges processed
HINWEIS:  5000 edges processed
HINWEIS:  6000 edges processed
HINWEIS:  7000 edges processed
HINWEIS:  -------------> TOPOLOGY CREATED FOR  7997 edges
HINWEIS:  Rows with NULL geometry or NULL id: 0
HINWEIS:  Vertices table for table public.atkis_streets_car is: public.atkis_streets_car_vertices_pgr
HINWEIS:  ----------------------------------------------
HINWEIS:  PROCESSING:
HINWEIS:  pgr_analyzeGraph('atkis_streets_car',1e-05,'the_geom','edge_id','source','target','true')
HINWEIS:  Performing checks, please wait ...
HINWEIS:  Analyzing for dead ends. Please wait...
HINWEIS:  Analyzing for gaps. Please wait...
HINWEIS:  Analyzing for isolated edges. Please wait...
HINWEIS:  Analyzing for ring geometries. Please wait...
HINWEIS:  Analyzing for intersections. Please wait...
HINWEIS:              ANALYSIS RESULTS FOR SELECTED EDGES:
HINWEIS:                    Isolated segments: 6
HINWEIS:                            Dead ends: 1690
HINWEIS:  Potential gaps found near dead ends: 0
HINWEIS:               Intersections detected: 79
HINWEIS:                      Ring geometries: 0

Successfully run. Total query runtime: 6 secs 874 msec.
1 rows affected.
*/


-- ****************************** weights for edges of network: ******************************

-- set length of edges
-- unit meters
CREATE OR REPLACE FUNCTION atkis_setLength()
RETURNS VOID
AS $$
BEGIN

    UPDATE atkis_streets_car
    SET distance = ST_Length(the_geom);

END
$$ LANGUAGE plpgsql;


-- set maxspeed of edges
-- unit kilometers per hour
CREATE OR REPLACE FUNCTION atkis_setSpeed()
RETURNS VOID
AS $$
BEGIN

    UPDATE atkis_streets_car
    SET maxspeed = 130  -- Richtgeschwindigkeit auf Autobahnen
    WHERE widmung = 1301;  -- OR bezeichnung LIKE 'A%';  -- "Bundesautobahn"

    UPDATE atkis_streets_car
    SET maxspeed = 100  -- could be 70 or 50
    WHERE widmung = 1303;  -- OR bezeichnung LIKE 'B%';  -- "Bundesstraße"

    UPDATE atkis_streets_car
    SET maxspeed = 70  -- could be 100 or 50
    WHERE widmung = 1305;  -- OR bezeichnung LIKE 'L%';  -- "Landesstraße, Staatsstraße"

    UPDATE atkis_streets_car
    SET maxspeed = 50  -- could be higher
    WHERE widmung = 1306;  -- OR bezeichnung LIKE 'K%';  -- "Kreisstraße"

    UPDATE atkis_streets_car
    SET maxspeed = 30  -- could be 50
    WHERE widmung = 1307;  -- "Gemeindestraße"

    UPDATE atkis_streets_car
    SET maxspeed = 30
    WHERE widmung = 9999;  -- "Sonstiges"

END
$$ LANGUAGE plpgsql;


-- calculate weights
CREATE OR REPLACE FUNCTION atkis_setWeights()
RETURNS VOID
AS $$
BEGIN

    -- set driving time of edges
    -- unit seconds
    -- will be overwritten in some cases afterwards
    UPDATE atkis_streets_car
    SET weights_car = distance * 3.6 / maxspeed::NUMERIC,
        weights_car_reverse = distance * 3.6 / maxspeed::NUMERIC;

    -- oneways
    UPDATE atkis_streets_car
    SET weights_car_reverse = -1
    WHERE fahrtrichtung = TRUE;

    UPDATE atkis_streets_car
    SET weights_car = -1
    WHERE fahrtrichtung = FALSE;


    -- roads initially under construction, not completed
    UPDATE atkis_streets_car
    SET weights_car = -1,
        weights_car_reverse = -1
    WHERE zustand IN (2100, 4000);  -- 2100: Außer Betrieb, stillgelegt, verlassen; 4000: Im Bau

END
$$ LANGUAGE plpgsql;


-- calculate one route (without consideration of turn restrictions because these do not exist in ATKIS)
-- parameters:
-- starting_point_id: primary key of table 'startingpoints_destinations', represents a Hauskoordinate
-- destination_id: primary key of table 'startingpoints_destinations', represents a Hauskoordinate
-- latest_route_id: will become the route_id in table 'atkis_routes_car'
CREATE OR REPLACE FUNCTION atkis_calcRoute(starting_point_id INTEGER, destination_id INTEGER, latest_route_id INTEGER default NULL)
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

    -- for using this function without an OSM equivalent
    IF latest_route_id IS NULL THEN
        latest_route_id = COALESCE((SELECT MAX(route_id) FROM atkis_routes_car) + 1, 1);
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
    starting_point_node_id = atkis_getNearestNode(starting_point_coor_from_addr);
    starting_point_hook_length = ST_Distance(starting_point_coor_from_addr, (SELECT the_geom
                                                                        FROM atkis_streets_car_vertices_pgr
                                                                        WHERE node_id = starting_point_node_id));
    RAISE NOTICE 'starting_point_node_id: %', starting_point_node_id;

    -- destination (procedure is explained in thesis)
    destination_node_id = atkis_getNearestNode(destination_coor_from_addr);
    destination_hook_length = ST_Distance(destination_coor_from_addr, (SELECT the_geom
                                                                  FROM atkis_streets_car_vertices_pgr
                                                                  WHERE node_id = destination_node_id));
    RAISE NOTICE 'destination_node_id: %', destination_node_id;

    IF starting_point_node_id = destination_node_id THEN
        RAISE EXCEPTION 'starting point node and destination node are the same (ID of this node: %)', starting_point_node_id;
    END IF;

    -- calculate and store route 
    INSERT INTO atkis_routes_car(route_id, seq, path_seq, node_id, edge_id, cost, agg_cost, source, target, gml_id, the_geom,
                                distance, maxspeed, weights_car, weights_car_reverse)
    SELECT
        -- "pk_id" is serial
        latest_route_id,
        seq,
        path_seq,
        node,  -- node = vertex
        edge,
        cost,
        agg_cost,
        source,
        target,
        gml_id,
        the_geom,
        distance,
        maxspeed,
        weights_car,
        weights_car_reverse
    -- calculation of route
    FROM pgr_dijkstra(
            'SELECT edge_id AS id, source, target, weights_car AS cost, weights_car_reverse AS reverse_cost
            FROM atkis_streets_car',
            starting_point_node_id,
            destination_node_id,
            TRUE) AS dijkstra
    LEFT JOIN atkis_streets_car ON (dijkstra.edge = atkis_streets_car.edge_id)  -- join needed for cumulating overall costs in 'agg_cost'
    ORDER BY seq;
    IF NOT FOUND THEN
        RAISE WARNING 'ATKIS: no car route found from % to %', starting_point_node_id, destination_node_id;
    END IF;

    -- store corresponding hook-length and ID of Hauskoordinate of starting point
    UPDATE atkis_routes_car
    SET hook_length = starting_point_hook_length,
        hauskoor_id = starting_point_hk_id
    WHERE pk_id = (
                  SELECT pk_id
                  FROM atkis_routes_car
                  WHERE route_id = latest_route_id 
                  ORDER BY seq ASC
                  LIMIT 1);

    -- store corresponding hook-length and ID of Hauskoordinate of destination
    UPDATE atkis_routes_car
    SET hook_length = destination_hook_length,
        hauskoor_id = destination_hk_id
    WHERE pk_id = (
                  SELECT pk_id
                  FROM atkis_routes_car
                  WHERE route_id = latest_route_id 
                  ORDER BY seq DESC
                  LIMIT 1);

END
$$ LANGUAGE plpgsql;


-- returns the ID of the nearest node in network within 0.25 m around the adress_point or, if such does not exist,
-- inserts a new node into network (with shortest distance to nearest edge) and returns its ID
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
CREATE OR REPLACE FUNCTION atkis_getNearestNode(adress_point GEOMETRY)
RETURNS INTEGER -- id of (new) node
AS $$
DECLARE
    latest_node_id INTEGER := (SELECT MAX(node_id) + 1 FROM atkis_streets_car_vertices_pgr);
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
    FROM atkis_streets_car
    ORDER BY ST_Distance(adress_point, the_geom) ASC
    LIMIT 1;
    RAISE NOTICE 'ID of nearest edge: %', nearest_edge_id;

    -- point which is closest to given adresspoint and lies nearly (not exactly) on the nearest edge:
    nearest_point_on_edge = (SELECT ST_ClosestPoint(nearest_edge_geom, adress_point));

    -- check whether there is a node within radius of 0.25 m to nearest_point_on_edge  
    SELECT node_id
    INTO suitable_node_id
    FROM atkis_streets_car_vertices_pgr
    WHERE ST_DWithin(the_geom, nearest_point_on_edge, 0.25) IS TRUE  -- 0.25 m radius
    ORDER BY ST_Distance(the_geom, nearest_point_on_edge) ASC
    LIMIT 1;

    IF FOUND THEN
        -- take this existing node
        RETURN suitable_node_id;
    ELSE
        -- insert a new node into network (with shortest distance to nearest edge) and return its ID
        RAISE NOTICE 'Call function "atkis_makeNewNode"';
        RETURN (SELECT (atkis_makeNewNode(latest_node_id, nearest_edge_geom, nearest_edge_id, nearest_edge_weights_car, nearest_edge_weights_car_reverse, nearest_edge_target, nearest_point_on_edge)));
    END IF;

END
$$ LANGUAGE plpgsql;


-- auxiliary function, called from atkis_getNearestNode(adress_point GEOMETRY)
CREATE OR REPLACE FUNCTION atkis_makeNewNode(latest_node_id INTEGER, nearest_edge_geom GEOMETRY, nearest_edge_id INTEGER, nearest_edge_weights_car NUMERIC(8,2), nearest_edge_weights_car_reverse NUMERIC(8,2), nearest_edge_target INTEGER, nearest_point_on_edge GEOMETRY)
RETURNS INTEGER -- id of new node
AS $$
DECLARE
    splitted_edge GEOMETRY;
    edge_first_part GEOMETRY;
    edge_second_part GEOMETRY;
    -- latest_edge_id has not to be set because it is a SERIAL in atkis_streets_car (different to osm_streets_car)
BEGIN

    -- split the nearest edge of network (nearest to the given adress-point) where the distance is shortest to given adress-point and insert a new node (at that split-point)

    -- split network-edge for later inserting the new node
    -- (splitting the edge into 3 edges instead of 2 because of buffer-polygon - but edge 2 and 3 will be merged again)
    -- buffer is needed because nearest_point_on_edge does not lie exactly on the edge
    splitted_edge = ST_Split(nearest_edge_geom, ST_Buffer(nearest_point_on_edge, 0.00001));

    edge_first_part = ST_GeometryN(splitted_edge, 1);  -- this edge-geometry will replace the primordial edge
    edge_second_part = ST_LineMerge(ST_Union(ST_GeometryN(splitted_edge, 2), ST_GeometryN(splitted_edge, 3))); -- this edge-geometry will be inserted into the network in addition

    -- change the 'atkis_streets_car' table (split edge into two rows):
    IF (nearest_edge_weights_car != -1) AND (nearest_edge_weights_car_reverse != -1) THEN
    -- weights have to be recalculated:

        -- first part of edge
        UPDATE atkis_streets_car
        SET the_geom = edge_first_part,
            distance = ST_Length(edge_first_part),
            weights_car = ST_Length(edge_first_part) * 3.6 / maxspeed::NUMERIC,
            weights_car_reverse = ST_Length(edge_first_part) * 3.6 / maxspeed::NUMERIC,
            target = latest_node_id
        WHERE atkis_streets_car.edge_id = nearest_edge_id;

        -- second part of edge
        INSERT INTO atkis_streets_car(source, target, gml_id, the_geom, istTeilVon,
                                      widmung, bezeichnung, name, fahrbahntrennung, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
                                      funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial,
                                      distance, maxspeed, weights_car, weights_car_reverse)
        SELECT latest_node_id, nearest_edge_target, gml_id, edge_second_part, istTeilVon,
               widmung, bezeichnung, name, fahrbahntrennung, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
               funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial, 
               ST_Length(edge_second_part), maxspeed, (ST_Length(edge_second_part) * 3.6 / maxspeed::NUMERIC), (ST_Length(edge_second_part) * 3.6 / maxspeed::NUMERIC)
        FROM atkis_streets_car
        WHERE atkis_streets_car.edge_id = nearest_edge_id;

    ELSIF (nearest_edge_weights_car = -1) AND (nearest_edge_weights_car_reverse = -1) THEN
    -- weights remain -1:

        -- first part of edge
        UPDATE atkis_streets_car
        SET the_geom = edge_first_part,
            distance = ST_Length(edge_first_part),
            target = latest_node_id
        WHERE atkis_streets_car.edge_id = nearest_edge_id;

        -- second part of edge
        INSERT INTO atkis_streets_car(source, target, gml_id, the_geom, istTeilVon,
                                      widmung, bezeichnung, name, fahrbahntrennung, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
                                      funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial,
                                      distance, maxspeed, weights_car, weights_car_reverse)
        SELECT latest_node_id, nearest_edge_target, gml_id, edge_second_part, istTeilVon,
               widmung, bezeichnung, name, fahrbahntrennung, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
               funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial, 
               ST_Length(edge_second_part), maxspeed, -1, -1
        FROM atkis_streets_car
        WHERE atkis_streets_car.edge_id = nearest_edge_id;

    ELSIF (nearest_edge_weights_car = -1) AND (nearest_edge_weights_car_reverse != -1) THEN
    -- non-reverse-weight remains -1, reverse-weight has to be recalculated:

        -- first part of edge
        UPDATE atkis_streets_car
        SET the_geom = edge_first_part,
            distance = ST_Length(edge_first_part),
            weights_car_reverse = ST_Length(edge_first_part) * 3.6 / maxspeed::NUMERIC,
            target = latest_node_id
        WHERE atkis_streets_car.edge_id = nearest_edge_id;

        -- second part of edge
        INSERT INTO atkis_streets_car(source, target, gml_id, the_geom, istTeilVon,
                                      widmung, bezeichnung, name, fahrbahntrennung, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
                                      funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial,
                                      distance, maxspeed, weights_car, weights_car_reverse)
        SELECT latest_node_id, nearest_edge_target, gml_id, edge_second_part, istTeilVon,
               widmung, bezeichnung, name, fahrbahntrennung, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
               funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial, 
               ST_Length(edge_second_part), maxspeed, -1, (ST_Length(edge_second_part) * 3.6 / maxspeed::NUMERIC)
        FROM atkis_streets_car
        WHERE atkis_streets_car.edge_id = nearest_edge_id;

    ELSIF (nearest_edge_weights_car != -1) AND (nearest_edge_weights_car_reverse = -1) THEN
    -- non-reverse-weight has to be recalculated, reverse-weight remains -1:

        -- first part of edge
        UPDATE atkis_streets_car
        SET the_geom = edge_first_part,
            distance = ST_Length(edge_first_part),
            weights_car = ST_Length(edge_first_part) * 3.6 / maxspeed::NUMERIC,
            target = latest_node_id
        WHERE atkis_streets_car.edge_id = nearest_edge_id;

        -- second part of edge
        INSERT INTO atkis_streets_car(source, target, gml_id, the_geom, istTeilVon,
                                      widmung, bezeichnung, name, fahrbahntrennung, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
                                      funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial,
                                      distance, maxspeed, weights_car, weights_car_reverse)
        SELECT latest_node_id, nearest_edge_target, gml_id, edge_second_part, istTeilVon,
               widmung, bezeichnung, name, fahrbahntrennung, verkehrsbedeutungInneroertlich, verkehrsbedeutungUeberoertlich,
               funktion, zustand, anzahlDerFahrstreifen, breiteDerFahrbahn, oberflaechenmaterial, 
               ST_Length(edge_second_part), maxspeed, (ST_Length(edge_second_part) * 3.6 / maxspeed::NUMERIC), -1
        FROM atkis_streets_car
        WHERE atkis_streets_car.edge_id = nearest_edge_id;

    END IF;

    -- insert the new node to 'atkis_streets_car_vertices_pgr':
    ALTER TABLE IF EXISTS atkis_streets_car_vertices_pgr
    RENAME COLUMN node_id TO id;
    PERFORM pgr_createVerticesTable('atkis_streets_car');
    ALTER TABLE atkis_streets_car_vertices_pgr
    RENAME COLUMN id TO node_id;

    RETURN(latest_node_id); -- ID of the new node

END
$$ LANGUAGE plpgsql;


-- calculate catchment nodes from given starting point and for given driving time in seconds
-- parameters:
-- starting_point_id: primary key of table 'startingpoints_destinations', represents a Hauskoordinate
-- driving_time: desired driving time in seconds
-- latest_catchment_nodes_id: will become the catchment_nodes_id in table 'atkis_catchment_nodes_car'
CREATE OR REPLACE FUNCTION atkis_calcCatchmentNodes(starting_point_id INTEGER, driving_time NUMERIC(9,4), latest_catchment_nodes_id INTEGER default NULL)
RETURNS VOID
AS $$
DECLARE
    starting_point_hk_id INTEGER;  -- PK from table "startingpoints_destinations"
    starting_point_coor_from_addr GEOMETRY;
    starting_point_node_id INTEGER;
    _starting_point_hook_length NUMERIC(9,4);
BEGIN

    -- for using this function without an OSM equivalent
    IF latest_catchment_nodes_id IS NULL THEN
        latest_catchment_nodes_id = COALESCE((SELECT MAX(catchment_nodes_id) FROM atkis_catchment_nodes_car) + 1, 1);
    END IF;

    SELECT id, coordinate
    INTO starting_point_hk_id, starting_point_coor_from_addr
    FROM startingpoints_destinations
    WHERE id = starting_point_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Given "starting_point_id" does not exist as an id (PK) in startingpoints_destinations.';
    END IF;

    -- starting point (as in route calculation)
    starting_point_node_id = atkis_getNearestNode(starting_point_coor_from_addr);
    _starting_point_hook_length = ST_Distance(starting_point_coor_from_addr, (SELECT the_geom
                                                                              FROM atkis_streets_car_vertices_pgr
                                                                              WHERE node_id = starting_point_node_id));
    RAISE NOTICE 'starting_point_node_id: %', starting_point_node_id;

    IF driving_time <= 0 THEN
        RAISE EXCEPTION 'driving distance has to be bigger than 0 seconds (entered driving_time: %)', driving_time;
    END IF;

    -- calculate and store catchment nodes
    INSERT INTO atkis_catchment_nodes_car(catchment_nodes_id, seq, node_id, edge_id_to_node, cost, total_cost_to_node, the_geom)
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
            FROM atkis_streets_car',
            starting_point_node_id,
            driving_time,
            TRUE) AS drivingDistance
	INNER JOIN atkis_streets_car_vertices_pgr ON (drivingDistance.node = atkis_streets_car_vertices_pgr.node_id)
    ORDER BY seq;

    -- store corresponding hook-length and ID of Hauskoordinate of starting point
    UPDATE atkis_catchment_nodes_car
    SET starting_point_hook_length = _starting_point_hook_length,
        start_hk_id = starting_point_hk_id
    WHERE pk_id = (SELECT pk_id
                   FROM atkis_catchment_nodes_car
                   WHERE catchment_nodes_id = latest_catchment_nodes_id
                   ORDER BY seq ASC
                   LIMIT 1);

END
$$ LANGUAGE plpgsql;
