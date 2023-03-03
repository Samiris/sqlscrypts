SET NOCOUNT ON

DROP TABLE IF EXISTS tempdb.dbo.TempResult
CREATE TABLE tempdb.dbo.TempResult (CardID INT, CustomerID BIGINT, CreatedUtc datetime, DecodedGuid varchar(100))
GO

	  DECLARE @StartTime DATETIME
		  , @EndTime DATETIME
		  , @Rowcount INT = 0
		  , @TotalRecords INT
		  , @BatchSize INT
		  , @InitialReferenceID INT
		  , @FinalReferenceID INT
		  , @LimitReferenceID INT = 1
		  , @TimeStamp DATETIME
		  , @StartTimeStamp DATETIME
		  , @EndTimeStamp DATETIME
		  , @IterationsCounter INT = 1
		  , @count INT = 0
		  , @ReferenceDate DATETIME = GETDATE()

	  
		SET @StartTime = GETDATE()
			
		DROP TABLE IF EXISTS tempdb.dbo.QUEUE_ITEMS
		SELECT --TOP 500000
			  IDENTITY(INT, 1, 1) AS ItemID
			  , cast(CardId as int) as CardId
			  , CustomerID as CustomerID
			  , CreatedUtc as CreatedUtc
			  , EncryptedValue [str]
			  , CAST(NULL AS VARCHAR(2000)) AS decodeStr
			  , CAST(NULL AS VARCHAR(200)) AS decodeValue
			  , isProcessed = 0
		INTO tempdb.dbo.QUEUE_ITEMS
		FROM dev.[Card] D
		ORDER BY 1 desc


		SELECT @InitialReferenceID = MIN(ItemID), @LimitReferenceID = MAX(ItemID), @TotalRecords = COUNT(1) -- SELECT MIN(ItemID), MAX(ItemID), COUNT(1)
		FROM tempdb.dbo.QUEUE_ITEMS
		WHERE isProcessed = 0

		    
		SET @Rowcount = 0
		SET @BatchSize = 1e5
		SET @IterationsCounter = 1
		SET @FinalReferenceID = @InitialReferenceID + @BatchSize - 1
		SELECT @InitialReferenceID AS InitialReferenceID, @FinalReferenceID AS FinalReferenceID, @TotalRecords AS TotalRecordToProcess, @BatchSize AS [BatchSize]


	    IF @TotalRecords > 0
		BEGIN

		    SELECT @StartTimeStamp = GETDATE()
	
			    WHILE @InitialReferenceID < @LimitReferenceID
			    BEGIN

				    UPDATE Q SET decodeStr = CONVERT(varchar(MAX), CONVERT(XML, [str]).value('.', 'varbinary(max)'))
				    FROM tempdb.dbo.QUEUE_ITEMS Q
				    WHERE ItemID BETWEEN @InitialReferenceID AND @FinalReferenceID

				    UPDATE Q SET decodeValue = SUBSTRING(decodeStr, CHARINDEX(CHAR(123), decodeStr)+1, (CHARINDEX(CHAR(125), decodeStr)-CHARINDEX(CHAR(123), decodeStr))-1)
				    FROM tempdb.dbo.QUEUE_ITEMS Q
				    WHERE ItemID BETWEEN @InitialReferenceID AND @FinalReferenceID
				    SET @count = @@ROWCOUNT
				    

					INSERT tempdb.dbo.TempResult(CardID, CustomerID, CreatedUtc, DecodedGuid)
					select CardID, CustomerID, CreatedUtc, decodeValue
					FROM tempdb.dbo.QUEUE_ITEMS 
					WHERE ItemID BETWEEN @InitialReferenceID AND @FinalReferenceID
					AND decodeValue IN (SELECT LOWER(id) AS id FROM dev.dbo.Keys)


					DELETE Q
				    --UPDATE Q SET isProcessed = 1
				    FROM tempdb.dbo.QUEUE_ITEMS Q
				    WHERE ItemID BETWEEN @InitialReferenceID AND @FinalReferenceID


				    PRINT CONVERT(VARCHAR(25), GETDATE(), 20) + ': ' + CAST(@IterationsCounter AS VARCHAR) + ' iteration with ' 
				    + CAST(@count AS VARCHAR) + ' rows ID from ' + CAST(@InitialReferenceID AS VARCHAR) + ' to ' + CAST(@FinalReferenceID AS VARCHAR) + CHAR(13) + CHAR(10)

				    SET @InitialReferenceID = @InitialReferenceID + @BatchSize
				    SET @FinalReferenceID = @InitialReferenceID + @BatchSize - 1
				    SET @Rowcount = @Rowcount + @Count
				    SET @IterationsCounter = @IterationsCounter + 1
			  END
		    END

		    --SELECT ItemID AS [ID(CardId)], [str] encryptStr, decodeStr, decodeValue FROM tempdb.dbo.QUEUE_ITEMS
			SELECT * FROM tempdb.dbo.TempResult

SET NOCOUNT OFF
