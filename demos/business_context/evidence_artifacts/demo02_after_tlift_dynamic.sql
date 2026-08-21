(@Region nvarchar(20), @TechnicianID int, @Priority tinyint, @OnlyBreached bit, @CustomerID int, @ProductCategory nvarchar(30), @PageSize int, @NowUtc DATETIME2(0) OUTPUT)/*Demo02_DispatchQueue*/

SELECT TOP (@PageSize)
t.TicketID,
t.OpenedAt,
t.Region,
t.Priority,
t.Status,
t.TechnicianID,
t.ProductCategory,
t.SLADeadline,
c.CustomerName,
c.CustomerSegment,
MinutesToSLA = DATEDIFF(MINUTE, @NowUtc, t.SLADeadline)
FROM demo.ServiceTickets AS t
INNER JOIN demo.Customers AS c
ON c.CustomerID = t.CustomerID
WHERE t.Status IN (N'Open', N'Assigned', N'Waiting')
AND
(
t.TechnicianID = @TechnicianID
)
AND
(
t.SLADeadline < @NowUtc
)
ORDER BY
CASE WHEN t.SLADeadline < @NowUtc THEN 0 ELSE 1 END,
t.Priority ASC,
t.SLADeadline ASC

