/*
Version: 1.0

Created by: Andrei Neagu
Created date: 2020-11-09

Modified by:
Modified date:
Modification details:

Description: Creates job and objects for collecting procedure statistics

Settings: collection database, @database_name, @create_job
*/

/*** Collection database ***/
USE ITCS_Analysis


/*** Collection table ***/
IF EXISTS (SELECT 1 FROM sys.tables WHERE [name] = 'ProcedureStats')
BEGIN
	DROP TABLE [dbo].[ProcedureStats]
END
GO

CREATE TABLE [dbo].[ProcedureStats](
	[database_name] [nvarchar](128) NULL,
	[object_name] [nvarchar](128) NULL,
	[type_desc] [nvarchar](60) NULL,
	[sql_handle] [varbinary](64) NOT NULL,
	[plan_handle] [varbinary](64) NOT NULL,
	[execution_count] [bigint] NOT NULL,
	[total_worker_time] [bigint] NOT NULL,
	[total_physical_reads] [bigint] NOT NULL,
	[total_logical_reads] [bigint] NOT NULL
) ON [PRIMARY]
GO

/*** Collection view ***/
IF EXISTS (SELECT 1 FROM sys.views WHERE [name] = 'ProcedureStatsViewTop20')
BEGIN
	DROP VIEW [dbo].[ProcedureStatsViewTop20]
END
GO

CREATE VIEW [dbo].[ProcedureStatsViewTop20]
AS
SELECT * FROM 
(SELECT TOP 20 DB_NAME([database_id]) as [database_name], OBJECT_NAME([object_id],[database_id]) as [object_name], [type_desc], [sql_handle], [plan_handle], [execution_count], [total_worker_time], [total_physical_reads], [total_logical_reads] 
FROM sys.dm_exec_procedure_stats
ORDER BY total_worker_time DESC) as a
UNION
SELECT * FROM 
(SELECT TOP 20 DB_NAME([database_id]) as [database_name], OBJECT_NAME([object_id],[database_id]) as [object_name], [type_desc], [sql_handle], [plan_handle], [execution_count], [total_worker_time], [total_physical_reads], [total_logical_reads] 
FROM sys.dm_exec_procedure_stats
ORDER BY total_physical_reads DESC) as b
UNION
SELECT * FROM 
(SELECT TOP 20 DB_NAME([database_id]) as [database_name], OBJECT_NAME([object_id],[database_id]) as [object_name], [type_desc], [sql_handle], [plan_handle], [execution_count], [total_worker_time], [total_physical_reads], [total_logical_reads] 
FROM sys.dm_exec_procedure_stats
ORDER BY total_logical_reads DESC) as c
GO

/*** Collection procedure ***/
IF EXISTS (SELECT 1 FROM sys.procedures WHERE [name] = 'usp_procedure_stats_collection')
BEGIN
	DROP PROCEDURE usp_procedure_stats_collection
END
GO

CREATE PROCEDURE usp_procedure_stats_collection
AS
UPDATE a 
SET a.execution_count = b.execution_count, 
	a.total_worker_time = b.total_worker_time, 
	a.total_physical_reads = b.total_physical_reads, 
	a.total_logical_reads = b.total_logical_reads
FROM ProcedureStats AS a
INNER JOIN ProcedureStatsViewTop20 AS b
	ON	a.database_name = b.database_name AND
		a.object_name = b.object_name AND
		a.sql_handle = b.sql_handle AND
		a.plan_handle = b.plan_handle AND
		a.execution_count < b.execution_count

INSERT INTO ProcedureStats 
SELECT a.[database_name], a.[object_name] as [object_name], a.[type_desc], a.[sql_handle], a.[plan_handle], a.[execution_count], a.[total_worker_time], a.[total_physical_reads], a.[total_logical_reads] 
FROM ProcedureStatsViewTop20 a
LEFT JOIN ProcedureStats b
	ON	a.database_name = b.database_name AND
		a.object_name = b.object_name AND
		a.sql_handle = b.sql_handle AND
		a.plan_handle = b.plan_handle
WHERE b.sql_handle IS NULL
GO

/*** Collection job ***/
USE msdb
GO

DECLARE @CREATE_JOB AS BINARY,
		@DBNAME varchar(50),
		@JOB_ID AS INT

SET @CREATE_JOB = 0
SET @DBNAME = 'ITCS_Analysis'

IF @CREATE_JOB = 1
BEGIN

	IF EXISTS (SELECT NAME FROM msdb.dbo.sysjobs WHERE NAME = 'ProcedureStatsCollection')
	BEGIN
		EXEC sp_delete_job 
			@job_name = 'ProcedureStatsCollection'
	END

	IF EXISTS (SELECT NAME FROM sysschedules WHERE NAME = 'Every 30 minutes ProcedureStatsCollection')
	BEGIN
		EXEC sp_delete_schedule @schedule_name = 'Every 30 minutes ProcedureStatsCollection'
	END

	EXEC dbo.sp_add_job  
	    @job_name = 'ProcedureStatsCollection' 
	EXEC sp_add_jobstep  
	    @job_name = 'ProcedureStatsCollection',  
		@step_name = 'usp_procedure_stats_collection',
		@database_name = 'ITCS_Analysis',
	    @command = N'exec usp_procedure_stats_collection'
	EXEC dbo.sp_add_schedule  
	    @schedule_name = 'Every 30 minutes ProcedureStatsCollection',  
	    @freq_type = 4, 
		@freq_interval = 1,
	    @freq_subday_type = 0x4,
		@freq_subday_interval = 30
	EXEC sp_attach_schedule  
		@job_name = 'ProcedureStatsCollection',  
		@schedule_name = 'Every 30 minutes ProcedureStatsCollection' 
	EXEC dbo.sp_add_jobserver  
	    @job_name = 'ProcedureStatsCollection' 
END