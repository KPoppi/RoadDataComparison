-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- delete tables which are not needed but loaded by PostNAS
DROP TABLE IF EXISTS alkis_beziehungen, ax_bahnstrecke, ax_bahnverkehr, ax_bahnverkehrsanlage, ax_bauwerkimgewaesserbereich,
ax_bauwerkoderanlagefuerindustrieundgewerbe, ax_bauwerkoderanlagefuersportfreizeitunderholung, ax_boeschungkliff,
ax_dammwalldeich, ax_einrichtungenfuerdenschiffsverkehr, ax_flaechebesondererfunktionalerpraegung, ax_flaechegemischternutzung,
ax_fliessgewaesser, ax_flugverkehr, ax_flugverkehrsanlage, ax_friedhof, ax_gehoelz, ax_gelaendekante, ax_gewaesserachse,
ax_gewaessermerkmal, ax_gewaesserstationierungsachse, ax_hafen, ax_hafenbecken, ax_industrieundgewerbeflaeche, ax_insel,
ax_kanal, ax_kommunalesgebiet, ax_landwirtschaft, ax_leitung, ax_meer, ax_moor, ax_naturumweltoderbodenschutzrecht,
ax_schiffsverkehr, ax_schleuse, ax_schutzgebietnachnaturumweltoderbodenschutzrecht, ax_schutzzone,
ax_sonstigesbauwerkodersonstigeeinrichtung, ax_sonstigesrecht, ax_sportfreizeitunderholungsflaeche, ax_stehendesgewaesser,
ax_transportanlage, ax_turm, ax_unlandvegetationsloseflaeche, ax_vegetationsmerkmal, ax_wald, ax_wasserlauf, ax_wegpfadsteig,
ax_wohnbauflaeche, ax_wohnplatz;

ALTER TABLE IF EXISTS ax_strassenachse
ADD COLUMN IF NOT EXISTS verkehrsbedeutungInneroertlich INTEGER,
ADD COLUMN IF NOT EXISTS verkehrsbedeutungUeberoertlich INTEGER,
ADD COLUMN IF NOT EXISTS funktion INTEGER, -- Fußgängerzone 1808 (G)
ADD COLUMN IF NOT EXISTS zustand INTEGER,  -- Außer Betrieb, stillgelegt, verlassen 2100 (G); Im Bau 4000 (G)
ADD COLUMN IF NOT EXISTS anzahlDerFahrstreifen INTEGER,
ADD COLUMN IF NOT EXISTS breiteDerFahrbahn NUMERIC(3,1),
ADD COLUMN IF NOT EXISTS oberflaechenmaterial INTEGER;

ALTER TABLE IF EXISTS ax_fahrbahnachse
ADD COLUMN IF NOT EXISTS funktion INTEGER, -- Fußgängerzone 1808 (G)
ADD COLUMN IF NOT EXISTS zustand INTEGER,  -- Außer Betrieb, stillgelegt, verlassen 2100 (G); Im Bau 4000 (G)
ADD COLUMN IF NOT EXISTS anzahlDerFahrstreifen INTEGER,
ADD COLUMN IF NOT EXISTS breiteDerFahrbahn NUMERIC(3,1),
ADD COLUMN IF NOT EXISTS oberflaechenmaterial INTEGER;

ALTER TABLE IF EXISTS ax_strasse
ADD COLUMN IF NOT EXISTS bezeichnung VARCHAR,
ADD COLUMN IF NOT EXISTS fahrbahntrennung INTEGER;


-- for the road network of ATKIS
DROP TABLE IF EXISTS atkis_streets_car;
CREATE TABLE atkis_streets_car(
    edge_id SERIAL PRIMARY KEY,
    gml_id VARCHAR(16),
    the_geom GEOMETRY,
    source INTEGER,  -- needed for pgr_createTopology, will contain node_ids
    target INTEGER,  -- needed for pgr_createTopology, will contain node_ids
    distance NUMERIC(9,4),  -- for length of edge
    maxspeed INTEGER,
    weights_car NUMERIC(8,2),  -- for driving time
    weights_car_reverse NUMERIC(8,2),  -- for driving time in reverse direction, needed for oneways
    istTeilVon VARCHAR(16),  -- from strassenachse
    widmung INTEGER,  -- from strasse
    bezeichnung VARCHAR, -- from strasse, e.g. A29
    name VARCHAR,  -- from strasse
    fahrbahntrennung INTEGER,  -- from strasse, Getrennt 2000 (G)
    verkehrsbedeutungInneroertlich INTEGER,  -- from strassenachse
    verkehrsbedeutungUeberoertlich INTEGER,  -- from strassenachse
    funktion INTEGER,  -- from strassenachse and fahrbahnachse, Fußgängerzone 1808 (G)
    zustand INTEGER,  -- from strassenachse and fahrbahnachse, Außer Betrieb, stillgelegt, verlassen 2100 (G); Im Bau 4000 (G)
    anzahlDerFahrstreifen INTEGER,  -- from strassenachse and fahrbahnachse
    breiteDerFahrbahn NUMERIC(3,1),  -- from strassenachse and fahrbahnachse
    oberflaechenmaterial INTEGER,  -- from strassenachse and fahrbahnachse
    fahrtrichtung BOOLEAN  -- just for some additional analysis
);


-- for calculated routes of ATKIS
DROP TABLE IF EXISTS atkis_routes_car;
CREATE TABLE atkis_routes_car(
    pk_id SERIAL PRIMARY KEY,
    route_id INTEGER,
    seq INTEGER,
    path_seq INTEGER,
    node_id INTEGER,  -- node = vertex
    edge_id INTEGER,  -- is not a FK to atkis_streets_car(edge_id) because at the route's destination the latest 'edge_id' in this table is -1
    cost DOUBLE PRECISION,
    agg_cost DOUBLE PRECISION,
    source INTEGER,
    target INTEGER,
    the_geom GEOMETRY,
    gml_id VARCHAR(16),
    distance NUMERIC(9,4),
    maxspeed INTEGER,
    weights_car NUMERIC(8,2),
    weights_car_reverse NUMERIC(8,2),
    hook_length NUMERIC(9,4),
    hauskoor_id INTEGER,
    CONSTRAINT fk_atkis_hk_id
        FOREIGN KEY(hauskoor_id)
        REFERENCES startingpoints_destinations(id)
        ON DELETE RESTRICT
);


-- for calculated catchment nodes of ATKIS
DROP TABLE IF EXISTS atkis_catchment_nodes_car;
CREATE TABLE atkis_catchment_nodes_car(
    pk_id SERIAL PRIMARY KEY,
    catchment_nodes_id INTEGER,
    seq INTEGER,
    node_id INTEGER,  -- node = vertex
    edge_id_to_node INTEGER,  -- is not a FK to atkis_streets_car(edge_id) because at the route's destination the latest 'edge_id' in this table is -1
    cost DOUBLE PRECISION,
    total_cost_to_node DOUBLE PRECISION,
    the_geom GEOMETRY,
    starting_point_hook_length NUMERIC(9,4),
    start_hk_id INTEGER,
    CONSTRAINT fk_atkis_hk_id
        FOREIGN KEY(start_hk_id)
        REFERENCES startingpoints_destinations(id)
        ON DELETE RESTRICT
);
