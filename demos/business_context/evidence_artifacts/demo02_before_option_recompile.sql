(@Region nvarchar(20),@TechnicianID int,@Priority tinyint,@OnlyBreached bit,@NowUtc datetime2(0),@CustomerID int,@ProductCategory nvarchar(30),@PageSize int)SELECT TOP (@PageSize)
        /*Demo02_DispatchQueue_Recompile*/
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
      AND (@Region IS NULL OR t.Region = @Region)
      AND (@TechnicianID IS NULL OR t.TechnicianID = @TechnicianID)
      AND (@Priority IS NULL OR t.Priority = @Priority)
      AND (@OnlyBreached = 0 OR t.SLADeadline < @NowUtc)
      AND (@CustomerID IS NULL OR t.CustomerID = @CustomerID)
      AND (@ProductCategory IS NULL OR t.ProductCategory = @ProductCategory)
    ORDER BY
        CASE WHEN t.SLADeadline < @NowUtc THEN 0 ELSE 1 END,
        t.Priority ASC,
        t.SLADeadline ASC
    OPTION (RECOMPILE)
