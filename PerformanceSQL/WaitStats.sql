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

/*** Collection tables ***/

IF EXISTS (SELECT 1 FROM sys.tables WHERE [name] = 'WaitStats')
BEGIN 
	ALTER TABLE [dbo].[WaitStats] DROP CONSTRAINT [FK_idWaitType_WaitType_WaitStats]
	DROP TABLE [dbo].[WaitStats]
END

IF EXISTS (SELECT 1 FROM sys.tables WHERE [name] = 'WaitType')
BEGIN
	DROP TABLE [dbo].[WaitType]
END

CREATE TABLE [dbo].[WaitType] (
	[idWaitType] int identity(1,1) PRIMARY KEY,
	[waitType] nvarchar(60))

INSERT INTO [dbo].[WaitType] ([waitType])
SELECT DISTINCT [wait_type] FROM 
sys.dm_os_wait_stats

CREATE TABLE [dbo].[WaitStats](
	[idWaitType] int NOT NULL,
	[waitingTasksCount] [bigint] NOT NULL,
	[waitTime_ms] [bigint] NOT NULL,
	[signalWaitTime_ms] [bigint] NOT NULL,
	[collectionTime] [datetimeoffset](7) NOT NULL DEFAULT GETDATE(),
	[snapshotId] [int] NOT NULL,
 CONSTRAINT [PK_os_wait_stats] PRIMARY KEY CLUSTERED 
(
	[snapshotId] ASC,
	[idWaitType] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY],
	CONSTRAINT FK_idWaitType_WaitType_WaitStats FOREIGN KEY ([idWaitType]) REFERENCES [WaitType] ([idWaitType])
) ON [PRIMARY]
GO

IF EXISTS (SELECT 1 FROM sys.views WHERE [name] = 'vw_WaitStatsDeltas')
BEGIN
	DROP VIEW [vw_WaitStatsDeltas]
END
GO

CREATE VIEW [vw_WaitStatsDeltas]
AS
SELECT  ws.snapshotId,
		wt.waitType,
		wt.idWaitType,
		ws.collectionTime,
		ws.waitingtaskscount,
		ws.waitingTasksCount - LAG(ws.waitingTasksCount,1,0) OVER (PARTITION BY wt.waitType ORDER BY ws.snapshotId) AS waiting_tasks_count_diff,
		ws.waitTime_ms,
		ws.waitTime_ms - LAG(ws.waitTime_ms,1,0) OVER (PARTITION BY wt.waitType ORDER BY ws.snapshotId) AS wait_time_ms_diff,
		ws.signalWaitTime_ms,
		ws.signalWaitTime_ms - LAG(ws.signalWaitTime_ms,1,0) OVER (PARTITION BY wt.waitType ORDER BY ws.snapshotId) AS signal_wait_time_ms_diff
FROM WaitStats AS ws
INNER JOIN WaitType AS wt
ON ws.idWaitType = wt.idWaitType
WHERE  (ws.waitingTasksCount - LAG(ws.waitingTasksCount,1,0) OVER (PARTITION BY wt.waitType ORDER BY ws.snapshotId)) >= 0 
	AND (ws.waitTime_ms - LAG(ws.waitTime_ms,1,0) OVER (PARTITION BY wt.waitType ORDER BY ws.snapshotId)) >= 0 
	AND (ws.signalWaitTime_ms - LAG(ws.signalWaitTime_ms,1,0) OVER (PARTITION BY wt.waitType ORDER BY ws.snapshotId)) >= 0
--ORDER BY collectionTime DESC, ws.snapshotId, idWaitType 
GO

/*** Collection stored procedure ***/

IF EXISTS (SELECT 1 FROM sys.procedures WHERE [name] = 'usp_WaitStatsInsert')
BEGIN
	DROP PROCEDURE [usp_WaitStatsInsert]
END
GO

CREATE PROCEDURE [usp_WaitStatsInsert]
AS

DECLARE @id int

SELECT @id = ISNULL(MAX(snapshotId),0) FROM [DBA].[dbo].[WaitStats]

INSERT INTO [dbo].[WaitStats] 
(
snapshotId,
idWaitType,
waitingTasksCount,
waitTime_ms,
signalWaitTime_ms
)
SELECT
@id+1,
idWaitType,
waiting_tasks_count,
wait_time_ms,
signal_wait_time_ms
FROM
sys.dm_os_wait_stats A
INNER JOIN [dbo].[WaitType] B
ON A.wait_type=B.waitType
WHERE A.wait_type NOT IN (
        -- These wait types are almost 100% never a problem and so they are
        -- filtered out to avoid them skewing the results. Click on the URL
        -- for more information.
        N'BROKER_EVENTHANDLER', -- https://www.sqlskills.com/help/waits/BROKER_EVENTHANDLER
        N'BROKER_RECEIVE_WAITFOR', -- https://www.sqlskills.com/help/waits/BROKER_RECEIVE_WAITFOR
        N'BROKER_TASK_STOP', -- https://www.sqlskills.com/help/waits/BROKER_TASK_STOP
        N'BROKER_TO_FLUSH', -- https://www.sqlskills.com/help/waits/BROKER_TO_FLUSH
        N'BROKER_TRANSMITTER', -- https://www.sqlskills.com/help/waits/BROKER_TRANSMITTER
        N'CHECKPOINT_QUEUE', -- https://www.sqlskills.com/help/waits/CHECKPOINT_QUEUE
        N'CHKPT', -- https://www.sqlskills.com/help/waits/CHKPT
        N'CLR_AUTO_EVENT', -- https://www.sqlskills.com/help/waits/CLR_AUTO_EVENT
        N'CLR_MANUAL_EVENT', -- https://www.sqlskills.com/help/waits/CLR_MANUAL_EVENT
        N'CLR_SEMAPHORE', -- https://www.sqlskills.com/help/waits/CLR_SEMAPHORE
        N'CXCONSUMER', -- https://www.sqlskills.com/help/waits/CXCONSUMER
 
        -- Maybe comment these four out if you have mirroring issues
        N'DBMIRROR_DBM_EVENT', -- https://www.sqlskills.com/help/waits/DBMIRROR_DBM_EVENT
        N'DBMIRROR_EVENTS_QUEUE', -- https://www.sqlskills.com/help/waits/DBMIRROR_EVENTS_QUEUE
        N'DBMIRROR_WORKER_QUEUE', -- https://www.sqlskills.com/help/waits/DBMIRROR_WORKER_QUEUE
        N'DBMIRRORING_CMD', -- https://www.sqlskills.com/help/waits/DBMIRRORING_CMD
 
        N'DIRTY_PAGE_POLL', -- https://www.sqlskills.com/help/waits/DIRTY_PAGE_POLL
        N'DISPATCHER_QUEUE_SEMAPHORE', -- https://www.sqlskills.com/help/waits/DISPATCHER_QUEUE_SEMAPHORE
        N'EXECSYNC', -- https://www.sqlskills.com/help/waits/EXECSYNC
        N'FSAGENT', -- https://www.sqlskills.com/help/waits/FSAGENT
        N'FT_IFTS_SCHEDULER_IDLE_WAIT', -- https://www.sqlskills.com/help/waits/FT_IFTS_SCHEDULER_IDLE_WAIT
        N'FT_IFTSHC_MUTEX', -- https://www.sqlskills.com/help/waits/FT_IFTSHC_MUTEX
 
        -- Maybe comment these six out if you have AG issues
        N'HADR_CLUSAPI_CALL', -- https://www.sqlskills.com/help/waits/HADR_CLUSAPI_CALL
        N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', -- https://www.sqlskills.com/help/waits/HADR_FILESTREAM_IOMGR_IOCOMPLETION
        N'HADR_LOGCAPTURE_WAIT', -- https://www.sqlskills.com/help/waits/HADR_LOGCAPTURE_WAIT
        N'HADR_NOTIFICATION_DEQUEUE', -- https://www.sqlskills.com/help/waits/HADR_NOTIFICATION_DEQUEUE
        N'HADR_TIMER_TASK', -- https://www.sqlskills.com/help/waits/HADR_TIMER_TASK
        N'HADR_WORK_QUEUE', -- https://www.sqlskills.com/help/waits/HADR_WORK_QUEUE
 
        N'KSOURCE_WAKEUP', -- https://www.sqlskills.com/help/waits/KSOURCE_WAKEUP
        N'LAZYWRITER_SLEEP', -- https://www.sqlskills.com/help/waits/LAZYWRITER_SLEEP
        N'LOGMGR_QUEUE', -- https://www.sqlskills.com/help/waits/LOGMGR_QUEUE
        N'MEMORY_ALLOCATION_EXT', -- https://www.sqlskills.com/help/waits/MEMORY_ALLOCATION_EXT
        N'ONDEMAND_TASK_QUEUE', -- https://www.sqlskills.com/help/waits/ONDEMAND_TASK_QUEUE
        N'PARALLEL_REDO_DRAIN_WORKER', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_DRAIN_WORKER
        N'PARALLEL_REDO_LOG_CACHE', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_LOG_CACHE
        N'PARALLEL_REDO_TRAN_LIST', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_TRAN_LIST
        N'PARALLEL_REDO_WORKER_SYNC', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_SYNC
        N'PARALLEL_REDO_WORKER_WAIT_WORK', -- https://www.sqlskills.com/help/waits/PARALLEL_REDO_WORKER_WAIT_WORK
        N'PREEMPTIVE_OS_FLUSHFILEBUFFERS', -- https://www.sqlskills.com/help/waits/PREEMPTIVE_OS_FLUSHFILEBUFFERS 
        N'PREEMPTIVE_XE_GETTARGETSTATE', -- https://www.sqlskills.com/help/waits/PREEMPTIVE_XE_GETTARGETSTATE
        N'PWAIT_ALL_COMPONENTS_INITIALIZED', -- https://www.sqlskills.com/help/waits/PWAIT_ALL_COMPONENTS_INITIALIZED
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', -- https://www.sqlskills.com/help/waits/PWAIT_DIRECTLOGCONSUMER_GETNEXT
        N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', -- https://www.sqlskills.com/help/waits/QDS_PERSIST_TASK_MAIN_LOOP_SLEEP
        N'QDS_ASYNC_QUEUE', -- https://www.sqlskills.com/help/waits/QDS_ASYNC_QUEUE
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', -- https://www.sqlskills.com/help/waits/QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP
        N'QDS_SHUTDOWN_QUEUE', -- https://www.sqlskills.com/help/waits/QDS_SHUTDOWN_QUEUE
        N'REDO_THREAD_PENDING_WORK', -- https://www.sqlskills.com/help/waits/REDO_THREAD_PENDING_WORK
        N'REQUEST_FOR_DEADLOCK_SEARCH', -- https://www.sqlskills.com/help/waits/REQUEST_FOR_DEADLOCK_SEARCH
        N'RESOURCE_QUEUE', -- https://www.sqlskills.com/help/waits/RESOURCE_QUEUE
        N'SERVER_IDLE_CHECK', -- https://www.sqlskills.com/help/waits/SERVER_IDLE_CHECK
        N'SLEEP_BPOOL_FLUSH', -- https://www.sqlskills.com/help/waits/SLEEP_BPOOL_FLUSH
        N'SLEEP_DBSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_DBSTARTUP
        N'SLEEP_DCOMSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_DCOMSTARTUP
        N'SLEEP_MASTERDBREADY', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERDBREADY
        N'SLEEP_MASTERMDREADY', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERMDREADY
        N'SLEEP_MASTERUPGRADED', -- https://www.sqlskills.com/help/waits/SLEEP_MASTERUPGRADED
        N'SLEEP_MSDBSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_MSDBSTARTUP
        N'SLEEP_SYSTEMTASK', -- https://www.sqlskills.com/help/waits/SLEEP_SYSTEMTASK
        N'SLEEP_TASK', -- https://www.sqlskills.com/help/waits/SLEEP_TASK
        N'SLEEP_TEMPDBSTARTUP', -- https://www.sqlskills.com/help/waits/SLEEP_TEMPDBSTARTUP
        N'SNI_HTTP_ACCEPT', -- https://www.sqlskills.com/help/waits/SNI_HTTP_ACCEPT
        N'SOS_WORK_DISPATCHER', -- https://www.sqlskills.com/help/waits/SOS_WORK_DISPATCHER
        N'SP_SERVER_DIAGNOSTICS_SLEEP', -- https://www.sqlskills.com/help/waits/SP_SERVER_DIAGNOSTICS_SLEEP
        N'SQLTRACE_BUFFER_FLUSH', -- https://www.sqlskills.com/help/waits/SQLTRACE_BUFFER_FLUSH
        N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', -- https://www.sqlskills.com/help/waits/SQLTRACE_INCREMENTAL_FLUSH_SLEEP
        N'SQLTRACE_WAIT_ENTRIES', -- https://www.sqlskills.com/help/waits/SQLTRACE_WAIT_ENTRIES
        N'VDI_CLIENT_OTHER', -- https://www.sqlskills.com/help/waits/VDI_CLIENT_OTHER
        N'WAIT_FOR_RESULTS', -- https://www.sqlskills.com/help/waits/WAIT_FOR_RESULTS
        N'WAITFOR', -- https://www.sqlskills.com/help/waits/WAITFOR
        N'WAITFOR_TASKSHUTDOWN', -- https://www.sqlskills.com/help/waits/WAITFOR_TASKSHUTDOWN
        N'WAIT_XTP_RECOVERY', -- https://www.sqlskills.com/help/waits/WAIT_XTP_RECOVERY
        N'WAIT_XTP_HOST_WAIT', -- https://www.sqlskills.com/help/waits/WAIT_XTP_HOST_WAIT
        N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', -- https://www.sqlskills.com/help/waits/WAIT_XTP_OFFLINE_CKPT_NEW_LOG
        N'WAIT_XTP_CKPT_CLOSE', -- https://www.sqlskills.com/help/waits/WAIT_XTP_CKPT_CLOSE
        N'XE_DISPATCHER_JOIN', -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_JOIN
        N'XE_DISPATCHER_WAIT', -- https://www.sqlskills.com/help/waits/XE_DISPATCHER_WAIT
        N'XE_TIMER_EVENT' -- https://www.sqlskills.com/help/waits/XE_TIMER_EVENT
        )
    AND [waiting_tasks_count] > 0
GO

/*** Collection job ***/

DECLARE @CREATE_JOB AS BINARY
SET @CREATE_JOB = 0

DECLARE @JOB_ID AS INT
DECLARE @frequency_type AS INT = 4 
DECLARE	@frequency_interval AS INT = 1
DECLARE	@frequency_subday_type AS INT = 0x2
DECLARE	@frequency_subday_interval AS INT = 10


USE msdb

IF @CREATE_JOB = 1
BEGIN
	IF EXISTS (SELECT NAME FROM msdb.dbo.sysjobs WHERE NAME = 'DBA_WaitStatsCollection')
	BEGIN
		EXEC sp_delete_job 
			@job_name = 'DBA_WaitStatsCollection'
	END
	
	IF EXISTS (SELECT NAME FROM sysschedules WHERE NAME = 'DBA_WaitStatsCollection Schedule')
	BEGIN
		EXEC sp_delete_schedule @schedule_name = 'DBA_WaitStatsCollection Schedule'
	END
		 
	EXEC dbo.sp_add_job  
	    @job_name = N'DBA_WaitStatsCollection'   
	 
	EXEC sp_add_jobstep  
	    @job_name = N'DBA_WaitStatsCollection',  
	    @step_name = N'Run script WaitStats', 
--------------------------------------------------------------------------------------------------------------------------
--!!!!!!!!!!!!!!! CHANGE THE DATABASE NAME IN THE NEXT COMMAND IF YOU WANT ANOTHER ONE FOR YOUR TABLES, VIEWS AND PROCEDURES !!!!!!!!!!!!!!!!!
--------------------------------------------------------------------------------------------------------------------------
	    @command = N'USE DBA EXEC usp_WaitStatsInsert' 
	
	EXEC dbo.sp_add_schedule  
	    @schedule_name = 'DBA_WaitStatsCollection Schedule',  
	    @freq_type = @frequency_type, 
		@freq_interval = @frequency_interval,
	    @freq_subday_type = @frequency_subday_type,
		@freq_subday_interval = @frequency_subday_interval
	
	EXEC sp_attach_schedule  
		@job_name = 'DBA_WaitStatsCollection',  
		@schedule_name = 'DBA_WaitStatsCollection Schedule' 
	  
	EXEC dbo.sp_add_jobserver  
	    @job_name = 'DBA_WaitStatsCollection'  
END



--------------------------------------------------------------------------------------------------------------------------
--RUN ME LATER:
--------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------
--!!!!!!!!!!!!!!! CHANGE THE DATABASE NAME IF YOU WANT ANOTHER ONE FOR YOUR TABLES, VIEWS AND PROCEDURES !!!!!!!!!!!!!!!!!
--------------------------------------------------------------------------------------------------------------------------

--USE DBA 
--SELECT  t.waitType,
--		max.waitingTasksCount - min.waitingTasksCount, 
--		max.waitTime_ms - min.waitTime_ms,
--		max.signalWaitTime_ms - min.signalWaitTime_ms
--FROM 
--(SELECT * FROM [dbo].[WaitStats]
--WHERE snapshotId = (SELECT MAX(snapshotId) FROM [dbo].[WaitStats])) as max
--INNER JOIN
--(SELECT * FROM [dbo].[WaitStats]
--WHERE snapshotId = (SELECT MIN(snapshotId) FROM [dbo].[WaitStats])) as min
--	ON min.idWaitType = max.idWaitType
--INNER JOIN [dbo].[WaitType] t
--	ON T.idWaitType = MAX.idWaitType --AND T.id_Wait_Type = MIN.id_Wait_Type
--ORDER BY 3 dESC

--SELECT	waitType,
--		waitingTasksCount - LAG(waitingTasksCount) OVER (ORDER BY waitType,snapshotId),
--		waitTime_ms - LAG(waitTime_ms) OVER (ORDER BY waitType,snapshotId),
--		signalWaitTime_ms - LAG(signalWaitTime_ms) OVER (ORDER BY waitType,snapshotId)
--FROM [dbo].[WaitStats] S
--INNER JOIN [dbo].[WaitType] T
--ON T.idWaitType = S.idWaitType
--ORDER BY waitType,snapshotId