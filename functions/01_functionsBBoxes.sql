-- description: code of bachelor thesis at ifgi, University of Muenster
-- author: Katharina Poppinga

-- bbox used for test area WHV as 'bbox_extent': xmin: 426529, ymin: 5925883, xmax: 445816, ymax: 5942057, EPSG: 25832

-- clip all streets and Hauskoordinaten to bboxes, to be able to analyze ATKIS and OSM for exactly the same area
-- Hauskoordinaten will be clipped to a smaller bbox than streets (reason for this is explained in thesis)
-- parameters:
-- bbox_extent: the intersection of this extent and an intersection of both extents of the data sets will become extent
-- of the inner_bbox which will be used for clipping streets
CREATE OR REPLACE FUNCTION clipStreetsToBBox(bbox_extent GEOMETRY default NULL)
RETURNS VOID
AS $$
BEGIN

    -- calculate bboxes
    PERFORM setBBoxes(bbox_extent);

    -- delete all objects which completely do not lie in their respective bbox 
    DELETE FROM atkis_streets_car
    WHERE NOT the_geom && (SELECT the_geom  -- &&: TRUE, if the_geom intersects inner_bbox
                           FROM bboxes
                           WHERE purpose = 'inner_bbox');
    DELETE FROM osm_2pgsql_notnoded
    WHERE NOT the_geom && (SELECT the_geom
                           FROM bboxes
                           WHERE purpose = 'inner_bbox');
    DELETE FROM osm_2po_4pgr
    WHERE NOT the_geom && (SELECT the_geom
                           FROM bboxes
                           WHERE purpose = 'inner_bbox');
    DELETE FROM hauskoordinaten
    WHERE NOT the_geom && (SELECT the_geom  -- &&: TRUE, if the_geom intersects address_bbox
                           FROM bboxes
                           WHERE purpose = 'address_bbox');

    -- trim road geometries exactly at bbox
    UPDATE atkis_streets_car
    SET the_geom = ST_Intersection((SELECT the_geom FROM bboxes WHERE purpose = 'inner_bbox'), the_geom);
    UPDATE osm_2pgsql_notnoded
    SET the_geom = ST_Intersection((SELECT the_geom FROM bboxes WHERE purpose = 'inner_bbox'), the_geom);
    UPDATE osm_2po_4pgr
    SET the_geom = ST_Intersection((SELECT the_geom FROM bboxes WHERE purpose = 'inner_bbox'), the_geom);

END
$$ LANGUAGE plpgsql;


-- create three bboxes (outer_bbox is just a helper, inner_box is for road geometries and address_box is for Hauskoordinaten)
-- parameters:
-- bbox_extent: the intersection of this extent and an intersection of both extents of the data sets will become extent
-- of the inner_bbox which will be used for clipping streets
CREATE OR REPLACE FUNCTION setBBoxes(bbox_extent GEOMETRY default NULL)
RETURNS VOID
AS $$
DECLARE
    -- here without SRID because it gets lost with ST_Extent(), will be added again in function body
    bbox_both_intersection GEOMETRY := (ST_Intersection(
                                (SELECT ST_Extent(the_geom)
                                FROM atkis_streets_car),
                                (SELECT ST_Extent(the_geom)
                                FROM osm_2pgsql_notnoded)));
    inner_bbox GEOMETRY;
BEGIN
    
    -- define OUTER-BBOX und INNER-BBOX:
    -- this case was not used in my analysis:
    IF bbox_extent IS NULL THEN
        -- intersection of raw data from ATKIS and OSM
        INSERT INTO bboxes(purpose) VALUES ('outer_bbox') ON CONFLICT ON CONSTRAINT unique_purpose DO NOTHING;
        UPDATE bboxes
        SET the_geom = (SELECT ST_SetSRID(ST_Extent(bbox_both_intersection), 25832))
        WHERE purpose = 'outer_bbox';

        inner_bbox = (SELECT ST_Buffer(ST_SetSRID(bbox_both_intersection, 25832), -1500));  -- 1,5 km distance
        INSERT INTO bboxes(purpose) VALUES ('inner_bbox') ON CONFLICT ON CONSTRAINT unique_purpose DO NOTHING;
        UPDATE bboxes
        SET the_geom = inner_bbox
        WHERE purpose = 'inner_bbox';

    -- this case was used in my analysis for test area WHV:
    ELSE
        -- use manually set bbox (is called bbox_extent)
        INSERT INTO bboxes(purpose) VALUES ('outer_bbox') ON CONFLICT ON CONSTRAINT unique_purpose DO NOTHING;
        UPDATE bboxes
        SET the_geom = bbox_extent
        WHERE purpose = 'outer_bbox';

        -- intersection of manually set bbox with bbox_both_intersection
        inner_bbox = (SELECT ST_Intersection(bbox_extent, (ST_SetSRID(bbox_both_intersection, 25832))));
        INSERT INTO bboxes(purpose) VALUES ('inner_bbox') ON CONFLICT ON CONSTRAINT unique_purpose DO NOTHING;
        UPDATE bboxes
        SET the_geom = inner_bbox
        WHERE purpose = 'inner_bbox';

    END IF;

    -- define ADDRESS-BBOX:
    -- the reason for a smaller bbox for Hauskoordinaten can be found in the thesis
    INSERT INTO bboxes(purpose) VALUES ('address_bbox') ON CONFLICT ON CONSTRAINT unique_purpose DO NOTHING;
    UPDATE bboxes
    SET the_geom = (SELECT ST_Buffer(inner_bbox, -1000))  -- 1 km distance to inner_bbox
    WHERE purpose = 'address_bbox';

END
$$ LANGUAGE plpgsql;
