# T-Lift: Simplifying T-SQL Optimization

### ⚠️ Early Development Notice ⚠️ 

**Please Note:** This project is in its early stages of development. While it's functional and can be used, it has not undergone comprehensive testing. We encourage you to try it out but be aware that:
- Some features may be incomplete or subject to change
- Bugs or unexpected behavior may occur
- Full stability is not yet guaranteed
We welcome your feedback and contributions to help improve the project!

### Project Description

T-Lift is a precompiler (written in T-SQL) that allows T-SQL developers to easily leverage dynamic T-SQL to create highly optimized query plans without the hassle of writing complex code. Traditional methods of using dynamic T-SQL often involve tedious coding practices that disrupt the development flow in SSMS. T-Lift simplifies this by automatically generating efficient T-SQL from your existing stored procedures, guided by simple directives embedded in T-SQL comments.

With T-Lift, developers can maintain their familiar workflow in SSMS or their favorite editor while benefiting from powerful, dynamic query optimization. 

Too good to be true? Read on. 😉

### An Introduction

```sql
USE [AdventureWorks2016_EXT]
GO

CREATE OR ALTER PROCEDURE tlift_demo_very_simple 
@id INT = NULL
AS
SELECT *
FROM sales.SalesOrderDetail sod 
WHERE (@id IS NULL or @id = sod.ProductID )
GO
```

This is a classic (straightforward) example of a multipurpose (aka one-size-fits-all) query. 
And it will work, of course. But, unfortunately the SQL Server query optimizer cannot create an optimal plan. 
What's more, the plan that's created and cached is heavily reliant on the 'first' execution, 
precisely the parameter value, adding an element of unpredictability to the process. 

To learn more about this, search for "sqlserver parameter sniffing". 
However, it's important to remember that the core functionality is a valuable feature, not necessarily an issue. This reassurance should instill confidence in the system's capabilities. 

Now, let's delve into a few examples of this issue to pique your interest and deepen your understanding. 

Since, we have no idea what kind of "monitoring" you are familar with, we use this friendly setting here for your session. 

```sql
SET STATISTICS IO ON; 

EXEC tlift_demo_very_simple @id= 897;
```

Now, you should see two rows. But what matters most is on the **messages tab** of your SSMS.

We are interested in this here: Table 'SalesOrderDetail'. Scan count 1, **logical reads 596**...

Maybe you are aware that SQL Server is most the time thinking in 8kb pages and a single logical read means that the SQL Server uses one of these 8kb pages. From your storage, your memory, it dosent matter. 

So, this tiny query from above needs 596 of these 8kb pages. Now, we have a single metric that is independent of your machine's age, size, and color. 

*We can compare.* 

Let's execute our procedure again but without a parameter. It will work because our query checks for NULL. 

```sql
EXEC tlift_demo_very_simple;
```

Wow, we now have 121317 rows. Take a look at the messages tab again: Table 'SalesOrderDetail'. Scan count 1, **logical reads 371722**...

Okay, but this number is so high because there are so many rows in the result set, right? (*Imagine the Princess Padmé Amidala Meme here*)

Let's try it again, but we change the order of executions. 

First marked our procedure for recompilation: 
```sql
EXEC sp_recompile 'tlift_demo_very_simple';
```

Now we start with this one friend here: 
```sql
EXEC tlift_demo_very_simple;
```

Do you remember the logical reads from last time? 371722! Now, take a look at the messages tab.

WTH?! "Table 'SalesOrderDetail'. Scan count 1, **logical reads 596**..."

And yes, it's the exact same result set. Please take your time and compare it row by row. We'll wait here. 

The root cause of this seemingly insane result is not the SQL Server itself, but rather the lack of understanding among many developers about the inner workings of the Query Optimizer and the Execution Engine. 

Since we are now on the same page, let's do it better.

Now, let's address the elephant in the room: Is there a magical 'golden index' that can be defined to optimize this seemingly nonsensical result? The answer is a resounding No. 

T-SQL is much harder to conquer than many developers are aware of. Sad news. 

What is now a possible answer? **Dynamic T-SQL**!

So, how can we do better? The answer lies in Dynamic T-SQL! With dynamic T-SQL, you gain the power to control which parts of your query are visible to the query optimizer, leading to better query optimization. 

Is this only our crazy idea? No, most of the *elders-of-the-sql-server-engine* (TM)... come up with this advice. 

However, utilizing dynamic T-SQL in T-SQL stored procedures can be brutal. And it's quite a hell to test. All the cozy comfort of our beloved SSMS will be gone (is that the reason why we all have at least two instances of the SSMS open in case one of them leaves us?). 

Now, let's turn our attention to T-Lift. What's this new tool all about? 

As we wrote above, T-Lift is a T-SQL precompiler to translate a stored procedure into a dynamic T-SQL procedure. 

The basic idea of T-Lift is to use dynamic T-SQL to render dynamic T-SQL. *Please, don't panic, breathe!*

T-Lift will generate (we call this render) a new version of your existing procedure, but now with dynamic T-SQL parts included.

And how can you control this? With directives hidden in T-SQL comments. This feature empowers you to develop as usual or even take already finished procedures and prepare them for T-Lift, giving you a sense of control and confidence. 

Don't tell, show... okay. 

```sql
CREATE OR ALTER PROCEDURE tlift_demo_very_simple 
@id int = null
AS
						--#[
SELECT *
FROM sales.SalesOrderDetail sod 
WHERE						--#if @id IS NOT NULL 
(							--#-
@id IS NULL or				--#-
@id = sod.ProductID			--#if @id IS NOT NULL
)							--#-
						--#]
```

It's the same query as above, but now we have added some line breaks AND comments. 

Open and close a **dynamic T-SQL section** in our T-SQL code:
```sql
--#[ // Open

--#] // Close
```

That's our query. Why did we add these brackets? Because not all codes of your procedure need to be handled as dynamic T-SQL. You decide. 

We have different types of possible condition directives:
```sql
--#if <condition> // Single line of T-SQL code

--#{if <condition> // Opens a section that is bound to this condition

--#} // Close
```

```sql
--#- // We don't need this line in a dynamic T-SQL scenario anymore. Get rid of it. 
```

Okay, but how does our procedure look after we did this precompiler thing? 

```sql
declare @dynsql nvarchar(max)
exec dbo.sp_tlift 
    @DatabaseName =  'AdventureWorks2016_EXT'
    ,@ProcedureName ='tlift_demo_very_simple'
    ,@result = @dynsql output 

print @dynsql
```

```sql
create   procedure tlift_version_of_your_sproc 
@id int = null
AS
declare @sql nvarchar(max) = N'' 
set @sql = @sql + 'SELECT *'+CHAR(13)+CHAR(10)
set @sql = @sql + 'FROM sales.SalesOrderDetail sod '+CHAR(13)+CHAR(10)
if @id IS NOT NULL
set @sql = @sql + 'WHERE						'+CHAR(13)+CHAR(10)
--(							
--@id IS NULL or				
if @id IS NOT NULL
set @sql = @sql + '@id = sod.ProductID			'+CHAR(13)+CHAR(10)
--)							
exec sp_executesql @sql, N'@id int', @id 
```

Such a beauty, right? :)

Okay, if you or one of your co-workers has never worked with dynamic T-SQL, that is the reason. 

But we need data. Let's rerun our tests. 


```sql
EXEC tlift_version_of_your_sproc @id= 897;
```

And we got our two rows. But what's that? "Table 'SalesOrderDetail'. Scan count 1, **logical reads 10**"

Let's do the second one: 


```sql
EXEC tlift_version_of_your_sproc;
```

And that's awesome, right? Only "Table 'SalesOrderDetail.' Scan count 1, **logical reads 596**"

Okay, but how can we do (a little) more complex stuff?

```sql
create or alter procedure tlift_demo_very_simple3 
@id int = null,
@orderQty int = null
AS
						--#[ simple3
SELECT *
FROM sales.SalesOrderDetail sod 
WHERE						--#if @id IS NOT NULL OR @orderQty IS NOT NULL
(							--#-
@id IS NULL or				--#-
@id = sod.ProductID			--#if @id IS NOT NULL
)							--#-
and							--#if @id IS NOT NULL AND @orderQty IS NOT NULL
(@orderQty IS NULL OR		--#-
sod.OrderQty >= @orderQty	--#if @orderQty IS NOT NULL
)							--#-
						--#]
```

Got the vibes? The only new thing here is after the "--#[" the "simple 3" because we want to show you how to identify such queries in the plan cache. 

Some more or less random tests: 
```sql
exec tlift_version_of_your_sproc3 @id= 897
exec tlift_version_of_your_sproc3 @id = 866
exec tlift_version_of_your_sproc3
exec tlift_version_of_your_sproc3 @orderQty = 4
exec tlift_version_of_your_sproc3 @orderQty = 4, @id = 866
```

```sql
SELECT cplan.usecounts, cplan.objtype, qtext.text, qplan.query_plan
FROM sys.dm_exec_cached_plans AS cplan
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS qtext
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qplan
WHERE qtext.text LIKE '%/*simple3*/%' AND qtext.text NOT LIKE '%SELECT cplan.usecounts%'
ORDER BY cplan.usecounts DESC;
```

Here, you can witness how these executions are fulfilled: 

```sql
(@id int, @orderQty int)/*simple3*/SELECT *  FROM sales.SalesOrderDetail sod   WHERE        @id = sod.ProductID     
(@id int, @orderQty int)/*simple3*/SELECT *  FROM sales.SalesOrderDetail sod   WHERE        @id = sod.ProductID     and         sod.OrderQty >= @orderQty   
(@id int, @orderQty int)/*simple3*/SELECT *  FROM sales.SalesOrderDetail sod   WHERE        sod.OrderQty >= @orderQty   
(@id int, @orderQty int)/*simple3*/SELECT *  FROM sales.SalesOrderDetail sod   
```

Ah, your question is, what does the new procedure look like?

```sql
 create or alter  procedure tlift_version_of_your_sproc3 
@id int = null,
@orderQty int = null
AS
declare @sql nvarchar(max) = N'' 
set @sql = @sql + 'SELECT *'+CHAR(13)+CHAR(10)
set @sql = @sql + 'FROM sales.SalesOrderDetail sod '+CHAR(13)+CHAR(10)
if @id IS NOT NULL OR @orderQty IS NOT NULL
set @sql = @sql + 'WHERE						'+CHAR(13)+CHAR(10)
--(							
--@id IS NULL or				
if @id IS NOT NULL
set @sql = @sql + '@id = sod.ProductID			'+CHAR(13)+CHAR(10)
--)							
if @id IS NOT NULL AND @orderQty IS NOT NULL
set @sql = @sql + 'and							'+CHAR(13)+CHAR(10)
--(@orderQty IS NULL OR		
if @orderQty IS NOT NULL
set @sql = @sql + 'sod.OrderQty >= @orderQty	'+CHAR(13)+CHAR(10)
--)							
set @sql = '/*simple3*/' + @sql
exec sp_executesql @sql, N'@id int, @orderQty int', @id , @orderQty 
```

As we said, dynamic T-SQL is no joke.

So, it's your turn, give it a try. ;)

Please use GitHub's precious feedback system.

### Installation
Here's how to get started: grab the code from the main branch and run it in a separate user database of your choice. It's important to note that this should not be the same user database where you have your procedures you want T-Lift to use on. We've spent a lot of time on the feature to ensure it can gather all necessary metadata from other databases. ;)

### Usage
As we showed in the Introduction but with more parameters:
```sql
declare @dynsql nvarchar(max)
exec dbo.sp_tlift 
    @DatabaseName =  'AdventureWorks2016_EXT'
    ,@SchemaName = 'dbo' -- default schema
    ,@ProcedureName = 'tlift_demo_very_simple'
    ,@ProcedureNameNew = = 'tlift_version_of_your_sproc' -- default name
    ,@result = @dynsql output 

print @dynsql
```

### Roadmap
We have so many ideas... 