-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- boundingboxes for clipping both road datasets and coordinates for starting points and destinations (Hauskoordinaten) to test area
DROP TABLE IF EXISTS bboxes;
CREATE TABLE bboxes(
    bbox_id SERIAL PRIMARY KEY,
    purpose VARCHAR CONSTRAINT unique_purpose UNIQUE,
    the_geom GEOMETRY
);


-- for importing Hauskoordinaten from CSV
DROP TABLE IF EXISTS hauskoordinaten; --CASCADE;
CREATE TABLE hauskoordinaten(
    id SERIAL PRIMARY KEY,
    NBA VARCHAR(1),
    OI VARCHAR(16),
    QUA VARCHAR(1),
    LAN VARCHAR(2),
    RBZ VARCHAR(1),
    KRS VARCHAR(2),
    GMD VARCHAR(3),
    OTT VARCHAR(4),
    SSS VARCHAR(5),
    HNR VARCHAR,
    ADZ VARCHAR,
    coor_easting VARCHAR(12),  -- with a leading "32" because of zone 32N
    coor_northing VARCHAR(11),
    STN VARCHAR,
    PLZ VARCHAR(5),
    ONM VARCHAR,
    ZON VARCHAR,
    POT VARCHAR,
    the_geom GEOMETRY
);


-- random chosen points from Hauskoordinaten for using as starting point and destination for route calculation
DROP TABLE IF EXISTS startingpoints_destinations;
CREATE TABLE startingpoints_destinations(
    id SERIAL PRIMARY KEY,
    hauskoordinaten_id INTEGER,
    coordinate GEOMETRY,
    CONSTRAINT fk_hk_id
        FOREIGN KEY(hauskoordinaten_id)
        REFERENCES hauskoordinaten(id)
        ON DELETE CASCADE
);
