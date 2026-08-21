(@Region nvarchar(20),@CustomerSegment nvarchar(20),@RiskClass nvarchar(10),@CurrencyCode char(3),@IncludeDisputed bit,@MinOpenAmount money,@MinDaysPastDue int,@Today date,@TopN int)SELECT TOP (@TopN)
        /*Demo03_ReceivablesRisk_Recompile*/
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
      AND (@Region IS NULL OR c.Region = @Region)
      AND (@CustomerSegment IS NULL OR c.CustomerSegment = @CustomerSegment)
      AND (@RiskClass IS NULL OR i.RiskClass = @RiskClass)
      AND (@CurrencyCode IS NULL OR i.CurrencyCode = @CurrencyCode)
      AND (@IncludeDisputed = 1 OR i.DisputeStatus <> N'Disputed')
    GROUP BY
        c.CustomerID,
        c.CustomerName,
        c.CustomerSegment,
        c.Region
    HAVING (@MinOpenAmount IS NULL OR SUM(i.OpenAmount) >= @MinOpenAmount)
       AND (@MinDaysPastDue IS NULL OR MAX(DATEDIFF(DAY, i.DueDate, @Today)) >= @MinDaysPastDue)
    ORDER BY SUM(i.OpenAmount) DESC
    OPTION (RECOMPILE)
