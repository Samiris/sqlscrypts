USE TemplateDB
GO

-- create master key
CREATE MASTER KEY ENCRYPTION
BY PASSWORD = 'A@#abcd@#abcd'
GO
-- symmetric key used to protect certificates private keys and asymmetric keys


-- create certificate
CREATE CERTIFICATE ApplicationSecurityCertificate
ENCRYPTION BY PASSWORD = 'certA@#abcd@#abcd'
WITH SUBJECT = 'Application Security Certificate'--, EXPIRY_DATE = '20501031'
GO

-- create symetric key
CREATE SYMMETRIC KEY Key_AppName
WITH ALGORITHM = AES_256
ENCRYPTION BY CERTIFICATE ApplicationSecurityCertificate

-- change cert password
-- ALTER CERTIFICATE ApplicationSecurityCertificate WITH PRIVATE KEY (DECRYPTION BY PASSWORD = 'newPass');

--select databases with master key
SELECT * FROM SYS.DATABASES WHERE [is_master_key_encrypted_by_server] = 1


--select master certificates and symetric key
SELECT * FROM master.SYS.CERTIFICATES
SELECT * FROM master.SYS.SYMMETRIC_KEYS

--select master certificates and symetric key
SELECT * FROM TemplateDB.SYS.CERTIFICATES
SELECT * FROM TemplateDB.SYS.SYMMETRIC_KEYS


-- Sample Usage 
USE TemplateDB
GO
DROP TABLE IF EXISTS dbo.SecureTable
CREATE TABLE dbo.SecureTable(
					    id INT IDENTITY(1,1)
					  , [Login] VARCHAR(50) NOT NULL
					  , [Password] VARBINARY (MAX) NOT NULL
					   )
GO

-- Encryption
-- Open key
OPEN SYMMETRIC KEY Key_AppName
DECRYPTION BY CERTIFICATE ApplicationSecurityCertificate WITH PASSWORD = 'certA@#abcd@#abcd'

DECLARE @GUID UNIQUEIDENTIFIER
SET @GUID = (SELECT CONVERT(VARCHAR(36), NEWID()))

INSERT dbo.SecureTable ([Login], [Password]) VALUES ('User', ENCRYPTBYKEY(KEY_GUID('Key_AppName'), 'pass123'))
GO

-- Close key
CLOSE SYMMETRIC KEY Key_AppName

SELECT * FROM dbo.SecureTable

-- Decrypt
-- Open key
OPEN SYMMETRIC KEY Key_AppName
DECRYPTION BY CERTIFICATE ApplicationSecurityCertificate WITH PASSWORD = 'certA@#abcd@#abcd'
GO

SELECT *, CAST(DECRYPTBYKEY([Password]) AS VARCHAR(MAX)) AS DecryptPassword
FROM dbo.SecureTable
GO

-- Close key
CLOSE SYMMETRIC KEY Key_AppName


USE TemplateDB
GO

--SELECT @@SERVERNAME AS 'Server Name',  physical_name AS 'Database File Path', name AS 'Database Name',  type_desc AS 'Database Type',  state_desc AS 'Database State'FROM sys.master_files WHERE state_desc = 'ONLINE' and name = 'TemplateDB'

-- backup (.CER) and (.KEY)
BACKUP CERTIFICATE ApplicationSecurityCertificate TO FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Backup\CERFile_ApplicationSecurityCertificate.CER' 
WITH PRIVATE KEY -- optional (but recommended)
    (  
    FILE = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Backup\KEYFile_ApplicationSecurityCertificate.KEY'
    , ENCRYPTION BY PASSWORD = 'certA@#abcd@#abcd'
    , DECRYPTION BY PASSWORD = 'certA@#abcd@#abcd'
    )

--use master
--SELECT @@version
--SELECT name, value, value_in_use, minimum, maximum, [description], is_dynamic, is_advanced FROM sys.configurations WHERE name = 'xp_cmdshell';
--GO
--EXEC sp_configure 'show advanced options', 1; 
--GO 
--RECONFIGURE;
--GO
--EXEC sp_configure 'xp_cmdshell', 1;
--GO
--RECONFIGURE;
--GO

-- list dir
    DECLARE @Path VARCHAR(255)
	    , @sqlcommand VARCHAR(8000) 
    
    SET @Path = 'C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\Backup\'
    SET @sqlcommand = 'dir/ -C /4 /N "' + @Path + '"'
    -- SELECT @sqlcommand

    EXEC master.dbo.XP_CMDSHELL @command_string = @sqlcommand






