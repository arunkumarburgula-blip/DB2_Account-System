//DB2BIND  JOB (ACCT001,'DB2-SYS'),
//            'DB2 BIND',
//            CLASS=A,
//            MSGCLASS=X,
//            NOTIFY=&SYSUID
//*
//*================================================================*
//*  JOB  : DB2BIND                                                 *
//*  DESC : BIND PACKAGE AND PLAN FOR CUSTOMER ACCOUNT SYSTEM       *
//*                                                                  *
//*  BIND STRATEGY:                                                  *
//*    - BIND PACKAGE PER PROGRAM (MODULAR, INDEPENDENT REBIND)     *
//*    - BIND PLAN INCLUDES ALL PACKAGES (SINGLE EXEC UNIT)        *
//*    - EXPLAIN(YES) POPULATES PLAN_TABLE FOR ANALYSIS             *
//*    - ISOLATION(CS) DEFAULT FOR ONLINE, (RR) FOR BATCH REPORTS   *
//*                                                                  *
//*  WHEN TO REBIND:                                                 *
//*    - AFTER PROGRAM RECOMPILE (NEW DBRM)                        *
//*    - AFTER RUNSTATS (NEW STATISTICS MAY CHANGE ACCESS PATH)    *
//*    - AFTER INDEX ADD/DROP                                       *
//*    - AFTER DB2 VERSION MIGRATION                                *
//*================================================================*
//*
//  SET DB2SYS=DB2P
//  SET DBRMLIB='PROD.DB2.DBRMLIB'
//*
//*================================================================*
//*  STEP010 - BIND PACKAGES (ONE PER PROGRAM)                     *
//*  PACKAGE = SQL ACCESS PATH FOR ONE PROGRAM                      *
//*  CAN BE REBOUND INDEPENDENTLY WITHOUT AFFECTING OTHERS          *
//*================================================================*
//STEP010  EXEC PGM=IKJEFT01,DYNAMNBR=20
//STEPLIB  DD DSN=DB2.&DB2SYS..RUNLIB.LOAD,DISP=SHR
//DBRMLIB  DD DSN=&DBRMLIB,DISP=SHR
//SYSTSPRT DD SYSOUT=*
//SYSPRINT DD SYSOUT=*
//SYSTSIN  DD *
  DSN SYSTEM(&DB2SYS)
  BIND PACKAGE(CUSTCOLL)                 -
       MEMBER(DBCUST01)                  -
       QUALIFIER(PROD)                   -
       OWNER(PRODUSER)                   -
       ACTION(REPLACE)                   -
       VALIDATE(BIND)                    -
       ISOLATION(CS)                     -
       RELEASE(COMMIT)                   -
       EXPLAIN(YES)                      -
       CURRENTDATA(NO)                   -
       ENCODING(EBCDIC)
  BIND PACKAGE(CUSTCOLL)                 -
       MEMBER(DBACCT01)                  -
       QUALIFIER(PROD)                   -
       OWNER(PRODUSER)                   -
       ACTION(REPLACE)                   -
       VALIDATE(BIND)                    -
       ISOLATION(CS)                     -
       RELEASE(COMMIT)                   -
       EXPLAIN(YES)                      -
       CURRENTDATA(NO)
  BIND PACKAGE(CUSTCOLL)                 -
       MEMBER(DBTXN01)                   -
       QUALIFIER(PROD)                   -
       OWNER(PRODUSER)                   -
       ACTION(REPLACE)                   -
       VALIDATE(BIND)                    -
       ISOLATION(CS)                     -
       RELEASE(COMMIT)                   -
       EXPLAIN(YES)                      -
       CURRENTDATA(NO)
  BIND PACKAGE(CUSTCOLL)                 -
       MEMBER(DBRPT01)                   -
       QUALIFIER(PROD)                   -
       OWNER(PRODUSER)                   -
       ACTION(REPLACE)                   -
       VALIDATE(BIND)                    -
       ISOLATION(RR)                     -
       RELEASE(DEALLOCATE)               -
       EXPLAIN(YES)                      -
       CURRENTDATA(YES)
  END
/*
//*
//*================================================================*
//*  STEP020 - BIND PLAN (INCLUDES ALL PACKAGES)                   *
//*  PLAN = EXECUTION UNIT REFERENCED BY RUN PROGRAM               *
//*================================================================*
//STEP020  EXEC PGM=IKJEFT01,
//         DYNAMNBR=20,
//         COND=(4,LT,STEP010)
//STEPLIB  DD DSN=DB2.&DB2SYS..RUNLIB.LOAD,DISP=SHR
//SYSTSPRT DD SYSOUT=*
//SYSPRINT DD SYSOUT=*
//SYSTSIN  DD *
  DSN SYSTEM(&DB2SYS)
  BIND PLAN(CUSTPLAN)                    -
       PKLIST(CUSTCOLL.DBCUST01,         -
              CUSTCOLL.DBACCT01,         -
              CUSTCOLL.DBTXN01,          -
              CUSTCOLL.DBRPT01)          -
       QUALIFIER(PROD)                   -
       OWNER(PRODUSER)                   -
       ACTION(REPLACE)                   -
       VALIDATE(BIND)                    -
       ISOLATION(CS)                     -
       RELEASE(COMMIT)                   -
       ACQUIRE(USE)
  END
/*
//*
//*================================================================*
//*  STEP030 - DISPLAY EXPLAIN OUTPUT (ACCESS PATHS)                *
//*================================================================*
//STEP030  EXEC PGM=IKJEFT01,
//         DYNAMNBR=20,
//         COND=(4,LT)
//STEPLIB  DD DSN=DB2.&DB2SYS..RUNLIB.LOAD,DISP=SHR
//SYSTSPRT DD SYSOUT=*
//SYSPRINT DD SYSOUT=*
//SYSTSIN  DD *
  DSN SYSTEM(&DB2SYS)
  RUN PROGRAM(DSNTEP2) PLAN(DSNTEP12)
  END
//SYSIN    DD *
  SELECT PROGNAME,
         QUERYNO,
         QBLOCKNO,
         PLANNO,
         METHOD,
         TNAME,
         ACCESSTYPE,
         MATCHCOLS,
         ACCESSNAME,
         INDEXONLY,
         PREFETCH,
         SORTC_UNIQ,
         SORTC_JOIN,
         SORTC_ORDERBY
  FROM   PLAN_TABLE
  WHERE  QUERYNO > 0
    AND  COLLID = 'CUSTCOLL'
  ORDER BY PROGNAME,
           QUERYNO,
           QBLOCKNO,
           PLANNO;
/*
//
