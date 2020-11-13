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



