/*** Collection database ***/

USE DBA
GO

/*** Collection table ***/

IF EXISTS (SELECT 1 FROM sys.tables WHERE [name] = 'LatchStats')
BEGIN 
	DROP TABLE [dbo].[LatchStats]
END

CREATE TABLE [dbo].[LatchStats] (
	snapshot_id int,
	latch_class nvarchar(120),
	waiting_requests_count bigint,
	wait_time_ms bigint,
	max_wait_time_ms bigint,
	[collection_time] [datetimeoffset](7) NOT NULL DEFAULT GETDATE(),
	CONSTRAINT [PK_LatchStats] PRIMARY KEY NONCLUSTERED (snapshot_id, latch_class)
)

/*** Collection stored procedure ***/

IF EXISTS (SELECT 1 FROM sys.procedures WHERE [name] = 'usp_LatchStatsInsert')
BEGIN
	DROP PROCEDURE [usp_LatchStatsInsert]
END
GO

CREATE PROCEDURE [usp_LatchStatsInsert]
AS
DECLARE @id int

SELECT @id = ISNULL(MAX(snapshot_id),0) FROM LatchStats

INSERT INTO [dbo].[LatchStats] 
(
	snapshot_id,
	latch_class,
	waiting_requests_count,
	wait_time_ms,
	max_wait_time_ms
)
SELECT
@id+1,
latch_class,
waiting_requests_count,
wait_time_ms,
max_wait_time_ms
FROM
sys.dm_os_latch_stats
--WHERE waiting_requests_count > 0
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
	IF EXISTS (SELECT NAME FROM msdb.dbo.sysjobs WHERE NAME = 'DBA_LatchStatsCollection')
	BEGIN
		EXEC sp_delete_job 
			@job_name = 'DBA_LatchStatsCollection'
	END
	
	IF EXISTS (SELECT NAME FROM sysschedules WHERE NAME = 'DBA_LatchStatsCollection Schedule')
	BEGIN
		EXEC sp_delete_schedule @schedule_name = 'DBA_LatchStatsCollection Schedule'
	END
		 
	EXEC dbo.sp_add_job  
	    @job_name = N'DBA_LatchStatsCollection'   
	 
	EXEC sp_add_jobstep  
	    @job_name = N'DBA_LatchStatsCollection',  
	    @step_name = N'Run script LatchStats', 
--------------------------------------------------------------------------------------------------------------------------
--!!!!!!!!!!!!!!! CHANGE THE DATABASE NAME IN THE NEXT COMMAND IF YOU WANT ANOTHER ONE FOR YOUR TABLES, VIEWS AND PROCEDURES !!!!!!!!!!!!!!!!!
--------------------------------------------------------------------------------------------------------------------------
	    @command = N'USE DBA EXEC usp_LatchStatsInsert' 
	
	EXEC dbo.sp_add_schedule  
	    @schedule_name = 'DBA_LatchStatsCollection Schedule',  
	    @freq_type = @frequency_type, 
		@freq_interval = @frequency_interval,
	    @freq_subday_type = @frequency_subday_type,
		@freq_subday_interval = @frequency_subday_interval
	
	EXEC sp_attach_schedule  
		@job_name = 'DBA_LatchStatsCollection',  
		@schedule_name = 'DBA_LatchStatsCollection Schedule' 
	  
	EXEC dbo.sp_add_jobserver  
	    @job_name = 'DBA_LatchStatsCollection'  
END


------------------- after inserts ---------------------------
--------------------------------------------------------------------------------------------------------------------------
--!!!!!!!!!!!!!!! CHANGE THE DATABASE NAME IF YOU WANT ANOTHER ONE FOR YOUR TABLES, VIEWS AND PROCEDURES !!!!!!!!!!!!!!!!!
--------------------------------------------------------------------------------------------------------------------------
--USE DBA

--CREATE CLUSTERED COLUMNSTORE INDEX CCI_LatchStats ON LatchStats

--ALTER TABLE LatchStats ADD CONSTRAINT [PK_os_wait_stats] PRIMARY KEY NONCLUSTERED (snapshot_id, latch_class)

--DELETE FROM LatchStats 
--WHERE latch_class IN (SELECT latch_class FROM LatchStats
--GROUP BY latch_class
--HAVING SUM(wait_time_ms) = 0)


--SELECT * FROM [dbo].[LatchStats]