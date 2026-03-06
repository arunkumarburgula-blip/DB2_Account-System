--================================================================--
--  DB2 DDL: COMPLETE SCHEMA FOR CUSTOMER ACCOUNT SYSTEM          --
--  DATABASE: CUSTDB                                               --
--  SUBSYSTEM: DB2P (PRODUCTION)                                   --
--                                                                  --
--  TABLESPACE STRATEGY:                                            --
--    TBCUST  - SEGMENTED TS, 32K PAGE, LOCKSIZE ROW               --
--    TBACCT  - SEGMENTED TS, 32K PAGE, LOCKSIZE ROW               --
--    TBTXN   - RANGE-PARTITIONED BY TXN_DATE (MONTHLY)            --
--                                                                  --
--  CHANGE LOG:                                                     --
--    2024-01-15  INITIAL CREATION                                  --
--    2024-04-20  ADDED TXN PARTITIONING                            --
--    2024-07-10  ADDED ACCOUNT SUMMARY VIEW                        --
--================================================================--

--================================================================--
--  DATABASE DEFINITION                                             --
--================================================================--
CREATE DATABASE CUSTDB
  STOGROUP SYSDEFLT
  BUFFERPOOL BP32K;

--================================================================--
--  TABLESPACE: CUSTOMER MASTER                                     --
--  SEGMENTED FOR MIXED ONLINE/BATCH ACCESS                        --
--  LOCKSIZE ROW REDUCES CONTENTION IN CICS                        --
--================================================================--
CREATE TABLESPACE TSCUST
  IN CUSTDB
  USING STOGROUP SYSDEFLT
  PRIQTY 5000
  SECQTY 1000
  SEGSIZE 64
  BUFFERPOOL BP32K
  LOCKSIZE ROW
  CLOSE YES
  COMPRESS YES;

--================================================================--
--  TABLE: TBCUST (CUSTOMER MASTER)                                 --
--================================================================--
CREATE TABLE TBCUST
  (CUST_ID          CHAR(10)        NOT NULL,
   LAST_NAME        VARCHAR(30)     NOT NULL,
   FIRST_NAME       VARCHAR(20)     NOT NULL,
   MIDDLE_INIT      CHAR(1)         DEFAULT ' ',
   SSN              CHAR(9)         NOT NULL,
   STATUS           CHAR(1)         NOT NULL
                    DEFAULT 'A'
                    WITH DEFAULT,
   DATE_OF_BIRTH    DATE,
   ADDR_LINE1       VARCHAR(30),
   ADDR_LINE2       VARCHAR(30),
   CITY             VARCHAR(20),
   STATE_CODE       CHAR(2),
   ZIP_CODE         CHAR(10),
   PHONE            CHAR(10),
   EMAIL            VARCHAR(50),
   CREDIT_SCORE     SMALLINT,
   RISK_RATING      CHAR(1)         DEFAULT 'M',
   CREATED_DATE     TIMESTAMP       NOT NULL
                    WITH DEFAULT CURRENT TIMESTAMP,
   CREATED_BY       VARCHAR(8)      NOT NULL,
   UPDATED_DATE     TIMESTAMP       NOT NULL
                    WITH DEFAULT CURRENT TIMESTAMP,
   UPDATED_BY       VARCHAR(8)      NOT NULL,
   PRIMARY KEY (CUST_ID))
  IN CUSTDB.TSCUST;

--================================================================--
--  TABLESPACE: ACCOUNT DETAIL                                      --
--================================================================--
CREATE TABLESPACE TSACCT
  IN CUSTDB
  USING STOGROUP SYSDEFLT
  PRIQTY 8000
  SECQTY 2000
  SEGSIZE 64
  BUFFERPOOL BP32K
  LOCKSIZE ROW
  CLOSE YES
  COMPRESS YES;

--================================================================--
--  TABLE: TBACCT (ACCOUNT DETAIL)                                  --
--  FOREIGN KEY TO TBCUST WITH ON DELETE RESTRICT                   --
--================================================================--
CREATE TABLE TBACCT
  (ACCT_NUMBER      CHAR(12)        NOT NULL,
   CUST_ID          CHAR(10)        NOT NULL,
   ACCT_TYPE        CHAR(2)         NOT NULL,
   ACCT_STATUS      CHAR(1)         NOT NULL
                    DEFAULT 'O',
   BALANCE          DECIMAL(15,2)   NOT NULL
                    DEFAULT 0,
   AVAIL_BALANCE    DECIMAL(15,2)   NOT NULL
                    DEFAULT 0,
   HOLD_AMOUNT      DECIMAL(13,2)   DEFAULT 0,
   INT_RATE         DECIMAL(9,6)    DEFAULT 0,
   YTD_INTEREST     DECIMAL(13,2)   DEFAULT 0,
   MTD_FEES         DECIMAL(11,2)   DEFAULT 0,
   OPEN_DATE        DATE            NOT NULL,
   CLOSE_DATE       DATE,
   LAST_ACTIVITY_DATE DATE,
   STMT_CYCLE_DAY   SMALLINT        DEFAULT 15,
   REGION_CODE      CHAR(3)         NOT NULL,
   BRANCH_CODE      CHAR(5)         NOT NULL,
   OFFICER_ID       CHAR(8),
   MTD_DEBITS       INTEGER         DEFAULT 0,
   MTD_CREDITS      INTEGER         DEFAULT 0,
   CREATED_DATE     TIMESTAMP       NOT NULL
                    WITH DEFAULT CURRENT TIMESTAMP,
   UPDATED_DATE     TIMESTAMP       NOT NULL
                    WITH DEFAULT CURRENT TIMESTAMP,
   PRIMARY KEY (ACCT_NUMBER),
   FOREIGN KEY FK_ACCT_CUST (CUST_ID)
     REFERENCES TBCUST (CUST_ID)
     ON DELETE RESTRICT)
  IN CUSTDB.TSACCT;

--================================================================--
--  TABLESPACE: TRANSACTION HISTORY (PARTITIONED BY MONTH)          --
--  RANGE PARTITIONING ENABLES EFFICIENT PURGE AND QUERY            --
--================================================================--
CREATE TABLESPACE TSTXN
  IN CUSTDB
  USING STOGROUP SYSDEFLT
  PRIQTY 20000
  SECQTY 5000
  BUFFERPOOL BP32K
  LOCKSIZE ROW
  COMPRESS YES
  NUMPARTS 12
  (PARTITION 1  ENDING('2024-01-31'),
   PARTITION 2  ENDING('2024-02-29'),
   PARTITION 3  ENDING('2024-03-31'),
   PARTITION 4  ENDING('2024-04-30'),
   PARTITION 5  ENDING('2024-05-31'),
   PARTITION 6  ENDING('2024-06-30'),
   PARTITION 7  ENDING('2024-07-31'),
   PARTITION 8  ENDING('2024-08-31'),
   PARTITION 9  ENDING('2024-09-30'),
   PARTITION 10 ENDING('2024-10-31'),
   PARTITION 11 ENDING('2024-11-30'),
   PARTITION 12 ENDING('2024-12-31'));

--================================================================--
--  TABLE: TBTXN (TRANSACTION HISTORY)                              --
--================================================================--
CREATE TABLE TBTXN
  (TXN_ID           CHAR(15)        NOT NULL,
   ACCT_NUMBER      CHAR(12)        NOT NULL,
   TXN_DATE         DATE            NOT NULL,
   TXN_TIME         TIME            NOT NULL,
   TXN_TYPE         CHAR(3)         NOT NULL,
   TXN_AMOUNT       DECIMAL(13,2)   NOT NULL,
   RUNNING_BALANCE  DECIMAL(15,2),
   DESCRIPTION      VARCHAR(50),
   REFERENCE_NUM    CHAR(20),
   CHANNEL          CHAR(3),
   TERMINAL_ID      CHAR(8),
   BATCH_ID         CHAR(10),
   CREATED_DATE     TIMESTAMP       NOT NULL
                    WITH DEFAULT CURRENT TIMESTAMP,
   PRIMARY KEY (TXN_ID),
   FOREIGN KEY FK_TXN_ACCT (ACCT_NUMBER)
     REFERENCES TBACCT (ACCT_NUMBER)
     ON DELETE CASCADE)
  IN CUSTDB.TSTXN;

--================================================================--
--  INDEXES                                                         --
--================================================================--

-- CUSTOMER: NAME SEARCH (COVERING INDEX)
CREATE INDEX IX_CUST_NAME
  ON TBCUST (LAST_NAME, FIRST_NAME)
  USING STOGROUP SYSDEFLT
  BUFFERPOOL BP32K
  CLOSE YES;

-- CUSTOMER: SSN LOOKUP (UNIQUE)
CREATE UNIQUE INDEX IX_CUST_SSN
  ON TBCUST (SSN)
  USING STOGROUP SYSDEFLT
  CLOSE YES;

-- ACCOUNT: CUSTOMER FK (CLUSTERING)
CREATE INDEX IX_ACCT_CUST
  ON TBACCT (CUST_ID)
  CLUSTER
  USING STOGROUP SYSDEFLT
  BUFFERPOOL BP32K
  CLOSE YES;

-- ACCOUNT: BRANCH/REGION LOOKUP
CREATE INDEX IX_ACCT_BRANCH
  ON TBACCT (REGION_CODE, BRANCH_CODE, ACCT_STATUS)
  USING STOGROUP SYSDEFLT
  CLOSE YES;

-- TRANSACTION: ACCOUNT + DATE (CLUSTERING, PARTITIONED)
CREATE INDEX IX_TXN_ACCT_DATE
  ON TBTXN (ACCT_NUMBER, TXN_DATE DESC)
  CLUSTER
  PARTITIONED
  USING STOGROUP SYSDEFLT
  BUFFERPOOL BP32K
  CLOSE YES;

-- TRANSACTION: DATE ONLY (FOR BATCH REPORTS)
CREATE INDEX IX_TXN_DATE
  ON TBTXN (TXN_DATE)
  PARTITIONED
  USING STOGROUP SYSDEFLT
  CLOSE YES;

--================================================================--
--  VIEW: ACCOUNT SUMMARY WITH AGGREGATES                          --
--================================================================--
CREATE VIEW VWACTSM
  (CUST_ID, CUST_NAME, TOTAL_ACCOUNTS, TOTAL_BALANCE,
   AVG_BALANCE, MAX_BALANCE, OLDEST_ACCOUNT)
AS
  SELECT C.CUST_ID,
         C.LAST_NAME CONCAT ', ' CONCAT C.FIRST_NAME,
         COUNT(*),
         SUM(A.BALANCE),
         AVG(A.BALANCE),
         MAX(A.BALANCE),
         MIN(A.OPEN_DATE)
  FROM   TBCUST C
  INNER JOIN TBACCT A
    ON   C.CUST_ID = A.CUST_ID
  WHERE  A.ACCT_STATUS = 'O'
  GROUP BY C.CUST_ID,
           C.LAST_NAME CONCAT ', ' CONCAT C.FIRST_NAME;

--================================================================--
--  GRANTS                                                          --
--================================================================--
GRANT SELECT, INSERT, UPDATE, DELETE
  ON TBCUST TO PLAN CUSTPLAN;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON TBACCT TO PLAN CUSTPLAN;

GRANT SELECT, INSERT
  ON TBTXN TO PLAN CUSTPLAN;

GRANT SELECT
  ON VWACTSM TO PLAN CUSTPLAN;
