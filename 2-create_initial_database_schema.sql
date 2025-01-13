-- Switch Database

-- Creating Schemas
CREATE SCHEMA Sales;
CREATE SCHEMA Inventory;
CREATE SCHEMA Customers;

-- Creating Roles
CREATE ROLE CustomerService;
CREATE ROLE Admin;

-- Tables in Customers Schema
CREATE TABLE Customers.Customer (
    CustomerID SERIAL PRIMARY KEY,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(100) UNIQUE NOT NULL,
    DateOfBirth DATE,
    Phone VARCHAR(20),
    Address VARCHAR(200)
);

CREATE TABLE Customers.LoyaltyProgram (
    ProgramID SERIAL PRIMARY KEY,
    ProgramName VARCHAR(50) NOT NULL,
    PointsMultiplier DECIMAL(3, 2) DEFAULT 1.0
);

CREATE TABLE Customers.CustomerFeedback (
    FeedbackID SERIAL PRIMARY KEY,
    CustomerID INT REFERENCES Customers.Customer(CustomerID),
    FeedbackDate TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    Rating INT CHECK (Rating BETWEEN 1 AND 5),
    Comments VARCHAR(500)
);

-- Tables in Inventory Schema
CREATE TABLE Inventory.Flight (
    FlightID SERIAL PRIMARY KEY,
    Airline VARCHAR(50) NOT NULL,
    DepartureCity VARCHAR(50) NOT NULL,
    ArrivalCity VARCHAR(50) NOT NULL,
    DepartureTime TIMESTAMPTZ NOT NULL,
    ArrivalTime TIMESTAMPTZ NOT NULL,
    Price DECIMAL(10, 2) NOT NULL,
    AvailableSeats INT NOT NULL
);

CREATE TABLE Inventory.FlightRoute (
    RouteID SERIAL PRIMARY KEY,
    DepartureCity VARCHAR(50) NOT NULL,
    ArrivalCity VARCHAR(50) NOT NULL,
    Distance INT NOT NULL
);

CREATE TABLE Inventory.MaintenanceLog (
    LogID SERIAL PRIMARY KEY,
    FlightID INT REFERENCES Inventory.Flight(FlightID),
    MaintenanceDate TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    Description VARCHAR(500),
    MaintenanceStatus VARCHAR(20) DEFAULT 'Pending'
);

-- Tables in Sales Schema
CREATE TABLE Sales.Orders (
    OrderID SERIAL PRIMARY KEY,
    CustomerID INT REFERENCES Customers.Customer(CustomerID),
    FlightID INT REFERENCES Inventory.Flight(FlightID),
    OrderDate TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    Status VARCHAR(20) DEFAULT 'Pending',
    TotalAmount DECIMAL(10, 2),
    TicketQuantity INT
);

CREATE TABLE Sales.DiscountCode (
    DiscountID SERIAL PRIMARY KEY,
    Code VARCHAR(20) UNIQUE NOT NULL,
    DiscountPercentage DECIMAL(4, 2) CHECK (DiscountPercentage BETWEEN 0 AND 100),
    ExpiryDate TIMESTAMPTZ
);

CREATE TABLE Sales.OrderAuditLog (
    AuditID SERIAL PRIMARY KEY,
    OrderID INT REFERENCES Sales.Orders(OrderID),
    ChangeDate TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    ChangeDescription VARCHAR(500)
);

-- Views
CREATE VIEW Sales.CustomerOrdersView AS
SELECT 
    c.CustomerID,
    c.FirstName,
    c.LastName,
    o.OrderID,
    o.OrderDate,
    o.Status,
    o.TotalAmount
FROM Customers.Customer c
JOIN Sales.Orders o ON c.CustomerID = o.CustomerID;

CREATE VIEW Customers.CustomerFeedbackSummary AS
SELECT 
    c.CustomerID,
    c.FirstName,
    c.LastName,
    AVG(f.Rating) AS AverageRating,
    COUNT(f.FeedbackID) AS FeedbackCount
FROM Customers.Customer c
LEFT JOIN Customers.CustomerFeedback f ON c.CustomerID = f.CustomerID
GROUP BY c.CustomerID, c.FirstName, c.LastName;

CREATE VIEW Inventory.FlightMaintenanceStatus AS
SELECT 
    f.FlightID,
    f.Airline,
    f.DepartureCity,
    f.ArrivalCity,
    COUNT(m.LogID) AS MaintenanceCount,
    SUM(CASE WHEN m.MaintenanceStatus = 'Completed' THEN 1 ELSE 0 END) AS CompletedMaintenance
FROM Inventory.Flight f
LEFT JOIN Inventory.MaintenanceLog m ON f.FlightID = m.FlightID
GROUP BY f.FlightID, f.Airline, f.DepartureCity, f.ArrivalCity;

-- Stored Procedures
CREATE OR REPLACE FUNCTION Sales.GetCustomerFlightHistory(CustomerID INT)
RETURNS TABLE(OrderID INT, Airline VARCHAR, DepartureCity VARCHAR, ArrivalCity VARCHAR, OrderDate TIMESTAMPTZ, Status VARCHAR, TotalAmount DECIMAL) AS
$$
BEGIN
    RETURN QUERY
    SELECT 
        o.OrderID,
        f.Airline,
        f.DepartureCity,
        f.ArrivalCity,
        o.OrderDate,
        o.Status,
        o.TotalAmount
    FROM Sales.Orders o
    JOIN Inventory.Flight f ON o.FlightID = f.FlightID
    WHERE o.CustomerID = CustomerID
    ORDER BY o.OrderDate;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION Sales.UpdateOrderStatus(OrderID INT, NewStatus VARCHAR)
RETURNS VOID AS
$$
BEGIN
    UPDATE Sales.Orders
    SET Status = NewStatus
    WHERE OrderID = OrderID;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION Inventory.UpdateAvailableSeats(FlightID INT, SeatChange INT)
RETURNS VOID AS
$$
BEGIN
    UPDATE Inventory.Flight
    SET AvailableSeats = AvailableSeats + SeatChange
    WHERE FlightID = FlightID;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION Sales.ApplyDiscount(OrderID INT, DiscountCode VARCHAR)
RETURNS VOID AS
$$
DECLARE
    DiscountID INT;
    DiscountPercentage DECIMAL(4, 2);
    ExpiryDate TIMESTAMPTZ;
BEGIN
    SELECT DiscountID, DiscountPercentage, ExpiryDate
    INTO DiscountID, DiscountPercentage, ExpiryDate
    FROM Sales.DiscountCode
    WHERE Code = DiscountCode;

    IF DiscountID IS NOT NULL AND ExpiryDate >= CURRENT_TIMESTAMP THEN
        UPDATE Sales.Orders
        SET TotalAmount = TotalAmount * (1 - DiscountPercentage / 100)
        WHERE OrderID = OrderID;

        INSERT INTO Sales.OrderAuditLog (OrderID, ChangeDescription)
        VALUES (OrderID, CONCAT('Discount ', DiscountCode, ' applied with ', DiscountPercentage, '% off.'));
    ELSE
        RAISE EXCEPTION 'Invalid or expired discount code.';
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION Inventory.AddMaintenanceLog(FlightID INT, Description VARCHAR)
RETURNS VOID AS
$$
BEGIN
    INSERT INTO Inventory.MaintenanceLog (FlightID, Description, MaintenanceStatus)
    VALUES (FlightID, Description, 'Pending');
    RAISE NOTICE 'Maintenance log entry created.';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION Customers.RecordFeedback(CustomerID INT, Rating INT, Comments VARCHAR)
RETURNS VOID AS
$$
BEGIN
    INSERT INTO Customers.CustomerFeedback (CustomerID, Rating, Comments)
    VALUES (CustomerID, Rating, Comments);
    RAISE NOTICE 'Customer feedback recorded successfully.';
END;
$$ LANGUAGE plpgsql;

-- Sample Data Insertion

-- Adding Customers
INSERT INTO Customers.Customer (FirstName, LastName, Email, DateOfBirth, Phone, Address)
VALUES ('Huxley', 'Kendell', 'FlywayAP@Red-Gate.com', '2000-08-10', '555-1234', '123 Main St'),
       ('Chris', 'Hawkins', 'Chrawkins@Red-Gate.com', '1971-07-20', '555-5678', '456 Elm St');

-- Adding Flights
INSERT INTO Inventory.Flight (Airline, DepartureCity, ArrivalCity, DepartureTime, ArrivalTime, Price, AvailableSeats)
VALUES ('Flyway Airlines', 'New York', 'London', '2024-11-20 10:00', '2024-11-20 20:00', 500.00, 150),
       ('AutoPilot', 'Los Angeles', 'Tokyo', '2024-12-01 16:00', '2024-12-02 08:00', 800.00, 200);

-- Adding Orders
INSERT INTO Sales.Orders (CustomerID, FlightID, OrderDate, Status, TotalAmount, TicketQuantity)
VALUES (1, 1, CURRENT_TIMESTAMP, 'Confirmed', 500.00, 1),
       (2, 2, CURRENT_TIMESTAMP, 'Pending', 1600.00, 2);

-- Adding Loyalty Programs
INSERT INTO Customers.LoyaltyProgram (ProgramName, PointsMultiplier)
VALUES ('Silver', 1.0), ('Gold', 1.5), ('Platinum', 2.0);

-- Adding Discount Codes
INSERT INTO Sales.DiscountCode (Code, DiscountPercentage, ExpiryDate)
VALUES ('FLY20', 20.00, '2024-12-31'), ('NEWYEAR', 10.00, '2025-01-04');
