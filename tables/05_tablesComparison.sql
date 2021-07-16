-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- for measures of comparison of both road networks
DROP TABLE IF EXISTS comparison_network;
CREATE TABLE comparison_network(
    id SERIAL PRIMARY KEY,
    data_basis VARCHAR CONSTRAINT unique_data_basis UNIQUE,
    network_length NUMERIC(12,4),  -- overall length of all edges
    motorway_length NUMERIC(12,4),
    name_length NUMERIC(12,4),
    name_ratio NUMERIC(5,2),
    no_name_ref_length NUMERIC(12,4),
    no_name_ref_ratio NUMERIC(5,2),
    maxspeed_length NUMERIC(12,4),
    maxspeed_ratio NUMERIC(5,2),
    oneway_length NUMERIC(12,4),  -- not for completeness analysis
    oneway_ratio NUMERIC(5,2)  -- not for completeness analysis
);


-- for measures of comparison of pairwise calculated routes
-- subtraction for differences: ATKIS - OSM
-- for route_id = 0 it will be filled with average values of all routes
DROP TABLE IF EXISTS comparison_routes;
CREATE TABLE comparison_routes(
    route_id INTEGER PRIMARY KEY,
    atkis_distance NUMERIC(9,4),
    osm_distance NUMERIC(9,4),
    distance_diff NUMERIC(9,4),
    atkis_driving_time NUMERIC(8,2),
    osm_driving_time NUMERIC(8,2),
    driving_time_diff NUMERIC(8,2),
    atkis_hook_length NUMERIC(9,4),
    osm_hook_length NUMERIC(9,4),
    hook_length_diff NUMERIC(9,4),
    buffer NUMERIC(5,2),
    hausdorff_distance NUMERIC(9,4),
    frechet_distance NUMERIC(9,4),  -- not used in analysis
    atkis_geom GEOMETRY,
    osm_geom GEOMETRY,
    start_hk_id INTEGER,
    dest_hk_id INTEGER,
    CONSTRAINT fk_route_start_hk_id
    FOREIGN KEY(start_hk_id)
        REFERENCES startingpoints_destinations(id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_route_dest_hk_id
    FOREIGN KEY(dest_hk_id)
        REFERENCES startingpoints_destinations(id)
        ON DELETE RESTRICT
);
