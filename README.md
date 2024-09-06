# T-Lift: Simplifying T-SQL Optimization

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
