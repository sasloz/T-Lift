USE [AdventureWorks2016_EXT]

DBCC FREEPROCCACHE
GO

CREATE or ALTER Procedure [dbo].[tlift_demo_very_simple]
@id int = NULL
as
select *
from sales.SalesOrderDetail sod 
where (@id is null or sod.ProductID = @id)
order by sod.ProductID
GO

-- Why can this be a tricky one? 
SELECT sod.ProductID, COUNT(*) [Count]
from sales.SalesOrderDetail sod 
GROUP BY sod.ProductID
ORDER BY 2 desc

SET STATISTICS IO ON;
EXEC [tlift_demo_very_simple] @id = 897		-- 2 rows
EXEC [tlift_demo_very_simple]				-- 121.317 rows

-- Lets start over again. 
EXEC sp_recompile 'tlift_demo_very_simple';

EXEC [tlift_demo_very_simple]				-- 121.317 rows
EXEC [tlift_demo_very_simple] @id = 897		-- 2 rows
GO

create OR alter  procedure [dbo].[tlift_demo_very_simple_dynamic_version]
@id int = null
AS
declare @sql nvarchar(max) = N'/*CatchMe*/' 
set @sql = @sql + 'SELECT *'+CHAR(13)+CHAR(10)
set @sql = @sql + 'FROM sales.SalesOrderDetail sod '+CHAR(13)+CHAR(10)
if @id IS NOT NULL
	set @sql = @sql + 'WHERE'+CHAR(13)+CHAR(10)
if @id IS NOT NULL
	set @sql = @sql + '@id = sod.ProductID'+CHAR(13)+CHAR(10)
set @sql = @sql + 'order by sod.ProductID'+CHAR(13)+CHAR(10)
exec sp_executesql @sql, N'@id int', @id 
GO

EXEC [tlift_demo_very_simple_dynamic_version] @id = 897		-- 2 rows
EXEC [tlift_demo_very_simple_dynamic_version]				-- 121.317 rows

-- Lets start over again. 
EXEC sp_recompile 'tlift_demo_very_simple_dynamic_version';

EXEC [tlift_demo_very_simple_dynamic_version]				-- 121.317 rows
EXEC [tlift_demo_very_simple_dynamic_version] @id = 897		-- 2 rows

-- Show me the plan(s)
SELECT cplan.usecounts, cplan.objtype, qtext.text, qplan.query_plan
FROM sys.dm_exec_cached_plans AS cplan
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS qtext
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qplan
WHERE qtext.text LIKE '%/*CatchMe*/%' AND qtext.text NOT LIKE '%SELECT cplan.usecounts%' AND objtype = 'Prepared'
ORDER BY cplan.usecounts DESC;
GO

CREATE OR ALTER PROCEDURE demo_very_simple42_but
@id INT = NULL
AS
IF @id IS NULL
BEGIN
	SELECT *
	FROM sales.SalesOrderDetail sod 
	ORDER BY sod.ProductID
END
ELSE
BEGIN
	SELECT *
	FROM sales.SalesOrderDetail sod 
	WHERE @id = sod.ProductID
	ORDER BY sod.ProductID
END
GO

EXEC [demo_very_simple42_but] @id = 897		-- 2 rows
EXEC [demo_very_simple42_but] @id = 870		-- 4688 rows
EXEC [demo_very_simple42_but]				-- 121.317 rows

-- Lets start over again. 
EXEC sp_recompile 'demo_very_simple42_but';

EXEC [demo_very_simple42_but]				-- 121.317 rows
EXEC [demo_very_simple42_but] @id = 897		-- 2 rows



CREATE or ALTER Procedure [dbo].[tlift_demo_very_simple]
@id int = NULL
as
								--#[ CatchMe2
select *
from sales.SalesOrderDetail sod 
where								--#if @id is not null
@id is null or						--#-
sod.ProductID = @id					--#if @id is not null
order by sod.ProductID
								--#]
GO

EXEC [tlift_demo_very_simple] @id = 897		-- 2 rows
EXEC [tlift_demo_very_simple]				-- 121.317 rows

SET STATISTICS IO OFF; -- Verbose...

declare @dynsql nvarchar(max)

exec [SX Playground V3]..[sp_tlift] @DatabaseName =  'AdventureWorks2016_EXT'
,@ProcedureName ='tlift_demo_very_simple'
,@result = @dynsql output

print @dynsql
GO

-- Grap this name here -> [tlift_demo_very_simple_after]

CREATE  OR ALTER  Procedure [dbo].[tlift_demo_very_simple_after]
@id int = NULL
as
declare @sql nvarchar(max) = N'' 
set @sql = @sql + 'select *'+CHAR(13)+CHAR(10)
set @sql = @sql + 'from sales.SalesOrderDetail sod '+CHAR(13)+CHAR(10)
if @id is not null
set @sql = @sql + 'where								'+CHAR(13)+CHAR(10)
--@id is null or						
if @id is not null
set @sql = @sql + 'sod.ProductID = @id					'+CHAR(13)+CHAR(10)
set @sql = @sql + 'order by sod.ProductID'+CHAR(13)+CHAR(10)
set @sql = '/*CatchMe2*/' + @sql
exec sp_executesql @sql, N'@id int', @id 


SET STATISTICS IO ON; -- Back on...
EXEC [tlift_demo_very_simple_after] @id = 897		-- 2 rows
EXEC [tlift_demo_very_simple_after]				-- 121.317 rows

-- Lets start over again. 
EXEC sp_recompile 'tlift_demo_very_simple_after';

EXEC [tlift_demo_very_simple_after]				-- 121.317 rows
EXEC [tlift_demo_very_simple_after] @id = 897		-- 2 rows


-- Show me the plan(s)
SELECT cplan.usecounts, cplan.objtype, qtext.text, qplan.query_plan
FROM sys.dm_exec_cached_plans AS cplan
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS qtext
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qplan
WHERE qtext.text LIKE '%/*CatchMe2*/%' AND qtext.text NOT LIKE '%SELECT cplan.usecounts%' AND objtype = 'Prepared'
ORDER BY cplan.usecounts DESC;
GO

create or alter procedure [dbo].[tlift_demo_very_simple3] 
@id int = null,
@orderQty int = null
AS
SELECT *
FROM sales.SalesOrderDetail sod 
WHERE (@id IS NULL or @id = sod.ProductID) AND (@orderQty IS NULL OR sod.OrderQty >= @orderQty) -- and so on
GO

exec tlift_demo_very_simple3 @id= 897
exec tlift_demo_very_simple3 @id = 866
exec tlift_demo_very_simple3
exec tlift_demo_very_simple3 @orderQty = 4
exec tlift_demo_very_simple3 @orderQty = 4, @id = 866
-- Lets start over again. 
EXEC sp_recompile 'tlift_demo_very_simple3';

go

create or alter procedure [dbo].[tlift_demo_very_simple3] 
@id int = null,
@orderQty int = null
AS
							--#[ CatchMe3
SELECT *
FROM sales.SalesOrderDetail sod 
WHERE								--#if @id IS NOT NULL OR @orderQty IS NOT NULL
(@id IS NULL or						--#-
@id = sod.ProductID					--#if @id IS NOT NULL
)									--#-
and									--#if @id IS NOT NULL AND @orderQty IS NOT NULL
(@orderQty IS NULL OR				--#-
sod.OrderQty >= @orderQty			--#if @orderQty IS NOT NULL
)									--#-
							--#]
go

SET STATISTICS IO OFF; -- Verbose...

declare @dynsql nvarchar(max)

exec [SX Playground V3]..[sp_tlift] @DatabaseName =  'AdventureWorks2016_EXT'
,@ProcedureName ='tlift_demo_very_simple3'
,@result = @dynsql output

print @dynsql
GO

-- Grap this name here -> [tlift_demo_very_simple3_after]

create   procedure [dbo].[tlift_demo_very_simple3_after] 
@id int = null,
@orderQty int = null
AS
declare @sql nvarchar(max) = N'' 
set @sql = @sql + 'SELECT *'+CHAR(13)+CHAR(10)
set @sql = @sql + 'FROM sales.SalesOrderDetail sod '+CHAR(13)+CHAR(10)
if @id IS NOT NULL OR @orderQty IS NOT NULL
set @sql = @sql + 'WHERE								'+CHAR(13)+CHAR(10)
--(@id IS NULL or						
if @id IS NOT NULL
set @sql = @sql + '@id = sod.ProductID					'+CHAR(13)+CHAR(10)
--)									
if @id IS NOT NULL AND @orderQty IS NOT NULL
set @sql = @sql + 'and									'+CHAR(13)+CHAR(10)
--(@orderQty IS NULL OR				
if @orderQty IS NOT NULL
set @sql = @sql + 'sod.OrderQty >= @orderQty			'+CHAR(13)+CHAR(10)
--)									
set @sql = '/*CatchMe3*/' + @sql
exec sp_executesql @sql, N'@id int, @orderQty int', @id , @orderQty 


exec tlift_demo_very_simple3_after @id= 897
exec tlift_demo_very_simple3_after @id = 866
exec tlift_demo_very_simple3_after
exec tlift_demo_very_simple3_after @orderQty = 4
exec tlift_demo_very_simple3_after @orderQty = 4, @id = 866
-- Lets start over again. 
EXEC sp_recompile 'tlift_demo_very_simple3_after';

-- Show me the plan(s)
SELECT cplan.usecounts, cplan.objtype, qtext.text, qplan.query_plan
FROM sys.dm_exec_cached_plans AS cplan
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS qtext
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qplan
WHERE qtext.text LIKE '%/*CatchMe3*/%' AND qtext.text NOT LIKE '%SELECT cplan.usecounts%' AND objtype = 'Prepared'
ORDER BY cplan.usecounts DESC;
GO