# DB2 Customer Account Management System (Z/OS)

## Overview
A production **DB2-based customer account management system** with full COBOL-DB2 programs, DDL schemas, BIND/compile workflows, utility JCL, and performance tuning artifacts. Covers the complete DB2 development lifecycle from table design through production REBIND and recovery.

## Architecture

```
                    ┌──────────────────────────────┐
                    │      DB2 SUBSYSTEM (DB2P)    │
                    │                               │
  ┌─────────────┐  │  ┌──────────┐  ┌──────────┐  │
  │ COBOL-DB2   │──┼─▶│ TBCUST   │  │ TBACCT   │  │
  │ PROGRAMS    │  │  │ (CUSTOMER│  │ (ACCOUNT │  │
  │             │  │  │  MASTER) │  │  DETAIL) │  │
  │ DBCUST01    │  │  └──────────┘  └──────────┘  │
  │ DBACCT01    │  │                               │
  │ DBTXN01     │  │  ┌──────────┐  ┌──────────┐  │
  │ DBPERF01    │  │  │ TBTXN    │  │ VWACTSM  │  │
  │ DBRPT01     │  │  │ (TXN     │  │ (ACCOUNT │  │
  └──────┬──────┘  │  │  HISTORY)│  │  SUMMARY │  │
         │         │  └──────────┘  │  VIEW)   │  │
         ▼         │                └──────────┘  │
  ┌─────────────┐  │                               │
  │ COMPILE     │  │  INDEXES:                     │
  │ WORKFLOW    │  │    IX_CUST_NAME               │
  │             │  │    IX_CUST_SSN                 │
  │ PRECOMPILE  │  │    IX_ACCT_CUST               │
  │ COMPILE     │  │    IX_ACCT_BRANCH             │
  │ LINK        │  │    IX_TXN_ACCT_DATE           │
  │ BIND        │  │    IX_TXN_DATE                │
  └─────────────┘  └──────────────────────────────┘
```

## Components

### DDL — Database Schema
| Member       | Description                                            |
|-------------|--------------------------------------------------------|
| `TBCUST`    | Customer master table with partitioned tablespace      |
| `TBACCT`    | Account detail with referential integrity              |
| `TBTXN`     | Transaction history — range-partitioned by date        |
| `INDEXES`   | All index definitions with clustering strategy         |
| `VIEWS`     | Account summary view with aggregate calculations       |
| `GRANTS`    | Authorization grants for application plan              |

### COBOL-DB2 Programs
| Program      | Description                                            |
|-------------|--------------------------------------------------------|
| `DBCUST01`  | Customer CRUD — INSERT/UPDATE/DELETE with error handling|
| `DBACCT01`  | Account operations — multi-table join with cursor       |
| `DBTXN01`   | Transaction posting — deadlock retry, isolation levels  |
| `DBRPT01`   | Reporting — dynamic SQL with PLAN_TABLE analysis        |

### JCL — Build and Utility
| Member       | Description                                            |
|-------------|--------------------------------------------------------|
| `COMPILE`   | Full compile workflow: precompile → compile → link      |
| `BINDJCL`   | BIND PACKAGE/PLAN with EXPLAIN(YES)                     |
| `RUNSTATS`  | RUNSTATS utility for catalog statistics refresh         |
| `REORG`     | REORG TABLESPACE with inline COPY                       |
| `RECOVER`   | RECOVER utility — point-in-time and full recovery       |
| `UNLOAD`    | UNLOAD utility for data extraction                      |

### Copybooks
| Member       | Description                                            |
|-------------|--------------------------------------------------------|
| `CPYDBCST`  | DB2 host variable declarations — customer               |
| `CPYDBACC`  | DB2 host variable declarations — account                |
| `CPYDBTXN`  | DB2 host variable declarations — transaction            |
| `CPYDBSQL`  | SQLCA and common SQLCODE handling routines              |

## Key Senior-Level Patterns

- **Precompile/Compile/Link/BIND**: Complete DB2 build chain
- **EXPLAIN and PLAN_TABLE**: Access path analysis, index selection
- **Deadlock Handling**: SQLCODE -911/-913 with retry logic
- **Package vs Plan**: BIND PACKAGE for modularity, BIND PLAN for execution
- **Partitioned Tablespace**: Range partitioning by date for TXN table
- **RUNSTATS Timing**: Post-LOAD, post-REORG, scheduled weekly
- **Point-in-Time Recovery**: IMAGE COPY + log-based recovery
- **Referential Integrity**: Foreign keys with CASCADE/RESTRICT rules
- **Dynamic SQL Patterns**: PREPARE/EXECUTE for flexible reporting
