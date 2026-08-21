/*=====================================================================
  T-Lift business context demo setup

  Creates:
    - TLift_BusinessDemo database
    - demo tables with deterministic sample data
    - helper proc demo.ExecuteRenderedScript for deploying T-Lift output

  Prerequisite:
    - TLift_Engine.dbo.sp_tlift already installed
=====================================================================*/

SET NOCOUNT ON;

IF DB_ID(N'TLift_Engine') IS NULL
BEGIN
    THROW 51000, 'TLift_Engine database not found. Install sp_tlift.sql into TLift_Engine first.', 1;
END;

IF OBJECT_ID(N'TLift_Engine.dbo.sp_tlift', N'P') IS NULL
BEGIN
    THROW 51001, 'TLift_Engine.dbo.sp_tlift not found. Execute sp_tlift.sql in TLift_Engine first.', 1;
END;

IF DB_ID(N'TLift_BusinessDemo') IS NULL
BEGIN
    CREATE DATABASE TLift_BusinessDemo;
END;
GO

USE TLift_BusinessDemo;
GO

IF SCHEMA_ID(N'demo') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA demo;');
END;
GO

DROP PROCEDURE IF EXISTS demo.ExecuteRenderedScript;
GO

CREATE OR ALTER PROCEDURE demo.ExecuteRenderedScript
    @Script NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @batch NVARCHAR(MAX) = N'';
    DECLARE @line NVARCHAR(MAX);
    DECLARE @cursorPos INT = 1;
    DECLARE @lineEnd INT;
    DECLARE @trimmedLine NVARCHAR(MAX);

    IF @Script IS NULL OR LEN(@Script) = 0
    BEGIN
        THROW 51010, 'No script was supplied to demo.ExecuteRenderedScript.', 1;
    END;

    WHILE @cursorPos <= LEN(@Script)
    BEGIN
        SET @lineEnd = CHARINDEX(CHAR(10), @Script, @cursorPos);

        IF @lineEnd = 0
        BEGIN
            SET @line = SUBSTRING(@Script, @cursorPos, LEN(@Script) - @cursorPos + 1);
            SET @cursorPos = LEN(@Script) + 1;
        END
        ELSE
        BEGIN
            SET @line = SUBSTRING(@Script, @cursorPos, @lineEnd - @cursorPos + 1);
            SET @cursorPos = @lineEnd + 1;
        END;

        SET @trimmedLine = UPPER(LTRIM(RTRIM(REPLACE(REPLACE(@line, CHAR(13), N''), CHAR(10), N''))));

        IF @trimmedLine = N'GO'
        BEGIN
            IF LEN(LTRIM(RTRIM(@batch))) > 0
            BEGIN
                SET @batch = REPLACE(@batch, N'create   procedure', N'CREATE OR ALTER PROCEDURE');
                SET @batch = REPLACE(@batch, N'create  procedure',  N'CREATE OR ALTER PROCEDURE');
                SET @batch = REPLACE(@batch, N'create procedure',   N'CREATE OR ALTER PROCEDURE');
                SET @batch = REPLACE(@batch, N'CREATE   PROCEDURE', N'CREATE OR ALTER PROCEDURE');
                SET @batch = REPLACE(@batch, N'CREATE  PROCEDURE',  N'CREATE OR ALTER PROCEDURE');
                SET @batch = REPLACE(@batch, N'CREATE PROCEDURE',   N'CREATE OR ALTER PROCEDURE');
                SET @batch = REPLACE(@batch, N'CREATE OR ALTER OR ALTER', N'CREATE OR ALTER');

                EXEC sys.sp_executesql @batch;
                SET @batch = N'';
            END;
        END
        ELSE
        BEGIN
            SET @batch = @batch + @line;
        END;
    END;

    IF LEN(LTRIM(RTRIM(@batch))) > 0
    BEGIN
        SET @batch = REPLACE(@batch, N'create   procedure', N'CREATE OR ALTER PROCEDURE');
        SET @batch = REPLACE(@batch, N'create  procedure',  N'CREATE OR ALTER PROCEDURE');
        SET @batch = REPLACE(@batch, N'create procedure',   N'CREATE OR ALTER PROCEDURE');
        SET @batch = REPLACE(@batch, N'CREATE   PROCEDURE', N'CREATE OR ALTER PROCEDURE');
        SET @batch = REPLACE(@batch, N'CREATE  PROCEDURE',  N'CREATE OR ALTER PROCEDURE');
        SET @batch = REPLACE(@batch, N'CREATE PROCEDURE',   N'CREATE OR ALTER PROCEDURE');
        SET @batch = REPLACE(@batch, N'CREATE OR ALTER OR ALTER', N'CREATE OR ALTER');

        EXEC sys.sp_executesql @batch;
    END;
END;
GO

DROP TABLE IF EXISTS demo.SalesOrderLines;
DROP TABLE IF EXISTS demo.SalesOrders;
DROP TABLE IF EXISTS demo.ServiceTickets;
DROP TABLE IF EXISTS demo.Invoices;
DROP TABLE IF EXISTS demo.Products;
DROP TABLE IF EXISTS demo.Customers;
GO

CREATE TABLE demo.Customers
(
    CustomerID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_demo_Customers PRIMARY KEY,
    CustomerName NVARCHAR(120) NOT NULL,
    CustomerSegment NVARCHAR(20) NOT NULL,
    Region NVARCHAR(20) NOT NULL,
    CountryCode CHAR(2) NOT NULL,
    IsStrategic BIT NOT NULL,
    CreditLimit MONEY NOT NULL,
    CreatedAt DATE NOT NULL
);

CREATE TABLE demo.Products
(
    ProductID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_demo_Products PRIMARY KEY,
    ProductName NVARCHAR(120) NOT NULL,
    ProductCategory NVARCHAR(30) NOT NULL,
    MarginBand NVARCHAR(10) NOT NULL,
    UnitPrice MONEY NOT NULL,
    IsRegulated BIT NOT NULL
);

CREATE TABLE demo.SalesOrders
(
    OrderID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_demo_SalesOrders PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    Status NVARCHAR(20) NOT NULL,
    Channel NVARCHAR(20) NOT NULL,
    WarehouseID INT NOT NULL,
    TotalAmount MONEY NOT NULL,
    CONSTRAINT FK_demo_SalesOrders_Customers FOREIGN KEY (CustomerID) REFERENCES demo.Customers(CustomerID)
);

CREATE TABLE demo.SalesOrderLines
(
    LineID BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_demo_SalesOrderLines PRIMARY KEY,
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice MONEY NOT NULL,
    LineAmount MONEY NOT NULL,
    CONSTRAINT FK_demo_SalesOrderLines_Orders FOREIGN KEY (OrderID) REFERENCES demo.SalesOrders(OrderID),
    CONSTRAINT FK_demo_SalesOrderLines_Products FOREIGN KEY (ProductID) REFERENCES demo.Products(ProductID)
);

CREATE TABLE demo.ServiceTickets
(
    TicketID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_demo_ServiceTickets PRIMARY KEY,
    CustomerID INT NOT NULL,
    OpenedAt DATETIME2(0) NOT NULL,
    Region NVARCHAR(20) NOT NULL,
    Priority TINYINT NOT NULL,
    Status NVARCHAR(20) NOT NULL,
    TechnicianID INT NULL,
    ProductCategory NVARCHAR(30) NOT NULL,
    SLADeadline DATETIME2(0) NOT NULL,
    CONSTRAINT FK_demo_ServiceTickets_Customers FOREIGN KEY (CustomerID) REFERENCES demo.Customers(CustomerID)
);

CREATE TABLE demo.Invoices
(
    InvoiceID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_demo_Invoices PRIMARY KEY,
    CustomerID INT NOT NULL,
    InvoiceDate DATE NOT NULL,
    DueDate DATE NOT NULL,
    OpenAmount MONEY NOT NULL,
    CurrencyCode CHAR(3) NOT NULL,
    DisputeStatus NVARCHAR(20) NOT NULL,
    RiskClass NVARCHAR(10) NOT NULL,
    CONSTRAINT FK_demo_Invoices_Customers FOREIGN KEY (CustomerID) REFERENCES demo.Customers(CustomerID)
);
GO

WITH
E1(N) AS
(
    SELECT 1 FROM (VALUES (0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) AS v(n)
),
E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),
Nums(N) AS
(
    SELECT TOP (2500) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM E4
)
INSERT demo.Customers
(
    CustomerName, CustomerSegment, Region, CountryCode, IsStrategic,
    CreditLimit, CreatedAt
)
SELECT
    CONCAT(N'Customer ', N),
    CASE WHEN N % 20 = 0 THEN N'Enterprise'
         WHEN N % 5 = 0 THEN N'MidMarket'
         ELSE N'SMB' END,
    CASE N % 5 WHEN 0 THEN N'North'
               WHEN 1 THEN N'South'
               WHEN 2 THEN N'East'
               WHEN 3 THEN N'West'
               ELSE N'Central' END,
    CASE N % 4 WHEN 0 THEN 'DE'
               WHEN 1 THEN 'US'
               WHEN 2 THEN 'GB'
               ELSE 'FR' END,
    CASE WHEN N % 25 = 0 THEN 1 ELSE 0 END,
    CONVERT(MONEY, 5000 + (N % 200) * 1000),
    DATEADD(DAY, -(N % 1800), CONVERT(DATE, GETDATE()))
FROM Nums;

WITH
E1(N) AS
(
    SELECT 1 FROM (VALUES (0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) AS v(n)
),
E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
Nums(N) AS
(
    SELECT TOP (250) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM E2 a CROSS JOIN E2 b
)
INSERT demo.Products
(
    ProductName, ProductCategory, MarginBand, UnitPrice, IsRegulated
)
SELECT
    CONCAT(N'Product ', N),
    CASE N % 6 WHEN 0 THEN N'Hardware'
               WHEN 1 THEN N'Software'
               WHEN 2 THEN N'SpareParts'
               WHEN 3 THEN N'Consumables'
               WHEN 4 THEN N'Services'
               ELSE N'Safety' END,
    CASE WHEN N % 11 = 0 THEN N'Low'
         WHEN N % 4 = 0 THEN N'Mid'
         ELSE N'High' END,
    CONVERT(MONEY, 25 + (N % 90) * 7.5),
    CASE WHEN N % 13 = 0 THEN 1 ELSE 0 END
FROM Nums;

WITH
E1(N) AS
(
    SELECT 1 FROM (VALUES (0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) AS v(n)
),
E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),
Nums(N) AS
(
    SELECT TOP (30000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM E4 a CROSS JOIN E2 b
)
INSERT demo.SalesOrders
(
    CustomerID, OrderDate, Status, Channel, WarehouseID, TotalAmount
)
SELECT
    ((N * 17) % 2500) + 1,
    DATEADD(DAY, -(N % 730), CONVERT(DATE, GETDATE())),
    CASE WHEN N % 17 = 0 THEN N'Cancelled'
         WHEN N % 11 = 0 THEN N'Open'
         WHEN N % 7 = 0 THEN N'Backorder'
         ELSE N'Shipped' END,
    CASE N % 4 WHEN 0 THEN N'Portal'
               WHEN 1 THEN N'EDI'
               WHEN 2 THEN N'InsideSales'
               ELSE N'Partner' END,
    (N % 12) + 1,
    CONVERT(MONEY, 100 + (N % 600) * 18 + CASE WHEN N % 1000 = 0 THEN 75000 ELSE 0 END)
FROM Nums;

INSERT demo.SalesOrderLines
(
    OrderID, ProductID, Quantity, UnitPrice, LineAmount
)
SELECT
    o.OrderID,
    ((o.OrderID * v.LineNumber * 19) % 250) + 1,
    ((o.OrderID + v.LineNumber) % 8) + 1,
    p.UnitPrice,
    CONVERT(MONEY, (((o.OrderID + v.LineNumber) % 8) + 1) * p.UnitPrice)
FROM demo.SalesOrders AS o
CROSS APPLY (VALUES (1),(2),(3)) AS v(LineNumber)
INNER JOIN demo.Products AS p
    ON p.ProductID = ((o.OrderID * v.LineNumber * 19) % 250) + 1;

WITH
E1(N) AS
(
    SELECT 1 FROM (VALUES (0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) AS v(n)
),
E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),
Nums(N) AS
(
    SELECT TOP (40000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM E4 a CROSS JOIN E2 b
)
INSERT demo.ServiceTickets
(
    CustomerID, OpenedAt, Region, Priority, Status, TechnicianID,
    ProductCategory, SLADeadline
)
SELECT
    ((N * 23) % 2500) + 1,
    DATEADD(HOUR, -(N % 720), SYSUTCDATETIME()),
    CASE N % 5 WHEN 0 THEN N'North'
               WHEN 1 THEN N'South'
               WHEN 2 THEN N'East'
               WHEN 3 THEN N'West'
               ELSE N'Central' END,
    CASE WHEN N % 23 = 0 THEN 1
         WHEN N % 9 = 0 THEN 2
         WHEN N % 4 = 0 THEN 3
         ELSE 4 END,
    CASE WHEN N % 19 = 0 THEN N'Closed'
         WHEN N % 13 = 0 THEN N'Waiting'
         WHEN N % 5 = 0 THEN N'Assigned'
         ELSE N'Open' END,
    CASE WHEN N % 6 = 0 THEN NULL ELSE ((N * 7) % 250) + 1 END,
    CASE N % 6 WHEN 0 THEN N'Hardware'
               WHEN 1 THEN N'Software'
               WHEN 2 THEN N'SpareParts'
               WHEN 3 THEN N'Consumables'
               WHEN 4 THEN N'Services'
               ELSE N'Safety' END,
    DATEADD(HOUR, CASE WHEN N % 11 = 0 THEN -1 * (N % 48) ELSE (N % 96) END, SYSUTCDATETIME())
FROM Nums;

WITH
E1(N) AS
(
    SELECT 1 FROM (VALUES (0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) AS v(n)
),
E2(N) AS (SELECT 1 FROM E1 a CROSS JOIN E1 b),
E4(N) AS (SELECT 1 FROM E2 a CROSS JOIN E2 b),
Nums(N) AS
(
    SELECT TOP (50000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM E4 a CROSS JOIN E2 b
)
INSERT demo.Invoices
(
    CustomerID, InvoiceDate, DueDate, OpenAmount, CurrencyCode,
    DisputeStatus, RiskClass
)
SELECT
    ((N * 31) % 2500) + 1,
    DATEADD(DAY, -(N % 500), CONVERT(DATE, GETDATE())),
    DATEADD(DAY, -(N % 470) + 30, CONVERT(DATE, GETDATE())),
    CONVERT(MONEY, CASE WHEN N % 3000 = 0 THEN 450000
                        WHEN N % 250 = 0 THEN 65000
                        ELSE 75 + (N % 1200) * 21 END),
    CASE N % 3 WHEN 0 THEN 'EUR'
               WHEN 1 THEN 'USD'
               ELSE 'GBP' END,
    CASE WHEN N % 29 = 0 THEN N'Disputed'
         WHEN N % 17 = 0 THEN N'Promise'
         ELSE N'None' END,
    CASE WHEN N % 37 = 0 THEN N'High'
         WHEN N % 8 = 0 THEN N'Medium'
         ELSE N'Low' END
FROM Nums;
GO

CREATE INDEX IX_demo_Customers_SegmentRegion ON demo.Customers(CustomerSegment, Region) INCLUDE (IsStrategic, CreditLimit);
CREATE INDEX IX_demo_SalesOrders_CustomerDate ON demo.SalesOrders(CustomerID, OrderDate) INCLUDE (Status, Channel, TotalAmount);
CREATE INDEX IX_demo_SalesOrders_StatusDate ON demo.SalesOrders(Status, OrderDate) INCLUDE (CustomerID, Channel, TotalAmount);
CREATE INDEX IX_demo_SalesOrders_DateAmount ON demo.SalesOrders(OrderDate, TotalAmount) INCLUDE (CustomerID, Status, Channel);
CREATE INDEX IX_demo_SalesOrderLines_ProductOrder ON demo.SalesOrderLines(ProductID, OrderID) INCLUDE (LineAmount);
CREATE INDEX IX_demo_Products_Category ON demo.Products(ProductCategory) INCLUDE (ProductName, MarginBand, UnitPrice);
CREATE INDEX IX_demo_ServiceTickets_Dispatch ON demo.ServiceTickets(Region, Priority, Status, SLADeadline) INCLUDE (TechnicianID, CustomerID);
CREATE INDEX IX_demo_ServiceTickets_Technician ON demo.ServiceTickets(TechnicianID, Status, SLADeadline) INCLUDE (Region, Priority, CustomerID);
CREATE INDEX IX_demo_Invoices_CustomerOpen ON demo.Invoices(CustomerID, OpenAmount) INCLUDE (DueDate, RiskClass, CurrencyCode, DisputeStatus);
CREATE INDEX IX_demo_Invoices_RiskDueAmount ON demo.Invoices(RiskClass, DueDate, OpenAmount) INCLUDE (CustomerID, CurrencyCode, DisputeStatus);
GO

SELECT
    Customers = (SELECT COUNT(*) FROM demo.Customers),
    Products = (SELECT COUNT(*) FROM demo.Products),
    SalesOrders = (SELECT COUNT(*) FROM demo.SalesOrders),
    SalesOrderLines = (SELECT COUNT(*) FROM demo.SalesOrderLines),
    ServiceTickets = (SELECT COUNT(*) FROM demo.ServiceTickets),
    Invoices = (SELECT COUNT(*) FROM demo.Invoices);
GO
