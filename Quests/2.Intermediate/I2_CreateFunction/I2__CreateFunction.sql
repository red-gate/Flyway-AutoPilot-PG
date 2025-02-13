CREATE OR REPLACE FUNCTION inventory.get_upcoming_flights(
    start_date timestamptz,
    end_date timestamptz
) RETURNS TABLE (
    flight_id int,
    airline text,
    departure_city text,
    arrival_city text,
    departure_time timestamptz,
    arrival_time timestamptz,
    price numeric,
    available_seats integer
) AS $$ 
    SELECT flight_id,
           airline,
           departure_city,
           arrival_city,
           departure_time,
           arrival_time,
           price,
           available_seats
    FROM inventory.flight
    WHERE departure_time BETWEEN start_date AND end_date;
$$
LANGUAGE SQL;