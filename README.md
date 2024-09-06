# T-Lift: Simplifying T-SQL Optimization

T-Lift is a precompiler (written in T-SQL) that allows T-SQL developers to easily leverage dynamic SQL to create highly optimized query plans without the hassle of writing complex code. Traditional methods of using dynamic T-SQL often involve tedious coding practices that disrupt the development flow. T-Lift simplifies this by automatically generating efficient T-SQL from your existing stored procedures, guided by simple directives embedded in T-SQL comments.

With T-Lift, developers can maintain their familiar workflow in SSMS or their favorite editor while benefiting from powerful, dynamic query optimization. 

```sql
USE [AdventureWorks2016_EXT]
GO

CREATE OR ALTER PROCEDURE demoOne
INT @id
AS
--#[
SELECT *
FROM sales.SalesOrderDetail sod 
WHERE 1 = 1
--#{if @id is not null
AND sod.ProductID = @id 
-- This is a ... comment that is part of this block
--#}
ORDER BY sod.ProductID
--#]

-- nothing special here
SELECT 4711

--#[
SELECT 42
--#]
GO
```
