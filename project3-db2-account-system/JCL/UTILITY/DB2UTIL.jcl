//DB2UTIL  JOB (ACCT001,'DB2-SYS'),
//            'DB2 UTILITIES',
//            CLASS=A,
//            MSGCLASS=X,
//            NOTIFY=&SYSUID,
//            TIME=(2,0)
//*
//*================================================================*
//*  JOB  : DB2UTIL                                                 *
//*  DESC : DB2 UTILITY EXECUTION                                   *
//*         RUNSTATS, REORG, COPY, RECOVER                          *
//*  SCHED: WEEKLY SUNDAY BATCH WINDOW                              *
//*================================================================*
//*
//  SET DB2SYS=DB2P
//  SET UTILID=DBUTIL01
//*
//*================================================================*
//*  STEP010 - RUNSTATS ON ALL TABLESPACES AND INDEXES              *
//*  UPDATES CATALOG STATISTICS FOR OPTIMIZER DECISIONS              *
//*  SHRLEVEL(REFERENCE) ALLOWS CONCURRENT READS                    *
//*================================================================*
//STEP010  EXEC PGM=DSNUTILB,
//         PARM='&DB2SYS,&UTILID.RS'
//STEPLIB  DD DSN=DB2.&DB2SYS..RUNLIB.LOAD,DISP=SHR
//SYSPRINT DD SYSOUT=*
//SYSIN    DD *
  RUNSTATS TABLESPACE CUSTDB.TSCUST
    TABLE(ALL)
    INDEX(ALL)
    SHRLEVEL(REFERENCE)
    REPORT YES
    UPDATE ALL
    HISTORY ALL

  RUNSTATS TABLESPACE CUSTDB.TSACCT
    TABLE(ALL)
    INDEX(ALL)
    SHRLEVEL(REFERENCE)
    REPORT YES
    UPDATE ALL

  RUNSTATS TABLESPACE CUSTDB.TSTXN
    TABLE(ALL)
    INDEX(ALL)
    SHRLEVEL(REFERENCE)
    REPORT YES
    UPDATE ALL
    HISTORY ALL
/*
//*
//*================================================================*
//*  STEP020 - IMAGE COPY (FULL) FOR ALL TABLESPACES               *
//*  REQUIRED BEFORE POINT-IN-TIME RECOVERY                         *
//*================================================================*
//STEP020  EXEC PGM=DSNUTILB,
//         PARM='&DB2SYS,&UTILID.CP',
//         COND=(4,LT,STEP010)
//STEPLIB  DD DSN=DB2.&DB2SYS..RUNLIB.LOAD,DISP=SHR
//SYSPRINT DD SYSOUT=*
//SYSCOPY1 DD DSN=PROD.DB2.COPY.TSCUST,
//            DISP=(NEW,CATLG,DELETE),
//            UNIT=SYSDA,
//            SPACE=(CYL,(500,100),RLSE)
//SYSCOPY2 DD DSN=PROD.DB2.COPY.TSACCT,
//            DISP=(NEW,CATLG,DELETE),
//            UNIT=SYSDA,
//            SPACE=(CYL,(800,200),RLSE)
//SYSCOPY3 DD DSN=PROD.DB2.COPY.TSTXN,
//            DISP=(NEW,CATLG,DELETE),
//            UNIT=SYSDA,
//            SPACE=(CYL,(2000,500),RLSE)
//SYSIN    DD *
  COPY TABLESPACE CUSTDB.TSCUST
    FULL YES
    SHRLEVEL REFERENCE
    COPYDDN(SYSCOPY1)

  COPY TABLESPACE CUSTDB.TSACCT
    FULL YES
    SHRLEVEL REFERENCE
    COPYDDN(SYSCOPY2)

  COPY TABLESPACE CUSTDB.TSTXN
    FULL YES
    SHRLEVEL REFERENCE
    COPYDDN(SYSCOPY3)
/*
//*
//*================================================================*
//*  STEP030 - REORG TABLESPACE WITH INLINE COPY AND STATS         *
//*  REORGANIZES DATA PAGES TO MATCH CLUSTERING INDEX ORDER         *
//*  INLINE COPY ELIMINATES NEED FOR SEPARATE COPY STEP             *
//*================================================================*
//STEP030  EXEC PGM=DSNUTILB,
//         PARM='&DB2SYS,&UTILID.RG',
//         COND=(4,LT,STEP020)
//STEPLIB  DD DSN=DB2.&DB2SYS..RUNLIB.LOAD,DISP=SHR
//SYSPRINT DD SYSOUT=*
//SYSREC   DD UNIT=SYSDA,SPACE=(CYL,(1000,200))
//SORTOUT  DD UNIT=SYSDA,SPACE=(CYL,(500,100))
//SORTWK01 DD UNIT=SYSDA,SPACE=(CYL,(200))
//SORTWK02 DD UNIT=SYSDA,SPACE=(CYL,(200))
//SYSCOPY  DD DSN=PROD.DB2.COPY.TSTXN.REORG,
//            DISP=(NEW,CATLG,DELETE),
//            UNIT=SYSDA,
//            SPACE=(CYL,(2000,500),RLSE)
//SYSIN    DD *
  REORG TABLESPACE CUSTDB.TSTXN
    LOG YES
    SHRLEVEL NONE
    STATISTICS TABLE(ALL) INDEX(ALL)
    COPYDDN(SYSCOPY)
    DRAIN_WAIT 120
    RETRY 3
    RETRY_DELAY 60
/*
//*
//*================================================================*
//*  STEP040 - RECOVER (COMMENTED - USE IN EMERGENCY ONLY)          *
//*  POINT-IN-TIME RECOVERY USING IMAGE COPY + LOGS                 *
//*================================================================*
//*STEP040 EXEC PGM=DSNUTILB,
//*        PARM='&DB2SYS,&UTILID.RC'
//*STEPLIB DD DSN=DB2.&DB2SYS..RUNLIB.LOAD,DISP=SHR
//*SYSPRINT DD SYSOUT=*
//*SYSCOPY DD DSN=PROD.DB2.COPY.TSTXN,DISP=SHR
//*SYSIN   DD *
//* RECOVER TABLESPACE CUSTDB.TSTXN
//*   TOLOGPOINT X'00000ABCDEF12345'
//*   TOCOPY DSNUM(ALL)
//
