IF OBJECT_ID('dbo.sp_tlift') IS NULL
	EXEC ('CREATE PROCEDURE dbo.sp_tlift AS RETURN 0;');
GO

ALTER PROCEDURE dbo.sp_tlift 
	@DatabaseName NVARCHAR(128) = NULL,
	@SchemaName NVARCHAR(128) = 'dbo',
	@ProcedureName NVARCHAR(128) = NULL,
	@ProcedureNameNew NVARCHAR(128) = 'tlift_version_of_your_sproc', -- to make our lives easier.
	@debugLevel INT = 0,
	@includeOurComments BIT = 0,
	@verboseMode BIT = 0,
	@validateOnly BIT = 0,
	@includeDebug BIT = 1,
	@help BIT = 0,
	@execute BIT = 0,
	@checkDrift BIT = 0,
	@suggest BIT = 0,
	@Result NVARCHAR(MAX) = N'' OUTPUT
WITH RECOMPILE
AS
SET XACT_ABORT, NOCOUNT ON;

-- I'm curious how long it will take!
DECLARE @StartTime DATETIME2;
DECLARE @EndTime DATETIME2;
DECLARE @ExecutionTime INT;

SET @StartTime = SYSUTCDATETIME();

DECLARE @Version CHAR(5) = '01.10'

PRINT ''
PRINT 'Welcome to T-Lift Version '+ @Version
PRINT ''
PRINT 'Main Reposiory for T-Lift is https://github.com/sasloz/T-Lift (There you can find also more info about the project.)'
PRINT ''
PRINT 'Maybe you guessed it already, but you can get help with ''exec dbo.sp_tlift @help = 1'''
PRINT ''

-- Help section
IF @help = 1
BEGIN
	PRINT 'Help:'
	PRINT ''
	PRINT 'T-Lift is a T-SQL precompiler that simplifies plan optimization in SQL Server.' 
	PRINT 'It maintains familiar development practices while automatically generating '
	PRINT 'optimized stored procedures using straightforward directives in T-SQL comments.'
	PRINT 'Enhance performance without sacrificing developer comfort.'
	PRINT ''
	PRINT 'Still there? Okay, how to archive this?'
	PRINT ''
	PRINT 'Basic Syntax:'
	PRINT ''
	PRINT 'DECLARE @dynsql NVARCHAR(MAX);'
	PRINT 'EXEC dbo.sp_tlift' 
    PRINT '  @DatabaseName = ''YourDatabase'', '
    PRINT '  @SchemaName = ''dbo'', '
    PRINT '  @ProcedureName = ''YourProcedure'', '
    PRINT '  @ProcedureNameNew = ''NewProcedure'', '
	PRINT '  @validateOnly = 0,  -- Set to 1 to validate without rendering'
	PRINT '  @Result = @dynsql OUTPUT;'
	PRINT ''
	PRINT 'Traditional methods of using dynamic T-SQL often involve tedious coding practices'
	PRINT 'that disrupt the development flow. T-Lift hopes to simplifies this by automatically generating'
	PRINT '(efficient) T-SQL from your existing stored procedures, guided by simple directives' 
	PRINT 'embedded in T-SQL comments.'
	PRINT ''
	PRINT 'In short: You can use SSMS as you are used to and decorate your T-SQL statements with comments.'
	PRINT ''
	PRINT 'Intrigued? Let''s go further.'
	PRINT ''
	PRINT 'So, the basic idea of T-Lift is to use dynamic T-SQL to render dynamic T-SQL. (Don''t panic!)'
	PRINT 'T-Lift will generate (we call this render) a new version of your already existing procedure, but now with dynamic T-SQL parts included.'
	PRINT ''
	PRINT 'Supported directives:'
	PRINT ''
	PRINT '''--#['' <- Opens a dynamic SQL Area'
	PRINT '''--#]'' <- Closes a dynamic SQL Area'
	PRINT ''
	PRINT '''--#IF'' <- Inside a dynamic SQL Area you can use conditions to control if this very T-SQL should be rendered.'
	PRINT '''--#-''  <-  We don''t need this line in a dynamic T-SQL scenario anymore. Get rid of it.' 
	PRINT '''--#else'' <- Inside a block condition (--#{if / --#}), provides an ELSE branch.'
	PRINT '''--#{elseif'' <- Inside a block condition, provides an ELSE IF branch with a new condition.'
	PRINT '''--#recompile'' <- Adds OPTION(RECOMPILE) to the dynamic SQL execution.'
	PRINT '''--#define <name> = <condition>'' <- Define a named condition for reuse in --#if / --#{if / --#{elseif.'
	PRINT '''--#{-'' <- Opens a removal block (all lines inside are treated as --#- and commented out).'
	PRINT '''--#-}'' <- Closes a removal block.'
	PRINT ''
	PRINT 'Wrapper procedure generation (splits plan cache per parameter pattern):'
	PRINT '''--#wrapper'' <- Enables wrapper generation mode.'
	PRINT '''--#branch <suffix> <condition>'' <- Defines a child branch.'
	PRINT '''--#branch-default <suffix>'' <- Default fallback child.'
	PRINT ''
	PRINT 'Safe dynamic sorting:'
	PRINT '''--#sort <@param>: <col1, col2, ...>'' <- Whitelist-based ORDER BY. Only listed columns (plus their "desc" variants) are accepted; anything else raises an error at runtime.'
	PRINT ''
	PRINT 'Lifecycle parameters:'
	PRINT '@execute = 1     <- Deploy the rendered procedure(s) directly into the target database (drop + create).'
	PRINT '@checkDrift = 1  <- Scan the target database for rendered procedures whose source changed since rendering (uses the metadata stamp).'
	PRINT '@suggest = 1     <- Scan a procedure for catch-all patterns (@p IS NULL OR / ISNULL / COALESCE) and suggest T-Lift annotations.'
	PRINT ''
	PRINT 'Here an example: '
	PRINT ''
	PRINT 'CREATE OR ALTER PROCEDURE tlift_demo_very_simple3 '
	PRINT '@id int = null,'
	PRINT '@orderQty int = null'
	PRINT 'AS'
	PRINT '						--#[ simple3'
	PRINT 'SELECT *'
	PRINT 'FROM sales.SalesOrderDetail sod '
	PRINT 'WHERE						--#if @id IS NOT NULL OR @orderQty IS NOT NULL'
	PRINT '(							--#-'
	PRINT '@id IS NULL or				--#-'
	PRINT '@id = sod.ProductID			--#if @id IS NOT NULL'
	PRINT ')							--#-'
	PRINT 'and							--#if @id IS NOT NULL AND @orderQty IS NOT NULL'
	PRINT '(@orderQty IS NULL OR		--#-'
	PRINT 'sod.OrderQty >= @orderQty	--#if @orderQty IS NOT NULL'
	PRINT ')							--#-'
	PRINT '						--#]'
	RETURN
END

PRINT 'Process starts'

IF NULLIF(@DatabaseName, '') IS NULL
BEGIN
	RAISERROR('@DatabaseName is missing or empty.', 16, 1);
    RETURN;
END
IF NULLIF(@SchemaName, '') IS NULL
BEGIN
	RAISERROR('@SchemaName is missing or empty.', 16, 1);
    RETURN;
END
IF @checkDrift = 0 AND NULLIF(@ProcedureName, '') IS NULL
BEGIN
	RAISERROR('@ProcedureName is missing or empty.', 16, 1);
    RETURN;
END
IF @checkDrift = 0 AND NULLIF(@ProcedureNameNew, '') IS NULL
BEGIN
	RAISERROR('@ProcedureNameNew is missing or empty.', 16, 1);
    RETURN;
END

-- TODO: use this guy here... so our users can set their own directive identifier
-- DECLARE @identifier CHAR(1) = '#'




DECLARE @SQL NVARCHAR(MAX);

-- ===================================================================
-- Drift check mode (@checkDrift = 1): compare the source hash stored
-- in each rendered procedure's metadata stamp against the current
-- hash of its source procedure. Standalone mode - returns one result
-- set and exits.
-- ===================================================================
IF @checkDrift = 1
BEGIN
	PRINT 'Drift check mode (@checkDrift = 1): scanning ' + QUOTENAME(@DatabaseName) + ' for T-Lift rendered procedures'

	SET @SQL = N'
;WITH Rendered AS (
	SELECT s.name AS RenderedSchema, o.name AS RenderedProcedure, sm.definition
	FROM ' + QUOTENAME(@DatabaseName) + N'.sys.sql_modules sm
	INNER JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.objects o ON o.object_id = sm.object_id
	INNER JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.schemas s ON s.schema_id = o.schema_id
	WHERE o.type = ''P''
	  AND sm.definition LIKE N''/* T-Lift:render%''
),
Parsed AS (
	SELECT r.RenderedSchema, r.RenderedProcedure,
		x2.v AS SourceSchema, x3.v AS SourceProcedure, x4.v AS StoredHash, x5.v AS RenderedUtc, x1.v AS TLiftVersion
	FROM Rendered r
	CROSS APPLY (SELECT k = CHARINDEX(N''TLiftVersion='', r.definition)) k1
	CROSS APPLY (SELECT v = SUBSTRING(r.definition, k1.k + 13, CHARINDEX(CHAR(13), r.definition + CHAR(13), k1.k) - (k1.k + 13))) x1
	CROSS APPLY (SELECT k = CHARINDEX(N''SourceSchema='', r.definition)) k2
	CROSS APPLY (SELECT v = SUBSTRING(r.definition, k2.k + 13, CHARINDEX(CHAR(13), r.definition + CHAR(13), k2.k) - (k2.k + 13))) x2
	CROSS APPLY (SELECT k = CHARINDEX(N''SourceProc='', r.definition)) k3
	CROSS APPLY (SELECT v = SUBSTRING(r.definition, k3.k + 11, CHARINDEX(CHAR(13), r.definition + CHAR(13), k3.k) - (k3.k + 11))) x3
	CROSS APPLY (SELECT k = CHARINDEX(N''SourceHash='', r.definition)) k4
	CROSS APPLY (SELECT v = SUBSTRING(r.definition, k4.k + 11, CHARINDEX(CHAR(13), r.definition + CHAR(13), k4.k) - (k4.k + 11))) x4
	CROSS APPLY (SELECT k = CHARINDEX(N''RenderedUtc='', r.definition)) k5
	CROSS APPLY (SELECT v = SUBSTRING(r.definition, k5.k + 12, CHARINDEX(CHAR(13), r.definition + CHAR(13), k5.k) - (k5.k + 12))) x5
	WHERE k1.k > 0 AND k2.k > 0 AND k3.k > 0 AND k4.k > 0 AND k5.k > 0
),
CurrentHashes AS (
	SELECT s.name AS SchemaName, o.name AS ProcName,
		CONVERT(NVARCHAR(70), HASHBYTES(''SHA2_256'', sm.definition), 1) AS CurrentHash
	FROM ' + QUOTENAME(@DatabaseName) + N'.sys.sql_modules sm
	INNER JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.objects o ON o.object_id = sm.object_id
	INNER JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.schemas s ON s.schema_id = o.schema_id
	WHERE o.type = ''P''
)
SELECT p.RenderedSchema, p.RenderedProcedure, p.SourceSchema, p.SourceProcedure,
	CASE WHEN ch.ProcName IS NULL THEN N''SOURCE_MISSING''
		 WHEN ch.CurrentHash = p.StoredHash THEN N''OK''
		 ELSE N''DRIFT'' END AS DriftStatus,
	p.StoredHash, ch.CurrentHash, p.RenderedUtc, p.TLiftVersion
FROM Parsed p
LEFT JOIN CurrentHashes ch
	ON ch.SchemaName COLLATE DATABASE_DEFAULT = p.SourceSchema COLLATE DATABASE_DEFAULT
	AND ch.ProcName COLLATE DATABASE_DEFAULT = p.SourceProcedure COLLATE DATABASE_DEFAULT
ORDER BY p.RenderedSchema, p.RenderedProcedure;';

	BEGIN TRY
		EXEC sp_executesql @SQL;
	END TRY
	BEGIN CATCH
		DECLARE @driftErr NVARCHAR(MAX) = ERROR_MESSAGE();
		RAISERROR('Drift check failed: %s', 16, 1, @driftErr);
		RETURN;
	END CATCH

	PRINT 'Drift check complete. Status values: OK (hash matches), DRIFT (source changed since render), SOURCE_MISSING (source procedure not found).'
	RETURN;
END

-- ===================================================================
-- Step 1.1: Verify target procedure exists before processing
-- ===================================================================
DECLARE @procExists INT = 0;

SET @SQL = N'
SELECT @procExists = COUNT(*)
FROM ' + QUOTENAME(@DatabaseName) + N'.sys.objects o
INNER JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.schemas s ON o.schema_id = s.schema_id
WHERE s.name = @SchemaName
  AND o.name = @ProcedureName
  AND o.type = ''P'';
';

BEGIN TRY
	EXEC sp_executesql @SQL,
		N'@SchemaName NVARCHAR(128), @ProcedureName NVARCHAR(128), @procExists INT OUTPUT',
		@SchemaName, @ProcedureName, @procExists OUTPUT;
END TRY
BEGIN CATCH
	DECLARE @existsErr NVARCHAR(MAX) = ERROR_MESSAGE();
	RAISERROR('Failed to check procedure existence in database [%s]: %s', 16, 1, @DatabaseName, @existsErr);
	RETURN;
END CATCH

IF @procExists = 0
BEGIN
	DECLARE @errMsg NVARCHAR(500) = N'Procedure [' + @DatabaseName + N'].[' + @SchemaName + N'].[' + @ProcedureName + N'] was not found.';
	RAISERROR(@errMsg, 16, 1);
	RETURN;
END

PRINT 'Procedure found: [' + @DatabaseName + '].[' + @SchemaName + '].[' + @ProcedureName + ']';

-- ===================================================================
-- Compute the source definition hash for the render metadata stamp
-- (used by @checkDrift to detect stale renders)
-- ===================================================================
DECLARE @sourceHash NVARCHAR(70);

SET @SQL = N'
SELECT @sourceHash = CONVERT(NVARCHAR(70), HASHBYTES(''SHA2_256'', sm.definition), 1)
FROM ' + QUOTENAME(@DatabaseName) + N'.sys.sql_modules sm
INNER JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.objects o ON sm.object_id = o.object_id
INNER JOIN ' + QUOTENAME(@DatabaseName) + N'.sys.schemas s ON o.schema_id = s.schema_id
WHERE s.name = @SchemaName
  AND o.name = @ProcedureName
  AND o.type = ''P'';';

BEGIN TRY
	EXEC sp_executesql @SQL,
		N'@SchemaName NVARCHAR(128), @ProcedureName NVARCHAR(128), @sourceHash NVARCHAR(70) OUTPUT',
		@SchemaName, @ProcedureName, @sourceHash OUTPUT;
END TRY
BEGIN CATCH
	PRINT 'WARNING: Could not compute source hash (' + ERROR_MESSAGE() + '). The render stamp will carry SourceHash=unknown.';
	SET @sourceHash = NULL;
END CATCH

-- ===================================================================
-- Step 1.4: TRY/CATCH wrapper for the entire processing pipeline
-- ===================================================================
BEGIN TRY

-- Create a temporary table to store the procedure text
CREATE TABLE #ProcText (
	LineNumber INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED
	,-- Creates a clustered index on LineNumber
	TEXT NVARCHAR(MAX)
	,CleanRow NVARCHAR(MAX)
	,DirectivePos INT NULL
	,Comment NVARCHAR(MAX)
	);

-- Construct the dynamic SQL
-- Step 1.3: Use STRING_SPLIT with enable_ordinal on SQL 2022+ for guaranteed line order.
-- On older versions, IDENTITY(1,1) provides ordering (works in practice but not guaranteed by docs).
DECLARE @useOrdinal BIT = 0;
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 16 -- SQL Server 2022+
	SET @useOrdinal = 1;

IF @useOrdinal = 1
BEGIN
	SET @SQL = N'
USE ' + QUOTENAME(@DatabaseName) + N';
WITH ProcDefinition AS (
    SELECT definition
    FROM sys.sql_modules sm
    INNER JOIN sys.objects o ON sm.object_id = o.object_id
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE s.name = @SchemaName
      AND o.name = @ProcedureName
      AND o.type = ''P''
)
INSERT INTO #ProcText (Text)
SELECT value+CHAR(13)+CHAR(10)
FROM ProcDefinition
CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(definition, CHAR(13), ''''), CHAR(10), CHAR(13)), CHAR(13), 1) ss
ORDER BY ss.ordinal;
';
END
ELSE
BEGIN
	SET @SQL = N'
USE ' + QUOTENAME(@DatabaseName) + N';
WITH ProcDefinition AS (
    SELECT definition
    FROM sys.sql_modules sm
    INNER JOIN sys.objects o ON sm.object_id = o.object_id
    INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE s.name = @SchemaName
      AND o.name = @ProcedureName
      AND o.type = ''P''
)
INSERT INTO #ProcText (Text)
SELECT value+CHAR(13)+CHAR(10)
FROM ProcDefinition
CROSS APPLY STRING_SPLIT(REPLACE(REPLACE(definition, CHAR(13), ''''), CHAR(10), CHAR(13)), CHAR(13));
';
END

-- Execute the dynamic SQL
EXEC sp_executesql @SQL, 
    N'@SchemaName NVARCHAR(128), @ProcedureName NVARCHAR(128)', 
    @SchemaName, @ProcedureName;

PRINT 'Got the procedure text'
PRINT 'Looking for directives'

DECLARE @directiveScanLineNumber INT;
DECLARE @directiveScanText NVARCHAR(MAX);
DECLARE @directiveScanCurrentPos INT;
DECLARE @directiveScanTextLength INT;
DECLARE @directiveScanInSingleQuote BIT = 0;
DECLARE @directiveScanChar NCHAR(1);
DECLARE @directiveScanNextChar NCHAR(1);
DECLARE @directivePos INT;

SELECT @directiveScanLineNumber = MIN(LineNumber)
FROM #ProcText;

WHILE @directiveScanLineNumber IS NOT NULL
BEGIN
	SELECT @directiveScanText = TEXT
	FROM #ProcText
	WHERE LineNumber = @directiveScanLineNumber;

	SET @directivePos = NULL;
	SET @directiveScanCurrentPos = 1;
	SET @directiveScanTextLength = DATALENGTH(@directiveScanText) / 2;

	-- Only treat --# markers outside quoted string literals as directives.
	-- Keep quote state across lines so multiline string literals are not parsed as directives.
	WHILE @directiveScanCurrentPos <= @directiveScanTextLength
	BEGIN
		SET @directiveScanChar = SUBSTRING(@directiveScanText, @directiveScanCurrentPos, 1);
		SET @directiveScanNextChar = CASE 
				WHEN @directiveScanCurrentPos < @directiveScanTextLength
					THEN SUBSTRING(@directiveScanText, @directiveScanCurrentPos + 1, 1)
				ELSE N''
				END;

		IF @directiveScanInSingleQuote = 1
		BEGIN
			IF @directiveScanChar = ''''
			BEGIN
				IF @directiveScanNextChar = ''''
					SET @directiveScanCurrentPos = @directiveScanCurrentPos + 2;
				ELSE
				BEGIN
					SET @directiveScanInSingleQuote = 0;
					SET @directiveScanCurrentPos = @directiveScanCurrentPos + 1;
				END
			END
			ELSE
				SET @directiveScanCurrentPos = @directiveScanCurrentPos + 1;
		END
		ELSE
		BEGIN
			IF @directiveScanChar = ''''
			BEGIN
				SET @directiveScanInSingleQuote = 1;
				SET @directiveScanCurrentPos = @directiveScanCurrentPos + 1;
			END
			ELSE IF @directiveScanChar = '-' 
				AND @directiveScanNextChar = '-'
				AND SUBSTRING(@directiveScanText, @directiveScanCurrentPos, 3) = '--#'
			BEGIN
				SET @directivePos = @directiveScanCurrentPos;
				BREAK;
			END
			ELSE
				SET @directiveScanCurrentPos = @directiveScanCurrentPos + 1;
		END
	END

	UPDATE #ProcText
	SET DirectivePos = @directivePos
	WHERE LineNumber = @directiveScanLineNumber;

	SELECT @directiveScanLineNumber = MIN(LineNumber)
	FROM #ProcText
	WHERE LineNumber > @directiveScanLineNumber;
END

UPDATE p
SET p.CleanRow = CASE 
		WHEN p.DirectivePos IS NOT NULL
			THEN LEFT(p.TEXT, p.DirectivePos - 1) + CHAR(13) + CHAR(10)
		ELSE p.TEXT
		END
	,p.Comment = CASE 
		WHEN p.DirectivePos IS NOT NULL
			THEN LTRIM(SUBSTRING(p.TEXT, p.DirectivePos + 3, LEN(p.TEXT)))
		ELSE NULL
		END
FROM #ProcText p;

UPDATE p
SET p.Comment = CASE 
		WHEN RIGHT(p.Comment, 2) = CHAR(13) + CHAR(10)
			THEN LEFT(p.Comment, len(p.Comment) - 2)
		ELSE p.Comment
		END
FROM #ProcText p;

-- ===================================================================
-- Step 1.2: Validate matched directive brackets
-- ===================================================================
DECLARE @openBrackets INT = 0, @closeBrackets INT = 0;
DECLARE @openBlocks INT = 0, @closeBlocks INT = 0;
DECLARE @firstUnmatchedLine INT = NULL;
DECLARE @unmatchedType NVARCHAR(20) = NULL;

-- Count --#[ and --#] pairs
SELECT @openBrackets = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND LEFT(TRIM(Comment), 1) = '[';
SELECT @closeBrackets = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = ']';

-- Count --#{if and --#} pairs
SELECT @openBlocks = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND LEFT(LOWER(TRIM(Comment)), 3) = '{if';
SELECT @closeBlocks = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = '}';

IF @openBrackets <> @closeBrackets
BEGIN
	IF @openBrackets > @closeBrackets
	BEGIN
		-- Find latest --#[ without a matching --#] after it
		SELECT TOP 1 @firstUnmatchedLine = LineNumber
		FROM #ProcText WHERE Comment IS NOT NULL AND LEFT(TRIM(Comment), 1) = '['
		ORDER BY LineNumber DESC;
		SET @unmatchedType = '--#[';
	END
	ELSE
	BEGIN
		SELECT TOP 1 @firstUnmatchedLine = LineNumber
		FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = ']'
		ORDER BY LineNumber DESC;
		SET @unmatchedType = '--#]';
	END

	DECLARE @bracketErr NVARCHAR(500) = N'Unmatched ' + @unmatchedType + N' directive. Found ' 
		+ CAST(@openBrackets AS NVARCHAR) + N' opener(s) and ' 
		+ CAST(@closeBrackets AS NVARCHAR) + N' closer(s). Check near line ' 
		+ CAST(@firstUnmatchedLine AS NVARCHAR) + N'.';
	RAISERROR(@bracketErr, 16, 1);
	RETURN;
END

IF @openBlocks <> @closeBlocks
BEGIN
	IF @openBlocks > @closeBlocks
	BEGIN
		SELECT TOP 1 @firstUnmatchedLine = LineNumber
		FROM #ProcText WHERE Comment IS NOT NULL AND LEFT(LOWER(TRIM(Comment)), 3) = '{if'
		ORDER BY LineNumber DESC;
		SET @unmatchedType = '--#{if';
	END
	ELSE
	BEGIN
		SELECT TOP 1 @firstUnmatchedLine = LineNumber
		FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = '}'
		ORDER BY LineNumber DESC;
		SET @unmatchedType = '--#}';
	END

	DECLARE @blockErr NVARCHAR(500) = N'Unmatched ' + @unmatchedType + N' directive. Found ' 
		+ CAST(@openBlocks AS NVARCHAR) + N' opener(s) and ' 
		+ CAST(@closeBlocks AS NVARCHAR) + N' closer(s). Check near line ' 
		+ CAST(@firstUnmatchedLine AS NVARCHAR) + N'.';
	RAISERROR(@blockErr, 16, 1);
	RETURN;
END

-- Count --#{- and --#-} pairs
DECLARE @openRemoval INT = 0, @closeRemoval INT = 0;
SELECT @openRemoval = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = '{-';
SELECT @closeRemoval = COUNT(*) FROM #ProcText WHERE Comment IS NOT NULL AND TRIM(Comment) = '-}';

IF @openRemoval <> @closeRemoval
BEGIN
	DECLARE @removalErr NVARCHAR(500) = N'Unmatched removal block directive. Found ' 
		+ CAST(@openRemoval AS NVARCHAR) + N' --#{- opener(s) and ' 
		+ CAST(@closeRemoval AS NVARCHAR) + N' --#-} closer(s).';
	RAISERROR(@removalErr, 16, 1);
	RETURN;
END

PRINT 'Directive brackets validated'

-- ===================================================================
-- Detect unknown directives
-- ===================================================================
DECLARE @unknownDirectives NVARCHAR(MAX) = NULL;

SELECT @unknownDirectives = STRING_AGG(
	N'Line ' + CAST(LineNumber AS NVARCHAR) + N': --#' + Comment, ', '
)
FROM #ProcText
WHERE Comment IS NOT NULL
	AND LEFT(TRIM(Comment), 1) <> '['         -- --#[ opener
	AND TRIM(Comment) <> ']'                   -- --#] closer
	AND LOWER(LEFT(TRIM(Comment), 3)) <> '{if' -- --#{if block
	AND LOWER(LEFT(TRIM(Comment), 8)) <> '{elseif ' -- --#{elseif block  
	AND LOWER(TRIM(Comment)) <> '{else'        -- --#{else
	AND LOWER(TRIM(Comment)) <> 'else'         -- --#else
	AND TRIM(Comment) <> '}'                   -- --#} block closer
	AND TRIM(Comment) <> '-'                   -- --#- remove line
	AND LOWER(TRIM(Comment)) <> 'c'            -- --#c comment
	AND LOWER(LEFT(TRIM(Comment), 2)) <> 'if'  -- --#if condition
	AND LOWER(TRIM(Comment)) <> 'var'          -- --#var
	AND LOWER(LEFT(TRIM(Comment), 6)) <> 'usevar' -- --#usevar
	AND LOWER(LEFT(TRIM(Comment), 7)) <> 'buckets' -- --#buckets
	AND LOWER(LEFT(TRIM(Comment), 5)) <> 'sort ' -- --#sort
	AND LOWER(TRIM(Comment)) <> 'recompile' -- --#recompile
	AND LOWER(LEFT(TRIM(Comment), 6)) <> 'define'  -- --#define
	AND TRIM(Comment) <> '{-'            -- --#{- removal block open
	AND TRIM(Comment) <> '-}'            -- --#-} removal block close
	AND LOWER(TRIM(Comment)) <> 'wrapper'   -- --#wrapper
	AND LOWER(LEFT(TRIM(Comment), 7)) <> 'branch '  -- --#branch
	AND LOWER(LEFT(TRIM(Comment), 14)) <> 'branch-default'; -- --#branch-default

IF @unknownDirectives IS NOT NULL
BEGIN
	DECLARE @unknownDirectiveErr NVARCHAR(MAX) = N'Unknown T-Lift directive(s) found: ' + @unknownDirectives;
	RAISERROR(@unknownDirectiveErr, 16, 1);
	RETURN;
END

-- ===================================================================
-- Detect conditional directives outside dynamic SQL sections
-- ===================================================================
DECLARE @outsideConditionals NVARCHAR(MAX) = NULL;

;WITH SectionBoundaries AS (
	SELECT LineNumber, Comment,
		SUM(CASE 
			WHEN LEFT(TRIM(Comment), 1) = '[' THEN 1
			WHEN TRIM(Comment) = ']' THEN -1
			ELSE 0
		END) OVER (ORDER BY LineNumber ROWS UNBOUNDED PRECEDING) AS Depth
	FROM #ProcText
	WHERE Comment IS NOT NULL
)
SELECT @outsideConditionals = STRING_AGG(
	N'Line ' + CAST(LineNumber AS NVARCHAR) + N': --#' + Comment, ', '
)
FROM SectionBoundaries
WHERE Depth = 0
	AND (LOWER(LEFT(TRIM(Comment), 2)) = 'if' 
		OR LOWER(LEFT(TRIM(Comment), 3)) = '{if'
		OR LOWER(LEFT(TRIM(Comment), 8)) = '{elseif '
		OR LOWER(TRIM(Comment)) = 'else'
		OR LOWER(TRIM(Comment)) = '{else'
		OR TRIM(Comment) = '}'
		OR LOWER(LEFT(TRIM(Comment), 6)) = 'usevar'
		OR TRIM(Comment) = '-');

IF @outsideConditionals IS NOT NULL
BEGIN
	PRINT 'WARNING: Directive(s) found outside a dynamic SQL section (--#[ / --#]): ' + @outsideConditionals;
END

-- ===================================================================
-- Warn about unqualified table references in dynamic SQL sections
-- (Sommarskog: "always use two-part notation in dynamic SQL")
-- ===================================================================
DECLARE @unqualifiedTables NVARCHAR(MAX) = NULL;

;WITH DynSections AS (
	SELECT LineNumber, TEXT, CleanRow, Comment,
		SUM(CASE 
			WHEN Comment IS NOT NULL AND LEFT(TRIM(Comment), 1) = '[' THEN 1
			WHEN Comment IS NOT NULL AND TRIM(Comment) = ']' THEN -1
			ELSE 0
		END) OVER (ORDER BY LineNumber ROWS UNBOUNDED PRECEDING) AS Depth
	FROM #ProcText
),
TableRefs AS (
	SELECT LineNumber, LTRIM(RTRIM(CleanRow)) AS line
	FROM DynSections
	WHERE Depth > 0  -- inside a dynamic section
		AND UPPER(LTRIM(RTRIM(CleanRow))) LIKE '%FROM %'
		OR (Depth > 0 AND UPPER(LTRIM(RTRIM(CleanRow))) LIKE '%JOIN %')
)
SELECT @unqualifiedTables = STRING_AGG(
	N'Line ' + CAST(LineNumber AS NVARCHAR) + N': ' + LEFT(line, 60), '; '
)
FROM TableRefs
WHERE line NOT LIKE '%[.]%'  -- no dot = likely unqualified
	AND line NOT LIKE '%--%'  -- not a comment-only line
	AND LEN(LTRIM(RTRIM(line))) > 5;

IF @unqualifiedTables IS NOT NULL
BEGIN
	PRINT 'WARNING: Possible unqualified table reference(s) in dynamic SQL (consider schema.table): ' + @unqualifiedTables;
END

/* Getting the parameters... */
DECLARE @Parameters NVARCHAR(MAX) = '';
DECLARE @Parameters2 NVARCHAR(MAX) = '';

-- Dynamic SQL to fetch parameters of the procedure.
-- Note: the INSERT lives inside the dynamic batch (no INSERT ... EXEC),
-- so callers may capture sp_tlift's own result sets via INSERT ... EXEC.
SET @SQL = N'
INSERT INTO #parameters (
    ParameterName
    ,DataType
    ,MaxLength
    ,Precision
    ,Scale
    ,IsOutput
    )
SELECT
    p.name AS ParameterName,
    t.name AS DataType,
    p.max_length AS MaxLength,
    p.precision AS Precision,
    p.scale AS Scale,
    p.is_output AS IsOutput
FROM ' + QUOTENAME(@DatabaseName) + '.sys.parameters p
INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.procedures sp ON p.object_id = sp.object_id
INNER JOIN ' + QUOTENAME(@DatabaseName) + '.sys.types t ON p.user_type_id = t.user_type_id
WHERE sp.schema_id = (
select schema_id
from ' + QUOTENAME(@DatabaseName) + '.sys.schemas
where name = @SchemaName )
    AND sp.name = @ProcedureName
ORDER BY p.parameter_id;
';

-- Create a temporary table to hold the parameters 
CREATE TABLE #parameters (
	ParameterName SYSNAME
	,DataType SYSNAME
	,MaxLength SMALLINT
	,Precision TINYINT
	,Scale TINYINT
	,IsOutput BIT
	);

-- Run the parameter query (the INSERT is part of the dynamic batch)
	EXEC sp_executesql @SQL
		,N'@SchemaName NVARCHAR(128), @ProcedureName NVARCHAR(128)'
		,@SchemaName
		,@ProcedureName;

-- Build the parameters string for the procedure
SELECT @Parameters = STRING_AGG(ParameterName + ' ' + DataType + CASE 
			WHEN DataType IN (
					'char'
					,'varchar'
					)
				THEN '(' + CASE 
						WHEN MaxLength = - 1
							THEN 'MAX'
						ELSE CAST(MaxLength AS VARCHAR(10))
						END + ')'
			WHEN DataType IN (
					'nchar'
					,'nvarchar'
					)
				THEN '(' + CASE 
						WHEN MaxLength = - 1
							THEN 'MAX'
						ELSE CAST(MaxLength / 2 AS VARCHAR(10))
						END + ')'
			WHEN DataType IN (
					'decimal'
					,'numeric'
					)
				THEN '(' + CAST(Precision AS VARCHAR(10)) + ',' + CAST(Scale AS VARCHAR(10)) + ')'
			ELSE ''
			END + CASE 
			WHEN IsOutput = 1
				THEN ' OUTPUT'
			ELSE ''
			END, ', ')
	,@Parameters2 = STRING_AGG(ParameterName + CASE 
			WHEN IsOutput = 1
				THEN ' OUTPUT'
			ELSE ''
			END, ', ')
FROM #parameters;

PRINT 'Got procedures parameters'

-- ===================================================================
-- Suggestion mode (@suggest = 1): scan for catch-all patterns and
-- propose T-Lift annotations. Standalone mode - returns one result
-- set and exits without rendering.
-- ===================================================================
IF @suggest = 1
BEGIN
	PRINT 'Suggestion mode (@suggest = 1): scanning for catch-all patterns'

	CREATE TABLE #suggestFindings (
		LineNumber INT NOT NULL,
		ParameterName NVARCHAR(200) NULL,
		PatternType NVARCHAR(20) NOT NULL,
		LineText NVARCHAR(200) NOT NULL,
		Suggestion NVARCHAR(MAX) NOT NULL
	);

	-- Pattern 1: classic catch-all "( @p IS NULL OR <predicate> )"
	INSERT INTO #suggestFindings (LineNumber, ParameterName, PatternType, LineText, Suggestion)
	SELECT p.LineNumber,
		x.ParamName,
		N'CATCH_ALL',
		LEFT(LTRIM(RTRIM(REPLACE(REPLACE(p.TEXT, CHAR(13), N''), CHAR(10), N''))), 200),
		CASE WHEN pr.ParameterName IS NOT NULL THEN
			N'Split the predicate over separate lines and annotate: the ''('' and ''' + x.ParamName
			+ N' IS NULL OR'' glue lines get --#- ; the real predicate line gets --#if ' + x.ParamName
			+ N' IS NOT NULL ; the closing '')'' gets --#- . Wrap the statement in --#[ / --#] if it is not already inside a dynamic section.'
		ELSE
			N'Looks like a catch-all pattern, but ' + x.ParamName
			+ N' is not a parameter of this procedure. Review manually (local variables need --#var / --#usevar).'
		END
	FROM #ProcText p
	CROSS APPLY (SELECT isNullPos = CHARINDEX(N' IS NULL OR', UPPER(p.TEXT))) f
	CROSS APPLY (SELECT prefixText = LEFT(p.TEXT, CASE WHEN f.isNullPos > 1 THEN f.isNullPos - 1 ELSE 0 END)) pre
	CROSS APPLY (SELECT atPos = CASE WHEN CHARINDEX(N'@', pre.prefixText) > 0
			THEN LEN(pre.prefixText) - CHARINDEX(N'@', REVERSE(pre.prefixText)) + 1
			ELSE 0 END) a
	CROSS APPLY (SELECT ParamName = CASE WHEN a.atPos > 0
			THEN RTRIM(SUBSTRING(pre.prefixText, a.atPos, f.isNullPos - a.atPos))
			ELSE NULL END) x
	LEFT JOIN #parameters pr ON pr.ParameterName = x.ParamName
	WHERE p.DirectivePos IS NULL
	  AND f.isNullPos > 1
	  AND a.atPos > 0
	  AND LEFT(LTRIM(p.TEXT), 2) <> N'--';

	-- Pattern 2: ISNULL(@p, ...) around a parameter
	INSERT INTO #suggestFindings (LineNumber, ParameterName, PatternType, LineText, Suggestion)
	SELECT p.LineNumber,
		x.ParamName,
		N'ISNULL',
		LEFT(LTRIM(RTRIM(REPLACE(REPLACE(p.TEXT, CHAR(13), N''), CHAR(10), N''))), 200),
		N'ISNULL(' + x.ParamName + N', ...) around a parameter usually hides a catch-all predicate. Consider an optional predicate with --#if '
			+ x.ParamName + N' IS NOT NULL instead. Review manually - this pattern also appears in harmless assignments.'
	FROM #ProcText p
	CROSS APPLY (SELECT pos = CHARINDEX(N'ISNULL(@', UPPER(p.TEXT))) f
	CROSS APPLY (SELECT tail = SUBSTRING(p.TEXT, f.pos + 7, 200)) t
	CROSS APPLY (SELECT stopPos = PATINDEX(N'%[^@A-Za-z0-9_#$]%', t.tail + N' ')) sp2
	CROSS APPLY (SELECT ParamName = LEFT(t.tail, sp2.stopPos - 1)) x
	WHERE p.DirectivePos IS NULL
	  AND f.pos > 0
	  AND LEFT(LTRIM(p.TEXT), 2) <> N'--';

	-- Pattern 3: COALESCE(@p, ...) around a parameter
	INSERT INTO #suggestFindings (LineNumber, ParameterName, PatternType, LineText, Suggestion)
	SELECT p.LineNumber,
		x.ParamName,
		N'COALESCE',
		LEFT(LTRIM(RTRIM(REPLACE(REPLACE(p.TEXT, CHAR(13), N''), CHAR(10), N''))), 200),
		N'COALESCE(' + x.ParamName + N', ...) around a parameter usually hides a catch-all predicate. Consider an optional predicate with --#if '
			+ x.ParamName + N' IS NOT NULL instead. Review manually - this pattern also appears in harmless assignments.'
	FROM #ProcText p
	CROSS APPLY (SELECT pos = CHARINDEX(N'COALESCE(@', UPPER(p.TEXT))) f
	CROSS APPLY (SELECT tail = SUBSTRING(p.TEXT, f.pos + 9, 200)) t
	CROSS APPLY (SELECT stopPos = PATINDEX(N'%[^@A-Za-z0-9_#$]%', t.tail + N' ')) sp2
	CROSS APPLY (SELECT ParamName = LEFT(t.tail, sp2.stopPos - 1)) x
	WHERE p.DirectivePos IS NULL
	  AND f.pos > 0
	  AND LEFT(LTRIM(p.TEXT), 2) <> N'--';

	DECLARE @suggestCount INT;
	SELECT @suggestCount = COUNT(*) FROM #suggestFindings;

	IF @suggestCount = 0
		PRINT 'No catch-all patterns detected. Nothing to suggest.';
	ELSE
		PRINT 'Found ' + CAST(@suggestCount AS VARCHAR(10)) + ' candidate line(s). See the result set for per-line suggestions.';

	SELECT LineNumber, ParameterName, PatternType, LineText, Suggestion
	FROM #suggestFindings
	ORDER BY LineNumber, PatternType;

	DROP TABLE #suggestFindings;
	DROP TABLE #ProcText;
	DROP TABLE #parameters;
	RETURN;
END

-- Catalog annotated variables
CREATE TABLE #AnnotatedVariables (
	VariableName NVARCHAR(128)
	,DataType SYSNAME
	,MaxLength SMALLINT
	,Precision TINYINT
	,Scale TINYINT
	,IsOutput BIT DEFAULT 0
	);

-- Create the temporary table #usedvars
CREATE TABLE #usedvars (VariableName NVARCHAR(128));

IF @debugLevel > 2
BEGIN
	SELECT *
	FROM #ProcText
	WHERE comment = 'var'
END

INSERT INTO #AnnotatedVariables (
	VariableName
	,DataType
	,MaxLength
	,Precision
	,Scale
	)
SELECT SUBSTRING(clean_decl, 1, CHARINDEX(' ', clean_decl) - 1) AS VariableName
	,CASE 
		WHEN CHARINDEX('(', clean_decl) > 0
			AND CHARINDEX('(', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
			THEN LTRIM(SUBSTRING(clean_decl, CHARINDEX(' ', clean_decl) + 1, CHARINDEX('(', clean_decl) - CHARINDEX(' ', clean_decl) - 1))
		ELSE LTRIM(SUBSTRING(clean_decl, CHARINDEX(' ', clean_decl) + 1, CASE 
						WHEN CHARINDEX('=', clean_decl) > 0
							THEN CHARINDEX('=', clean_decl) - CHARINDEX(' ', clean_decl) - 1
						ELSE LEN(clean_decl)
						END))
		END AS DataType
	,CASE 
		WHEN CHARINDEX('(', clean_decl) > 0
			AND CHARINDEX('(', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
			THEN CASE 
					WHEN CHARINDEX(',', clean_decl) > 0
						AND CHARINDEX(',', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
						THEN TRY_CAST(SUBSTRING(clean_decl, CHARINDEX('(', clean_decl) + 1, CHARINDEX(',', clean_decl) - CHARINDEX('(', clean_decl) - 1) AS SMALLINT)
					ELSE TRY_CAST(SUBSTRING(clean_decl, CHARINDEX('(', clean_decl) + 1, CHARINDEX(')', clean_decl) - CHARINDEX('(', clean_decl) - 1) AS SMALLINT)
					END
		ELSE NULL
		END AS MaxLength
	,CASE 
		WHEN CHARINDEX(',', clean_decl) > 0
			AND CHARINDEX(',', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
			THEN TRY_CAST(SUBSTRING(clean_decl, CHARINDEX('(', clean_decl) + 1, CHARINDEX(',', clean_decl) - CHARINDEX('(', clean_decl) - 1) AS TINYINT)
		ELSE NULL
		END AS Precision
	,CASE 
		WHEN CHARINDEX(',', clean_decl) > 0
			AND CHARINDEX(',', clean_decl) < COALESCE(NULLIF(CHARINDEX('=', clean_decl), 0), LEN(clean_decl) + 1)
			THEN TRY_CAST(SUBSTRING(clean_decl, CHARINDEX(',', clean_decl) + 1, CHARINDEX(')', clean_decl) - CHARINDEX(',', clean_decl) - 1) AS TINYINT)
		ELSE NULL
		END AS Scale
FROM (
	SELECT LTRIM(RTRIM(SUBSTRING(TEXT, CHARINDEX('@', TEXT), CHARINDEX(';', TEXT + ';') - CHARINDEX('@', TEXT)))) AS clean_decl
	FROM #ProcText
	WHERE Comment = 'var'
	) AS cleaned_declarations


PRINT 'Got marked variables'

IF @debugLevel > 2
BEGIN
	SELECT *
	FROM #AnnotatedVariables
END

IF @debugLevel > 2
BEGIN
	---- Now you can use the updated results in your normal control flow
	SELECT LineNumber
		,TEXT
		,len(TEXT)
		,CleanRow
		,Comment
		,len(trim(comment))
	FROM #ProcText;
END

-- ===================================================================
-- Validate --#usevar references match --#var declarations
-- ===================================================================
DECLARE @missingVars NVARCHAR(MAX) = NULL;

;WITH UsevarRefs AS (
	SELECT LTRIM(value) AS VariableName
	FROM #ProcText
	CROSS APPLY STRING_SPLIT(SUBSTRING(Comment, CHARINDEX('@', Comment), LEN(Comment)), ',')
	WHERE Comment IS NOT NULL AND lower(left(Comment, 6)) = 'usevar'
)
SELECT @missingVars = STRING_AGG(u.VariableName, ', ')
FROM (SELECT DISTINCT VariableName FROM UsevarRefs) u
WHERE NOT EXISTS (
	SELECT 1 FROM #AnnotatedVariables av WHERE av.VariableName = u.VariableName
);

IF @missingVars IS NOT NULL
BEGIN
	DECLARE @usevarErr NVARCHAR(500) = N'--#usevar references undeclared variable(s): ' + @missingVars 
		+ N'. Mark them with --#var first.';
	RAISERROR(@usevarErr, 16, 1);
	RETURN;
END

-- ===================================================================
-- Validation-only mode: stop here if @validateOnly = 1
-- ===================================================================
IF @validateOnly = 1
BEGIN
	PRINT 'Validation passed. No rendering performed (@validateOnly = 1).';
	SET @Result = N'';
	
	-- Clean up temp tables
	DROP TABLE #ProcText;
	DROP TABLE #parameters;
	DROP TABLE #AnnotatedVariables;
	DROP TABLE #usedvars;
	RETURN;
END

-- ===================================================================
-- Phase 3: Wrapper Procedure Generation — detect and parse
-- ===================================================================
DECLARE @wrapperMode BIT = 0;
DECLARE @branches TABLE (
	BranchOrder INT IDENTITY(1,1),
	Suffix NVARCHAR(128),
	Condition NVARCHAR(MAX),
	IsDefault BIT DEFAULT 0
);

IF EXISTS (SELECT 1 FROM #ProcText WHERE Comment IS NOT NULL AND LOWER(TRIM(Comment)) = 'wrapper')
	SET @wrapperMode = 1;

IF @wrapperMode = 1
BEGIN
	PRINT 'Wrapper generation mode enabled';

	-- Parse --#branch <suffix> <condition>
	INSERT INTO @branches (Suffix, Condition, IsDefault)
	SELECT 
		LEFT(rest, CHARINDEX(' ', rest + ' ') - 1),
		NULLIF(LTRIM(SUBSTRING(rest, CHARINDEX(' ', rest + ' '), LEN(rest) + 1)), ''),
		0
	FROM (
		SELECT LTRIM(RIGHT(TRIM(Comment), LEN(TRIM(Comment)) - 6)) AS rest, LineNumber
		FROM #ProcText 
		WHERE Comment IS NOT NULL 
			AND LOWER(LEFT(TRIM(Comment), 7)) = 'branch '
			AND LOWER(LEFT(TRIM(Comment), 14)) <> 'branch-default'
	) x
	ORDER BY LineNumber;

	-- Parse --#branch-default <suffix>
	INSERT INTO @branches (Suffix, Condition, IsDefault)
	SELECT LTRIM(RIGHT(TRIM(Comment), LEN(TRIM(Comment)) - 14)), NULL, 1
	FROM #ProcText
	WHERE Comment IS NOT NULL 
		AND LOWER(LEFT(TRIM(Comment), 14)) = 'branch-default';

	IF NOT EXISTS (SELECT 1 FROM @branches)
	BEGIN
		RAISERROR('--#wrapper specified but no --#branch or --#branch-default directives found.', 16, 1);
		RETURN;
	END

	-- Validate: non-default branches must have a condition
	IF EXISTS (SELECT 1 FROM @branches WHERE IsDefault = 0 AND (Condition IS NULL OR LEN(LTRIM(Condition)) = 0))
	BEGIN
		RAISERROR('--#branch directive must include a condition (--#branch <suffix> <condition>).', 16, 1);
		RETURN;
	END

	IF @debugLevel > 0
		SELECT * FROM @branches;
END

-- Setup Buckets feature:
DECLARE @buckets_statements TABLE (statement NVARCHAR(MAX));
DECLARE @buckets TABLE (param_name SYSNAME, valuelist NVARCHAR(MAX));

-- Setup Sort whitelist feature (--#sort):
DECLARE @sort_statements TABLE (statement NVARCHAR(MAX));

-- Named conditions (--#define)
DECLARE @conditions TABLE (
    ConditionName NVARCHAR(128),
    ConditionText NVARCHAR(MAX),
    UsedFlag BIT DEFAULT 0
);

-- Removal block state (--#{- / --#-})
DECLARE @removalBlockFlag BIT = 0

-- Condition resolution variables (declared before WHILE to avoid re-declaration)
DECLARE @resolvedCondition NVARCHAR(MAX)
DECLARE @condLookup NVARCHAR(MAX)

PRINT 'Start precompiler aka rendering loop'

-- START RENDER PROCESS "Light"... 
DECLARE @s NVARCHAR(max) = N''
DECLARE @lr CHAR(2) = CHAR(13) + CHAR(10)
DECLARE @dynSQLFlag BIT = 0
	,@firstDynSQLArea BIT = 0
	,@renameProc BIT = 0
	,@recompileFlag BIT = 0
DECLARE @LineNumber INT

SELECT @LineNumber = MIN(LineNumber)
FROM #ProcText

WHILE @LineNumber IS NOT NULL
BEGIN
	DECLARE @CleanRow NVARCHAR(MAX)
		,@Comment NVARCHAR(MAX)

	DECLARE @DynQueryName NVARCHAR(128)

	SELECT @CleanRow = TRIM(CleanRow)
		,@Comment = TRIM(Comment)
	FROM #ProcText
	WHERE LineNumber = @LineNumber

	IF @debugLevel > 0
	BEGIN
		SELECT @CleanRow
			,@Comment
			,len(@Comment)
	END

	-- Step 1.5: Only rename on the CREATE/ALTER PROCEDURE line
	IF @renameProc = 0
	BEGIN
		DECLARE @upperRow NVARCHAR(MAX) = UPPER(@CleanRow);

		IF @upperRow LIKE '%CREATE%PROCEDURE%' OR @upperRow LIKE '%ALTER%PROCEDURE%'
		BEGIN
			DECLARE @tempRow NVARCHAR(max) = @CleanRow

			SET @CleanRow = REPLACE(@CleanRow, @ProcedureName, @ProcedureNameNew)

			IF @CleanRow <> @tempRow
			BEGIN
				SET @renameProc = 1
			END
		END
	END

	IF @Comment IS NOT NULL
	BEGIN
		-- select 'a command'
		IF left(@Comment,1 ) = '['
		BEGIN
			SET @dynSQLFlag = 1;

			IF len(@Comment) > 1
				SET @DynQueryName = trim(right(@Comment, len(@Comment)-1))

			IF @debugLevel > 0
			BEGIN
				SELECT 'Start DynSQL Area';
			END

			PRINT 'Start DynSQL Area at line '+CAST(@LineNumber AS CHAR(4)) 

			-- Here we should setup a dynSQL Area... 
			-- If this is our first dynSQL Area... we need some boilerplate? Variables? 
			IF @firstDynSQLArea = 0
			BEGIN
				IF @includeOurComments = 1
					SET @s = @s + '-- SETUP DynSQL Stuff for the first time' + @lr
				SET @s = @s + N'declare @sql nvarchar(max) = N'''' ' + @lr
				IF @includeDebug = 1
					SET @s = @s + N'declare @debug BIT = 0 -- set to 1 to print dynamic SQL' + @lr
				SET @firstDynSQLArea = 1
			END
			ELSE
			BEGIN
				IF @includeOurComments = 1 --TODO: Check this crap out.. 
					SET @s = @s + '-- recycle DynSQL Stuff, set @s = ' + @lr
				SET @s = @s + 'SET @sql = N'''' ' + @lr
			END
		END

		IF @Comment = ']' -- here ends the dyn SQL section... and we have to execute what we have so far. 
		BEGIN
			DECLARE @has_parameters BIT = 0;
			DECLARE @has_usedvars BIT = 0;
			DECLARE @has_buckets BIT = 0;

			-- Check if we have any buckets here
			IF EXISTS (
					SELECT 1
					FROM @buckets_statements
					)
				SET @has_buckets = 1;

			-- Check if we have any existing parameters
			IF LEN(@parameters) > 0
				OR LEN(@parameters2) > 0
				SET @has_parameters = 1;

			-- Check if we have any used variables
			IF EXISTS (
					SELECT 1
					FROM #usedvars
					)
				SET @has_usedvars = 1;

			-- Prepare the parameter string
			DECLARE @full_parameter_string NVARCHAR(MAX) = @parameters;
			DECLARE @full_variable_string NVARCHAR(MAX) = @parameters2;

			IF @debugLevel > 2
			BEGIN
				print '@full_parameter_string '+ @full_parameter_string
				print '@full_variable_string '+ @full_variable_string
			END

			-- If we have used variables, add them to the parameter strings
			IF @has_usedvars = 1
			BEGIN
				DECLARE @parameter_string NVARCHAR(MAX) = N'';
				DECLARE @variable_string NVARCHAR(MAX) = N'';

				IF @debugLevel > 2
				BEGIN
					SELECT 'we have to add variables: '

					SELECT *
					FROM #usedvars
				END

				SELECT @parameter_string = @parameter_string + CASE 
						--WHEN left(av.DataType,4) = 'time' THEN 
						--	',' + av.VariableName + ' ' + av.DataType
						WHEN av.MaxLength IS NOT NULL
							THEN ',' + av.VariableName + ' ' + av.DataType + '(' + CAST(av.MaxLength AS NVARCHAR) + ')'
						WHEN av.Precision IS NOT NULL
							AND av.Scale IS NOT NULL
							THEN ',' + av.VariableName + ' ' + av.DataType + '(' + CAST(av.Precision AS NVARCHAR) + ',' + CAST(av.Scale AS NVARCHAR) + ')'
						WHEN av.Precision IS NOT NULL
							THEN ',' + av.VariableName + ' ' + av.DataType + '(' + CAST(av.Precision AS NVARCHAR) + ')'
						ELSE ',' + av.VariableName + ' ' + av.DataType 
						END + ' OUTPUT'
					,@variable_string = @variable_string + ',' + av.VariableName + ' OUTPUT'
				FROM #usedvars uv
				JOIN #AnnotatedVariables av ON uv.VariableName = av.VariableName;

				-- Remove leading comma
				SET @parameter_string = STUFF(@parameter_string, 1, 1, '');
				SET @variable_string = STUFF(@variable_string, 1, 1, '');

				-- Now @parameter_string and @variable_string can be used in sp_executesql
				IF @debugLevel > 2
				BEGIN
					PRINT 'Parameter String: ' + @parameter_string;
					PRINT 'Variable String: ' + @variable_string;
				END

				IF @has_parameters = 1
				BEGIN
					IF @debugLevel > 2
					BEGIN
						print '@has_parameters = 1'
					END
					SET @full_parameter_string = @full_parameter_string + N', ' + @parameter_string;
					SET @full_variable_string = @full_variable_string + N', ' + @variable_string;
				END
				ELSE
				BEGIN
					IF @debugLevel > 2
					BEGIN
						print '@has_parameters = 1 else...'
					END
					SET @full_parameter_string = @parameter_string;
					SET @full_variable_string = @variable_string;
				END
			END

			-- Emit safe ORDER BY whitelist chains (--#sort) before any
			-- prefixes and before OPTION(RECOMPILE) is appended.
			IF EXISTS (SELECT 1 FROM @sort_statements)
			BEGIN
				DECLARE @invalid_sort_params TABLE (param_name NVARCHAR(128));

				INSERT INTO @invalid_sort_params (param_name)
				SELECT DISTINCT
					SUBSTRING(ss.statement, CHARINDEX('@', ss.statement) + 1, CHARINDEX(':', ss.statement) - CHARINDEX('@', ss.statement) - 1)
				FROM @sort_statements ss
				WHERE NOT EXISTS (
					SELECT 1
					FROM #parameters
					WHERE ParameterName = '@' + SUBSTRING(ss.statement, CHARINDEX('@', ss.statement) + 1, CHARINDEX(':', ss.statement) - CHARINDEX('@', ss.statement) - 1)
				)
				AND NOT EXISTS (
					SELECT 1
					FROM #usedvars
					WHERE VariableName = '@' + SUBSTRING(ss.statement, CHARINDEX('@', ss.statement) + 1, CHARINDEX(':', ss.statement) - CHARINDEX('@', ss.statement) - 1)
				);

				IF EXISTS (SELECT 1 FROM @invalid_sort_params)
				BEGIN
					DECLARE @sort_error NVARCHAR(MAX);

					SELECT @sort_error = 'The following sort parameters are not declared or marked with usevar: ' +
						STRING_AGG(param_name, ', ') WITHIN GROUP (ORDER BY param_name)
					FROM @invalid_sort_params;

					RAISERROR(@sort_error, 16, 1);
					RETURN;
				END

				DECLARE @sortStmt NVARCHAR(MAX), @sortParam NVARCHAR(130), @sortList NVARCHAR(MAX);

				DECLARE sort_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT statement FROM @sort_statements;
				OPEN sort_cursor;
				FETCH NEXT FROM sort_cursor INTO @sortStmt;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					SET @sortParam = '@' + SUBSTRING(@sortStmt, CHARINDEX('@', @sortStmt) + 1, CHARINDEX(':', @sortStmt) - CHARINDEX('@', @sortStmt) - 1);
					SET @sortList = LTRIM(SUBSTRING(@sortStmt, CHARINDEX(':', @sortStmt) + 1, LEN(@sortStmt)));

					DECLARE @sortChain NVARCHAR(MAX) = N'IF ' + @sortParam + N' IS NOT NULL' + @lr + N'BEGIN' + @lr;
					DECLARE @sortFirst BIT = 1;
					DECLARE @sortEntry NVARCHAR(256);
					DECLARE @sortEntryEsc NVARCHAR(512);

					DECLARE sort_entry_cursor CURSOR LOCAL FAST_FORWARD FOR
						SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@sortList, ',') WHERE LEN(LTRIM(RTRIM(value))) > 0;
					OPEN sort_entry_cursor;
					FETCH NEXT FROM sort_entry_cursor INTO @sortEntry;

					WHILE @@FETCH_STATUS = 0
					BEGIN
						SET @sortEntryEsc = REPLACE(@sortEntry, '''', '''''');

						SET @sortChain = @sortChain
							+ CASE WHEN @sortFirst = 1 THEN N'IF ' ELSE N'ELSE IF ' END
							+ N'LOWER(LTRIM(RTRIM(' + @sortParam + N'))) = N''' + LOWER(@sortEntryEsc) + N''''
							+ N' set @sql = @sql + '' ORDER BY ' + @sortEntryEsc + N'''+CHAR(13)+CHAR(10)' + @lr;
						SET @sortFirst = 0;

						IF LOWER(RIGHT(@sortEntry, 5)) <> N' desc'
							SET @sortChain = @sortChain
								+ N'ELSE IF LOWER(LTRIM(RTRIM(' + @sortParam + N'))) = N''' + LOWER(@sortEntryEsc) + N' desc'''
								+ N' set @sql = @sql + '' ORDER BY ' + @sortEntryEsc + N' DESC''+CHAR(13)+CHAR(10)' + @lr;

						FETCH NEXT FROM sort_entry_cursor INTO @sortEntry;
					END

					CLOSE sort_entry_cursor;
					DEALLOCATE sort_entry_cursor;

					IF @sortFirst = 1
					BEGIN
						RAISERROR('--#sort directive has no columns in its whitelist. Expected: --#sort <@param>: <col1, col2, ...>', 16, 1);
						RETURN;
					END

					SET @sortChain = @sortChain
						+ N'ELSE' + @lr + N'BEGIN' + @lr
						+ N'RAISERROR(''T-Lift: value of ' + @sortParam + N' is not in the sort whitelist.'', 16, 1)' + @lr
						+ N'RETURN' + @lr
						+ N'END' + @lr
						+ N'END' + @lr;

					SET @s = @s + @sortChain;

					FETCH NEXT FROM sort_cursor INTO @sortStmt;
				END

				CLOSE sort_cursor;
				DEALLOCATE sort_cursor;

				DELETE FROM @sort_statements;
			END

			IF @has_buckets = 1
			BEGIN
				IF @debugLevel > 2
				BEGIN
					print 'we have buckets'
				END

				-- Validate bucket parameters before processing
				DECLARE @invalid_params TABLE (param_name NVARCHAR(128));
    
				INSERT INTO @invalid_params (param_name)
				SELECT DISTINCT 
					SUBSTRING(statement, CHARINDEX('@', statement) + 1, CHARINDEX(':', statement) - CHARINDEX('@', statement) - 1)
				FROM @buckets_statements bs
				WHERE NOT EXISTS (
					SELECT 1 
					FROM #parameters 
					WHERE ParameterName = '@' + SUBSTRING(bs.statement, CHARINDEX('@', bs.statement) + 1, CHARINDEX(':', bs.statement) - CHARINDEX('@', bs.statement) - 1)
				)
				AND NOT EXISTS (
					SELECT 1 
					FROM #usedvars 
					WHERE VariableName = '@' + SUBSTRING(bs.statement, CHARINDEX('@', bs.statement) + 1, CHARINDEX(':', bs.statement) - CHARINDEX('@', bs.statement) - 1)
				);

				IF EXISTS (SELECT 1 FROM @invalid_params)
				BEGIN
					DECLARE @error_message NVARCHAR(MAX);
        
					SELECT @error_message = 'The following bucket parameters are not declared or marked with usevar: ' + 
						STRING_AGG(param_name, ', ') WITHIN GROUP (ORDER BY param_name)
					FROM @invalid_params;
        
					RAISERROR(@error_message, 16, 1);
					RETURN;
				END

				-- Parse the bucket statements
				INSERT INTO @buckets (param_name, valuelist)
				SELECT 
					SUBSTRING(statement, CHARINDEX('@', statement) + 1, CHARINDEX(':', statement) - CHARINDEX('@', statement) - 1) AS param_name,
					LTRIM(SUBSTRING(statement, CHARINDEX(':', statement) + 1, LEN(statement))) AS valuelist
				FROM @buckets_statements;

				-- Generate the CASE statements
				DECLARE @case_statements NVARCHAR(MAX) = '';
				DECLARE @buckets_counter INT = 1;

				DECLARE @param_name SYSNAME, @valuelist NVARCHAR(MAX);

				DECLARE @bucket_concat NVARCHAR(MAX) = 'DECLARE @bucket NVARCHAR(MAX) = '''';';


				DECLARE buckets_cursor CURSOR FOR SELECT param_name, valuelist FROM @buckets;
				OPEN buckets_cursor;
				FETCH NEXT FROM buckets_cursor INTO @param_name, @valuelist;

				WHILE @@FETCH_STATUS = 0
				BEGIN
					DECLARE @case_structure NVARCHAR(MAX) = 'DECLARE @buckets' + CAST(@buckets_counter AS NVARCHAR(10)) + ' CHAR(2) = CASE '+ @lr;
					DECLARE @value_list TABLE (value NVARCHAR(100), row_num INT);
    
					-- Split the values and remove spaces
					INSERT INTO @value_list (value, row_num)
					SELECT LTRIM(RTRIM(value)), ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
					FROM STRING_SPLIT(@valuelist, ',');

					DECLARE @max_row INT = (SELECT MAX(row_num) FROM @value_list);

					-- Generate WHEN clauses
					SELECT @case_structure = @case_structure + 
						CASE 
							WHEN row_num = 1 THEN '        WHEN @' + @param_name + ' < ' + value + ' THEN ''' + FORMAT(row_num - 1, '00') + ''''+ @lr
							ELSE '        WHEN @' + @param_name + ' >= ' + LAG(value) OVER (ORDER BY row_num) + ' AND @' + @param_name + ' < ' + value + ' THEN ''' + FORMAT(row_num - 1, '00') + ''''+ @lr
						END
					FROM @value_list
					ORDER BY row_num;

					-- Add the ELSE clause
					SET @case_structure = @case_structure + '        ELSE ''' + FORMAT(@max_row, '00') + ''''+ @lr+' END;';

					SET @case_statements = @case_statements + @case_structure + @lr;

					-- Add to the bucket concatenation string
					SET @bucket_concat = @bucket_concat + ' SET @bucket = @bucket + @buckets' + CAST(@buckets_counter AS NVARCHAR(10)) + ';';
    
					SET @buckets_counter = @buckets_counter + 1;
					DELETE FROM @value_list;
					FETCH NEXT FROM buckets_cursor INTO @param_name, @valuelist;
				END

				CLOSE buckets_cursor;
				DEALLOCATE buckets_cursor;

				-- Add the bucket concatenation to the case statements
				SET @case_statements = @case_statements + CHAR(13) + CHAR(10) + @bucket_concat;

				
				IF @debugLevel > 2
				BEGIN
					PRINT @case_statements;
				END

				SET @s = @s + @case_statements + @lr+ @lr;

				SET @s = @s + N'set @sql = ''/*''+@bucket+''*/'' + @sql'  + @lr 

				DELETE FROM @buckets
				DELETE FROM @buckets_statements
			END

			IF len(@DynQueryName) > 0
			BEGIN
				SET @s = @s + N'set @sql = ''/*'+@DynQueryName+'*/'' + @sql'  + @lr 
				SET @DynQueryName = N''
			END

			-- Inject OPTION(RECOMPILE) if --#recompile was used in this section
			IF @recompileFlag = 1
			BEGIN
				SET @s = @s + N'set @sql = @sql + '' OPTION(RECOMPILE)''' + @lr
				SET @recompileFlag = 0
			END

			IF @has_parameters = 1 OR @has_usedvars = 1
				BEGIN
					IF @includeDebug = 1
						SET @s = @s + N'IF @debug = 1 PRINT @sql' + @lr
					SET @s = @s + N'exec sp_executesql @sql, N''' + @full_parameter_string + ''', ' + @full_variable_string + @lr;
				END
			ELSE
				BEGIN
					IF @includeDebug = 1
						SET @s = @s + N'IF @debug = 1 PRINT @sql' + @lr
					SET @s = @s + N'exec sp_executesql @sql' + @lr;
				END
			

			SET @dynSQLFlag = 0;

			TRUNCATE TABLE #usedvars

			IF @debugLevel > 0
			BEGIN
				SELECT 'End DynSQL Area';
			END

			PRINT 'End DynSQL Area at line '+CAST(@LineNumber AS CHAR(4)) 
		END

		IF @Comment = '}'
		BEGIN
			SET @s = @s + N'END' + @lr
		END

		IF LOWER(TRIM(@Comment)) = 'else' OR LOWER(TRIM(@Comment)) = '{else'
		BEGIN
			SET @s = @s + N'END' + @lr
			SET @s = @s + N'ELSE' + @lr
			SET @s = @s + N'BEGIN' + @lr
		END

		IF @Comment = '-'
			OR @Comment = 'c'
		BEGIN
			SET @s = @s + N'--' + @CleanRow
		END

		IF LOWER(TRIM(@Comment)) = 'recompile'
		BEGIN
			SET @recompileFlag = 1
		END

		IF @Comment = 'var'
		BEGIN
			SET @s = @s + @CleanRow
		END

		IF lower(left(@Comment, 6)) = 'usevar'
		BEGIN
			SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr

			IF @debugLevel > 2
			BEGIN
				SELECT @comment
			END

			-- Insert the extracted variable names into #usedvars
			INSERT INTO #usedvars (VariableName)
			SELECT LTRIM(value) AS VariableName
			FROM STRING_SPLIT(SUBSTRING(@Comment, CHARINDEX('@', @Comment), LEN(@Comment)), ',')
		END

		IF lower(left(@Comment, 7)) = 'buckets'
		BEGIN
			INSERT INTO @buckets_statements (statement) VALUES (@Comment);
			IF @debugLevel > 2
			BEGIN
				PRINT @comment
			END
		END

		IF lower(left(@Comment, 5)) = 'sort '
		BEGIN
			INSERT INTO @sort_statements (statement) VALUES (@Comment);
			IF @debugLevel > 2
			BEGIN
				PRINT @comment
			END
		END

		IF lower(left(@Comment, 6)) = 'define'
		BEGIN
			-- Parse: define <name> = <condition>
			DECLARE @defineBody NVARCHAR(MAX) = LTRIM(RIGHT(@Comment, LEN(@Comment) - 6));
			DECLARE @eqPos INT = CHARINDEX('=', @defineBody);

			IF @eqPos > 0
			BEGIN
				DECLARE @condName NVARCHAR(128) = RTRIM(LTRIM(LEFT(@defineBody, @eqPos - 1)));
				DECLARE @condText NVARCHAR(MAX) = LTRIM(RIGHT(@defineBody, LEN(@defineBody) - @eqPos));

				IF LEN(@condName) > 0 AND LEN(@condText) > 0
				BEGIN
					IF LEFT(@condName, 1) = '@'
						PRINT 'WARNING: --#define name should not start with @ (found: ' + @condName + '). Use a plain name to avoid confusion with parameters.';

					IF EXISTS (SELECT 1 FROM @conditions WHERE ConditionName = LOWER(@condName))
					BEGIN
						PRINT 'WARNING: --#define name ''' + @condName + ''' is already defined. Overwriting previous definition.';
						DELETE FROM @conditions WHERE ConditionName = LOWER(@condName);
					END

					INSERT INTO @conditions (ConditionName, ConditionText)
					VALUES (LOWER(@condName), @condText);

					IF @debugLevel > 0
						PRINT '--#define: ' + @condName + ' = ' + @condText;
				END
				ELSE
					PRINT 'WARNING: --#define has empty name or condition at line ' + CAST(@LineNumber AS VARCHAR) + '.';
			END
			ELSE
				PRINT 'WARNING: --#define missing ''='' separator at line ' + CAST(@LineNumber AS VARCHAR) + '. Expected: --#define <name> = <condition>';
		END

		IF @Comment = '{-'
		BEGIN
			SET @removalBlockFlag = 1
		END

		IF @Comment = '-}'
		BEGIN
			SET @removalBlockFlag = 0
		END

		IF lower(LEFT(@Comment, 8)) = '{elseif '
		BEGIN
			-- Resolve named condition
			SET @resolvedCondition = LTRIM(RIGHT(@Comment, LEN(@Comment) - 7));
			SET @condLookup = NULL;
			SELECT @condLookup = ConditionText FROM @conditions WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
			IF @condLookup IS NOT NULL
			BEGIN
				UPDATE @conditions SET UsedFlag = 1 WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
				SET @resolvedCondition = @condLookup;
			END

			-- Block else-if: close current block, emit ELSE IF condition, open new block
			SET @s = @s + N'END' + @lr
			SET @s = @s + N'ELSE IF ' + @resolvedCondition + @lr
			SET @s = @s + N'BEGIN' + @lr
			IF @dynSQLFlag = 1 AND LEN(LTRIM(RTRIM(REPLACE(REPLACE(@CleanRow, CHAR(13), ''), CHAR(10), '')))) > 0
				SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr
		END
		ELSE IF lower(LEFT(@Comment, 3)) = '{if'
		BEGIN
			-- Resolve named condition
			SET @resolvedCondition = LTRIM(RIGHT(@Comment, LEN(@Comment) - 3));
			SET @condLookup = NULL;
			SELECT @condLookup = ConditionText FROM @conditions WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
			IF @condLookup IS NOT NULL
			BEGIN
				UPDATE @conditions SET UsedFlag = 1 WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
				SET @resolvedCondition = @condLookup;
			END

			SET @s = @s + N'IF ' + @resolvedCondition + @lr
			SET @s = @s + N'BEGIN' + @lr
			IF @dynSQLFlag = 1 AND LEN(LTRIM(RTRIM(REPLACE(REPLACE(@CleanRow, CHAR(13), ''), CHAR(10), '')))) > 0
				SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr
		END
		ELSE IF lower(LEFT(@Comment, 2)) = 'if' -- in ELSE because of a "shorter" if... 
		BEGIN
			-- Resolve named condition
			SET @resolvedCondition = LTRIM(RIGHT(@Comment, LEN(@Comment) - 2));
			SET @condLookup = NULL;
			SELECT @condLookup = ConditionText FROM @conditions WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
			IF @condLookup IS NOT NULL
			BEGIN
				UPDATE @conditions SET UsedFlag = 1 WHERE ConditionName = LOWER(LTRIM(RTRIM(@resolvedCondition)));
				SET @resolvedCondition = @condLookup;
			END

			SET @s = @s + N'IF ' + @resolvedCondition + @lr
			IF RIGHT(@CleanRow, 2) = CHAR(13) + CHAR(10)
				SET @CleanRow = LEFT(@CleanRow, LEN(@CleanRow) - 2)
			SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr
		END
	END
	ELSE IF @dynSQLFlag = 1
	BEGIN
		IF @removalBlockFlag = 1
		BEGIN
			-- Inside --#{- block: treat as --#- (comment out)
			SET @s = @s + N'--' + @CleanRow
		END
		ELSE
		BEGIN
			IF RIGHT(@CleanRow, 2) = CHAR(13) + CHAR(10)
				SET @CleanRow = LEFT(@CleanRow, LEN(@CleanRow) - 2)
			SET @s = @s + N'set @sql = @sql + ''' + REPLACE(@CleanRow, '''', '''''') + '''+CHAR(13)+CHAR(10)' + @lr
		END
	END
	ELSE
	BEGIN
		-- Nothing special here... 
		SET @s = @s + @CleanRow -- dont need this here... -> +@lr
	END

	SELECT @LineNumber = MIN(LineNumber)
	FROM #ProcText
	WHERE LineNumber > @LineNumber
END

PRINT ''
PRINT 'Precompiler aka render loop is done.'

-- Warn about unused --#define definitions
DECLARE @unusedDefs NVARCHAR(MAX) = NULL;
SELECT @unusedDefs = STRING_AGG(ConditionName, ', ')
FROM @conditions
WHERE UsedFlag = 0;

IF @unusedDefs IS NOT NULL
	PRINT 'WARNING: --#define condition(s) defined but never referenced: ' + @unusedDefs;

IF @debugLevel > 2
BEGIN
	PRINT @s;
END

-- ===================================================================
-- Phase 3: Wrapper — generate wrapper + child procedures
-- ===================================================================
IF @wrapperMode = 1
BEGIN
	-- Build the EXEC parameter list: @p1 = @p1, @p2 = @p2, ...
	DECLARE @execParamList NVARCHAR(MAX) = N'';
	SELECT @execParamList = STRING_AGG(
		ParameterName + N' = ' + ParameterName +
		CASE WHEN IsOutput = 1 THEN N' OUTPUT' ELSE N'' END,
		N', ')
	FROM #parameters;

	-- Extract procedure header from @s (up to and including AS line)
	DECLARE @asSearchStr NVARCHAR(10) = CHAR(10) + N'AS' + CHAR(13) + CHAR(10);
	DECLARE @headerEndPos INT = CHARINDEX(@asSearchStr, @s);
	DECLARE @procHeader NVARCHAR(MAX);

	IF @headerEndPos > 0
		SET @procHeader = LEFT(@s, @headerEndPos + LEN(@asSearchStr) - 1);
	ELSE
	BEGIN
		-- Fallback: try \nAS\r without trailing \n
		SET @headerEndPos = CHARINDEX(CHAR(10) + N'AS' + CHAR(13), @s);
		IF @headerEndPos > 0
			SET @procHeader = LEFT(@s, @headerEndPos + 3) + CHAR(10);
		ELSE
		BEGIN
			RAISERROR('Wrapper mode: could not locate AS keyword in rendered output.', 16, 1);
			RETURN;
		END
	END

	-- Build wrapper body: header + IF/ELSE dispatch
	DECLARE @wrapperBody NVARCHAR(MAX) = @procHeader;
	DECLARE @brSuffix NVARCHAR(128), @brCondition NVARCHAR(MAX), @brIsDefault BIT;
	DECLARE @brFirst BIT = 1;

	DECLARE br_cursor CURSOR LOCAL FAST_FORWARD FOR 
		SELECT Suffix, Condition, IsDefault 
		FROM @branches 
		ORDER BY IsDefault, BranchOrder;
	OPEN br_cursor;
	FETCH NEXT FROM br_cursor INTO @brSuffix, @brCondition, @brIsDefault;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF @brIsDefault = 1
		BEGIN
			IF @brFirst = 1
				SET @wrapperBody = @wrapperBody; -- single default, no IF needed
			ELSE
				SET @wrapperBody = @wrapperBody + N'ELSE' + @lr;
		END
		ELSE IF @brFirst = 1
		BEGIN
			SET @wrapperBody = @wrapperBody + N'IF ' + @brCondition + @lr;
			SET @brFirst = 0;
		END
		ELSE
			SET @wrapperBody = @wrapperBody + N'ELSE IF ' + @brCondition + @lr;

		SET @wrapperBody = @wrapperBody + N'    EXEC ' + QUOTENAME(@SchemaName) + N'.'
			+ QUOTENAME(@ProcedureNameNew + @brSuffix);

		IF LEN(@execParamList) > 0
			SET @wrapperBody = @wrapperBody + N' ' + @execParamList;

		SET @wrapperBody = @wrapperBody + N';' + @lr;

		FETCH NEXT FROM br_cursor INTO @brSuffix, @brCondition, @brIsDefault;
	END

	CLOSE br_cursor;
	DEALLOCATE br_cursor;

	-- Build child procedures (each is @s with procedure name suffixed)
	DECLARE @allChildren NVARCHAR(MAX) = N'';
	DECLARE @childProc NVARCHAR(MAX);

	DECLARE child_cursor CURSOR LOCAL FAST_FORWARD FOR 
		SELECT Suffix FROM @branches ORDER BY BranchOrder;
	OPEN child_cursor;
	FETCH NEXT FROM child_cursor INTO @brSuffix;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @childProc = STUFF(@s,
			CHARINDEX(@ProcedureNameNew, @s),
			LEN(@ProcedureNameNew),
			@ProcedureNameNew + @brSuffix);

		SET @allChildren = @allChildren + @lr + N'GO' + @lr + @childProc;

		FETCH NEXT FROM child_cursor INTO @brSuffix;
	END

	CLOSE child_cursor;
	DEALLOCATE child_cursor;

	-- Final output: wrapper + GO + children
	SET @s = @wrapperBody + @allChildren;

	DECLARE @branchCount INT;
	SELECT @branchCount = COUNT(*) FROM @branches;
	PRINT 'Wrapper generation complete: 1 wrapper + '
		+ CAST(@branchCount AS VARCHAR) + ' child procedure(s)';
END

-- ===================================================================
-- Render metadata stamp: traceability + drift detection (@checkDrift)
-- ===================================================================
DECLARE @renderStamp NVARCHAR(MAX) =
	  N'/* T-Lift:render' + @lr
	+ N'TLiftVersion=' + @Version + @lr
	+ N'SourceSchema=' + @SchemaName + @lr
	+ N'SourceProc=' + @ProcedureName + @lr
	+ N'SourceHash=' + ISNULL(@sourceHash, N'unknown') + @lr
	+ N'RenderedUtc=' + CONVERT(NVARCHAR(33), SYSUTCDATETIME(), 126) + @lr
	+ N'*/' + @lr;

SET @s = @renderStamp + @s;

SET @Result = @s;

-- ===================================================================
-- @execute = 1: deploy the rendered output into the target database
-- ===================================================================
IF @execute = 1
BEGIN
	PRINT 'Deploy mode (@execute = 1): deploying rendered procedure(s) to ' + QUOTENAME(@DatabaseName)

	DECLARE @deployExecProc NVARCHAR(300) = QUOTENAME(@DatabaseName) + N'.sys.sp_executesql';
	DECLARE @deployTargets TABLE (ProcName SYSNAME);

	INSERT INTO @deployTargets (ProcName) VALUES (@ProcedureNameNew);
	IF @wrapperMode = 1
		INSERT INTO @deployTargets (ProcName)
		SELECT @ProcedureNameNew + Suffix FROM @branches;

	-- Drop existing targets so CREATE PROCEDURE succeeds on re-render
	DECLARE @deployDropSql NVARCHAR(MAX);
	SELECT @deployDropSql = STRING_AGG(
		CONVERT(NVARCHAR(MAX), N'IF OBJECT_ID(N''' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(ProcName) + N''', N''P'') IS NOT NULL DROP PROCEDURE ' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(ProcName) + N';'),
		CHAR(13) + CHAR(10))
	FROM @deployTargets;

	EXEC @deployExecProc @deployDropSql;

	-- Split the rendered output on standalone GO lines (quote and
	-- block-comment aware) and execute each batch in the target database.
	DECLARE @deployBatch NVARCHAR(MAX) = N'';
	DECLARE @deployLine NVARCHAR(MAX);
	DECLARE @deployTrimmed NVARCHAR(MAX);
	DECLARE @deployPos INT = 1;
	DECLARE @deployLineEnd INT;
	DECLARE @deployInQuote BIT = 0;
	DECLARE @deployInBlockComment BIT = 0;
	DECLARE @deployScanPos INT;
	DECLARE @deployScanLen INT;
	DECLARE @deployCh NCHAR(1);
	DECLARE @deployNextCh NCHAR(1);
	DECLARE @deployTotalLen INT = LEN(@s);

	WHILE @deployPos <= @deployTotalLen + 1
	BEGIN
		SET @deployLineEnd = CHARINDEX(CHAR(10), @s, @deployPos);
		IF @deployLineEnd = 0
		BEGIN
			SET @deployLine = SUBSTRING(@s, @deployPos, @deployTotalLen - @deployPos + 1);
			SET @deployPos = @deployTotalLen + 2;
		END
		ELSE
		BEGIN
			SET @deployLine = SUBSTRING(@s, @deployPos, @deployLineEnd - @deployPos + 1);
			SET @deployPos = @deployLineEnd + 1;
		END

		SET @deployTrimmed = LTRIM(RTRIM(REPLACE(REPLACE(@deployLine, CHAR(13), N''), CHAR(10), N'')));

		IF @deployInQuote = 0 AND @deployInBlockComment = 0 AND UPPER(@deployTrimmed) = N'GO'
		BEGIN
			IF LEN(LTRIM(RTRIM(@deployBatch))) > 0
			BEGIN
				EXEC @deployExecProc @deployBatch;
				SET @deployBatch = N'';
			END
		END
		ELSE
		BEGIN
			SET @deployBatch = @deployBatch + @deployLine;
			SET @deployScanPos = 1;
			SET @deployScanLen = LEN(@deployLine);

			WHILE @deployScanPos <= @deployScanLen
			BEGIN
				SET @deployCh = SUBSTRING(@deployLine, @deployScanPos, 1);
				SET @deployNextCh = SUBSTRING(@deployLine, @deployScanPos + 1, 1);

				IF @deployInQuote = 1
				BEGIN
					IF @deployCh = N''''
					BEGIN
						IF @deployNextCh = N''''
							SET @deployScanPos = @deployScanPos + 2;
						ELSE
						BEGIN
							SET @deployInQuote = 0;
							SET @deployScanPos = @deployScanPos + 1;
						END
					END
					ELSE
						SET @deployScanPos = @deployScanPos + 1;
				END
				ELSE IF @deployInBlockComment = 1
				BEGIN
					IF @deployCh = N'*' AND @deployNextCh = N'/'
					BEGIN
						SET @deployInBlockComment = 0;
						SET @deployScanPos = @deployScanPos + 2;
					END
					ELSE
						SET @deployScanPos = @deployScanPos + 1;
				END
				ELSE IF @deployCh = N'-' AND @deployNextCh = N'-'
					BREAK;
				ELSE IF @deployCh = N'/' AND @deployNextCh = N'*'
				BEGIN
					SET @deployInBlockComment = 1;
					SET @deployScanPos = @deployScanPos + 2;
				END
				ELSE IF @deployCh = N''''
				BEGIN
					SET @deployInQuote = 1;
					SET @deployScanPos = @deployScanPos + 1;
				END
				ELSE
					SET @deployScanPos = @deployScanPos + 1;
			END
		END
	END

	IF LEN(LTRIM(RTRIM(@deployBatch))) > 0
		EXEC @deployExecProc @deployBatch;

	-- Verify every expected procedure exists after deployment
	DECLARE @deployMissing NVARCHAR(MAX) = NULL;
	DECLARE @deployName SYSNAME;

	DECLARE deploy_verify_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT ProcName FROM @deployTargets;
	OPEN deploy_verify_cursor;
	FETCH NEXT FROM deploy_verify_cursor INTO @deployName;

	WHILE @@FETCH_STATUS = 0
	BEGIN
		IF OBJECT_ID(QUOTENAME(@DatabaseName) + N'.' + QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@deployName), N'P') IS NULL
			SET @deployMissing = ISNULL(@deployMissing + N', ', N'') + @deployName;
		FETCH NEXT FROM deploy_verify_cursor INTO @deployName;
	END

	CLOSE deploy_verify_cursor;
	DEALLOCATE deploy_verify_cursor;

	IF @deployMissing IS NOT NULL
	BEGIN
		DECLARE @deployErr NVARCHAR(MAX) = N'@execute = 1: deployment finished but these procedures were not found afterwards: ' + @deployMissing;
		RAISERROR(@deployErr, 16, 1);
		RETURN;
	END

	DECLARE @deployCount INT;
	SELECT @deployCount = COUNT(*) FROM @deployTargets;
	PRINT '@execute: deployed ' + CAST(@deployCount AS VARCHAR(10)) + ' procedure(s) to ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@SchemaName)
END

END TRY
BEGIN CATCH
	IF @@trancount > 0
		ROLLBACK TRANSACTION;

	-- Clean up temp tables on error
	IF OBJECT_ID('tempdb..#ProcText') IS NOT NULL
		DROP TABLE #ProcText;
	IF OBJECT_ID('tempdb..#parameters') IS NOT NULL
		DROP TABLE #parameters;
	IF OBJECT_ID('tempdb..#AnnotatedVariables') IS NOT NULL
		DROP TABLE #AnnotatedVariables;
	IF OBJECT_ID('tempdb..#usedvars') IS NOT NULL
		DROP TABLE #usedvars;

	;THROW;
END CATCH

-- Clean up
IF OBJECT_ID('tempdb..#ProcText') IS NOT NULL
	DROP TABLE #ProcText;

IF OBJECT_ID('tempdb..#parameters') IS NOT NULL
	DROP TABLE #parameters;

IF OBJECT_ID('tempdb..#AnnotatedVariables') IS NOT NULL
	DROP TABLE #AnnotatedVariables;

IF OBJECT_ID('tempdb..#usedvars') IS NOT NULL
	DROP TABLE #usedvars;

SET @EndTime = SYSUTCDATETIME();

SET @ExecutionTime = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

PRINT 'Execution time: ' + CAST(@ExecutionTime AS VARCHAR(20)) + ' milliseconds';
PRINT ''
PRINT 'Done.'
PRINT ''
