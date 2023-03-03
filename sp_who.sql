DECLARE @x NVARCHAR(128) = NULL

SET NOCOUNT ON;
IF @x IS NULL
BEGIN
SELECT r.session_id, se.host_name, se.login_name, Db_name(r.database_id) AS dbname, r.status, r.command,
  CAST(((DATEDIFF(s,start_time,GetDate()))/3600) as varchar) + ' hour(s), '
+ CAST((DATEDIFF(s,start_time,GetDate())%3600)/60 as varchar) + 'min, '
+ CAST((DATEDIFF(s,start_time,GetDate())%60) as varchar) + ' sec' as running_time,
  r.blocking_session_id AS BlkBy, r.open_transaction_count AS NoOfOpenTran, r.wait_type,
  CAST(ROUND((r.granted_query_memory / 128.0)  / 1024,2) AS NUMERIC(10,2))AS granted_memory_GB,
  object_name = OBJECT_SCHEMA_NAME(s.objectid,s.dbid) + '.' + OBJECT_NAME(s.objectid, s.dbid),
    program_name = se.program_name, p.query_plan AS query_plan,
  sql_text = SUBSTRING (s.text,r.statement_start_offset/2,
(CASE WHEN r.statement_end_offset = -1 THEN LEN(CONVERT(nvarchar(MAX), s.text)) * 2
ELSE r.statement_end_offset END - r.statement_start_offset)/2),
r.cpu_time, start_time, percent_complete,
CAST((estimated_completion_time/3600000) as varchar) + ' hour(s), '
+ CAST((estimated_completion_time %3600000)/60000 as varchar) + 'min, '
+ CAST((estimated_completion_time %60000)/1000 as varchar) + ' sec' as est_time_to_go,
dateadd(second,estimated_completion_time/1000, getdate()) as est_completion_time
FROM   sys.dm_exec_requests r WITH (NOLOCK)
JOIN sys.dm_exec_sessions se WITH (NOLOCK)
ON r.session_id = se.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) s
OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) p
WHERE  r.session_id <> @@SPID AND se.is_user_process = 1;
END
ELSE IF @x = '1'  OR @x = 'memory'
BEGIN
-- who is consuming the memory
SELECT session_id, granted_memory_kb FROM sys.dm_exec_query_memory_grants WITH (NOLOCK) ORDER BY 1 DESC;
END
ELSE IF @x = '2'  OR @x = 'cpu'
BEGIN
-- who has cached plans that consumed the most cumulative CPU (top 10)
SELECT TOP 10 DatabaseName = DB_Name(t.dbid),
sql_text = SUBSTRING (t.text, qs.statement_start_offset/2,
(CASE WHEN qs.statement_end_offset = -1 THEN LEN(CONVERT(nvarchar(MAX), t.text)) * 2
ELSE qs.statement_end_offset END - qs.statement_start_offset)/2),
ObjectName = OBJECT_SCHEMA_NAME(t.objectid,t.dbid) + '.' + OBJECT_NAME(t.objectid, t.dbid),
qs.execution_count AS [Executions], qs.total_worker_time AS [Total CPU Time],
qs.total_physical_reads AS [Disk Reads (worst reads)], qs.total_elapsed_time AS [Duration],
qs.total_worker_time/qs.execution_count AS [Avg CPU Time],qs.plan_generation_num,
qs.creation_time AS [Data Cached], qp.query_plan
FROM sys.dm_exec_query_stats qs WITH(NOLOCK)
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp
ORDER BY DatabaseName, qs.total_worker_time DESC;
END
ELSE IF @x = '3'  OR @x = 'count'
BEGIN
-- who is connected and how many sessions it has
SELECT login_name, [program_name],No_of_Connections = COUNT(session_id)
FROM sys.dm_exec_sessions WITH (NOLOCK)
WHERE session_id > 50 GROUP BY login_name, [program_name] ORDER BY COUNT(session_id) DESC
END
ELSE IF @x = '4'  OR @x = 'idle'
BEGIN
-- who is idle that have open transactions
SELECT s.session_id, login_name, login_time, host_name, host_process_id, status FROM sys.dm_exec_sessions AS s WITH (NOLOCK)
WHERE EXISTS (SELECT * FROM sys.dm_tran_session_transactions AS t WHERE t.session_id = s.session_id)
AND NOT EXISTS (SELECT * FROM sys.dm_exec_requests AS r WHERE r.session_id = s.session_id)
END
ELSE IF @x = '5' OR @x = 'tempdb'
BEGIN
-- who is running tasks that use tempdb (top 5)
SELECT TOP 5 session_id, request_id,  user_objects_alloc_page_count + internal_objects_alloc_page_count as task_alloc
FROM    tempdb.sys.dm_db_task_space_usage  WITH (NOLOCK)
WHERE   session_id > 50 ORDER BY user_objects_alloc_page_count + internal_objects_alloc_page_count DESC
END
ELSE IF @x = '6' OR @x = 'block'
BEGIN
-- who is blocking
SELECT DB_NAME(lok.resource_database_id) as db_name,lok.resource_description,lok.request_type,lok.request_status,lok.request_owner_type
,wat.session_id as wait_session_id,wat.wait_duration_ms,wat.wait_type,wat.blocking_session_id
FROM  sys.dm_tran_locks lok WITH (NOLOCK) JOIN sys.dm_os_waiting_tasks wat WITH (NOLOCK) ON lok.lock_owner_address = wat.resource_address
END
ELSE IF @x = '0' OR @x = 'help'
BEGIN
DECLARE @text NVARCHAR(4000);
DECLARE @NewLineChar AS CHAR(2) = CHAR(13) + CHAR(10);
SET @text = N'Synopsis:' + @NewLineChar +
N'Who is currently running on my system?'  + @NewLineChar +
N'-------------------------------------------------------------------------------------------------------------------------------------'  + @NewLineChar +
N'Description:'  + @NewLineChar +
N'The first area to look at on a system running SQL Server is the utilization of hardware resources, the core of which are memory,' + @NewLineChar +
N'storage, CPU and long blockings. Use sp_who3 to first view the current system load and to identify a session of interest.' + @NewLineChar +
N'You should execute the query several times to identify which session id is most consuming teh system resources.' + @NewLineChar +
N'-------------------------------------------------------------------------------------------------------------------------------------' + @NewLineChar +
N'Parameters:'  + @NewLineChar +
N'sp_who3 null - who is active;' + @NewLineChar +
N'sp_who3 1 or ''memory''   - who is consuming the memory;' + @NewLineChar +
N'sp_who3 2 or ''cpu''   - who has cached plans that consumed the most cumulative CPU (top 10);'+ @NewLineChar +
N'sp_who3 3 or ''count''   - who is connected and how many sessions it has;'+ @NewLineChar +
N'sp_who3 4 or ''idle'' - who is idle that has open transactions;'+ @NewLineChar +
N'sp_who3 5 or ''tempdb'' - who is running tasks that use tempdb (top 5); and,'+ @NewLineChar +
N'sp_who3 6 or ''block'' - who is blocking.'
PRINT @text;
END




--SELECT DISTINCT
--    SPID                = er.session_id
--    ,BlkBy              = CASE WHEN lead_blocker = 1 THEN -1 ELSE er.blocking_session_id END
--    ,ElapsedMS          = er.total_elapsed_time
--    ,CPU                = er.cpu_time
--    ,IOReads            = er.logical_reads + er.reads
--    ,IOWrites           = er.writes    
--    ,Executions         = ec.execution_count  
--    ,CommandType        = er.command        
--    ,LastWaitType       = er.last_wait_type    
--    ,ObjectName         = OBJECT_SCHEMA_NAME(qt.objectid,dbid) + '.' + OBJECT_NAME(qt.objectid, qt.dbid)  
--    ,SQLStatement       =
--        SUBSTRING
--        (
--            qt.text,
--            er.statement_start_offset/2,
--            (CASE WHEN er.statement_end_offset = -1
--                THEN LEN(CONVERT(nvarchar(MAX), qt.text)) * 2
--                ELSE er.statement_end_offset
--                END - er.statement_start_offset)/2
--        )        
--    ,STATUS             = ses.STATUS
--    ,[Login]            = ses.login_name
--    ,Host               = ses.host_name
--,ProgramName = ses.program_name
--    ,DBName             = DB_Name(er.database_id)
--    ,StartTime          = er.start_time
--    ,Protocol           = con.net_transport
--    ,transaction_isolation =
--        CASE ses.transaction_isolation_level
--            WHEN 0 THEN 'Unspecified'
--            WHEN 1 THEN 'Read Uncommitted'
--            WHEN 2 THEN 'Read Committed'
--            WHEN 3 THEN 'Repeatable'
--            WHEN 4 THEN 'Serializable'
--            WHEN 5 THEN 'Snapshot'
--        END
--    ,ConnectionWrites   = con.num_writes
--    ,ConnectionReads    = con.num_reads
--    ,ClientAddress      = con.client_net_address
--    ,Authentication     = con.auth_scheme
--    ,DatetimeSnapshot   = GETDATE()
--FROM sys.dm_exec_requests er
--LEFT JOIN sys.dm_exec_sessions ses
--ON ses.session_id = er.session_id
--LEFT JOIN sys.dm_exec_connections con
--ON con.session_id = ses.session_id
--CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) AS qt
--OUTER APPLY
--(
--    SELECT execution_count = MAX(cp.usecounts)
--    FROM sys.dm_exec_cached_plans cp
--    WHERE cp.plan_handle = er.plan_handle
--) ec
--OUTER APPLY
--(
--    SELECT
--        lead_blocker = 1
--    FROM master.dbo.sysprocesses sp
--    WHERE sp.spid IN (SELECT blocked FROM master.dbo.sysprocesses)
--    AND sp.blocked = 0
--    AND sp.spid = er.session_id
--) lb
--ORDER BY 2 DESC, 4 DESC
----1--qt.objectid
--    --er.blocking_session_id DESC,
--    --er.logical_reads + er.reads DESC,
--    --er.session_id
 

  
USE [master]
GO
--SET ANSI_NULLS ON
--GO
--SET QUOTED_IDENTIFIER ON
--GO
--IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'sp_who3')
--DROP PROCEDURE sp_who3
--GO
--CREATE PROCEDURE sp_who3 @spid INT = NULL, @database SYSNAME = NULL
--AS

--BEGIN
--	SET NOCOUNT ON;
	DECLARE @spid INT = NULL, @database SYSNAME = NULL
	
	
	DECLARE @sql_who NVARCHAR(4000);
	DECLARE @NewLineChar AS CHAR(2) = CHAR(13) + CHAR(10);
	DECLARE @ParmDefinition NVARCHAR(500);
	DECLARE @pSPID INT;
	DECLARE @pDatabase SYSNAME;
	


	SET @sql_who = N'SELECT r.session_id
				    , r.blocking_session_id AS blk_by
				    , r.open_transaction_count AS open_tran_count
				    , mg.requested_memory_kb
				    , mg.query_cost
				    , r.cpu_time
				    , se.host_name
				    , se.login_name
				    , db_name(r.database_id) AS db_name
				    , r.status
				    , r.command
				    , CAST(((DATEDIFF(s,start_time,GetDate()))/3600) as varchar) + '' hour(s), '' + CAST((DATEDIFF(s,start_time,GetDate())%3600)/60 as varchar) + ''min, '' + CAST((DATEDIFF(s,start_time,GetDate())%60) as varchar) + '' sec'' as running_time
				    , r.wait_type
				    , object_name = OBJECT_SCHEMA_NAME(s.objectid,s.dbid) + ''.'' + OBJECT_NAME(s.objectid, s.dbid)
				    , sql_text = SUBSTRING(s.text, 1+(CASE WHEN r.statement_start_offset = 0 THEN 0 ELSE r.statement_start_offset/2 END), 1+(CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(s.text) ELSE r.statement_end_offset/2 END - (CASE WHEN r.statement_start_offset = 0 THEN 0 ELSE r.statement_start_offset/2 END)))
				    , program_name = se.program_name, p.query_plan AS query_plan
				    , r.sql_handle
				    , mg.granted_memory_kb
				    , mg.ideal_memory_kb
				    , ((((ssu.user_objects_alloc_page_count + (SELECT SUM(tsu.user_objects_alloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)) -
					  (ssu.user_objects_dealloc_page_count + (SELECT SUM(tsu.user_objects_dealloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)))*8)/1024) AS user_obj_in_tempdb_MB,
					  ((((ssu.internal_objects_alloc_page_count + (SELECT SUM(tsu.internal_objects_alloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)) -
					  (ssu.internal_objects_dealloc_page_count + (SELECT SUM(tsu.internal_objects_dealloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)))*8)/1024) AS internal_obj_in_tempdb_MB
				    , start_time
				    , percent_complete
				    , CAST((estimated_completion_time/3600000) as varchar) + '' hour(s), '' + CAST((estimated_completion_time %3600000)/60000 as varchar) + ''min, '' + CAST((estimated_completion_time %60000)/1000 as varchar) + '' sec'' as est_time_to_go
				    , dateadd(second,estimated_completion_time/1000, getdate()) as est_completion_time
			FROM sys.dm_exec_requests r WITH (NOLOCK)  
			JOIN sys.dm_exec_sessions se WITH (NOLOCK) ON r.session_id = se.session_id
			LEFT OUTER JOIN sys.dm_exec_query_memory_grants mg WITH (NOLOCK) ON r.session_id = mg.session_id AND r.request_id = mg.request_id
			LEFT OUTER JOIN sys.dm_db_session_space_usage ssu WITH (NOLOCK) ON r.session_id = ssu.session_id
			OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) s 
			OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) p ';

	IF (@spid IS NOT NULL) AND (@database IS NOT NULL)
		BEGIN
			SET @sql_who = @sql_who + N'WHERE r.session_id = @pSPID AND db_name(r.database_id) = @pDatabase  ORDER BY running_time DESC;';
			SET @ParmDefinition = N'@pSPID INT, @pDatabase SYSNAME';
			EXECUTE sp_executesql @sql_who, @ParmDefinition, @pSPID = @spid, @pDatabase = @database;
		END;
	ELSE IF @spid IS NOT NULL
		BEGIN
			SET @sql_who = @sql_who + N'WHERE r.session_id = @pSPID ORDER BY running_time DESC;';
			SET @ParmDefinition = N'@pSPID INT';
			EXECUTE sp_executesql @sql_who, @ParmDefinition, @pSPID = @spid;
		END;
	ELSE IF @database IS NOT NULL
		BEGIN
			SET @sql_who = @sql_who + N'WHERE r.session_id <> @@SPID AND se.is_user_process = 1 AND db_name(r.database_id) = @pDatabase  ORDER BY running_time DESC;'
			SET @ParmDefinition = N'@pDatabase SYSNAME';
			EXECUTE sp_executesql @sql_who, @ParmDefinition, @pDatabase = @database;
		END;
	ELSE
		BEGIN
			SET @sql_who = @sql_who + N'WHERE r.session_id <> @@SPID AND se.is_user_process = 1  ORDER BY running_time DESC;';
			EXECUTE sp_executesql @sql_who;
		END;
--END;
--GO
