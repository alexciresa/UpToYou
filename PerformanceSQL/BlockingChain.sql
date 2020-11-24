/*
Version: 1.0

Created by: Alexandra Ionescu
Created date: 2020-11-09

Modified by:
Modified date:
Modification details:

Description: Collects the blocked processes list

Settings: @CREATE_JOB
		  Before running the script, please check the variables. If needed, change their values.
*/


/*** Collection database ***/
USE DBA
GO

/*** Collection table ***/

IF EXISTS (SELECT 1 FROM sys.tables WHERE [name] = 'BlockingChain')
BEGIN
	DROP TABLE [dbo].[BlockingChain]
END

CREATE TABLE [dbo].[BlockingChain](
	[spid] [smallint] NOT NULL,
	[blocked] [smallint] NOT NULL,
	[lastwaittype] [nchar](32) NOT NULL,
	[waitresource] [nchar](256) NOT NULL,
	[dbid] [smallint] NOT NULL,
	[cpu] [int] NOT NULL,
	[physical_io] [bigint] NOT NULL,
	[memusage] [int] NOT NULL,
	[open_tran] [smallint] NOT NULL,
	[status] [nchar](30) NOT NULL,
	[hostname] [nchar](128) NOT NULL,
	[program_name] [nchar](128) NOT NULL,
	[cmd] [nchar](16) NOT NULL,
	[loginame] [nchar](128) NOT NULL,
	[sql_handle] [binary](20) NOT NULL,
	[stmt_start] [int] NOT NULL,
	[stmt_end] [int] NOT NULL,
	[collection_time] [datetimeoffset](7) NOT NULL DEFAULT GETDATE(),
	[snapshot_id] [int] NOT NULL,
	PRIMARY KEY (snapshot_id, spid)
) ON [PRIMARY]
GO

/*** Collection stored procedure ***/

IF EXISTS (SELECT 1 FROM sys.procedures WHERE [name] = 'usp_BlockingChainInsert')
BEGIN
	DROP PROCEDURE [usp_BlockingChainInsert] 
END
GO

CREATE PROCEDURE [usp_BlockingChainInsert] 
AS

DECLARE @id int

SELECT @id = ISNULL(MAX(snapshot_id),0) FROM [dbo].[BlockingChain]

INSERT INTO [dbo].[BlockingChain]
           ([spid]
           ,[blocked]
           ,[lastwaittype]
           ,[waitresource]
           ,[dbid]
           ,[cpu]
           ,[physical_io]
           ,[memusage]
           ,[open_tran]
           ,[status]
           ,[hostname]
           ,[program_name]
           ,[cmd]
           ,[loginame]
           ,[sql_handle]
           ,[stmt_start]
           ,[stmt_end]
		   ,[snapshot_id])
SELECT
			[spid]
           ,[blocked]
           ,[lastwaittype]
           ,[waitresource]
           ,[dbid]
           ,[cpu]
           ,[physical_io]
           ,[memusage]
           ,[open_tran]
           ,[status]
           ,[hostname]
           ,[program_name]
           ,[cmd]
           ,[loginame]
           ,[sql_handle]
           ,[stmt_start]
           ,[stmt_end]
		   ,@id+1
FROM sys.sysprocesses 
WHERE blocked != 0 OR spid IN
(SELECT blocked FROM sys.sysprocesses
WHERE blocked != 0)

GO

/*** Collection job ***/

DECLARE @CREATE_JOB AS BINARY
SET @CREATE_JOB = 1
DECLARE @JOB_ID AS INT
DECLARE @frequency_type AS INT = 4 
DECLARE	@frequency_interval AS INT = 1
DECLARE	@frequency_subday_type AS INT = 0x2
DECLARE	@frequency_subday_interval AS INT = 10

USE msdb

IF @CREATE_JOB = 1
BEGIN
	IF EXISTS (SELECT NAME FROM msdb.dbo.sysjobs WHERE NAME = 'DBA_BlockingChainCollection')
	BEGIN
		EXEC sp_delete_job 
			@job_name = 'DBA_BlockingChainCollection'
	END

	IF EXISTS (SELECT NAME FROM sysschedules WHERE NAME = 'DBA_BlockingChainCollection Schedule')
	BEGIN
		EXEC sp_delete_schedule @schedule_name = 'DBA_BlockingChainCollection Schedule'
	END

	EXEC dbo.sp_add_job  
	    @job_name = 'DBA_BlockingChainCollection' 
	EXEC sp_add_jobstep  
	    @job_name = 'DBA_BlockingChainCollection',  
		@step_name = 'Run script BlockingChain',
--------------------------------------------------------------------------------------------------------------------------
--!!!!!!!!!!!!!!! CHANGE THE DATABASE NAME IN THE NEXT COMMAND IF YOU WANT ANOTHER ONE FOR YOUR TABLES, VIEWS AND PROCEDURES !!!!!!!!!!!!!!!!!
--------------------------------------------------------------------------------------------------------------------------
	    @command = N'USE DBA exec usp_BlockingChainInsert'
	EXEC dbo.sp_add_schedule  
	    @schedule_name = 'DBA_BlockingChainCollection Schedule',  
	    @freq_type = @frequency_type, 
		@freq_interval = @frequency_interval,
	    @freq_subday_type = @frequency_subday_type,
		@freq_subday_interval = @frequency_subday_interval
	EXEC sp_attach_schedule  
		@job_name = 'DBA_BlockingChainCollection',  
		@schedule_name = 'DBA_BlockingChainCollection Schedule' 
	EXEC dbo.sp_add_jobserver  
	    @job_name = 'DBA_BlockingChainCollection' 
END