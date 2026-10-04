-- PostGIS is required for playable/restricted polygons and later
-- server-side distance / containment checks.
create extension if not exists postgis;
