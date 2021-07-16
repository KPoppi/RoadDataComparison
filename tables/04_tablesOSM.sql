-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- delete tables which are not needed but created by osm2pgsql
DROP TABLE IF EXISTS osm_nodes, osm_roads, osm_ways;


-- for car-streets gotten from osm2pgsql
-- datatypes are VARCHAR because it is text in OSM (not more specified, OSM-mapper can fill in everything, e.g. "none" as "maxspeed")
DROP TABLE IF EXISTS osm_2pgsql_notnoded;
CREATE TABLE osm_2pgsql_notnoded(
    edge_id SERIAL PRIMARY KEY,
    osm_id BIGINT,
    the_geom GEOMETRY,
    maxspeed VARCHAR,
    access VARCHAR,
    barrier VARCHAR,
    bridge VARCHAR,
    construction VARCHAR,  -- road under construction
    duration VARCHAR,
    highway VARCHAR,
    junction VARCHAR,
    lanes VARCHAR,
    layer VARCHAR,
    maxaxleload VARCHAR,
    maxheight VARCHAR,
    maxlength VARCHAR,
    source_maxspeed VARCHAR,  -- named source:maxspeed in OSM
    maxspeed_type VARCHAR,  -- named maxspeed:type in OSM, rather used in UK
    maxweight VARCHAR,
    maxwidth VARCHAR,
    motorcar VARCHAR,
    motor_vehicle VARCHAR,
    name VARCHAR,
    alt_name VARCHAR,
    oneway VARCHAR,
    ref VARCHAR,
    restriction VARCHAR,
    service VARCHAR,  -- description/purpose of service-highways
    surface VARCHAR,
    toll VARCHAR,
    tracktype VARCHAR,
    traffic_signals VARCHAR,
    tunnel VARCHAR,
    vehicle VARCHAR,
    width VARCHAR,
    source_width VARCHAR,  -- named source:width in OSM
    width_lanes VARCHAR,  -- named width:lanes in OSM
    zone_traffic VARCHAR  -- named zone:traffic in OSM
);


-- for the road network of OSM
DROP TABLE IF EXISTS osm_streets_car; --CASCADE;
CREATE TABLE osm_streets_car(
    edge_id INTEGER PRIMARY KEY,  -- from osm2po
    osm_id BIGINT,  -- from osm2po 
    pgsql_osm_id BIGINT,  -- from osm2pgsql, was needed for join
    the_geom GEOMETRY,  -- from osm2po
    source INTEGER,  -- needed for pgr_createTopology, will contain node_ids
    target INTEGER,  -- needed for pgr_createTopology, will contain node_ids
    distance NUMERIC(9,4),  -- for length of edge
    maxspeed VARCHAR,
    weights_car NUMERIC(8,2),  -- for driving time
    weights_car_reverse NUMERIC(8,2),  -- for driving time in reverse direction, needed for oneways
    access VARCHAR,
    barrier VARCHAR,
    bridge VARCHAR,
    construction VARCHAR,
    duration VARCHAR,
    highway VARCHAR,
    junction VARCHAR,
    lanes VARCHAR,
    layer VARCHAR,
    maxaxleload VARCHAR,
    maxheight VARCHAR,
    maxlength VARCHAR,
    source_maxspeed VARCHAR,
    maxspeed_type VARCHAR,
    maxweight VARCHAR,
    maxwidth VARCHAR,
    motorcar VARCHAR,
    motor_vehicle VARCHAR,
    name VARCHAR,
    alt_name VARCHAR,
    oneway VARCHAR,
    ref VARCHAR,
    restriction VARCHAR,
    service VARCHAR,
    surface VARCHAR,
    toll VARCHAR,
    tracktype VARCHAR,
    traffic_signals VARCHAR,
    tunnel VARCHAR,
    vehicle VARCHAR,
    width VARCHAR,
    source_width VARCHAR,
    width_lanes VARCHAR,
    zone_traffic VARCHAR
);


-- represents turn restrictions
DROP TABLE IF EXISTS osm_restrictions;
CREATE TABLE osm_restrictions (
    r_id SERIAL PRIMARY KEY,
    restriction_cost FLOAT8,
    to_edge_id INTEGER,
    from_edge_id INTEGER,  -- is used if via_path is NULL
    via_path TEXT
    /*
    CONSTRAINT fk_osm_to_edge_id
        FOREIGN KEY(to_edge_id)
        REFERENCES osm_streets_car(edge_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_osm_from_edge_id
        FOREIGN KEY(from_edge_id)
        REFERENCES osm_streets_car(edge_id)
        ON DELETE CASCADE
    */
);


-- for calculated routes of OSM, taking turn restrictions into account
DROP TABLE IF EXISTS osm_routes_car;
CREATE TABLE osm_routes_car(
    pk_id SERIAL PRIMARY KEY,
    route_id INTEGER,
    seq INTEGER,
    node_id INTEGER,  -- node = vertex
    edge_id INTEGER,  -- is not a FK to osm_streets_car(edge_id) because at the route's destination the latest 'edge_id' in this table is -1
    cost DOUBLE PRECISION,
    source INTEGER,
    target INTEGER,
    the_geom GEOMETRY,
    osm_id BIGINT,
    maxspeed VARCHAR,
    distance NUMERIC(9,4),
    weights_car NUMERIC(8,2),
    weights_car_reverse NUMERIC(8,2),
    hook_length NUMERIC(9,4),
    hauskoor_id INTEGER,
    CONSTRAINT fk_osm_hk_id
        FOREIGN KEY(hauskoor_id)
        REFERENCES startingpoints_destinations(id)
        ON DELETE RESTRICT
);

-- for calculated catchment nodes of OSM
DROP TABLE IF EXISTS osm_catchment_nodes_car;
CREATE TABLE osm_catchment_nodes_car(
    pk_id SERIAL PRIMARY KEY,
    catchment_nodes_id INTEGER,
    seq INTEGER,
    node_id INTEGER,  -- node = vertex
    edge_id_to_node INTEGER,  -- is not a FK to osm_streets_car(edge_id) because at the route's destination the latest 'edge_id' in this table is -1
    cost DOUBLE PRECISION,
    total_cost_to_node DOUBLE PRECISION,
    the_geom GEOMETRY,
    starting_point_hook_length NUMERIC(9,4),
    start_hk_id INTEGER,
    CONSTRAINT fk_osm_hk_id
        FOREIGN KEY(start_hk_id)
        REFERENCES startingpoints_destinations(id)
        ON DELETE RESTRICT
);
