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
	@help BIT = 0,
	@Result NVARCHAR(MAX) = N'' OUTPUT
WITH RECOMPILE
AS
SET NOCOUNT ON;

-- I'm curious how long it will take!
DECLARE @StartTime DATETIME2;
DECLARE @EndTime DATETIME2;
DECLARE @ExecutionTime INT;

SET @StartTime = SYSUTCDATETIME();

DECLARE @Version CHAR(5) = '00.46'

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
IF NULLIF(@ProcedureName, '') IS NULL
BEGIN
	RAISERROR('@ProcedureName is missing or empty.', 16, 1);
    RETURN;
END
IF NULLIF(@ProcedureNameNew, '') IS NULL
BEGIN
	RAISERROR('@ProcedureNameNew is missing or empty.', 16, 1);
    RETURN;
END

-- TODO: use this guy here... so our users can set their own directive identifier
-- DECLARE @identifier CHAR(1) = '#'




DECLARE @SQL NVARCHAR(MAX);

-- Create a temporary table to store the procedure text
CREATE TABLE #ProcText (
	LineNumber INT IDENTITY(1, 1) PRIMARY KEY CLUSTERED
	,-- Creates a clustered index on LineNumber
	TEXT NVARCHAR(MAX)
	,CleanRow NVARCHAR(MAX)
	,Comment NVARCHAR(MAX)
	);

-- Construct the dynamic SQL
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

-- Execute the dynamic SQL
BEGIN TRY
	EXEC sp_executesql @SQL, 
    N'@SchemaName NVARCHAR(128), @ProcedureName NVARCHAR(128)', 
    @SchemaName, @ProcedureName;
END TRY
BEGIN CATCH
	PRINT 'Error: '+ ERROR_MESSAGE()
	RETURN
END CATCH

PRINT 'Got the procedure text'
PRINT 'Looking for directives'

UPDATE p
SET p.CleanRow = CASE 
		WHEN CHARINDEX('--#', p.TEXT) > 0
			THEN LEFT(p.TEXT, CHARINDEX('--#', p.TEXT) - 1) + CHAR(13) + CHAR(10)
		ELSE p.TEXT
		END
	,p.Comment = CASE 
		WHEN CHARINDEX('--#', p.TEXT) > 0
			THEN LTRIM(SUBSTRING(p.TEXT, CHARINDEX('--#', p.TEXT) + 3, LEN(p.TEXT)))
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

/* Getting the parameters... */
DECLARE @Parameters NVARCHAR(MAX) = '';
DECLARE @Parameters2 NVARCHAR(MAX) = '';

-- Dynamic SQL to fetch parameters of the procedure
SET @SQL = N'
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

BEGIN TRY
-- Insert the results of the parameter query into the temporary table
	INSERT INTO #parameters (
		ParameterName
		,DataType
		,MaxLength
		,Precision
		,Scale
		,IsOutput
		)
	EXEC sp_executesql @SQL
		,N'@SchemaName NVARCHAR(128), @ProcedureName NVARCHAR(128)'
		,@SchemaName
		,@ProcedureName;
END TRY
BEGIN CATCH
	PRINT 'Error: '+ ERROR_MESSAGE()
	RETURN
END CATCH

-- Build the parameters string for the procedure
SELECT @Parameters = STRING_AGG(ParameterName + ' ' + DataType + CASE 
			WHEN DataType IN (
					'char'
					,'varchar'
					,'nchar'
					,'nvarchar'
					)
				THEN '(' + CASE 
						WHEN MaxLength = - 1
							THEN 'MAX'
						ELSE CAST(MaxLength AS VARCHAR(10))
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
	,@Parameters2 = STRING_AGG(ParameterName + ' ', ', ')
FROM #parameters;

PRINT 'Got procedures parameters'

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

-- Setup Buckets feature:
DECLARE @buckets_statements TABLE (statement NVARCHAR(MAX));
DECLARE @buckets TABLE (param_name NVARCHAR(10), valuelist NVARCHAR(MAX));

PRINT 'Start precompiler aka rendering loop'

-- START RENDER PROCESS "Light"... 
DECLARE @s NVARCHAR(max) = N''
DECLARE @lr CHAR(2) = CHAR(13) + CHAR(10)
DECLARE @dynSQLFlag BIT = 0
	,@firstDynSQLArea BIT = 0
	,@renameProc BIT = 0
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

	IF @renameProc = 0
	BEGIN
		DECLARE @tempRow NVARCHAR(max) = @CleanRow

		SET @CleanRow = REPLACE(@CleanRow, @ProcedureName, @ProcedureNameNew)

		IF @CleanRow <> @tempRow
		BEGIN
			SET @renameProc = 1
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

				DECLARE @param_name NVARCHAR(10), @valuelist NVARCHAR(MAX);

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

			IF @has_parameters = 1 OR @has_usedvars = 1
				BEGIN
					SET @s = @s + N'exec sp_executesql @sql, N''' + @full_parameter_string + ''', ' + @full_variable_string + @lr;
				END
			ELSE
				BEGIN
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

		IF @Comment = '-'
			OR @Comment = 'c'
		BEGIN
			SET @s = @s + N'--' + @CleanRow
		END

		IF @Comment = 'var'
		BEGIN
			SET @s = @s + @CleanRow
		END

		IF lower(left(@Comment, 6)) = 'usevar'
		BEGIN
			SET @s = @s + N'set @sql = @sql + ''' + @CleanRow + '''+CHAR(13)+CHAR(10)' + @lr

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

		IF lower(LEFT(@Comment, 3)) = '{if'
		BEGIN
			-- SELECT 'Hey, look. A condition with a block...'
			SET @s = @s + RIGHT(@Comment, LEN(@Comment) - 1) + @lr
			SET @s = @s + N'BEGIN' + @lr
			SET @s = @s + N'set @sql = @sql + ''' + @CleanRow + '''+CHAR(13)+CHAR(10)' + @lr -- this is dynamic... 
		END
		ELSE IF lower(LEFT(@Comment, 2)) = 'if' -- in ELSE because of a "shorter" if... 
		BEGIN
			 -- SELECT 'Hey, look. A condition...'
			 SET @s = @s + + @Comment + @lr
			IF RIGHT(@CleanRow, 2) = CHAR(13) + CHAR(10)
				SET @CleanRow = LEFT(@CleanRow, LEN(@CleanRow) - 2)
			SET @s = @s + N'set @sql = @sql + ''' + @CleanRow + '''+CHAR(13)+CHAR(10)' + @lr -- this is dynamic... 
		END
	END
	ELSE IF @dynSQLFlag = 1
	BEGIN
		IF RIGHT(@CleanRow, 2) = CHAR(13) + CHAR(10)
			SET @CleanRow = LEFT(@CleanRow, LEN(@CleanRow) - 2)
		SET @s = @s + N'set @sql = @sql + ''' + @CleanRow + '''+CHAR(13)+CHAR(10)' + @lr
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

IF @debugLevel > 2
BEGIN
	PRINT @s;
END

SET @Result = @s;

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