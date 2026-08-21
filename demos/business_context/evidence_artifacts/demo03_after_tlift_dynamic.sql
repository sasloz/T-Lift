(@Region nvarchar(20), @CustomerSegment nvarchar(20), @RiskClass nvarchar(10), @CurrencyCode char(3), @MinOpenAmount money, @MinDaysPastDue int, @IncludeDisputed bit, @TopN int, @Today DATE  OUTPUT)/*Demo03_ReceivablesRisk*//*04*/

SELECT TOP (@TopN)
c.CustomerID,
c.CustomerName,
c.CustomerSegment,
c.Region,
InvoiceCount = COUNT_BIG(*),
TotalOpenAmount = SUM(i.OpenAmount),
OldestDueDate = MIN(i.DueDate),
MaxDaysPastDue = MAX(DATEDIFF(DAY, i.DueDate, @Today)),
DisputedAmount = SUM(CASE WHEN i.DisputeStatus = N'Disputed' THEN i.OpenAmount ELSE 0 END)
FROM demo.Invoices AS i
INNER JOIN demo.Customers AS c
ON c.CustomerID = i.CustomerID
WHERE i.OpenAmount > 0
AND
(
c.CustomerSegment = @CustomerSegment
)
AND
(
i.DisputeStatus <> N'Disputed'
)
GROUP BY
c.CustomerID,
c.CustomerName,
c.CustomerSegment,
c.Region
HAVING 1 = 1
AND
(
SUM(i.OpenAmount) >= @MinOpenAmount
)
ORDER BY SUM(i.OpenAmount) DESC

