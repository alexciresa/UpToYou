--SECTIUNEA INTRE '*' CONTINE VARIABILE CE TREBUIE INITIALIZATE IN FUNCTIE DE CONTEXT 
--******************************* 
DECLARE @DB_NAME varchar(50)

SET @DB_NAME = 'ISIS_D'

--******************************* 
DECLARE @SQL_VERSION varchar(1000)

SET @SQL_VERSION = '1. SQL Server Version and Service Pack level -> '

DECLARE @WINDOWS_VERSION varchar(1000)

SET @WINDOWS_VERSION = '2. Windows version -> '

DECLARE @RTO varchar(1000)

SET @RTO = '3. RTO (Recovery Time Objective) -> '

DECLARE @RPO varchar(1000)

SET @RPO =
'4. RPO (Recovery Point Objective) -> '

DECLARE @CHECKDB varchar(1000)

SET @CHECKDB =
'5. CHECKDB (Database consistency check) -> last clean DBCC check -> '

DECLARE @INDEX_FRAGM varchar(1000)

SET @INDEX_FRAGM = '6. Index fragmentation -> '

DECLARE @MAINTENANCE_JOB varchar(1000)

SET @MAINTENANCE_JOB =
'7. Maintenance jobs (Index reorg/rebuild, update statistics) '

DECLARE @FILES_SEGREGATION varchar(1000)

SET @FILES_SEGREGATION =
'8. SQL Server binary, data and log files segregation: '

DECLARE @HA_DR varchar(1000)

SET @HA_DR = '9. HA and DR: '

DECLARE @DB_SIZE varchar(50)

SET @DB_SIZE = '10. Database size -> '

DECLARE @LOG_SIZE varchar(50)

SET @LOG_SIZE = '11. Log file size -> '

--1. 
SELECT
  @SQL_VERSION += SUBSTRING(@@VERSION, 1, CHARINDEX('X', @@VERSION, 1) + 3)
--2. 
SELECT
  @WINDOWS_VERSION += SUBSTRING(@@VERSION, CHARINDEX(' on ', @@VERSION, 1)
  + 4,
  CHARINDEX('(', @@VERSION, 1) + 1)
--3.
DECLARE @EXISTS_DIFF AS int
DECLARE @rtoTemp AS int
DECLARE @FULL AS int
DECLARE @LOG AS int
SET @EXISTS_DIFF = (SELECT
  MAX(DATEDIFF(MINUTE, backup_start_date, backup_finish_date))
FROM msdb..backupset
WHERE database_name = @db_name
AND TYPE = 'I'
AND DATEDIFF(MONTH, BACKUP_START_DATE, GETDATE()) <= 2)
SET @FULL = (SELECT
  MAX(DATEDIFF(MINUTE, backup_start_date, backup_finish_date))
FROM msdb..backupset
WHERE database_name = @db_name
AND TYPE = 'D'
AND DATEDIFF(MONTH, BACKUP_START_DATE, GETDATE()) <= 2)
IF @EXISTS_DIFF IS NOT NULL --E DIFF
BEGIN
  SET @LOG = (SELECT
    SUM(DATEDIFF(MINUTE, backup_start_date, backup_finish_date))
  FROM msdb..backupset
  WHERE database_name = @db_name
  AND TYPE = 'L'
  AND backup_finish_date >= (SELECT TOP 1
    backup_finish_date
  FROM msdb..backupset
  WHERE database_name = @db_name
  AND TYPE = 'I'
  ORDER BY backup_finish_date DESC))
  SET @rtoTemp = @FULL + @EXISTS_DIFF + ISNULL(@LOG, 0)
END
ELSE
IF @FULL IS NOT NULL
BEGIN --NU E DIFF
  SET @LOG = ((SELECT
    SUM(DATEDIFF(MINUTE, backup_start_date, backup_finish_date))
  FROM msdb..backupset
  WHERE database_name = @db_name
  AND TYPE = 'L'
  AND DATEDIFF(MONTH, BACKUP_START_DATE, GETDATE()) <= 2
  AND backup_finish_date >= (SELECT TOP 1
    backup_finish_date
  FROM msdb..backupset
  WHERE database_name = @db_name
  AND TYPE = 'D'
  AND DATEDIFF(MONTH, BACKUP_START_DATE, GETDATE()) <= 2
  ORDER
  BY backup_finish_date DESC))
  )
  SET @rtoTemp = @FULL + ISNULL(@LOG, 0)
END
IF @FULL IS NULL
  SELECT
    @RTO += 'NO BACKUPS FOUND'
ELSE
  SELECT
    @RTO += ('1h ' + CAST(@rtoTemp AS varchar(30)) + 'min (includes SQL Server installation and configuration, database restore and recovery)')
--4. --only for FullBackup Restore 
DECLARE @RPOtemp int
SELECT TOP 1
  @RPOtemp = (DATEDIFF(MINUTE, backup_finish_date, (LAG(backup_finish_date, 1, 0) OVER (
  ORDER BY backup_finish_date DESC))))
FROM msdb..backupset
WHERE database_name = @db_name AND DATEDIFF(MONTH, BACKUP_START_DATE, GETDATE()) <= 2
ORDER BY 1 DESC
SELECT
  @RPO += IIF(@RPOtemp IS NULL, 'NO BACKUPS FOUND', ('maximum data lost in case of server failure is ' + CAST(@RPOtemp AS varchar(30)) + 'min'))
--5. --last check db 
DECLARE @QUERY varchar(60)
SELECT
  @QUERY = 'DBCC dbinfo(' + @DB_NAME + ') WITH tableresults'
DECLARE @dbinfo TABLE (
  parentobject varchar(255),
  [object] varchar(255),
  [field] varchar(255),
  [value] varchar(255)
)
INSERT INTO @dbinfo EXECUTE (@QUERY)
SELECT
  @CHECKDB +=
  ISNULL(value, 0)
FROM @dbinfo
WHERE field = 'dbi_dbccLastKnownGood'
--6.
SELECT
  @INDEX_FRAGM +=
  CAST(COUNT(*) AS varchar(10)) + ' highly fragmented indexes'
FROM sys.DM_DB_INDEX_PHYSICAL_STATS(DB_ID(@DB_NAME), NULL
, NULL,
NULL, NULL)
WHERE avg_fragmentation_in_percent >= 30
AND page_count > 1000
--7. 
DECLARE @TRUEidx AS varchar(100)
DECLARE @TRUEstat AS varchar(100)
DECLARE @INDEX_JOB varchar(100)
DECLARE @STATISTICS_JOB varchar(100)

SET @INDEX_JOB = '-> Index rebuild/reorg job -> '
SET @STATISTICS_JOB = '-> Statistics update job -> '

SELECT
  @TRUEidx = j.NAME
FROM msdb..sysjobs j
INNER JOIN msdb..sysjobhistory h
  ON H.job_id = J.job_id
INNER JOIN msdb..sysjobschedules JS
  ON JS.job_id = J.job_id
INNER JOIN msdb..sysschedules S
  ON S.schedule_id = JS.schedule_id
WHERE J.NAME LIKE '%index%'
AND h.message LIKE '%The step succeeded%'
AND j.enabled = 1

SELECT
  @TRUEstat = j.NAME
FROM msdb..sysjobs j
INNER JOIN msdb..sysjobhistory h
  ON H.job_id = J.job_id
INNER JOIN msdb..sysjobschedules JS
  ON JS.job_id = J.job_id
INNER JOIN msdb..sysschedules S
  ON S.schedule_id = JS.schedule_id
WHERE J.NAME LIKE '%statistic%'
AND h.message LIKE '%The step succeeded%'
AND j.enabled = 1

SELECT
  @STATISTICS_JOB += ISNULL(@TRUEstat, 'NO JOB FOUND')
SELECT
  @INDEX_JOB += ISNULL(@TRUEidx, 'NO JOB FOUND')
DECLARE @LAST_STATISTICS_UPDATE varchar(100)
DECLARE @LAST varchar(30)
USE ISIS_D
SELECT TOP 1
  @LAST = CAST(last_updated AS varchar(30))
FROM SYS.STATS
CROSS APPLY sys.Dm_db_stats_properties(statS.object_id, statS.stats_id) AS sp
WHERE SYS.STATS.object_id IN (SELECT
  object_id
FROM SYS.OBJECTS
WHERE type_desc IN ('VIEW', 'USER_TABLE'))
ORDER BY 1 DESC
SET @LAST_STATISTICS_UPDATE = '-> Last statistics update -> ' + ISNULL(@LAST, 'NO STATISTICS UPDATE FOUND')
USE master
--8. 
DECLARE @FILE_MDF varchar(500)
DECLARE @FILE_LDF varchar(500)
DECLARE @FILE_BCKUPS varchar(500)
DECLARE @FILE_BINARY varchar(500)
DECLARE @FILE_BACKUPS_PATH varchar(500)
SET @FILE_MDF = '  ->mdf -> '
SET @FILE_LDF = '	->ldf -> '
SET @FILE_BCKUPS = '	->backups -> '
SET @FILE_BINARY = '	->binary -> '

SELECT
  @FILE_MDF += (SELECT
    physical_name
  FROM sys.master_files
  WHERE DB_NAME(database_id) = @DB_NAME
  AND physical_name LIKE '%.mdf')

SELECT
  @FILE_LDF += (SELECT
    physical_name
  FROM sys.master_files
  WHERE DB_NAME(database_id) = @DB_NAME
  AND physical_name LIKE '%.ldf')
DECLARE @path nvarchar(100)
DECLARE @instance_name nvarchar(100)
DECLARE @instance_name1 nvarchar(100)
DECLARE @system_instance_name nvarchar(100)
DECLARE @key nvarchar(1000)

SET @instance_name = COALESCE(CONVERT(nvarchar(100),
SERVERPROPERTY('InstanceName')), 'MSSQLSERVER');

IF @instance_name != 'MSSQLSERVER'
  SET @instance_name = @instance_name

SET @instance_name1 = COALESCE(CONVERT(nvarchar(100),
SERVERPROPERTY('InstanceName')), 'MSSQLSERVER');

IF @instance_name1 != 'MSSQLSERVER'
  SET @instance_name1 = 'MSSQL$' + @instance_name1

EXEC master.dbo.Xp_regread N'HKEY_LOCAL_MACHINE',
                           N'Software\Microsoft\Microsoft SQL Server\Instance Names\SQL',
                           @instance_name,
                           @system_instance_name OUTPUT;

SET @key = N'SYSTEM\CurrentControlSet\Services\'
+ @instance_name1;

EXEC master.dbo.Xp_regread 'HKEY_LOCAL_MACHINE',
                           @key,
                           @value_name = 'ImagePath',
                           @value = @path OUTPUT

SELECT
  @FILE_BINARY += @PATH

SELECT TOP 1
  @FILE_BACKUPS_PATH = physical_device_name
FROM msdb..backupmediafamily S
INNER JOIN msdb..backupmediaset F
  ON S.media_set_id = F.media_set_id
INNER JOIN msdb..backupset B
  ON b.media_set_id = f.media_set_id
WHERE database_name = @DB_NAME
ORDER BY BACKUP_FINISH_DATE DESC
SELECT
  @FILE_BCKUPS += ISNULL(@FILE_BACKUPS_PATH, 'NO PATH FOUND')

--9. --search for cluster/availability groups  
DECLARE @CLUSTER varchar(500)
DECLARE @AVAILABILITY_GROUPS varchar(500)
DECLARE @MIRROR varchar(500)
DECLARE @AVAILABILITY_GROUPS_CK varchar(500)
DECLARE @MIRROR_CK varchar(500)
DECLARE @MIRROR_CK2 varchar(500)

SET @CLUSTER = '-> CLUSTER -> '
SET @AVAILABILITY_GROUPS = '-> AVAILABILITY GROUPS -> '
SET @MIRROR = '-> MIRRORING -> '


SELECT
  @AVAILABILITY_GROUPS_CK = AGDatabases.group_id
FROM sys.availability_databases_cluster
AGDatabases
WHERE AGDatabases.database_name = @DB_NAME
IF @AVAILABILITY_GROUPS_CK IS NULL
  SELECT
    @AVAILABILITY_GROUPS += 'NONE FOUND'
ELSE
  SELECT
    @AVAILABILITY_GROUPS += 'GROUP FOUND - ID: ' + @AVAILABILITY_GROUPS_CK
IF SERVERPROPERTY('IsCluster') = 1
  SELECT
    @CLUSTER += 'True'
ELSE
  SELECT
    @CLUSTER += 'False'

SELECT
  @MIRROR_CK = mirroring_partner_name
FROM sys.database_mirroring
WHERE database_id = DB_ID(@DB_NAME)

SELECT
  @MIRROR_CK2 += ' -> '

SELECT
  @MIRROR_CK2 = mirroring_state_desc
FROM sys.database_mirroring
WHERE database_id = DB_ID(@DB_NAME)

SELECT
  @MIRROR += ISNULL(@MIRROR_CK, 'NO PARTNER FOUND') + ' ' + ISNULL(@MIRROR_CK2, 'NO SYNCHRONIZATION FOUND')
--10. 
SELECT TOP 1
  @DB_SIZE += CAST(SUM(m.size * 8 / 1024)
  OVER (
  PARTITION BY d.NAME) AS varchar(30)) + 'MB'
FROM sys.master_files m
INNER JOIN sys.databases d
  ON d.database_id = m.database_id
WHERE d.NAME = @DB_NAME
--11.
SELECT
  @LOG_SIZE += CAST((size * 8) / 1024 AS varchar(30)) + 'MB'
FROM sys.master_files
WHERE DB_NAME(database_id) = @DB_NAME
AND physical_name LIKE '%.ldf'

PRINT 'Raport SQL Server -> Database ' + @DB_NAME

PRINT @SQL_VERSION

PRINT @WINDOWS_VERSION

PRINT @RTO

PRINT @RPO

PRINT @CHECKDB

PRINT @INDEX_FRAGM

PRINT @MAINTENANCE_JOB

PRINT @LAST_STATISTICS_UPDATE

PRINT @STATISTICS_JOB

PRINT @INDEX_JOB

PRINT @FILES_SEGREGATION

PRINT @FILE_MDF

PRINT @FILE_LDF

PRINT @FILE_BCKUPS

PRINT @FILE_BINARY

PRINT @HA_DR

PRINT @AVAILABILITY_GROUPS

PRINT @CLUSTER

PRINT @MIRROR

PRINT @DB_SIZE

PRINT @LOG_SIZE

GO