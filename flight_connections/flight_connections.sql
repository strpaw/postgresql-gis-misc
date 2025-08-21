CREATE EXTENSION IF NOT EXISTS postgis;

DROP TABLE IF EXISTS flight_path;
DROP TABLE IF EXISTS flight_connection;
DROP TABLE IF EXISTS airport;

CREATE TABLE airport (
	iata_code char(3) PRIMARY KEY,
	city varchar(128) NOT NULL,
	geog geography(POINT, 4326)
);

CREATE TABLE flight_connection (
	id serial PRIMARY KEY,
	dep_iata_code char(3) NOT NULL,
	arr_iata_code char(3) NOT NULL,
	FOREIGN KEY (dep_iata_code) REFERENCES airport(iata_code),
	FOREIGN KEY (arr_iata_code) REFERENCES airport(iata_code)
);

-- replace <data path> with path to the actual CSV file with airports coordinates
COPY airport (iata_code, city, geog)
FROM '<data path>' 
DELIMITERS ';' CSV HEADER;

-- replace <data path> with path to the actual CSV file with dep-dest flight connections
COPY flight_connection (dep_iata_code, arr_iata_code)
FROM '<data path>'
DELIMITERS ';' CSV HEADER;

SELECT
	d.city AS dep_city,
	d.iata_code AS dep_iata_code,
	a.city AS arr_city,
	a.iata_code AS arr_iata_code,
	ST_Multi(
		ST_Segmentize(
			ST_MakeLine(
				d.geog::geometry,
				a.geog::geometry
			)::geography,
			10000
		)::geometry
	)::geography AS geog
INTO flight_path
FROM
	flight_connection AS fc
	JOIN airport AS d ON fc.dep_iata_code = d.iata_code
	JOIN airport AS a ON fc.arr_iata_code = a.iata_code;

ALTER TABLE flight_path
ADD COLUMN id serial PRIMARY KEY;
	
	
UPDATE flight_path
SET geog = ST_CollectionExtract(
                ST_WrapX(
					ST_Split(
							ST_ShiftLongitude(geog::geometry),
							ST_ShiftLongitude(ST_GeogFromText('LINESTRING(180 -90, 180 90)')::geometry)
					),
					180,
					-360
				)
			)::geography
WHERE ST_Intersects(
	geog,
	ST_GeogFromText('LINESTRING (180 -89.99999, 180 90)') -- -89.99999 - to avoid ERROR:  Antipodal (180 degrees long) edge detected!
)
