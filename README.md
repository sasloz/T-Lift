# T-Lift: Simplifying T-SQL Optimization

### ⚠️ Early Development Notice ⚠️ 

**Please Note:** This project is in its early stages of development. While it's functional and can be used, it has not undergone comprehensive testing. We encourage you to try it out but be aware that:
- Some features may be incomplete or subject to change
- Bugs or unexpected behavior may occur
- Full stability is not yet guaranteed

We welcome your feedback and contributions to help improve the project!

[Project Description - Short Pitch](#project-description)

[An Introduction](#an-introduction)

[Examples & Basic Syntax](#examples--basic-syntax)

[Installation](#installation)

[Basic Usage](#basic-usage)

[Using Variables instead of Parameters](#using-variables-instead-of-parameters)

[Roadmap](#roadmap)


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

With dynamic T-SQL, you gain the power to control which parts of your query are visible to the query optimizer, leading to better query optimization. 

Is this only our crazy idea? No, most of the *elders-of-the-sql-server-engine* (TM)... come up with this advice. 

However, utilizing dynamic T-SQL in T-SQL stored procedures can be brutal. And it's quite a hell to test. All the cozy comfort of our beloved SSMS will be gone (is that the reason why we all have at least two instances of the SSMS open in case one of them leaves us?). 

Now, let's turn our attention to T-Lift. What's this new tool all about? 

As we wrote above, T-Lift is a T-SQL precompiler to translate a stored procedure into a dynamic T-SQL procedure. 

The basic idea of T-Lift is to use dynamic T-SQL to render dynamic T-SQL. *Please, don't panic, breathe!*

T-Lift will generate (we call this render) a new version of your existing procedure, but now with dynamic T-SQL parts included.

And how can you control this? With directives hidden in T-SQL comments. This feature empowers you to develop as usual or even take already finished procedures and prepare them for T-Lift, giving you a sense of control and confidence. 

Don't tell, show... okay. 

### Examples & Basic Syntax

```sql
CREATE OR ALTER PROCEDURE tlift_demo_very_simple 
@id int = null
AS
						--#[
SELECT *
FROM sales.SalesOrderDetail sod 
WHERE							--#if @id IS NOT NULL 
(							--#-
@id IS NULL or						--#-
@id = sod.ProductID					--#if @id IS NOT NULL
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

Okay, if you or one of your co-workers has never worked with dynamic T-SQL, that is why. 

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
WHERE							--#if @id IS NOT NULL OR @orderQty IS NOT NULL
(							--#-
@id IS NULL or						--#-
@id = sod.ProductID					--#if @id IS NOT NULL
)							--#-
and							--#if @id IS NOT NULL AND @orderQty IS NOT NULL
(@orderQty IS NULL OR					--#-
sod.OrderQty >= @orderQty				--#if @orderQty IS NOT NULL
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

### Basic Usage
As we showed in the introduction but with more parameters:
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

You also can ask for help. 
```sql
exec dbo.sp_tlift @help=1
```

### Using Variables instead of Parameters
You may have noticed, but T-Lift has automatically recognised the parameters of the example procedure. Cool, right? SQL Server is still one of the most informative databases when it comes to metadata. 

But what about using variables instead of parameters in a statement in a procedure? 

**First of all, if you are not aware of it, it is not the same thing!**

And yes, at first glance, T-SQL variables and parameters look identical. Both start with that funny @, have to be declared with a type, etc. 

But when it comes to the use of variables by the Query Optimizer, things look really bleak, as it cannot see and evaluate them at all due to the way it works.

However. T-Lift also helps here, because if you work with dynamic T-SQL, the Query Optimizer is also able to evaluate the passed variables when sp_executesql is called. 

But, why we have to talk about variables hier in an extra section? The reason for this is that we unfortunately cannot access the variables used in a procedure as easily as we can access the parameters. And T-Lift does not (yet...) rely on a lexer and parser, so we have to help it a little by indicating the use of variables with two more directives. 

First of all, when declaring a variable, we have to tell the precompiler that we want to use it later in a dynamic statement. To be clear, this is only necessary for variables that we want to use later in dynamic T-SQL; this does not apply to all others. 

```sql
--#var
```

Here are a few examples. As you will have noticed, we currently support a notation with and without initial value assignment. 
```sql
DECLARE @customer_name1 varchar(50); --#var
DECLARE @product_price1 decimal(10,2); --#var
DECLARE @order_date1 datetime2(3); --#var
DECLARE @is_active1 bit; --#var
DECLARE @large_text1 nvarchar(max); --#var
DECLARE @small_number1 tinyint; --#var
DECLARE @unique_id1 uniqueidentifier; --#var
DECLARE @binary_data1 varbinary(100); --#var
DECLARE @float_value1 float(24); --#var
DECLARE @customer_name varchar(50) = 'John Doe'; --#var
DECLARE @product_price decimal(10,2) = 99.99; --#var
DECLARE @order_date datetime2(3) = GETDATE(); --#var
DECLARE @is_active bit = 1; --#var
DECLARE @large_text nvarchar(max) = N'This is a long text...'; --#var
DECLARE @small_number tinyint = 255; --#var
DECLARE @unique_id uniqueidentifier = NEWID(); --#var
DECLARE @binary_data varbinary(100) = 0x1234567890; --#var
DECLARE @float_value float(24) = 3.14159; --#var
DECLARE @xml_data xml = '<root><element>Test</element></root>'; --#var
DECLARE @json_data nvarchar(max) = N'{"key": "value"}'; --#var
DECLARE @date_only date = '2023-09-17'; --#var
DECLARE @time_only time(7) = '12:34:56.1234567'; --#var
DECLARE @money_amount money = $1234.56; --#var
```

However, it is important to note that we currently only support one variable per declaration and line. If your existing code looks different, you will unfortunately have to adjust it accordingly. 
```sql
/* Not supported, yet. */
DECLARE @v1 INT = 1, @v2 INT = 2 --#var

/* Supported. */
DECLARE @v1 INT = 1 --#var
DECLARE @v2 INT = 2 --#var
```

Okay, that's the first half of the work to use variables. Now we need to specify within the dynamic T-SQL section (Do you remember those brackets with *--#[* and *--#]* ?) that you want to use this particular variable. We do that with this directive here: 
```sql
--#usevar @variableName1, @variableName2
```

Here is a small example of more cohesive code. 
```sql
declare @v1 int = 897 --#var
--#[ Query 4
select * --#usevar @v1
from sales.SalesOrderDetail sod 
where sod.ProductID = @v1 
--#]
```
As you can see, the *--#usevar* directive does not have to be used exactly in the line of use. And, at least we've got this far, you can specify multiple variables separated by a comma. 



### Roadmap
We have so many ideas... but first we need to add much more error checks. 
