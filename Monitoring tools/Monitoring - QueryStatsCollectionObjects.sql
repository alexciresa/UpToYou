/*
Version: 1.0

Created by: Andrei Neagu
Created date: 2020-11-09

Modified by:
Modified date:
Modification details:

Description: Creates job and objects for collecting query statistics

Settings: collection database, @database_name, @create_job
*/


/*** Collection database ***/
USE ITCS_Analysis

/*** Collection table ***/
IF EXISTS (SELECT 1 FROM sys.tables WHERE [name] = 'QueryStats')
BEGIN
	DROP TABLE [dbo].[QueryStats]
END
GO

CREATE TABLE [dbo].[QueryStats](
	[sql_handle] [varbinary](64) NOT NULL,
	[statement_start_offset] [int] NOT NULL,
	[statement_end_offset] [int] NOT NULL,
	[plan_generation_num] [bigint] NULL,
	[plan_handle] [varbinary](64) NOT NULL,
	[execution_count] [bigint] NOT NULL,
	[total_worker_time] [bigint] NOT NULL,
	[total_physical_reads] [bigint] NOT NULL,
	[total_logical_reads] [bigint] NOT NULL,
	[total_rows] [bigint] NULL,
	[max_dop] [bigint] NULL,
	[total_grant_kb] [bigint] NULL
) ON [PRIMARY]
GO

/*** Collection view ***/
IF EXISTS (SELECT 1 FROM sys.views WHERE [name] = 'QueryStatsViewTop20')
BEGIN
	DROP VIEW [dbo].[QueryStatsViewTop20]
END
GO

CREATE VIEW [dbo].[QueryStatsViewTop20]
AS
SELECT * FROM 
(SELECT tOp 20 sql_handle, statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_reads, total_rows, max_dop, total_grant_kb  
FROM sys.dm_exec_query_stats
ORDER BY total_worker_time DESC) as a
UNION
SELECT * FROM 
(SELECT top 20 sql_handle, statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_reads, total_rows, max_dop, total_grant_kb  
FROM sys.dm_exec_query_stats
ORDER BY total_physical_reads DESC) as b
UNION
SELECT * FROM 
(SELECT top 20 sql_handle, statement_start_offset, statement_end_offset, plan_generation_num, plan_handle, execution_count, total_worker_time, total_physical_reads, total_logical_reads, total_rows, max_dop, total_grant_kb  
FROM sys.dm_exec_query_stats
ORDER BY total_logical_reads DESC) as c
GO

/*** Collection stored procedure ***/
IF EXISTS (SELECT 1 FROM sys.procedures WHERE [name] = 'usp_query_stats_collection')
BEGIN
	DROP PROCEDURE usp_query_stats_collection
END
GO

CREATE PROCEDURE usp_query_stats_collection
AS
UPDATE a 
SET a.plan_generation_num = b.plan_generation_num,
	a.execution_count = b.execution_count, 
	a.total_worker_time = b.total_worker_time, 
	a.total_physical_reads = b.total_physical_reads, 
	a.total_logical_reads = b.total_logical_reads, 
	a.total_rows = b.total_rows, 
	a.max_dop = b.max_dop, 
	a.total_grant_kb = b.total_grant_kb
FROM QueryStats AS a
INNER JOIN QueryStatsViewTop20 AS b
	ON a.sql_handle = b.sql_handle AND
		a.statement_start_offset = b.statement_start_offset AND
		a.statement_end_offset = b.statement_end_offset AND
		a.plan_handle = b.plan_handle AND
		a.execution_count < b.execution_count

INSERT INTO QueryStats 
SELECT a.sql_handle, a.statement_start_offset, a.statement_end_offset, a.plan_generation_num, a.plan_handle, a.execution_count, a.total_worker_time, a.total_physical_reads, a.total_logical_reads, a.total_rows, a.max_dop, a.total_grant_kb   
FROM QueryStatsViewTop20 a
LEFT JOIN QueryStats b
	ON a.sql_handle = b.sql_handle AND
		a.statement_start_offset = b.statement_start_offset AND
		a.statement_end_offset = b.statement_end_offset AND
		a.plan_handle = b.plan_handle
WHERE b.sql_handle IS NULL
GO

/*** Collection job ***/
USE msdb
GO

DECLARE @CREATE_JOB AS BINARY
SET @CREATE_JOB = 0
DECLARE @JOB_ID AS INT

IF @CREATE_JOB = 1
BEGIN

	IF EXISTS (SELECT NAME FROM msdb.dbo.sysjobs WHERE NAME = 'QueryStatsCollection')
	BEGIN
		EXEC sp_delete_job 
			@job_name = 'QueryStatsCollection'
	END

	IF EXISTS (SELECT NAME FROM sysschedules WHERE NAME = 'Every 30 minutes QueryStatsCollection')
	BEGIN
		EXEC sp_delete_schedule @schedule_name = 'Every 30 minutes QueryStatsCollection'
	END

	EXEC dbo.sp_add_job  
	    @job_name = 'QueryStatsCollection' 
	EXEC sp_add_jobstep  
	    @job_name = 'QueryStatsCollection',  
		@step_name = 'usp_query_stats_collection',
		@database_name = 'ITCS_Analysis',
	    @command = N'exec usp_query_stats_collection'
	EXEC dbo.sp_add_schedule  
	    @schedule_name = 'Every 30 minutes QueryStatsCollection',  
	    @freq_type = 4, 
		@freq_interval = 1,
	    @freq_subday_type = 0x4,
		@freq_subday_interval = 30
	EXEC sp_attach_schedule  
		@job_name = 'QueryStatsCollection',  
		@schedule_name = 'Every 30 minutes QueryStatsCollection' 
	EXEC dbo.sp_add_jobserver  
	    @job_name = 'QueryStatsCollection' 
END