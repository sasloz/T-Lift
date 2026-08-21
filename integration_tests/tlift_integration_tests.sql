USE [$(TargetDatabase)];
GO

SET NOCOUNT ON;
GO

CREATE SCHEMA it;
GO

CREATE TABLE it.TestResults (
    TestID INT IDENTITY(1,1) PRIMARY KEY,
    Feature NVARCHAR(100) NOT NULL,
    Scenario NVARCHAR(200) NOT NULL,
    Phase NVARCHAR(50) NOT NULL,
    Status NVARCHAR(10) NOT NULL,
    Detail NVARCHAR(MAX) NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE it.Observed (
    RunID UNIQUEIDENTIFIER NOT NULL,
    SectionName NVARCHAR(80) NOT NULL,
    RowKey INT NOT NULL,
    ValueText NVARCHAR(200) NULL,
    Amount DECIMAL(18,2) NULL
);
GO

CREATE TABLE it.RenderOutput (
    ProcedureName SYSNAME NOT NULL,
    RenderedName SYSNAME NOT NULL,
    RenderedSql NVARCHAR(MAX) NOT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE it.Customers (
    CustomerID INT NOT NULL PRIMARY KEY,
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    City NVARCHAR(50) NOT NULL,
    Country NVARCHAR(50) NOT NULL,
    IsActive BIT NOT NULL,
    CreatedDate DATE NOT NULL
);

CREATE TABLE it.Orders (
    OrderID INT NOT NULL PRIMARY KEY,
    CustomerID INT NOT NULL REFERENCES it.Customers(CustomerID),
    Status NVARCHAR(20) NOT NULL,
    OrderDate DATE NOT NULL,
    TotalAmount DECIMAL(12,2) NOT NULL
);

CREATE TABLE it.Products (
    ProductID INT NOT NULL PRIMARY KEY,
    ProductName NVARCHAR(80) NOT NULL,
    Category NVARCHAR(50) NOT NULL,
    UnitPrice DECIMAL(10,2) NOT NULL,
    IsActive BIT NOT NULL
);

INSERT INTO it.Customers (CustomerID, FirstName, LastName, City, Country, IsActive, CreatedDate)
VALUES
    (1, N'Alice', N'Smith', N'Berlin', N'Germany', 1, '2025-01-10'),
    (2, N'Bob', N'Jones', N'Munich', N'Germany', 1, '2025-02-11'),
    (3, N'Carol', N'Brown', N'Vienna', N'Austria', 0, '2024-12-01'),
    (4, N'Dave', N'Smith', N'Berlin', N'Germany', 1, '2025-06-15'),
    (5, N'Eve', N'Hall', N'Prague', N'Czech Republic', 0, '2023-05-20');

INSERT INTO it.Orders (OrderID, CustomerID, Status, OrderDate, TotalAmount)
VALUES
    (101, 1, N'Pending', '2025-06-01', 25.00),
    (102, 1, N'Shipped', '2025-06-10', 125.50),
    (103, 2, N'Shipped', '2025-07-01', 260.00),
    (104, 3, N'Cancelled', '2025-03-09', 10.00),
    (105, 4, N'Delivered', '2025-08-20', 510.00);

INSERT INTO it.Products (ProductID, ProductName, Category, UnitPrice, IsActive)
VALUES
    (11, N'Camera', N'Electronics', 99.99, 1),
    (12, N'Keyboard', N'Electronics', 49.95, 1),
    (13, N'Novel', N'Books', 14.50, 1),
    (14, N'Legacy Cable', N'Electronics', 7.25, 0);
GO

CREATE OR ALTER PROCEDURE it.RecordResult
    @Feature NVARCHAR(100),
    @Scenario NVARCHAR(200),
    @Phase NVARCHAR(50),
    @Status NVARCHAR(10),
    @Detail NVARCHAR(MAX) = NULL
AS
BEGIN
    INSERT INTO it.TestResults (Feature, Scenario, Phase, Status, Detail)
    VALUES (@Feature, @Scenario, @Phase, @Status, @Detail);
END;
GO

CREATE OR ALTER PROCEDURE it.AssertTrue
    @Feature NVARCHAR(100),
    @Scenario NVARCHAR(200),
    @Phase NVARCHAR(50),
    @Condition BIT,
    @PassDetail NVARCHAR(MAX),
    @FailDetail NVARCHAR(MAX)
AS
BEGIN
    DECLARE @status NVARCHAR(10) = CASE WHEN @Condition = 1 THEN N'PASS' ELSE N'FAIL' END;
    DECLARE @detail NVARCHAR(MAX) = CASE WHEN @Condition = 1 THEN @PassDetail ELSE @FailDetail END;

    EXEC it.RecordResult @Feature, @Scenario, @Phase, @status, @detail;
END;
GO

CREATE OR ALTER PROCEDURE it.AssertContains
    @Feature NVARCHAR(100),
    @Scenario NVARCHAR(200),
    @Needle NVARCHAR(MAX),
    @Haystack NVARCHAR(MAX)
AS
BEGIN
    DECLARE @condition BIT = CASE WHEN CHARINDEX(@Needle, @Haystack) > 0 THEN 1 ELSE 0 END;
    DECLARE @passDetail NVARCHAR(MAX) = N'Found expected text: ' + @Needle;
    DECLARE @failDetail NVARCHAR(MAX) = N'Missing expected text: ' + @Needle;

    EXEC it.AssertTrue
        @Feature,
        @Scenario,
        N'RENDER',
        @condition,
        @passDetail,
        @failDetail;
END;
GO

CREATE OR ALTER PROCEDURE it.AssertNotContains
    @Feature NVARCHAR(100),
    @Scenario NVARCHAR(200),
    @Needle NVARCHAR(MAX),
    @Haystack NVARCHAR(MAX)
AS
BEGIN
    DECLARE @condition BIT = CASE WHEN CHARINDEX(@Needle, @Haystack) = 0 THEN 1 ELSE 0 END;
    DECLARE @passDetail NVARCHAR(MAX) = N'Did not find forbidden text: ' + @Needle;
    DECLARE @failDetail NVARCHAR(MAX) = N'Found forbidden text: ' + @Needle;

    EXEC it.AssertTrue
        @Feature,
        @Scenario,
        N'RENDER',
        @condition,
        @passDetail,
        @failDetail;
END;
GO

CREATE OR ALTER PROCEDURE it.DeployScript
    @RenderedSql NVARCHAR(MAX)
AS
BEGIN
    DECLARE @batch NVARCHAR(MAX) = N'';
    DECLARE @line NVARCHAR(MAX);
    DECLARE @cursorPos INT = 1;
    DECLARE @lineEnd INT;
    DECLARE @trimmedLine NVARCHAR(MAX);
    DECLARE @inSingleQuote BIT = 0;
    DECLARE @inBlockComment BIT = 0;
    DECLARE @scanPos INT;
    DECLARE @scanLen INT;
    DECLARE @ch NCHAR(1);
    DECLARE @nextCh NCHAR(1);

    WHILE @cursorPos <= LEN(@RenderedSql) + 1
    BEGIN
        SET @lineEnd = CHARINDEX(CHAR(10), @RenderedSql, @cursorPos);
        IF @lineEnd = 0
        BEGIN
            SET @line = SUBSTRING(@RenderedSql, @cursorPos, LEN(@RenderedSql) - @cursorPos + 1);
            SET @cursorPos = LEN(@RenderedSql) + 2;
        END
        ELSE
        BEGIN
            SET @line = SUBSTRING(@RenderedSql, @cursorPos, @lineEnd - @cursorPos + 1);
            SET @cursorPos = @lineEnd + 1;
        END

        SET @trimmedLine = LTRIM(RTRIM(REPLACE(REPLACE(@line, CHAR(13), N''), CHAR(10), N'')));

        IF @inSingleQuote = 0 AND @inBlockComment = 0 AND UPPER(@trimmedLine) = N'GO'
        BEGIN
            IF LEN(LTRIM(RTRIM(@batch))) > 0
            BEGIN
                EXEC sys.sp_executesql @batch;
                SET @batch = N'';
            END;
        END
        ELSE
        BEGIN
            SET @batch += @line;
            SET @scanPos = 1;
            SET @scanLen = LEN(@line);

            WHILE @scanPos <= @scanLen
            BEGIN
                SET @ch = SUBSTRING(@line, @scanPos, 1);
                SET @nextCh = SUBSTRING(@line, @scanPos + 1, 1);

                IF @inSingleQuote = 1
                BEGIN
                    IF @ch = N''''
                    BEGIN
                        IF @nextCh = N''''
                            SET @scanPos += 2;
                        ELSE
                        BEGIN
                            SET @inSingleQuote = 0;
                            SET @scanPos += 1;
                        END;
                    END
                    ELSE
                        SET @scanPos += 1;
                END
                ELSE IF @inBlockComment = 1
                BEGIN
                    IF @ch = N'*' AND @nextCh = N'/'
                    BEGIN
                        SET @inBlockComment = 0;
                        SET @scanPos += 2;
                    END
                    ELSE
                        SET @scanPos += 1;
                END
                ELSE IF @ch = N'-' AND @nextCh = N'-'
                    BREAK;
                ELSE IF @ch = N'/' AND @nextCh = N'*'
                BEGIN
                    SET @inBlockComment = 1;
                    SET @scanPos += 2;
                END
                ELSE IF @ch = N''''
                BEGIN
                    SET @inSingleQuote = 1;
                    SET @scanPos += 1;
                END
                ELSE
                    SET @scanPos += 1;
            END;
        END;
    END;

    IF LEN(LTRIM(RTRIM(@batch))) > 0
        EXEC sys.sp_executesql @batch;
END;
GO

CREATE OR ALTER PROCEDURE it.RenderAndDeploy
    @Feature NVARCHAR(100),
    @SourceProcedure SYSNAME,
    @RenderedProcedure SYSNAME,
    @RenderedSql NVARCHAR(MAX) OUTPUT
AS
BEGIN
    DECLARE @renderCondition BIT;
    DECLARE @deployCondition BIT;

    BEGIN TRY
        EXEC [$(EngineDatabase)].dbo.sp_tlift
            @DatabaseName = N'$(TargetDatabase)',
            @SchemaName = N'it',
            @ProcedureName = @SourceProcedure,
            @ProcedureNameNew = @RenderedProcedure,
            @Result = @RenderedSql OUTPUT;

        INSERT INTO it.RenderOutput (ProcedureName, RenderedName, RenderedSql)
        VALUES (@SourceProcedure, @RenderedProcedure, @RenderedSql);

        SET @renderCondition = CASE WHEN LEN(@RenderedSql) > 0 THEN 1 ELSE 0 END;
        DECLARE @renderPass NVARCHAR(MAX) = N'Rendered ' + CONVERT(NVARCHAR(20), LEN(@RenderedSql)) + N' characters.';

        EXEC it.AssertTrue
            @Feature, N'render output is non-empty', N'RENDER',
            @renderCondition,
            @renderPass,
            N'Rendered SQL was empty.';

        EXEC it.DeployScript @RenderedSql;

        SET @deployCondition = CASE WHEN OBJECT_ID(N'it.' + @RenderedProcedure, N'P') IS NOT NULL THEN 1 ELSE 0 END;
        DECLARE @deployPass NVARCHAR(MAX) = N'Deployed it.' + @RenderedProcedure;
        DECLARE @deployFail NVARCHAR(MAX) = N'Procedure it.' + @RenderedProcedure + N' was not found after deploy.';

        EXEC it.AssertTrue
            @Feature, N'rendered procedure deploys', N'DEPLOY',
            @deployCondition,
            @deployPass,
            @deployFail;
    END TRY
    BEGIN CATCH
        DECLARE @errorMessage NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC it.RecordResult @Feature, @SourceProcedure, N'RENDER_OR_DEPLOY', N'FAIL', @errorMessage;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE it.AssertEquivalent
    @Feature NVARCHAR(100),
    @Scenario NVARCHAR(200),
    @SourceExec NVARCHAR(MAX),
    @RenderedExec NVARCHAR(MAX)
AS
BEGIN
    DECLARE @sourceRun UNIQUEIDENTIFIER = NEWID();
    DECLARE @renderedRun UNIQUEIDENTIFIER = NEWID();
    DECLARE @diffCount INT;

    BEGIN TRY
        EXEC sys.sp_executesql @SourceExec, N'@RunID UNIQUEIDENTIFIER', @RunID = @sourceRun;
        EXEC sys.sp_executesql @RenderedExec, N'@RunID UNIQUEIDENTIFIER', @RunID = @renderedRun;

        ;WITH SourceRows AS (
            SELECT SectionName, RowKey, ValueText, Amount
            FROM it.Observed
            WHERE RunID = @sourceRun
        ),
        RenderedRows AS (
            SELECT SectionName, RowKey, ValueText, Amount
            FROM it.Observed
            WHERE RunID = @renderedRun
        ),
        DiffRows AS (
            SELECT * FROM SourceRows
            EXCEPT
            SELECT * FROM RenderedRows
            UNION ALL
            SELECT * FROM RenderedRows
            EXCEPT
            SELECT * FROM SourceRows
        )
        SELECT @diffCount = COUNT(*) FROM DiffRows;

        DECLARE @same BIT = CASE WHEN @diffCount = 0 THEN 1 ELSE 0 END;
        DECLARE @diffFail NVARCHAR(MAX) = N'Source/rendered observation diff count: ' + CONVERT(NVARCHAR(20), @diffCount);

        EXEC it.AssertTrue
            @Feature,
            @Scenario,
            N'EXECUTE',
            @same,
            N'Source and rendered procedure produced identical observations.',
            @diffFail;
    END TRY
    BEGIN CATCH
        DECLARE @errorMessage NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC it.RecordResult @Feature, @Scenario, N'EXECUTE', N'FAIL', @errorMessage;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE it.AssertThrows
    @Feature NVARCHAR(100),
    @Scenario NVARCHAR(200),
    @Sql NVARCHAR(MAX),
    @ExpectedText NVARCHAR(MAX)
AS
BEGIN
    BEGIN TRY
        EXEC sys.sp_executesql @Sql;
        EXEC it.RecordResult @Feature, @Scenario, N'VALIDATION', N'FAIL', N'Expected an error but command succeeded.';
    END TRY
    BEGIN CATCH
        DECLARE @message NVARCHAR(MAX) = ERROR_MESSAGE();
        DECLARE @matched BIT = CASE WHEN CHARINDEX(@ExpectedText, @message) > 0 THEN 1 ELSE 0 END;
        DECLARE @passDetail NVARCHAR(MAX) = N'Got expected error: ' + @message;
        DECLARE @failDetail NVARCHAR(MAX) = N'Unexpected error. Expected fragment: ' + @ExpectedText + N'. Actual: ' + @message;

        EXEC it.AssertTrue
            @Feature,
            @Scenario,
            N'VALIDATION',
            @matched,
            @passDetail,
            @failDetail;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE it.src_single_filter
    @RunID UNIQUEIDENTIFIER,
    @CustomerID INT = NULL
AS
                            --#[ SingleFilter
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'single', c.CustomerID, c.LastName, NULL
FROM it.Customers c
WHERE                       --#if @CustomerID IS NOT NULL
(                           --#-
@CustomerID IS NULL OR      --#-
c.CustomerID = @CustomerID  --#if @CustomerID IS NOT NULL
)                           --#-
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_multi_filter
    @RunID UNIQUEIDENTIFIER,
    @CustomerID INT = NULL,
    @Status NVARCHAR(20) = NULL,
    @OrderDateFrom DATE = NULL
AS
                                    --#[ MultiFilter
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'multi', o.OrderID, o.Status, o.TotalAmount
FROM it.Orders o
WHERE                               --#if @CustomerID IS NOT NULL OR @Status IS NOT NULL OR @OrderDateFrom IS NOT NULL
(                                   --#-
@CustomerID IS NULL OR              --#-
o.CustomerID = @CustomerID          --#if @CustomerID IS NOT NULL
)                                   --#-
AND                                 --#if @CustomerID IS NOT NULL AND @Status IS NOT NULL
(                                   --#-
@Status IS NULL OR                  --#-
o.Status = @Status                  --#if @Status IS NOT NULL
)                                   --#-
AND                                 --#if (@CustomerID IS NOT NULL OR @Status IS NOT NULL) AND @OrderDateFrom IS NOT NULL
(                                   --#-
@OrderDateFrom IS NULL OR           --#-
o.OrderDate >= @OrderDateFrom       --#if @OrderDateFrom IS NOT NULL
)                                   --#-
                                    --#]
GO

CREATE OR ALTER PROCEDURE it.src_block_logic
    @RunID UNIQUEIDENTIFIER,
    @Mode INT = 0
AS
                            --#[ BlockBase
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'base', c.CustomerID, c.City, NULL
FROM it.Customers c
                            --#]

                            --#{if @Mode = 1
                            --#[ BlockOne
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'mode', c.CustomerID, N'one', NULL
FROM it.Customers c
WHERE c.IsActive = 1
                            --#]
                            --#{elseif @Mode = 2
                            --#[ BlockTwo
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'mode', c.CustomerID, N'two', NULL
FROM it.Customers c
WHERE c.IsActive = 0
                            --#]
                            --#else
                            --#[ BlockDefault
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'mode', 0, N'default', NULL
                            --#]
                            --#}
GO

CREATE OR ALTER PROCEDURE it.src_inline_block_and_remove
    @RunID UNIQUEIDENTIFIER,
    @City NVARCHAR(50) = NULL
AS
                            --#[ InlineBlock
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'inline', c.CustomerID, c.City, NULL
FROM it.Customers c
                            --#{if @City IS NOT NULL
WHERE
                            --#{-
(
@City IS NULL OR
                            --#-}
c.City = @City
                            --#{-
)
                            --#-}
                            --#}
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_comment_named_recompile
    @RunID UNIQUEIDENTIFIER,
    @OrderID INT = NULL
AS
                            --#[ NamedRecompile
                            --#recompile
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'named', o.OrderID, o.Status, o.TotalAmount
FROM it.Orders o
WHERE                       --#if @OrderID IS NOT NULL
(                           --#-
@OrderID IS NULL OR         --#-
o.OrderID = @OrderID        --#if @OrderID IS NOT NULL
)                           --#-
ORDER BY o.OrderDate DESC   --#c
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_named_conditions
    @RunID UNIQUEIDENTIFIER,
    @CustomerID INT = NULL,
    @IncludeOrders BIT = 0
AS
                            --#define custFilter = @CustomerID IS NOT NULL

                            --#[ NamedConditionCustomers
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'named-condition-customers', c.CustomerID, c.LastName, NULL
FROM it.Customers c
                            --#{if custFilter
WHERE
c.CustomerID = @CustomerID
                            --#}
                            --#]

                            --#{if @IncludeOrders = 1
                            --#[ NamedConditionOrders
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'named-condition-orders', o.OrderID, o.Status, o.TotalAmount
FROM it.Orders o
                            --#{if custFilter
WHERE
o.CustomerID = @CustomerID
                            --#}
                            --#]
                            --#}
GO

CREATE OR ALTER PROCEDURE it.src_variables
    @RunID UNIQUEIDENTIFIER,
    @Category NVARCHAR(50) = NULL
AS
DECLARE @ActiveOnly BIT = 1;                    --#var
DECLARE @PriceFloor DECIMAL(10,2) = 10.00;      --#var
                                                --#[ Variables
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount) --#usevar @ActiveOnly, @PriceFloor
SELECT @RunID, N'variables', p.ProductID, p.Category, p.UnitPrice
FROM it.Products p
WHERE                                           --#if @Category IS NOT NULL OR @ActiveOnly = 1 OR @PriceFloor IS NOT NULL
(                                               --#-
@Category IS NULL OR                            --#-
p.Category = @Category                          --#if @Category IS NOT NULL
)                                               --#-
AND                                             --#if @Category IS NOT NULL AND @ActiveOnly = 1
p.IsActive = @ActiveOnly                        --#if @ActiveOnly = 1
AND                                             --#if (@Category IS NOT NULL OR @ActiveOnly = 1) AND @PriceFloor IS NOT NULL
p.UnitPrice >= @PriceFloor                      --#if @PriceFloor IS NOT NULL
                                                --#]
GO

CREATE OR ALTER PROCEDURE it.src_types_and_output
    @RunID UNIQUEIDENTIFIER,
    @SearchName NVARCHAR(50) = NULL,
    @Code NCHAR(10) = NULL,
    @MinimumAmount DECIMAL(12,2) = NULL,
    @HitCount INT OUTPUT
AS
SET @HitCount = 0;
                            --#[ TypesAndOutput
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'types-output', c.CustomerID, c.LastName, @MinimumAmount
FROM it.Customers c
WHERE                       --#if @SearchName IS NOT NULL OR @Code IS NOT NULL
(                           --#-
@SearchName IS NULL OR      --#-
c.LastName = @SearchName    --#if @SearchName IS NOT NULL
)                           --#-
AND                         --#if @SearchName IS NOT NULL AND @Code IS NOT NULL
(                           --#-
@Code IS NULL OR            --#-
c.City = @Code              --#if @Code IS NOT NULL
)                           --#-

SELECT @HitCount = COUNT(*)
FROM it.Observed
WHERE RunID = @RunID
  AND SectionName = N'types-output'
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_buckets
    @RunID UNIQUEIDENTIFIER,
    @MinimumAmount DECIMAL(12,2) = NULL,
    @VeryLongParameterName INT = NULL
AS
                            --#[ Buckets
                            --#buckets @MinimumAmount: 50, 100, 250
                            --#buckets @VeryLongParameterName: 2, 4
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'buckets', o.OrderID, o.Status, o.TotalAmount
FROM it.Orders o
WHERE                       --#if @MinimumAmount IS NOT NULL OR @VeryLongParameterName IS NOT NULL
(                           --#-
@MinimumAmount IS NULL OR   --#-
o.TotalAmount >= @MinimumAmount --#if @MinimumAmount IS NOT NULL
)                           --#-
AND                         --#if @MinimumAmount IS NOT NULL AND @VeryLongParameterName IS NOT NULL
(                           --#-
@VeryLongParameterName IS NULL OR --#-
o.CustomerID = @VeryLongParameterName --#if @VeryLongParameterName IS NOT NULL
)                           --#-
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_wrapper
    @RunID UNIQUEIDENTIFIER,
    @CustomerID INT = NULL,
    @City NVARCHAR(50) = NULL
AS
--#wrapper
--#branch _byCustomer @CustomerID IS NOT NULL
--#branch _byCity @City IS NOT NULL
--#branch-default _all
                            --#[ Wrapper
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'wrapper', c.CustomerID, c.City, NULL
FROM it.Customers c
WHERE                       --#if @CustomerID IS NOT NULL OR @City IS NOT NULL
(                           --#-
@CustomerID IS NULL OR      --#-
c.CustomerID = @CustomerID  --#if @CustomerID IS NOT NULL
)                           --#-
AND                         --#if @CustomerID IS NOT NULL AND @City IS NOT NULL
(                           --#-
@City IS NULL OR            --#-
c.City = @City              --#if @City IS NOT NULL
)                           --#-
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_no_directives
    @RunID UNIQUEIDENTIFIER,
    @CustomerID INT
AS
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'plain', c.CustomerID, c.LastName, NULL
FROM it.Customers c
WHERE c.CustomerID = @CustomerID;
GO

CREATE OR ALTER PROCEDURE it.src_literal_scanner
    @RunID UNIQUEIDENTIFIER
AS
DECLARE @msg NVARCHAR(MAX) = N'alpha
GO
beta --#if still literal';
PRINT @msg;

                            --#[ LiteralScanner
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT TOP (1) @RunID, N'literal', c.CustomerID, N'Brian O''Brien --#if literal', NULL
FROM it.Customers c
ORDER BY c.CustomerID
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_bad_unmatched_section
AS
                            --#[
SELECT 1;
GO

CREATE OR ALTER PROCEDURE it.src_bad_unknown_directive
AS
                            --#[ BadUnknown
SELECT 1                    --#fi @x = 1
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_bad_usevar
AS
                            --#[ BadUsevar
SELECT 1                    --#usevar @Missing
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_bad_removal_block
AS
                            --#[ BadRemoval
                            --#{-
SELECT 1;
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_bad_wrapper
AS
--#wrapper
                            --#[ BadWrapper
SELECT 1;
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_bad_bucket
AS
                            --#[ BadBucket
                            --#buckets @Missing: 1, 2
SELECT 1;
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_sort
    @RunID UNIQUEIDENTIFIER,
    @City NVARCHAR(50) = NULL,
    @SortColumn NVARCHAR(50) = NULL
AS
                            --#[ SortWhitelist
                            --#sort @SortColumn: LastName, City
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'sort', c.CustomerID, c.LastName, NULL
FROM it.Customers c
WHERE                       --#if @City IS NOT NULL
(                           --#-
@City IS NULL OR            --#-
c.City = @City              --#if @City IS NOT NULL
)                           --#-
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_bad_sort
AS
                            --#[ BadSort
                            --#sort @Missing: LastName
SELECT 1;
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_suggest_candidate
    @RunID UNIQUEIDENTIFIER,
    @CustomerID INT = NULL,
    @City NVARCHAR(50) = NULL,
    @MinAmount DECIMAL(12,2) = NULL
AS
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'suggest', o.OrderID, o.Status, o.TotalAmount
FROM it.Orders o
INNER JOIN it.Customers c ON c.CustomerID = o.CustomerID
WHERE (@CustomerID IS NULL OR o.CustomerID = @CustomerID)
  AND (@City IS NULL OR c.City = @City)
  AND o.TotalAmount >= ISNULL(@MinAmount, 0);
GO

CREATE OR ALTER PROCEDURE it.src_drift_probe
    @RunID UNIQUEIDENTIFIER,
    @CustomerID INT = NULL
AS
                            --#[ DriftProbe
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'drift-probe', c.CustomerID, c.LastName, NULL
FROM it.Customers c
WHERE                       --#if @CustomerID IS NOT NULL
(                           --#-
@CustomerID IS NULL OR      --#-
c.CustomerID = @CustomerID  --#if @CustomerID IS NOT NULL
)                           --#-
                            --#]
GO

CREATE OR ALTER PROCEDURE it.src_drift_orphan
    @RunID UNIQUEIDENTIFIER
AS
                            --#[ DriftOrphan
INSERT INTO it.Observed (RunID, SectionName, RowKey, ValueText, Amount)
SELECT @RunID, N'drift-orphan', c.CustomerID, c.LastName, NULL
FROM it.Customers c
                            --#]
GO

DECLARE @dyn NVARCHAR(MAX);

BEGIN TRY
    EXEC [$(EngineDatabase)].dbo.sp_tlift @help = 1;
    EXEC it.RecordResult N'Installation', N'help mode prints without requiring target metadata', N'EXECUTE', N'PASS', N'@help = 1 completed.';
END TRY
BEGIN CATCH
    DECLARE @helpError NVARCHAR(MAX) = ERROR_MESSAGE();
    EXEC it.RecordResult N'Installation', N'help mode prints without requiring target metadata', N'EXECUTE', N'FAIL', @helpError;
END CATCH;

EXEC it.AssertThrows
    N'Parameter validation',
    N'missing @DatabaseName fails',
    N'DECLARE @r NVARCHAR(MAX); EXEC [$(EngineDatabase)].dbo.sp_tlift @ProcedureName = N''src_single_filter'', @Result = @r OUTPUT;',
    N'@DatabaseName is missing or empty';

EXEC it.AssertThrows
    N'Parameter validation',
    N'missing procedure fails',
    N'DECLARE @r NVARCHAR(MAX); EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N''$(TargetDatabase)'', @SchemaName = N''it'', @ProcedureName = N''does_not_exist'', @Result = @r OUTPUT;',
    N'was not found';

EXEC it.RenderAndDeploy N'Dynamic sections and single-line IF', N'src_single_filter', N'rendered_single_filter', @dyn OUTPUT;
EXEC it.AssertContains N'Dynamic sections and single-line IF', N'section label emitted', N'/*SingleFilter*/', @dyn;
EXEC it.AssertContains N'Dynamic sections and single-line IF', N'sp_executesql used', N'exec sp_executesql @sql', @dyn;
EXEC it.AssertEquivalent N'Dynamic sections and single-line IF', N'@CustomerID = NULL', N'EXEC it.src_single_filter @RunID = @RunID, @CustomerID = NULL;', N'EXEC it.rendered_single_filter @RunID = @RunID, @CustomerID = NULL;';
EXEC it.AssertEquivalent N'Dynamic sections and single-line IF', N'@CustomerID = 1', N'EXEC it.src_single_filter @RunID = @RunID, @CustomerID = 1;', N'EXEC it.rendered_single_filter @RunID = @RunID, @CustomerID = 1;';
EXEC it.AssertEquivalent N'Dynamic sections and single-line IF', N'@CustomerID = 999', N'EXEC it.src_single_filter @RunID = @RunID, @CustomerID = 999;', N'EXEC it.rendered_single_filter @RunID = @RunID, @CustomerID = 999;';

EXEC it.RenderAndDeploy N'Multiple optional filters', N'src_multi_filter', N'rendered_multi_filter', @dyn OUTPUT;
EXEC it.AssertEquivalent N'Multiple optional filters', N'all filters NULL', N'EXEC it.src_multi_filter @RunID = @RunID;', N'EXEC it.rendered_multi_filter @RunID = @RunID;';
EXEC it.AssertEquivalent N'Multiple optional filters', N'customer only', N'EXEC it.src_multi_filter @RunID = @RunID, @CustomerID = 1;', N'EXEC it.rendered_multi_filter @RunID = @RunID, @CustomerID = 1;';
EXEC it.AssertEquivalent N'Multiple optional filters', N'status only', N'EXEC it.src_multi_filter @RunID = @RunID, @Status = N''Shipped'';', N'EXEC it.rendered_multi_filter @RunID = @RunID, @Status = N''Shipped'';';
EXEC it.AssertEquivalent N'Multiple optional filters', N'all filters', N'EXEC it.src_multi_filter @RunID = @RunID, @CustomerID = 1, @Status = N''Shipped'', @OrderDateFrom = ''2025-06-01'';', N'EXEC it.rendered_multi_filter @RunID = @RunID, @CustomerID = 1, @Status = N''Shipped'', @OrderDateFrom = ''2025-06-01'';';

EXEC it.RenderAndDeploy N'Block if else elseif', N'src_block_logic', N'rendered_block_logic', @dyn OUTPUT;
EXEC it.AssertContains N'Block if else elseif', N'ELSE IF rendered', N'ELSE IF @Mode = 2', @dyn;
EXEC it.AssertEquivalent N'Block if else elseif', N'default branch', N'EXEC it.src_block_logic @RunID = @RunID, @Mode = 0;', N'EXEC it.rendered_block_logic @RunID = @RunID, @Mode = 0;';
EXEC it.AssertEquivalent N'Block if else elseif', N'if branch', N'EXEC it.src_block_logic @RunID = @RunID, @Mode = 1;', N'EXEC it.rendered_block_logic @RunID = @RunID, @Mode = 1;';
EXEC it.AssertEquivalent N'Block if else elseif', N'elseif branch', N'EXEC it.src_block_logic @RunID = @RunID, @Mode = 2;', N'EXEC it.rendered_block_logic @RunID = @RunID, @Mode = 2;';

EXEC it.RenderAndDeploy N'Inline block and block removal', N'src_inline_block_and_remove', N'rendered_inline_block_and_remove', @dyn OUTPUT;
EXEC it.AssertContains N'Inline block and block removal', N'static catch-all predicate is commented out', N'--@City IS NULL OR', @dyn;
EXEC it.AssertEquivalent N'Inline block and block removal', N'city NULL', N'EXEC it.src_inline_block_and_remove @RunID = @RunID, @City = NULL;', N'EXEC it.rendered_inline_block_and_remove @RunID = @RunID, @City = NULL;';
EXEC it.AssertEquivalent N'Inline block and block removal', N'city Berlin', N'EXEC it.src_inline_block_and_remove @RunID = @RunID, @City = N''Berlin'';', N'EXEC it.rendered_inline_block_and_remove @RunID = @RunID, @City = N''Berlin'';';

EXEC it.RenderAndDeploy N'Named section comment and recompile', N'src_comment_named_recompile', N'rendered_comment_named_recompile', @dyn OUTPUT;
EXEC it.AssertContains N'Named section comment and recompile', N'named section label', N'/*NamedRecompile*/', @dyn;
EXEC it.AssertContains N'Named section comment and recompile', N'OPTION RECOMPILE', N'OPTION(RECOMPILE)', @dyn;
EXEC it.AssertContains N'Named section comment and recompile', N'comment directive preserved as SQL comment', N'--ORDER BY o.OrderDate DESC', @dyn;
EXEC it.AssertEquivalent N'Named section comment and recompile', N'order NULL', N'EXEC it.src_comment_named_recompile @RunID = @RunID, @OrderID = NULL;', N'EXEC it.rendered_comment_named_recompile @RunID = @RunID, @OrderID = NULL;';
EXEC it.AssertEquivalent N'Named section comment and recompile', N'order 102', N'EXEC it.src_comment_named_recompile @RunID = @RunID, @OrderID = 102;', N'EXEC it.rendered_comment_named_recompile @RunID = @RunID, @OrderID = 102;';

EXEC it.RenderAndDeploy N'Named conditions', N'src_named_conditions', N'rendered_named_conditions', @dyn OUTPUT;
EXEC it.AssertContains N'Named conditions', N'condition was resolved', N'IF @CustomerID IS NOT NULL', @dyn;
EXEC it.AssertEquivalent N'Named conditions', N'customer with orders', N'EXEC it.src_named_conditions @RunID = @RunID, @CustomerID = 1, @IncludeOrders = 1;', N'EXEC it.rendered_named_conditions @RunID = @RunID, @CustomerID = 1, @IncludeOrders = 1;';
DECLARE @namedRun UNIQUEIDENTIFIER = NEWID();
EXEC it.rendered_named_conditions @RunID = @namedRun, @CustomerID = NULL, @IncludeOrders = 0;
DECLARE @namedOrderCount INT = (
    SELECT COUNT(*)
    FROM it.Observed
    WHERE RunID = @namedRun
      AND SectionName = N'named-condition-orders'
);
DECLARE @namedOrdersSkipped BIT = CASE WHEN @namedOrderCount = 0 THEN 1 ELSE 0 END;
DECLARE @namedOrdersFail NVARCHAR(MAX) = N'Expected zero order rows when @IncludeOrders = 0, got ' + CONVERT(NVARCHAR(20), @namedOrderCount);
EXEC it.AssertTrue N'Named conditions', N'outer block suppresses order section', N'EXECUTE', @namedOrdersSkipped, N'Order section skipped.', @namedOrdersFail;

EXEC it.RenderAndDeploy N'Variables and usevar', N'src_variables', N'rendered_variables', @dyn OUTPUT;
EXEC it.AssertContains N'Variables and usevar', N'local bit variable passed to sp_executesql', N'@ActiveOnly bit', @dyn;
EXEC it.AssertContains N'Variables and usevar', N'local decimal variable passed to sp_executesql', N'@PriceFloor decimal(10,2)', @dyn;
EXEC it.AssertEquivalent N'Variables and usevar', N'category NULL', N'EXEC it.src_variables @RunID = @RunID, @Category = NULL;', N'EXEC it.rendered_variables @RunID = @RunID, @Category = NULL;';
EXEC it.AssertEquivalent N'Variables and usevar', N'category Electronics', N'EXEC it.src_variables @RunID = @RunID, @Category = N''Electronics'';', N'EXEC it.rendered_variables @RunID = @RunID, @Category = N''Electronics'';';

EXEC it.RenderAndDeploy N'Types and output parameters', N'src_types_and_output', N'rendered_types_and_output', @dyn OUTPUT;
EXEC it.AssertContains N'Types and output parameters', N'nvarchar length is character count', N'@SearchName nvarchar(50)', @dyn;
EXEC it.AssertContains N'Types and output parameters', N'nchar length is character count', N'@Code nchar(10)', @dyn;
EXEC it.AssertContains N'Types and output parameters', N'decimal precision scale retained', N'@MinimumAmount decimal(12,2)', @dyn;
EXEC it.AssertContains N'Types and output parameters', N'output parameter retained', N'@HitCount int OUTPUT', @dyn;
DECLARE @srcHits INT = -1, @renderedHits INT = -2, @sourceRun UNIQUEIDENTIFIER = NEWID(), @renderedRun UNIQUEIDENTIFIER = NEWID();
EXEC it.src_types_and_output @RunID = @sourceRun, @SearchName = N'Smith', @Code = NULL, @MinimumAmount = 42.25, @HitCount = @srcHits OUTPUT;
EXEC it.rendered_types_and_output @RunID = @renderedRun, @SearchName = N'Smith', @Code = NULL, @MinimumAmount = 42.25, @HitCount = @renderedHits OUTPUT;
DECLARE @outputMatches BIT = CASE WHEN @srcHits = @renderedHits THEN 1 ELSE 0 END;
DECLARE @outputFailDetail NVARCHAR(MAX) = N'Source output ' + CONVERT(NVARCHAR(20), @srcHits) + N', rendered output ' + CONVERT(NVARCHAR(20), @renderedHits);
EXEC it.AssertTrue N'Types and output parameters', N'output value matches source', N'EXECUTE', @outputMatches, N'Output values match.', @outputFailDetail;

EXEC it.RenderAndDeploy N'Buckets', N'src_buckets', N'rendered_buckets', @dyn OUTPUT;
EXEC it.AssertContains N'Buckets', N'first bucket variable generated', N'DECLARE @buckets1 CHAR(2)', @dyn;
EXEC it.AssertContains N'Buckets', N'second bucket variable generated', N'DECLARE @buckets2 CHAR(2)', @dyn;
EXEC it.AssertContains N'Buckets', N'bucket comment prefix generated', N'set @sql = ''/*''+@bucket+''*/'' + @sql', @dyn;
EXEC it.AssertEquivalent N'Buckets', N'below first bucket', N'EXEC it.src_buckets @RunID = @RunID, @MinimumAmount = 25, @VeryLongParameterName = NULL;', N'EXEC it.rendered_buckets @RunID = @RunID, @MinimumAmount = 25, @VeryLongParameterName = NULL;';
EXEC it.AssertEquivalent N'Buckets', N'on boundary with long parameter name', N'EXEC it.src_buckets @RunID = @RunID, @MinimumAmount = 100, @VeryLongParameterName = 1;', N'EXEC it.rendered_buckets @RunID = @RunID, @MinimumAmount = 100, @VeryLongParameterName = 1;';
EXEC it.AssertEquivalent N'Buckets', N'above last bucket', N'EXEC it.src_buckets @RunID = @RunID, @MinimumAmount = 300, @VeryLongParameterName = NULL;', N'EXEC it.rendered_buckets @RunID = @RunID, @MinimumAmount = 300, @VeryLongParameterName = NULL;';

EXEC it.RenderAndDeploy N'Wrapper procedures', N'src_wrapper', N'rendered_wrapper', @dyn OUTPUT;
EXEC it.AssertContains N'Wrapper procedures', N'wrapper contains child batch separator', N'GO', @dyn;
DECLARE @wrapperCustomerExists BIT = CASE WHEN OBJECT_ID(N'it.rendered_wrapper_byCustomer', N'P') IS NOT NULL THEN 1 ELSE 0 END;
DECLARE @wrapperCityExists BIT = CASE WHEN OBJECT_ID(N'it.rendered_wrapper_byCity', N'P') IS NOT NULL THEN 1 ELSE 0 END;
DECLARE @wrapperDefaultExists BIT = CASE WHEN OBJECT_ID(N'it.rendered_wrapper_all', N'P') IS NOT NULL THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Wrapper procedures', N'customer child exists', N'DEPLOY', @wrapperCustomerExists, N'Customer child exists.', N'Customer child missing.';
EXEC it.AssertTrue N'Wrapper procedures', N'city child exists', N'DEPLOY', @wrapperCityExists, N'City child exists.', N'City child missing.';
EXEC it.AssertTrue N'Wrapper procedures', N'default child exists', N'DEPLOY', @wrapperDefaultExists, N'Default child exists.', N'Default child missing.';
EXEC it.AssertEquivalent N'Wrapper procedures', N'dispatch customer branch', N'EXEC it.src_wrapper @RunID = @RunID, @CustomerID = 1, @City = NULL;', N'EXEC it.rendered_wrapper @RunID = @RunID, @CustomerID = 1, @City = NULL;';
EXEC it.AssertEquivalent N'Wrapper procedures', N'dispatch city branch', N'EXEC it.src_wrapper @RunID = @RunID, @CustomerID = NULL, @City = N''Berlin'';', N'EXEC it.rendered_wrapper @RunID = @RunID, @CustomerID = NULL, @City = N''Berlin'';';
EXEC it.AssertEquivalent N'Wrapper procedures', N'dispatch default branch', N'EXEC it.src_wrapper @RunID = @RunID, @CustomerID = NULL, @City = NULL;', N'EXEC it.rendered_wrapper @RunID = @RunID, @CustomerID = NULL, @City = NULL;';

EXEC it.RenderAndDeploy N'No directives baseline', N'src_no_directives', N'rendered_no_directives', @dyn OUTPUT;
EXEC it.AssertEquivalent N'No directives baseline', N'plain procedure keeps semantics', N'EXEC it.src_no_directives @RunID = @RunID, @CustomerID = 1;', N'EXEC it.rendered_no_directives @RunID = @RunID, @CustomerID = 1;';

EXEC it.RenderAndDeploy N'Literal scanner and deployment splitter', N'src_literal_scanner', N'rendered_literal_scanner', @dyn OUTPUT;
EXEC it.AssertContains N'Literal scanner and deployment splitter', N'directive token in string remains literal', N'--#if literal', @dyn;
EXEC it.AssertEquivalent N'Literal scanner and deployment splitter', N'GO and directive tokens inside literals', N'EXEC it.src_literal_scanner @RunID = @RunID;', N'EXEC it.rendered_literal_scanner @RunID = @RunID;';

EXEC it.AssertThrows
    N'Validation mode',
    N'unmatched dynamic section',
    N'DECLARE @r NVARCHAR(MAX); EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N''$(TargetDatabase)'', @SchemaName = N''it'', @ProcedureName = N''src_bad_unmatched_section'', @validateOnly = 1, @Result = @r OUTPUT;',
    N'Unmatched --#[';

EXEC it.AssertThrows
    N'Validation mode',
    N'unknown directive',
    N'DECLARE @r NVARCHAR(MAX); EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N''$(TargetDatabase)'', @SchemaName = N''it'', @ProcedureName = N''src_bad_unknown_directive'', @validateOnly = 1, @Result = @r OUTPUT;',
    N'Unknown T-Lift directive';

EXEC it.AssertThrows
    N'Validation mode',
    N'usevar without var',
    N'DECLARE @r NVARCHAR(MAX); EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N''$(TargetDatabase)'', @SchemaName = N''it'', @ProcedureName = N''src_bad_usevar'', @validateOnly = 1, @Result = @r OUTPUT;',
    N'--#usevar references undeclared variable';

EXEC it.AssertThrows
    N'Validation mode',
    N'unmatched removal block',
    N'DECLARE @r NVARCHAR(MAX); EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N''$(TargetDatabase)'', @SchemaName = N''it'', @ProcedureName = N''src_bad_removal_block'', @validateOnly = 1, @Result = @r OUTPUT;',
    N'Unmatched removal block directive';

EXEC it.AssertThrows
    N'Validation mode',
    N'wrapper without branch',
    N'DECLARE @r NVARCHAR(MAX); EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N''$(TargetDatabase)'', @SchemaName = N''it'', @ProcedureName = N''src_bad_wrapper'', @Result = @r OUTPUT;',
    N'--#wrapper specified but no --#branch';

EXEC it.AssertThrows
    N'Validation mode',
    N'bucket references unknown parameter',
    N'DECLARE @r NVARCHAR(MAX); EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N''$(TargetDatabase)'', @SchemaName = N''it'', @ProcedureName = N''src_bad_bucket'', @Result = @r OUTPUT;',
    N'The following bucket parameters are not declared or marked with usevar';

-- ===================================================================
-- --#sort: whitelist-based safe dynamic ORDER BY
-- ===================================================================
EXEC it.RenderAndDeploy N'Sort whitelist', N'src_sort', N'rendered_sort', @dyn OUTPUT;
EXEC it.AssertContains N'Sort whitelist', N'ascending order by generated', N'ORDER BY LastName', @dyn;
EXEC it.AssertContains N'Sort whitelist', N'descending variant generated', N'ORDER BY LastName DESC', @dyn;
EXEC it.AssertContains N'Sort whitelist', N'runtime whitelist guard generated', N'is not in the sort whitelist', @dyn;
EXEC it.AssertEquivalent N'Sort whitelist', N'no sort requested', N'EXEC it.src_sort @RunID = @RunID;', N'EXEC it.rendered_sort @RunID = @RunID;';
EXEC it.AssertEquivalent N'Sort whitelist', N'sort by city with filter', N'EXEC it.src_sort @RunID = @RunID, @City = N''Berlin'', @SortColumn = N''City'';', N'EXEC it.rendered_sort @RunID = @RunID, @City = N''Berlin'', @SortColumn = N''City'';';
EXEC it.AssertEquivalent N'Sort whitelist', N'case-insensitive descending sort', N'EXEC it.src_sort @RunID = @RunID, @SortColumn = N''lastname DESC'';', N'EXEC it.rendered_sort @RunID = @RunID, @SortColumn = N''lastname DESC'';';

EXEC it.AssertThrows
    N'Sort whitelist',
    N'non-whitelisted sort value fails at runtime',
    N'DECLARE @rid UNIQUEIDENTIFIER = NEWID(); EXEC it.rendered_sort @RunID = @rid, @SortColumn = N''CustomerID; DROP TABLE it.Customers'';',
    N'is not in the sort whitelist';

EXEC it.AssertThrows
    N'Sort whitelist',
    N'sort parameter must exist',
    N'DECLARE @r NVARCHAR(MAX); EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N''$(TargetDatabase)'', @SchemaName = N''it'', @ProcedureName = N''src_bad_sort'', @Result = @r OUTPUT;',
    N'The following sort parameters are not declared or marked with usevar';

-- ===================================================================
-- Render metadata stamp
-- ===================================================================
EXEC it.AssertContains N'Render metadata stamp', N'stamp marker present', N'/* T-Lift:render', @dyn;
EXEC it.AssertContains N'Render metadata stamp', N'source hash recorded', N'SourceHash=0x', @dyn;
EXEC it.AssertContains N'Render metadata stamp', N'source procedure recorded', N'SourceProc=src_sort', @dyn;
EXEC it.AssertContains N'Render metadata stamp', N'source schema recorded', N'SourceSchema=it', @dyn;

-- ===================================================================
-- @execute = 1: render and deploy in one call
-- ===================================================================
BEGIN TRY
    EXEC [$(EngineDatabase)].dbo.sp_tlift
        @DatabaseName = N'$(TargetDatabase)', @SchemaName = N'it',
        @ProcedureName = N'src_single_filter', @ProcedureNameNew = N'rendered_exec_single',
        @execute = 1, @Result = @dyn OUTPUT;
    EXEC it.RecordResult N'Execute deployment', N'@execute renders and deploys in one call', N'DEPLOY', N'PASS', N'sp_tlift @execute = 1 completed.';
END TRY
BEGIN CATCH
    DECLARE @execErr1 NVARCHAR(MAX) = ERROR_MESSAGE();
    EXEC it.RecordResult N'Execute deployment', N'@execute renders and deploys in one call', N'DEPLOY', N'FAIL', @execErr1;
END CATCH;

DECLARE @execSingleExists BIT = CASE WHEN OBJECT_ID(N'it.rendered_exec_single', N'P') IS NOT NULL THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Execute deployment', N'deployed procedure exists', N'DEPLOY', @execSingleExists, N'it.rendered_exec_single exists.', N'it.rendered_exec_single missing.';

BEGIN TRY
    EXEC [$(EngineDatabase)].dbo.sp_tlift
        @DatabaseName = N'$(TargetDatabase)', @SchemaName = N'it',
        @ProcedureName = N'src_single_filter', @ProcedureNameNew = N'rendered_exec_single',
        @execute = 1, @Result = @dyn OUTPUT;
    EXEC it.RecordResult N'Execute deployment', N're-run replaces existing procedure', N'DEPLOY', N'PASS', N'Second @execute = 1 run completed (drop + create).';
END TRY
BEGIN CATCH
    DECLARE @execErr2 NVARCHAR(MAX) = ERROR_MESSAGE();
    EXEC it.RecordResult N'Execute deployment', N're-run replaces existing procedure', N'DEPLOY', N'FAIL', @execErr2;
END CATCH;

DECLARE @execSingleStillExists BIT = CASE WHEN OBJECT_ID(N'it.rendered_exec_single', N'P') IS NOT NULL THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Execute deployment', N'procedure exists after re-run', N'DEPLOY', @execSingleStillExists, N'it.rendered_exec_single exists after re-run.', N'it.rendered_exec_single missing after re-run.';
EXEC it.AssertEquivalent N'Execute deployment', N'deployed procedure parity', N'EXEC it.src_single_filter @RunID = @RunID, @CustomerID = 1;', N'EXEC it.rendered_exec_single @RunID = @RunID, @CustomerID = 1;';

BEGIN TRY
    EXEC [$(EngineDatabase)].dbo.sp_tlift
        @DatabaseName = N'$(TargetDatabase)', @SchemaName = N'it',
        @ProcedureName = N'src_wrapper', @ProcedureNameNew = N'rendered_exec_wrapper',
        @execute = 1, @Result = @dyn OUTPUT;
    EXEC it.RecordResult N'Execute deployment', N'@execute deploys wrapper and children', N'DEPLOY', N'PASS', N'Wrapper @execute = 1 completed.';
END TRY
BEGIN CATCH
    DECLARE @execErr3 NVARCHAR(MAX) = ERROR_MESSAGE();
    EXEC it.RecordResult N'Execute deployment', N'@execute deploys wrapper and children', N'DEPLOY', N'FAIL', @execErr3;
END CATCH;

DECLARE @execWrapperAll BIT = CASE WHEN OBJECT_ID(N'it.rendered_exec_wrapper', N'P') IS NOT NULL
    AND OBJECT_ID(N'it.rendered_exec_wrapper_byCustomer', N'P') IS NOT NULL
    AND OBJECT_ID(N'it.rendered_exec_wrapper_byCity', N'P') IS NOT NULL
    AND OBJECT_ID(N'it.rendered_exec_wrapper_all', N'P') IS NOT NULL THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Execute deployment', N'wrapper and all children deployed', N'DEPLOY', @execWrapperAll, N'Wrapper plus 3 children exist.', N'Wrapper or a child procedure is missing.';
EXEC it.AssertEquivalent N'Execute deployment', N'deployed wrapper dispatch parity', N'EXEC it.src_wrapper @RunID = @RunID, @CustomerID = NULL, @City = NULL;', N'EXEC it.rendered_exec_wrapper @RunID = @RunID, @CustomerID = NULL, @City = NULL;';

BEGIN TRY
    EXEC [$(EngineDatabase)].dbo.sp_tlift
        @DatabaseName = N'$(TargetDatabase)', @SchemaName = N'it',
        @ProcedureName = N'src_literal_scanner', @ProcedureNameNew = N'rendered_exec_literal',
        @execute = 1, @Result = @dyn OUTPUT;
    EXEC it.RecordResult N'Execute deployment', N'@execute survives GO inside string literals', N'DEPLOY', N'PASS', N'Literal-scanner @execute = 1 completed.';
END TRY
BEGIN CATCH
    DECLARE @execErr4 NVARCHAR(MAX) = ERROR_MESSAGE();
    EXEC it.RecordResult N'Execute deployment', N'@execute survives GO inside string literals', N'DEPLOY', N'FAIL', @execErr4;
END CATCH;
EXEC it.AssertEquivalent N'Execute deployment', N'literal scanner parity after @execute', N'EXEC it.src_literal_scanner @RunID = @RunID;', N'EXEC it.rendered_exec_literal @RunID = @RunID;';

-- ===================================================================
-- @suggest = 1: catch-all pattern detection
-- ===================================================================
CREATE TABLE #sugg (
    LineNumber INT,
    ParameterName NVARCHAR(200) NULL,
    PatternType NVARCHAR(20),
    LineText NVARCHAR(200),
    Suggestion NVARCHAR(MAX)
);

BEGIN TRY
    INSERT INTO #sugg
    EXEC [$(EngineDatabase)].dbo.sp_tlift
        @DatabaseName = N'$(TargetDatabase)', @SchemaName = N'it',
        @ProcedureName = N'src_suggest_candidate', @suggest = 1;
    EXEC it.RecordResult N'Suggestion mode', N'@suggest returns a findings result set', N'EXECUTE', N'PASS', N'@suggest = 1 completed.';
END TRY
BEGIN CATCH
    DECLARE @suggErr NVARCHAR(MAX) = ERROR_MESSAGE();
    EXEC it.RecordResult N'Suggestion mode', N'@suggest returns a findings result set', N'EXECUTE', N'FAIL', @suggErr;
END CATCH;

DECLARE @suggCatchAll INT = (SELECT COUNT(*) FROM #sugg WHERE PatternType = N'CATCH_ALL');
DECLARE @suggCatchAllOk BIT = CASE WHEN @suggCatchAll >= 2 THEN 1 ELSE 0 END;
DECLARE @suggCatchAllFail NVARCHAR(MAX) = N'Expected at least 2 CATCH_ALL findings, got ' + CONVERT(NVARCHAR(20), @suggCatchAll);
EXEC it.AssertTrue N'Suggestion mode', N'detects classic catch-all predicates', N'EXECUTE', @suggCatchAllOk, N'Both catch-all predicates detected.', @suggCatchAllFail;

DECLARE @suggHasCustomer BIT = CASE WHEN EXISTS (SELECT 1 FROM #sugg WHERE ParameterName = N'@CustomerID' AND PatternType = N'CATCH_ALL') THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Suggestion mode', N'extracts @CustomerID from catch-all', N'EXECUTE', @suggHasCustomer, N'@CustomerID finding present.', N'@CustomerID finding missing.';

DECLARE @suggHasCity BIT = CASE WHEN EXISTS (SELECT 1 FROM #sugg WHERE ParameterName = N'@City' AND PatternType = N'CATCH_ALL') THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Suggestion mode', N'extracts @City from catch-all', N'EXECUTE', @suggHasCity, N'@City finding present.', N'@City finding missing.';

DECLARE @suggHasIsnull BIT = CASE WHEN EXISTS (SELECT 1 FROM #sugg WHERE ParameterName = N'@MinAmount' AND PatternType = N'ISNULL') THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Suggestion mode', N'detects ISNULL variant', N'EXECUTE', @suggHasIsnull, N'ISNULL(@MinAmount, ...) finding present.', N'ISNULL finding missing.';

DROP TABLE #sugg;

-- ===================================================================
-- @checkDrift = 1: stale-render detection via metadata stamp
-- ===================================================================
BEGIN TRY
    EXEC [$(EngineDatabase)].dbo.sp_tlift
        @DatabaseName = N'$(TargetDatabase)', @SchemaName = N'it',
        @ProcedureName = N'src_drift_probe', @ProcedureNameNew = N'rendered_drift_probe',
        @execute = 1, @Result = @dyn OUTPUT;
    EXEC [$(EngineDatabase)].dbo.sp_tlift
        @DatabaseName = N'$(TargetDatabase)', @SchemaName = N'it',
        @ProcedureName = N'src_drift_orphan', @ProcedureNameNew = N'rendered_drift_orphan',
        @execute = 1, @Result = @dyn OUTPUT;
    EXEC it.RecordResult N'Drift detection', N'drift fixtures rendered and deployed', N'DEPLOY', N'PASS', N'Both drift fixtures deployed via @execute = 1.';
END TRY
BEGIN CATCH
    DECLARE @driftDeployErr NVARCHAR(MAX) = ERROR_MESSAGE();
    EXEC it.RecordResult N'Drift detection', N'drift fixtures rendered and deployed', N'DEPLOY', N'FAIL', @driftDeployErr;
END CATCH;

CREATE TABLE #drift (
    RenderedSchema SYSNAME,
    RenderedProcedure SYSNAME,
    SourceSchema NVARCHAR(500) NULL,
    SourceProcedure NVARCHAR(500) NULL,
    DriftStatus NVARCHAR(20),
    StoredHash NVARCHAR(70) NULL,
    CurrentHash NVARCHAR(70) NULL,
    RenderedUtc NVARCHAR(40) NULL,
    TLiftVersion NVARCHAR(20) NULL
);

BEGIN TRY
    INSERT INTO #drift
    EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N'$(TargetDatabase)', @checkDrift = 1;
    EXEC it.RecordResult N'Drift detection', N'@checkDrift returns a report', N'EXECUTE', N'PASS', N'First drift scan completed.';
END TRY
BEGIN CATCH
    DECLARE @driftErr1 NVARCHAR(MAX) = ERROR_MESSAGE();
    EXEC it.RecordResult N'Drift detection', N'@checkDrift returns a report', N'EXECUTE', N'FAIL', @driftErr1;
END CATCH;

DECLARE @driftFreshOk BIT = CASE WHEN EXISTS (
    SELECT 1 FROM #drift WHERE RenderedProcedure = N'rendered_drift_probe' AND DriftStatus = N'OK'
) THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Drift detection', N'fresh render reports OK', N'EXECUTE', @driftFreshOk, N'rendered_drift_probe reported OK.', N'rendered_drift_probe not reported as OK after fresh render.';

-- Change the source procedure and drop the orphan source
EXEC sys.sp_executesql N'ALTER PROCEDURE it.src_drift_probe @RunID UNIQUEIDENTIFIER, @CustomerID INT = NULL AS SELECT 1 AS DriftChanged;';
EXEC sys.sp_executesql N'DROP PROCEDURE it.src_drift_orphan;';

TRUNCATE TABLE #drift;

BEGIN TRY
    INSERT INTO #drift
    EXEC [$(EngineDatabase)].dbo.sp_tlift @DatabaseName = N'$(TargetDatabase)', @checkDrift = 1;
    EXEC it.RecordResult N'Drift detection', N'second drift scan completes', N'EXECUTE', N'PASS', N'Second drift scan completed.';
END TRY
BEGIN CATCH
    DECLARE @driftErr2 NVARCHAR(MAX) = ERROR_MESSAGE();
    EXEC it.RecordResult N'Drift detection', N'second drift scan completes', N'EXECUTE', N'FAIL', @driftErr2;
END CATCH;

DECLARE @driftChangedOk BIT = CASE WHEN EXISTS (
    SELECT 1 FROM #drift WHERE RenderedProcedure = N'rendered_drift_probe' AND DriftStatus = N'DRIFT'
) THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Drift detection', N'changed source reports DRIFT', N'EXECUTE', @driftChangedOk, N'rendered_drift_probe reported DRIFT after source change.', N'rendered_drift_probe did not report DRIFT after source change.';

DECLARE @driftOrphanOk BIT = CASE WHEN EXISTS (
    SELECT 1 FROM #drift WHERE RenderedProcedure = N'rendered_drift_orphan' AND DriftStatus = N'SOURCE_MISSING'
) THEN 1 ELSE 0 END;
EXEC it.AssertTrue N'Drift detection', N'dropped source reports SOURCE_MISSING', N'EXECUTE', @driftOrphanOk, N'rendered_drift_orphan reported SOURCE_MISSING.', N'rendered_drift_orphan did not report SOURCE_MISSING.';

DROP TABLE #drift;

DECLARE @failCount INT = (SELECT COUNT(*) FROM it.TestResults WHERE Status = N'FAIL');
IF @failCount > 0
BEGIN
    SELECT TestID, Feature, Scenario, Phase, Status, Detail
    FROM it.TestResults
    WHERE Status = N'FAIL'
    ORDER BY TestID;
END;

SELECT Status, COUNT(*) AS Count
FROM it.TestResults
GROUP BY Status;
GO
