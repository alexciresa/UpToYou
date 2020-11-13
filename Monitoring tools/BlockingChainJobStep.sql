DECLARE @id int

SELECT @id = ISNULL(MAX(snapshot_id),0) FROM BlockingChain

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