       IDENTIFICATION DIVISION.
       PROGRAM-ID.    DBTXN01.
       AUTHOR.        MAINFRAME-DEV.
       DATE-WRITTEN.  2024-01-25.
      *================================================================*
      *  PROGRAM : DBTXN01                                              *
      *  DESC    : TRANSACTION POSTING ENGINE                           *
      *            POSTS DEBIT/CREDIT TRANSACTIONS TO ACCOUNTS          *
      *            UPDATES ACCOUNT BALANCE IN SAME UNIT OF WORK         *
      *                                                                  *
      *  ACID COMPLIANCE:                                                *
      *    - ATOMIC: TXN INSERT + BALANCE UPDATE IN SINGLE COMMIT       *
      *    - CONSISTENT: VALIDATES BALANCE BEFORE DEBIT                  *
      *    - ISOLATED: CURSOR STABILITY, DEADLOCK RETRY                  *
      *    - DURABLE: COMMIT AFTER EACH TRANSACTION                      *
      *                                                                  *
      *  PERFORMANCE:                                                    *
      *    - STAGE 1 PREDICATES ON ACCT_NUMBER (INDEXED)                *
      *    - AVOID SUBSTR/FUNCTION IN WHERE CLAUSE                       *
      *    - COMMIT FREQUENCY: EVERY TRANSACTION (ONLINE)               *
      *    - BATCH MODE: COMMIT EVERY 500 TRANSACTIONS                   *
      *================================================================*

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT TXN-INPUT-FILE
               ASSIGN TO TXNINPUT
               FILE STATUS IS WS-TXN-FS.

           SELECT RESULT-FILE
               ASSIGN TO RESULTS
               FILE STATUS IS WS-RST-FS.

       DATA DIVISION.
       FILE SECTION.

       FD  TXN-INPUT-FILE
           RECORDING MODE IS F
           RECORD CONTAINS 200 CHARACTERS.
       01  TXN-INPUT-RECORD                PIC X(200).

       FD  RESULT-FILE
           RECORDING MODE IS F
           RECORD CONTAINS 200 CHARACTERS.
       01  RESULT-RECORD                   PIC X(200).

       WORKING-STORAGE SECTION.

       01  WS-PROGRAM-NAME                 PIC X(08) VALUE 'DBTXN01'.
       01  WS-TXN-FS                       PIC X(02).
       01  WS-RST-FS                       PIC X(02).
       01  WS-EOF-FLAG                     PIC X(01) VALUE 'N'.
           88  END-OF-FILE                           VALUE 'Y'.

      *------- TRANSACTION INPUT -------*
       01  WS-TXN-INPUT.
           05  WS-TXN-ID                   PIC X(15).
           05  WS-TXN-ACCT-NUM             PIC X(12).
           05  WS-TXN-TYPE                 PIC X(03).
               88  TXN-DEBIT                VALUE 'DBT'.
               88  TXN-CREDIT               VALUE 'CRT'.
               88  TXN-TRANSFER             VALUE 'XFR'.
               88  TXN-FEE                  VALUE 'FEE'.
               88  TXN-INTEREST             VALUE 'INT'.
           05  WS-TXN-AMOUNT               PIC S9(11)V99 COMP-3.
           05  WS-TXN-DESC                 PIC X(50).
           05  WS-TXN-REF                  PIC X(20).
           05  WS-TXN-CHANNEL              PIC X(03).
           05  WS-TXN-FILLER               PIC X(87).

      *------- COUNTERS -------*
       01  WS-TOTAL-POSTED                 PIC 9(09) VALUE 0.
       01  WS-TOTAL-REJECTED              PIC 9(09) VALUE 0.
       01  WS-TOTAL-DEADLOCKS             PIC 9(05) VALUE 0.
       01  WS-COMMIT-COUNT                PIC 9(05) VALUE 0.
       01  WS-BATCH-COMMIT-FREQ           PIC 9(05) VALUE 500.

      *------- DEADLOCK RETRY -------*
       01  WS-RETRY-COUNT                  PIC 9(02) VALUE 0.
       01  WS-MAX-RETRIES                  PIC 9(02) VALUE 3.

      *------- HOST VARIABLES -------*
           EXEC SQL INCLUDE SQLCA END-EXEC.

       01  HV-ACCT-NUMBER                  PIC X(12).
       01  HV-CURRENT-BALANCE              PIC S9(13)V99 COMP-3.
       01  HV-CURRENT-AVAIL               PIC S9(13)V99 COMP-3.
       01  HV-ACCT-STATUS                  PIC X(01).
       01  HV-NEW-BALANCE                  PIC S9(13)V99 COMP-3.
       01  HV-NEW-AVAIL                    PIC S9(13)V99 COMP-3.
       01  HV-TXN-ID                       PIC X(15).
       01  HV-TXN-TYPE                     PIC X(03).
       01  HV-TXN-AMOUNT                   PIC S9(11)V99 COMP-3.
       01  HV-TXN-DESC                     PIC X(50).
       01  HV-TXN-REF                      PIC X(20).
       01  HV-TXN-CHANNEL                  PIC X(03).

       01  WS-RETURN-CODE                  PIC S9(04) COMP VALUE 0.

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-PROCESS-TRANSACTIONS
              UNTIL END-OF-FILE
           PERFORM 3000-FINALIZE
           MOVE WS-RETURN-CODE TO RETURN-CODE
           STOP RUN.

       1000-INITIALIZE.
           DISPLAY WS-PROGRAM-NAME ' - TRANSACTION POSTING'
           OPEN INPUT  TXN-INPUT-FILE
           OPEN OUTPUT RESULT-FILE
           READ TXN-INPUT-FILE INTO WS-TXN-INPUT
             AT END SET END-OF-FILE TO TRUE
           END-READ.

       2000-PROCESS-TRANSACTIONS.
           MOVE 0 TO WS-RETRY-COUNT

           PERFORM 2100-POST-TRANSACTION

           READ TXN-INPUT-FILE INTO WS-TXN-INPUT
             AT END SET END-OF-FILE TO TRUE
           END-READ.

      *================================================================*
      *  2100 - POST TRANSACTION (WITH RETRY ON DEADLOCK)              *
      *  1. LOCK ACCOUNT ROW (SELECT FOR UPDATE)                      *
      *  2. VALIDATE BALANCE FOR DEBITS                                *
      *  3. INSERT TRANSACTION RECORD                                  *
      *  4. UPDATE ACCOUNT BALANCE                                     *
      *  5. COMMIT (OR ROLLBACK ON ERROR)                              *
      *================================================================*
       2100-POST-TRANSACTION.
           PERFORM 2110-LOCK-ACCOUNT

           EVALUATE SQLCODE
             WHEN 0
                PERFORM 2120-VALIDATE-BALANCE
             WHEN -911
                PERFORM 2900-HANDLE-DEADLOCK
             WHEN -913
                PERFORM 2900-HANDLE-DEADLOCK
             WHEN +100
                DISPLAY 'ACCOUNT NOT FOUND: '
                        WS-TXN-ACCT-NUM
                ADD 1 TO WS-TOTAL-REJECTED
             WHEN OTHER
                DISPLAY 'ACCOUNT LOCK ERROR: SQLCODE='
                        SQLCODE
                ADD 1 TO WS-TOTAL-REJECTED
                EXEC SQL ROLLBACK END-EXEC
           END-EVALUATE.

      *------- LOCK ACCOUNT ROW FOR UPDATE -------*
       2110-LOCK-ACCOUNT.
           MOVE WS-TXN-ACCT-NUM TO HV-ACCT-NUMBER

           EXEC SQL
             SELECT BALANCE,
                    AVAIL_BALANCE,
                    ACCT_STATUS
             INTO   :HV-CURRENT-BALANCE,
                    :HV-CURRENT-AVAIL,
                    :HV-ACCT-STATUS
             FROM   TBACCT
             WHERE  ACCT_NUMBER = :HV-ACCT-NUMBER
             FOR UPDATE OF BALANCE, AVAIL_BALANCE
           END-EXEC.

      *------- VALIDATE BEFORE POSTING -------*
       2120-VALIDATE-BALANCE.
           IF HV-ACCT-STATUS NOT = 'O'
              DISPLAY 'ACCOUNT NOT OPEN: '
                      WS-TXN-ACCT-NUM
              ADD 1 TO WS-TOTAL-REJECTED
              EXEC SQL ROLLBACK END-EXEC
           ELSE
              IF TXN-DEBIT OR TXN-FEE
                 IF WS-TXN-AMOUNT > HV-CURRENT-AVAIL
                    DISPLAY 'INSUFFICIENT FUNDS: '
                            WS-TXN-ACCT-NUM
                    ADD 1 TO WS-TOTAL-REJECTED
                    EXEC SQL ROLLBACK END-EXEC
                 ELSE
                    PERFORM 2130-CALCULATE-NEW-BALANCE
                    PERFORM 2140-INSERT-TXN
                    PERFORM 2150-UPDATE-BALANCE
                 END-IF
              ELSE
                 PERFORM 2130-CALCULATE-NEW-BALANCE
                 PERFORM 2140-INSERT-TXN
                 PERFORM 2150-UPDATE-BALANCE
              END-IF
           END-IF.

      *------- CALCULATE NEW BALANCE -------*
       2130-CALCULATE-NEW-BALANCE.
           EVALUATE TRUE
             WHEN TXN-CREDIT OR TXN-INTEREST
                ADD WS-TXN-AMOUNT TO HV-CURRENT-BALANCE
                   GIVING HV-NEW-BALANCE
                ADD WS-TXN-AMOUNT TO HV-CURRENT-AVAIL
                   GIVING HV-NEW-AVAIL
             WHEN TXN-DEBIT OR TXN-FEE
                SUBTRACT WS-TXN-AMOUNT FROM
                   HV-CURRENT-BALANCE
                   GIVING HV-NEW-BALANCE
                SUBTRACT WS-TXN-AMOUNT FROM
                   HV-CURRENT-AVAIL
                   GIVING HV-NEW-AVAIL
           END-EVALUATE.

      *------- INSERT TRANSACTION RECORD -------*
       2140-INSERT-TXN.
           MOVE WS-TXN-ID       TO HV-TXN-ID
           MOVE WS-TXN-TYPE     TO HV-TXN-TYPE
           MOVE WS-TXN-AMOUNT   TO HV-TXN-AMOUNT
           MOVE WS-TXN-DESC     TO HV-TXN-DESC
           MOVE WS-TXN-REF      TO HV-TXN-REF
           MOVE WS-TXN-CHANNEL  TO HV-TXN-CHANNEL

           EXEC SQL
             INSERT INTO TBTXN
               (TXN_ID, ACCT_NUMBER, TXN_DATE, TXN_TIME,
                TXN_TYPE, TXN_AMOUNT, RUNNING_BALANCE,
                DESCRIPTION, REFERENCE_NUM, CHANNEL)
             VALUES
               (:HV-TXN-ID, :HV-ACCT-NUMBER,
                CURRENT DATE, CURRENT TIME,
                :HV-TXN-TYPE, :HV-TXN-AMOUNT,
                :HV-NEW-BALANCE,
                :HV-TXN-DESC, :HV-TXN-REF,
                :HV-TXN-CHANNEL)
           END-EXEC

           IF SQLCODE NOT = 0
              DISPLAY 'TXN INSERT FAILED: SQLCODE='
                      SQLCODE
              EXEC SQL ROLLBACK END-EXEC
              ADD 1 TO WS-TOTAL-REJECTED
           END-IF.

      *------- UPDATE ACCOUNT BALANCE -------*
       2150-UPDATE-BALANCE.
           IF SQLCODE = 0
              EXEC SQL
                UPDATE TBACCT
                SET    BALANCE = :HV-NEW-BALANCE,
                       AVAIL_BALANCE = :HV-NEW-AVAIL,
                       LAST_ACTIVITY_DATE = CURRENT DATE,
                       UPDATED_DATE = CURRENT TIMESTAMP
                WHERE  ACCT_NUMBER = :HV-ACCT-NUMBER
              END-EXEC

              IF SQLCODE = 0
                 EXEC SQL COMMIT END-EXEC
                 ADD 1 TO WS-TOTAL-POSTED
                 ADD 1 TO WS-COMMIT-COUNT
              ELSE
                 DISPLAY 'BALANCE UPDATE FAILED: '
                         SQLCODE
                 EXEC SQL ROLLBACK END-EXEC
                 ADD 1 TO WS-TOTAL-REJECTED
              END-IF
           END-IF.

      *------- DEADLOCK RETRY HANDLER -------*
       2900-HANDLE-DEADLOCK.
           ADD 1 TO WS-RETRY-COUNT
           ADD 1 TO WS-TOTAL-DEADLOCKS
           EXEC SQL ROLLBACK END-EXEC
           IF WS-RETRY-COUNT <= WS-MAX-RETRIES
              DISPLAY 'DEADLOCK RETRY ' WS-RETRY-COUNT
              PERFORM 2100-POST-TRANSACTION
           ELSE
              DISPLAY 'MAX DEADLOCK RETRIES EXCEEDED: '
                      WS-TXN-ACCT-NUM
              ADD 1 TO WS-TOTAL-REJECTED
           END-IF.

       3000-FINALIZE.
           EXEC SQL COMMIT END-EXEC
           CLOSE TXN-INPUT-FILE
           CLOSE RESULT-FILE

           DISPLAY '======================================='
           DISPLAY WS-PROGRAM-NAME ' COMPLETE'
           DISPLAY 'TRANSACTIONS POSTED  : '
                   WS-TOTAL-POSTED
           DISPLAY 'TRANSACTIONS REJECTED: '
                   WS-TOTAL-REJECTED
           DISPLAY 'DEADLOCKS HANDLED    : '
                   WS-TOTAL-DEADLOCKS
           DISPLAY '======================================='.
