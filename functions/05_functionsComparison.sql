-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- calculate measures / comparison values for both networks
CREATE OR REPLACE FUNCTION compareNetworks()
RETURNS VOID
AS $$
DECLARE
    atkis_network_length NUMERIC(12,4) := (SELECT SUM(distance)
                                           FROM atkis_streets_car);
    osm_network_length NUMERIC(12,4) := (SELECT SUM(distance)
                                         FROM osm_streets_car);
    atkis_bundesautobahn_length NUMERIC(12,4) := (SELECT SUM(distance)
                                                  FROM atkis_streets_car
                                                  WHERE widmung = 1301);
    osm_motorway_length NUMERIC(12,4) := (SELECT SUM(distance)
                                          FROM osm_streets_car
                                          WHERE highway = 'motorway' OR highway = 'motorway_link');
    atkis_name_length NUMERIC(12,4) := (SELECT SUM(distance)
                                        FROM atkis_streets_car
                                        WHERE name IS NOT NULL);
    osm_name_length NUMERIC(12,4) := (SELECT SUM(distance)
                                      FROM osm_streets_car
                                      WHERE name IS NOT NULL);
    atkis_no_name_ref_length NUMERIC(12,4) := (SELECT SUM(distance)
                                               FROM atkis_streets_car
                                               WHERE name IS NULL AND bezeichnung IS NULL);
    osm_no_name_ref_length NUMERIC(12,4) := (SELECT SUM(distance)
                                             FROM osm_streets_car
                                             WHERE name IS NULL AND ref IS NULL);
    osm_maxspeed_length NUMERIC(12,4) := (SELECT SUM(distance)
                                          FROM osm_streets_car
                                          WHERE maxspeed IS NOT NULL);
    osm_oneway_length NUMERIC(12,4) := (SELECT SUM(distance)
                                        FROM osm_streets_car
                                        WHERE oneway = 'yes');
BEGIN

    -- ******************************* completeness of geometry *******************************

    -- overall length ATKIS-Straßennetzwerk:
    INSERT INTO comparison_network(data_basis, network_length)
    VALUES ('ATKIS', atkis_network_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET network_length = atkis_network_length;

    -- overall length OSM-Straßennetzwerk:
    INSERT INTO comparison_network(data_basis, network_length)
    VALUES ('OSM', osm_network_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET network_length = osm_network_length;


    -- overall length of Bundesautobahnen (motorways) im ATKIS-Straßennetzwerk:
    INSERT INTO comparison_network(data_basis, motorway_length)
    VALUES ('ATKIS', atkis_bundesautobahn_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET motorway_length = atkis_bundesautobahn_length;

    -- overall length of motorways im OSM-Straßennetzwerk:
    INSERT INTO comparison_network(data_basis, motorway_length)
    VALUES ('OSM', osm_motorway_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET motorway_length = osm_motorway_length;


    -- ************************* completeness of thematic attributes *************************

    -- ********** ATKIS:

    -- overall length of edges with street names
    INSERT INTO comparison_network(data_basis, name_length)
    VALUES ('ATKIS', atkis_name_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET name_length = atkis_name_length;

    INSERT INTO comparison_network(data_basis, name_ratio)
    VALUES ('ATKIS', (atkis_name_length / atkis_network_length * 100))
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET name_ratio = (atkis_name_length / atkis_network_length * 100);


    -- overall length of edges with no street names and no Bezeichnung (ref)
    INSERT INTO comparison_network(data_basis, no_name_ref_length)
    VALUES ('ATKIS', atkis_no_name_ref_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET no_name_ref_length = atkis_no_name_ref_length;

    INSERT INTO comparison_network(data_basis, no_name_ref_ratio)
    VALUES ('ATKIS', (atkis_no_name_ref_length / atkis_network_length * 100))
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET no_name_ref_ratio = (atkis_no_name_ref_length / atkis_network_length * 100);


    -- ********** OSM:

    -- overall length of edges with street names
    INSERT INTO comparison_network(data_basis, name_length)
    VALUES ('OSM', osm_name_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET name_length = osm_name_length;

    INSERT INTO comparison_network(data_basis, name_ratio)
    VALUES ('OSM', (osm_name_length / osm_network_length * 100))
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET name_ratio = (osm_name_length / osm_network_length * 100);


    -- overall length of edges with no street names and no Bezeichnung (ref)
    INSERT INTO comparison_network(data_basis, no_name_ref_length)
    VALUES ('OSM', osm_no_name_ref_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET no_name_ref_length = osm_no_name_ref_length;

    INSERT INTO comparison_network(data_basis, no_name_ref_ratio)
    VALUES ('OSM', (osm_no_name_ref_length / osm_network_length * 100))
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET no_name_ref_ratio = (osm_no_name_ref_length / osm_network_length * 100);


    -- overall length of edges with maxspeed
    -- has to be checked before assigning additional maxspeed values
    INSERT INTO comparison_network(data_basis, maxspeed_length)
    VALUES ('OSM', osm_maxspeed_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET maxspeed_length = osm_maxspeed_length;

    INSERT INTO comparison_network(data_basis, maxspeed_ratio)
    VALUES ('OSM', (osm_maxspeed_length / osm_network_length * 100))
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET maxspeed_ratio = (osm_maxspeed_length / osm_network_length * 100);


    -- overall length of edges with oneway
    INSERT INTO comparison_network(data_basis, oneway_length)
    VALUES ('OSM', osm_oneway_length)
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET oneway_length = osm_oneway_length;

    INSERT INTO comparison_network(data_basis, oneway_ratio)
    VALUES ('OSM', (osm_oneway_length / osm_network_length * 100))
    ON CONFLICT ON CONSTRAINT unique_data_basis DO UPDATE
    SET oneway_ratio = (osm_oneway_length / osm_network_length * 100);

END
$$ LANGUAGE plpgsql;


-- calculate measures / comparison values for all routes
-- if the table 'comparison_routes' is already filled, it overwrites it
-- parameters:
-- buffer_radius: radius of the buffer that gets placed around the OSM-route in meters
CREATE OR REPLACE FUNCTION compareRoutes(buffer_radius FLOAT)
RETURNS VOID
AS $$
BEGIN

    DELETE FROM comparison_routes;

    -- at first insert only ATKIS data:
    -- (because routes from ATKIS and OSM have different numbers of edges and therefore different numbers of rows per route in their respective routes-tables)
    INSERT INTO comparison_routes(route_id, atkis_distance, atkis_driving_time, atkis_hook_length, atkis_geom)
    SELECT route_id,
		   SUM(distance),
           -- use SUM(cost) instead of SUM(weights_car) if oneways are included as 'fahrtrichtung', otherwise the driving time would be wrong !!!
           -- because the direction of a oneway is in ATKIS not always the same as the direction of the line-geometry
           -- (this is not the case for OSM because in OSM oneways are in direction of line-geometry)!
           -- but do not use column cost if turn restrictions are included (currently not the case for ATKIS)
           SUM(weights_car), -- do not use if oneways are included! (see note above)
           SUM(hook_length),
           mergeRouteGeom(route_id, 'ATKIS')
    FROM atkis_routes_car
    GROUP BY route_id
    HAVING route_id IN (SELECT DISTINCT a.route_id AS route_id  -- get all route_ids
                        FROM atkis_routes_car AS a
                        INNER JOIN osm_routes_car AS o  -- insert (and compare) only those routes that were calculated for both ATKIS and OSM
                        ON a.route_id = o.route_id)
	ORDER BY route_id;

    -- now insert OSM data:
    UPDATE comparison_routes
    SET osm_distance = o.route_length,
        osm_driving_time = o.route_duration,
        osm_hook_length = o.hook_length,
        osm_geom = mergeRouteGeom(o.route_id, 'OSM')
    FROM (
          SELECT route_id,
                 SUM(distance) AS route_length,
                 SUM(weights_car) AS route_duration,  -- do not use SUM(cost) because column cost contains the turn restriction cost as well
                 SUM(hook_length) AS hook_length
          FROM osm_routes_car
          GROUP BY route_id
          ORDER BY route_id ) AS o
    WHERE comparison_routes.route_id = o.route_id;

    -- at last insert differences and geometry-based data that need both ATKIS and OSM data for their calculation:
    UPDATE comparison_routes
    SET distance_diff = (c.atkis_distance - c.osm_distance),
        driving_time_diff = (c.atkis_driving_time - c.osm_driving_time),
        hook_length_diff = (c.atkis_hook_length - c.osm_hook_length),
        buffer = checkBuffer(buffer_radius, c.osm_geom, c.atkis_geom), -- buffer OSM-route and check percentage of ATKIS within this buffer
        hausdorff_distance = ST_HausdorffDistance(c.atkis_geom, c.osm_geom)::NUMERIC(9,4),
        frechet_distance = ST_FrechetDistance(c.atkis_geom, c.osm_geom)::NUMERIC(9,4),  -- not used in analysis
        start_hk_id = (SELECT hauskoor_id
                       FROM atkis_routes_car  -- hk_ids are the same for ATKIS and OSM
                       WHERE route_id = c.route_id
                       ORDER BY seq ASC
                       LIMIT 1),
        dest_hk_id = (SELECT hauskoor_id
                      FROM atkis_routes_car
                      WHERE route_id = c.route_id
                      ORDER BY seq DESC
                      LIMIT 1)
    FROM (
          SELECT route_id, atkis_distance, osm_distance, atkis_driving_time, osm_driving_time, atkis_hook_length, osm_hook_length, atkis_geom, osm_geom
          FROM comparison_routes
          GROUP BY route_id
          ORDER BY route_id ) AS c
    WHERE comparison_routes.route_id = c.route_id;

    -- insert arithmetic mean values (with route_id 0 because it is a primary key and has to be filled)
    INSERT INTO comparison_routes(route_id, distance_diff, driving_time_diff, hook_length_diff, buffer, hausdorff_distance, frechet_distance)
    SELECT 0, AVG(distance_diff), AVG(driving_time_diff), AVG(hook_length_diff), AVG(buffer), AVG(hausdorff_distance), AVG(frechet_distance)
    FROM comparison_routes;

END
$$ LANGUAGE plpgsql;


-- merge route geometry from multiple table rows into one overall geometry for one table row
-- parameters:
-- _route_id: route_id from table '..._routes_car'
-- data_basis: 'ATKIS' or 'OSM'
CREATE OR REPLACE FUNCTION mergeRouteGeom(_route_id INTEGER, data_basis VARCHAR)
RETURNS GEOMETRY
AS $$
DECLARE
    merged_geom GEOMETRY;
BEGIN

    IF data_basis = 'atkis' OR data_basis = 'ATKIS' THEN
        merged_geom = (SELECT ST_LineMerge(atkis_route_edges)
                       FROM
                           (SELECT ST_Union(the_geom) AS atkis_route_edges  -- put together
                            FROM atkis_routes_car AS a
                            WHERE a.route_id = _route_id) AS atkis_route_union);
    ELSIF data_basis = 'osm' OR data_basis = 'OSM' THEN
        merged_geom = (SELECT ST_LineMerge(osm_route_edges)
                       FROM
                           (SELECT ST_Union(the_geom) AS osm_route_edges  -- put together
                            FROM osm_routes_car AS o
                            WHERE o.route_id = _route_id) AS osm_route_union);
    ELSE
        RAISE EXCEPTION 'invalid data_basis. data_basis must be one of the following: ''atkis'', ''ATKIS'', ''osm'', ''OSM''';
    END IF;
    RETURN(merged_geom);

END
$$ LANGUAGE plpgsql;


-- buffer-method by Goodchild & Hunter
-- parameters:
-- radius: radius of the buffer that gets placed around the route_to_buffer in meters
-- route_to_buffer: geometry of the route to be buffered
-- route_to_check: geometry of the route whose portion lying within the buffer is calculated
-- in this analysis: route_to_buffer: OSM, route_to_check: ATKIS
CREATE OR REPLACE FUNCTION checkBuffer(radius FLOAT, route_to_buffer GEOMETRY, route_to_check GEOMETRY)
RETURNS NUMERIC(5,2)  -- portion of route to check that lies within buffer of reference route (in percent)
AS $$
DECLARE
    route_to_check_length_in_buffer NUMERIC(9,4);
    route_to_check_length_full NUMERIC(9,4);
    percentage_in_buffer NUMERIC(5,2);
BEGIN

    -- length of route to check that lies within buffer of reference route
    route_to_check_length_in_buffer = ST_Length(ST_Intersection(ST_Buffer(route_to_buffer, radius), route_to_check));
    route_to_check_length_full = ST_Length(route_to_check);  -- overall length of route to check
    percentage_in_buffer = route_to_check_length_in_buffer / route_to_check_length_full * 100;
    RETURN percentage_in_buffer;

END
$$ LANGUAGE plpgsql;
