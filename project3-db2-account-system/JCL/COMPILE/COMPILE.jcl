//DB2COMP  JOB (ACCT001,'DB2-SYS'),
//            'DB2 COMPILE',
//            CLASS=A,
//            MSGCLASS=X,
//            MSGLEVEL=(1,1),
//            NOTIFY=&SYSUID
//*
//*================================================================*
//*  JOB  : DB2COMP                                                 *
//*  DESC : FULL DB2-COBOL COMPILE WORKFLOW                         *
//*         PRECOMPILE → COMPILE → LINK-EDIT                        *
//*                                                                  *
//*  THE DBRM PRODUCED IN STEP010 MUST BE BOUND SEPARATELY          *
//*  VIA BINDJCL BEFORE PROGRAM CAN EXECUTE                         *
//*                                                                  *
//*  PARAMETERS:                                                     *
//*    &PROG    - PROGRAM NAME (E.G. DBCUST01)                      *
//*    &DB2SYS  - DB2 SUBSYSTEM ID                                  *
//*    &SRCLIB  - SOURCE PDS                                        *
//*    &COPYLIB - COPYBOOK PDS                                      *
//*    &DBRMLIB - DBRM OUTPUT PDS                                   *
//*    &LOADLIB - LOAD MODULE OUTPUT PDS                             *
//*================================================================*
//*
//  SET PROG=DBCUST01
//  SET DB2SYS=DB2P
//  SET SRCLIB='PROD.DB2.SRCLIB'
//  SET COPYLIB='PROD.DB2.COPYLIB'
//  SET DBRMLIB='PROD.DB2.DBRMLIB'
//  SET LOADLIB='PROD.DB2.LOADLIB'
//*
//*================================================================*
//*  STEP010 - DB2 PRECOMPILE                                       *
//*  INPUT : COBOL SOURCE WITH EMBEDDED SQL                         *
//*  OUTPUT: MODIFIED COBOL SOURCE + DBRM                           *
//*                                                                  *
//*  DBRM (DATABASE REQUEST MODULE):                                 *
//*    CONTAINS SQL STATEMENTS EXTRACTED FROM SOURCE                *
//*    REQUIRED INPUT FOR BIND STEP                                 *
//*================================================================*
//STEP010  EXEC PGM=DSNHPC,
//         PARM='HOST(COB2),APOST,APOSTSQL,SOURCE,XREF'
//*
//STEPLIB  DD DSN=DB2.&DB2SYS..RUNLIB.LOAD,DISP=SHR
//DBRMLIB  DD DSN=&DBRMLIB(&PROG),DISP=SHR
//SYSCIN   DD DSN=&&DSNHOUT,
//            DISP=(NEW,PASS),
//            UNIT=SYSDA,
//            SPACE=(CYL,(10,5))
//SYSIN    DD DSN=&SRCLIB(&PROG),DISP=SHR
//SYSLIB   DD DSN=&COPYLIB,DISP=SHR
//         DD DSN=DB2.&DB2SYS..SRCLIB.DATA,DISP=SHR
//SYSPRINT DD SYSOUT=*
//SYSTERM  DD SYSOUT=*
//SYSUT1   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//SYSUT2   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//*
//*================================================================*
//*  STEP020 - COBOL COMPILE                                        *
//*  INPUT : MODIFIED COBOL SOURCE FROM PRECOMPILE                  *
//*  OUTPUT: OBJECT MODULE                                          *
//*================================================================*
//STEP020  EXEC PGM=IGYCRCTL,
//         PARM='RENT,APOST,MAP,LIST,OFFSET,XREF',
//         COND=(4,LT,STEP010)
//*
//STEPLIB  DD DSN=IGY.V6R4M0.SIGYCOMP,DISP=SHR
//SYSIN    DD DSN=&&DSNHOUT,DISP=(OLD,DELETE)
//SYSLIB   DD DSN=&COPYLIB,DISP=SHR
//         DD DSN=CEE.SCEESAMP,DISP=SHR
//SYSLIN   DD DSN=&&LOADSET,
//            DISP=(NEW,PASS),
//            UNIT=SYSDA,
//            SPACE=(CYL,(5,1))
//SYSPRINT DD SYSOUT=*
//SYSUT1   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//SYSUT2   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//SYSUT3   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//SYSUT4   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//SYSUT5   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//SYSUT6   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//SYSUT7   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//*
//*================================================================*
//*  STEP030 - LINK-EDIT                                            *
//*  INPUT : OBJECT MODULE FROM COMPILE                             *
//*  OUTPUT: EXECUTABLE LOAD MODULE IN LOADLIB                      *
//*  INCLUDES DB2 LANGUAGE INTERFACE (DSNELI)                       *
//*================================================================*
//STEP030  EXEC PGM=IEWBLINK,
//         PARM='RENT,REUS,AMODE=31,RMODE=ANY,MAP,XREF,LIST',
//         COND=(4,LT)
//*
//SYSLIB   DD DSN=CEE.SCEELKED,DISP=SHR
//         DD DSN=DB2.&DB2SYS..RUNLIB.LOAD,DISP=SHR
//SYSLIN   DD DSN=&&LOADSET,DISP=(OLD,DELETE)
//         DD *
  INCLUDE SYSLIB(DSNELI)
  NAME &PROG(R)
/*
//SYSLMOD  DD DSN=&LOADLIB(&PROG),DISP=SHR
//SYSPRINT DD SYSOUT=*
//SYSUT1   DD UNIT=SYSDA,SPACE=(CYL,(5,1))
//*
//*================================================================*
//*  STEP040 - VERIFY LOAD MODULE                                   *
//*================================================================*
//STEP040  EXEC PGM=AMBLIST,
//         COND=(4,LT)
//SYSPRINT DD SYSOUT=*
//SYSIN    DD *
  LISTLOAD OUTPUT=XREF,MEMBER=&PROG
/*
//SYSLIB   DD DSN=&LOADLIB,DISP=SHR
//
