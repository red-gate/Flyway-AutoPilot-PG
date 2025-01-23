-- Flyway AutoPilot FastTrack Database Setup Script --

-- Creating Schemas
CREATE SCHEMA sales;
CREATE SCHEMA inventory;
CREATE SCHEMA customers;


-- Tables in Customers Schema
CREATE TABLE customers.customer (
    customer_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    date_of_birth DATE,
    phone VARCHAR(20),
    address VARCHAR(200)
);

CREATE TABLE customers.loyalty_program (
    program_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    program_name VARCHAR(50) NOT NULL,
    points_multiplier DECIMAL(3, 2) DEFAULT 1.0
);

CREATE TABLE customers.customer_feedback (
    feedback_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    customer_id INT REFERENCES customers.customer(customer_id),
    feedback_date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    rating INT CHECK (Rating BETWEEN 1 AND 5),
    comments VARCHAR(500)
);


-- Tables in Inventory Schema
CREATE TABLE inventory.flight (
    flight_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    airline VARCHAR(50) NOT NULL,
    departure_city VARCHAR(50) NOT NULL,
    arrival_city VARCHAR(50) NOT NULL,
    departure_time TIMESTAMPTZ NOT NULL,
    arrival_time TIMESTAMPTZ NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    available_seats INT NOT NULL
);

CREATE TABLE inventory.flight_route (
    routeID INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    departure_city VARCHAR(50) NOT NULL,
    arrival_city VARCHAR(50) NOT NULL,
    distance INT NOT NULL
);


CREATE TABLE inventory.maintenance_log (
    log_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    flight_id INT REFERENCES inventory.flight(flight_id),
    maintenance_date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    description VARCHAR(500),
    maintenance_status VARCHAR(20) DEFAULT 'Pending'
);

-- Tables in Sales Schema
CREATE TABLE sales.orders (
    order_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    customer_id INT REFERENCES customers.customer(customer_id),
    flight_id INT REFERENCES inventory.flight(flight_id),
    order_date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'Pending',
    total_amount DECIMAL(10, 2),
    ticket_quantity INT
);

CREATE TABLE sales.discount_code (
    discount_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    code VARCHAR(20) UNIQUE NOT NULL,
    discount_percentage DECIMAL(4, 2) CHECK (discount_percentage BETWEEN 0 AND 100),
    expiry_date TIMESTAMPTZ
);

CREATE TABLE sales.order_audit_log (
    audit_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    order_id INT REFERENCES sales.orders(order_id),
    change_date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    change_description VARCHAR(500)
);


-- Views
CREATE VIEW sales.customer_orders_view AS
SELECT 
    c.customer_id,
    c.first_name,
    c.last_name,
    o.order_id,
    o.order_date,
    o.status,
    o.total_amount
FROM customers.customer c
JOIN sales.orders o ON c.customer_id = o.customer_id;


CREATE VIEW customers.customer_feedback_summary AS
SELECT 
    c.customer_id,
    c.first_name,
    c.last_name,
    AVG(f.rating) AS average_rating,
    COUNT(f.feedback_id) AS feedback_count
FROM customers.customer c
LEFT JOIN customers.customer_feedback f ON c.customer_id = f.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name;


CREATE VIEW inventory.flight_maintenance_status AS
SELECT 
    f.flight_id,
    f.airline,
    f.departure_city,
    f.arrival_city,
    COUNT(m.log_id) AS maintenance_count,
    SUM(CASE WHEN m.maintenance_status = 'completed' THEN 1 ELSE 0 END) AS completed_maintenance
FROM inventory.flight f
LEFT JOIN inventory.maintenance_log m ON f.flight_id = m.flight_id
GROUP BY f.flight_id, f.airline, f.departure_city, f.arrival_city;


-- Functions
CREATE OR REPLACE FUNCTION sales.get_customer_flight_history(customer_id INT)
RETURNS TABLE (
    order_id INT,
    airline VARCHAR,
    departure_city VARCHAR,
    arrival_city VARCHAR,
    order_date TIMESTAMPTZ,
    status VARCHAR,
    total_amount NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.order_id,
        f.airline,
        f.departure_city,
        f.arrival_city,
        o.order_date,
        o.status,
        o.total_amount
    FROM sales.orders o
    JOIN inventory.flight f ON o.flight_id = f.flight_id
    WHERE o.customer_id = customer_id
    ORDER BY o.order_date;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE sales.update_order_status(
    order_id INT,
    new_status VARCHAR(20)
)
AS $$
BEGIN
    UPDATE sales.orders
    SET status = new_status
    WHERE order_id = order_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE PROCEDURE inventory.update_available_seats(
    flight_id INT,
    seat_change INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE inventory.flight
    SET available_seats = available_seats + seat_change
    WHERE flight_id = flight_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sales.apply_discount(
    order_id INT,
    discount_code VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
DECLARE
        discount_id INT;
        discount_percentage NUMERIC(4, 2);
        expiry_date TIMESTAMPTZ;
BEGIN
    SELECT 
        discount_id,
        discount_percentage,
        expiry_date
    INTO 
        discount_id,
        discount_percentage,
        expiry_date
    FROM sales.discount_code
    WHERE code = discount_code;
    
    IF discount_id IS NOT NULL AND expiry_date >= CURRENT_TIMESTAMP THEN
        UPDATE sales.orders
        SET total_amount = total_amount * (1 - discount_percentage / 100)
        WHERE order_id = order_id;

        INSERT INTO sales.order_audit_log (order_id, change_description)
        VALUES (order_id, CONCAT('Discount ', discount_code, ' applied with ', discount_percentage, '% off.'));
    ELSE
        RAISE EXCEPTION 'Invalid or expired discount code.';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE inventory.add_maintenance_log(
    flight_id INT,
    description VARCHAR(500)
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO inventory.maintenance_log (flight_id, description, maintenance_status)
    VALUES (flight_id, description, 'pending');

    RAISE NOTICE 'Maintenance log entry created.';
END;
$$;

CREATE OR REPLACE PROCEDURE customers.record_feedback(
    customer_id INT,
    rating INT,
    comments VARCHAR(500)
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO customers.customer_feedback (customer_id, rating, comments)
    VALUES (customer_id, rating, comments);

    RAISE NOTICE 'Customer feedback recorded successfully.';
END;
$$;

-- Sample Data Insertion

-- Adding Customers
INSERT INTO customers.customer (first_name, last_name, email, date_of_birth, phone, address)
VALUES ('Huxley', 'Kendell', 'FlywayAP@Red-Gate.com', '2000-08-10', '555-1234', '123 Main St'),
       ('Chris', 'Hawkins', 'Chrawkins@Red-Gate.com', '1971-07-20', '555-5678', '456 Elm St');

-- Adding Flights
INSERT INTO inventory.flight (airline, departure_city, arrival_city, departure_time, arrival_time, price, available_seats)
VALUES ('Flyway Airlines', 'New York', 'London', '2024-11-20 10:00', '2024-11-20 20:00', 500.00, 150),
       ('AutoPilot', 'Los Angeles', 'Tokyo', '2024-12-01 16:00', '2024-12-02 08:00', 800.00, 200);

-- Adding Orders
INSERT INTO sales.orders (customer_id, flight_id, order_date, status, total_amount, ticket_quantity)
VALUES (1, 1, CURRENT_TIMESTAMP, 'Confirmed', 500.00, 1),
       (2, 2, CURRENT_TIMESTAMP, 'Pending', 1600.00, 2);

-- Adding Loyalty Programs
INSERT INTO customers.loyalty_program (program_name, points_multiplier)
VALUES ('Silver', 1.0), ('Gold', 1.5), ('Platinum', 2.0);

-- Adding Discount Codes
INSERT INTO sales.discount_code (code, discount_percentage, expiry_date)
VALUES ('FLY20', 20.00, '2024-12-31'), ('NEWYEAR', 10.00, '2025-01-04');
