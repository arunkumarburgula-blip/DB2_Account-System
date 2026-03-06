       IDENTIFICATION DIVISION.
       PROGRAM-ID.    DBCUST01.
       AUTHOR.        MAINFRAME-DEV.
       DATE-WRITTEN.  2024-01-20.
      *================================================================*
      *  PROGRAM : DBCUST01                                             *
      *  DESC    : DB2 CUSTOMER CRUD OPERATIONS                         *
      *            INSERT, UPDATE, DELETE, SELECT BY KEY                 *
      *            FULL SQLCODE HANDLING WITH DEADLOCK RETRY             *
      *                                                                 *
      *  DB2 PLAN  : CUSTPLAN                                           *
      *  DB2 PACKAGE: CUSTCOLL.DBCUST01                                *
      *  ISOLATION : CS (CURSOR STABILITY)                              *
      *                                                                 *
      *  OPERATIONS (VIA INPUT PARM):                                   *
      *    I = INSERT NEW CUSTOMER                                     *
      *    U = UPDATE EXISTING CUSTOMER                                *
      *    D = DELETE (SOFT DELETE - SET STATUS='C')                    *
      *    S = SELECT BY CUSTOMER ID                                   *
      *    L = SELECT BY LAST NAME (CURSOR)                            *
      *================================================================*

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT INPUT-FILE
               ASSIGN TO INFILE
               FILE STATUS IS WS-INP-FS.

           SELECT OUTPUT-FILE
               ASSIGN TO OUTFILE
               FILE STATUS IS WS-OUT-FS.

       DATA DIVISION.
       FILE SECTION.

       FD  INPUT-FILE
           RECORDING MODE IS F
           RECORD CONTAINS 300 CHARACTERS.
       01  INPUT-RECORD                    PIC X(300).

       FD  OUTPUT-FILE
           RECORDING MODE IS F
           RECORD CONTAINS 300 CHARACTERS.
       01  OUTPUT-RECORD                   PIC X(300).

       WORKING-STORAGE SECTION.

       01  WS-PROGRAM-NAME                 PIC X(08) VALUE 'DBCUST01'.

       01  WS-INP-FS                       PIC X(02).
       01  WS-OUT-FS                       PIC X(02).
       01  WS-EOF-FLAG                     PIC X(01) VALUE 'N'.
           88  END-OF-FILE                           VALUE 'Y'.

      *------- INPUT REQUEST -------*
       01  WS-REQUEST.
           05  WS-REQ-OPER                 PIC X(01).
               88  REQ-INSERT                        VALUE 'I'.
               88  REQ-UPDATE                        VALUE 'U'.
               88  REQ-DELETE                        VALUE 'D'.
               88  REQ-SELECT                        VALUE 'S'.
               88  REQ-LIST                          VALUE 'L'.
           05  WS-REQ-DATA                 PIC X(299).

      *------- COUNTERS -------*
       01  WS-COUNTERS.
           05  WS-TOTAL-PROCESSED          PIC 9(07) VALUE 0.
           05  WS-TOTAL-SUCCESS            PIC 9(07) VALUE 0.
           05  WS-TOTAL-ERRORS             PIC 9(07) VALUE 0.
           05  WS-TOTAL-DEADLOCKS          PIC 9(05) VALUE 0.

      *------- DEADLOCK RETRY -------*
       01  WS-RETRY-COUNT                  PIC 9(02) VALUE 0.
       01  WS-MAX-RETRIES                  PIC 9(02) VALUE 3.
       01  WS-RETRY-FLAG                   PIC X(01) VALUE 'N'.
           88  SHOULD-RETRY                          VALUE 'Y'.

       01  WS-RETURN-CODE                  PIC S9(04) COMP VALUE 0.

      *------- DB2 HOST VARIABLES -------*
           EXEC SQL INCLUDE SQLCA END-EXEC.

       01  HV-CUST.
           05  HV-CUST-ID                  PIC X(10).
           05  HV-LAST-NAME               PIC X(30).
           05  HV-FIRST-NAME              PIC X(20).
           05  HV-MIDDLE-INIT             PIC X(01).
           05  HV-SSN                     PIC X(09).
           05  HV-STATUS                  PIC X(01).
           05  HV-DOB                     PIC X(10).
           05  HV-ADDR1                   PIC X(30).
           05  HV-CITY                    PIC X(20).
           05  HV-STATE                   PIC X(02).
           05  HV-ZIP                     PIC X(10).
           05  HV-PHONE                   PIC X(10).
           05  HV-EMAIL                   PIC X(50).
           05  HV-CREDIT-SCORE            PIC S9(04) COMP.
           05  HV-RISK-RATING             PIC X(01).

       01  HV-NULL-INDICATORS.
           05  HV-NI-DOB                  PIC S9(04) COMP.
           05  HV-NI-ADDR1               PIC S9(04) COMP.
           05  HV-NI-CITY                PIC S9(04) COMP.
           05  HV-NI-EMAIL               PIC S9(04) COMP.
           05  HV-NI-CREDIT              PIC S9(04) COMP.

      *------- CURSOR FOR NAME SEARCH -------*
           EXEC SQL
             DECLARE CSR-BY-NAME CURSOR FOR
               SELECT CUST_ID,
                      LAST_NAME,
                      FIRST_NAME,
                      STATUS,
                      PHONE,
                      EMAIL
               FROM   TBCUST
               WHERE  LAST_NAME LIKE :HV-LAST-NAME
                 AND  STATUS <> 'C'
               ORDER BY LAST_NAME, FIRST_NAME
               FETCH FIRST 100 ROWS ONLY
           END-EXEC.

       PROCEDURE DIVISION.

       0000-MAIN-PROCESS.
           PERFORM 1000-INITIALIZE
           PERFORM 2000-PROCESS-REQUESTS
              UNTIL END-OF-FILE
           PERFORM 3000-FINALIZE
           MOVE WS-RETURN-CODE TO RETURN-CODE
           STOP RUN.

       1000-INITIALIZE.
           DISPLAY WS-PROGRAM-NAME ' - STARTED'
           OPEN INPUT  INPUT-FILE
           OPEN OUTPUT OUTPUT-FILE
           READ INPUT-FILE INTO WS-REQUEST
             AT END SET END-OF-FILE TO TRUE
           END-READ.

       2000-PROCESS-REQUESTS.
           ADD 1 TO WS-TOTAL-PROCESSED
           MOVE 0 TO WS-RETRY-COUNT
           MOVE 'N' TO WS-RETRY-FLAG

           EVALUATE TRUE
             WHEN REQ-INSERT
                PERFORM 2100-INSERT-CUSTOMER
             WHEN REQ-UPDATE
                PERFORM 2200-UPDATE-CUSTOMER
             WHEN REQ-DELETE
                PERFORM 2300-DELETE-CUSTOMER
             WHEN REQ-SELECT
                PERFORM 2400-SELECT-CUSTOMER
             WHEN REQ-LIST
                PERFORM 2500-LIST-BY-NAME
             WHEN OTHER
                DISPLAY 'INVALID OPERATION: '
                        WS-REQ-OPER
                ADD 1 TO WS-TOTAL-ERRORS
           END-EVALUATE

           READ INPUT-FILE INTO WS-REQUEST
             AT END SET END-OF-FILE TO TRUE
           END-READ.

      *================================================================*
      *  2100 - INSERT NEW CUSTOMER                                    *
      *================================================================*
       2100-INSERT-CUSTOMER.
           PERFORM 8000-MAP-INPUT-TO-HV

           EXEC SQL
             INSERT INTO TBCUST
               (CUST_ID, LAST_NAME, FIRST_NAME,
                MIDDLE_INIT, SSN, STATUS,
                DATE_OF_BIRTH, ADDR_LINE1, CITY,
                STATE_CODE, ZIP_CODE, PHONE,
                EMAIL, CREDIT_SCORE, RISK_RATING,
                CREATED_BY, UPDATED_BY)
             VALUES
               (:HV-CUST-ID, :HV-LAST-NAME,
                :HV-FIRST-NAME, :HV-MIDDLE-INIT,
                :HV-SSN, 'A',
                :HV-DOB :HV-NI-DOB,
                :HV-ADDR1 :HV-NI-ADDR1,
                :HV-CITY :HV-NI-CITY,
                :HV-STATE, :HV-ZIP,
                :HV-PHONE,
                :HV-EMAIL :HV-NI-EMAIL,
                :HV-CREDIT-SCORE :HV-NI-CREDIT,
                :HV-RISK-RATING,
                USER, USER)
           END-EXEC

           PERFORM 9000-CHECK-SQLCODE.

      *================================================================*
      *  2200 - UPDATE CUSTOMER (WITH DEADLOCK RETRY)                  *
      *================================================================*
       2200-UPDATE-CUSTOMER.
           PERFORM 8000-MAP-INPUT-TO-HV

           PERFORM UNTIL NOT SHOULD-RETRY
              EXEC SQL
                UPDATE TBCUST
                SET    LAST_NAME   = :HV-LAST-NAME,
                       FIRST_NAME  = :HV-FIRST-NAME,
                       PHONE       = :HV-PHONE,
                       EMAIL       = :HV-EMAIL
                                     :HV-NI-EMAIL,
                       CREDIT_SCORE = :HV-CREDIT-SCORE
                                      :HV-NI-CREDIT,
                       UPDATED_DATE = CURRENT TIMESTAMP,
                       UPDATED_BY   = USER
                WHERE  CUST_ID = :HV-CUST-ID
                  AND  STATUS <> 'C'
              END-EXEC

              PERFORM 9000-CHECK-SQLCODE
           END-PERFORM.

      *================================================================*
      *  2300 - SOFT DELETE (SET STATUS = 'C')                         *
      *================================================================*
       2300-DELETE-CUSTOMER.
           PERFORM 8000-MAP-INPUT-TO-HV

           EXEC SQL
             UPDATE TBCUST
             SET    STATUS = 'C',
                    UPDATED_DATE = CURRENT TIMESTAMP,
                    UPDATED_BY = USER
             WHERE  CUST_ID = :HV-CUST-ID
               AND  STATUS <> 'C'
           END-EXEC

           PERFORM 9000-CHECK-SQLCODE

           IF SQLCODE = 0
              EXEC SQL COMMIT END-EXEC
              DISPLAY 'CUSTOMER SOFT-DELETED: '
                      HV-CUST-ID
           END-IF.

      *================================================================*
      *  2400 - SELECT BY PRIMARY KEY                                  *
      *================================================================*
       2400-SELECT-CUSTOMER.
           PERFORM 8000-MAP-INPUT-TO-HV

           EXEC SQL
             SELECT CUST_ID, LAST_NAME, FIRST_NAME,
                    MIDDLE_INIT, SSN, STATUS,
                    PHONE, EMAIL
             INTO   :HV-CUST-ID, :HV-LAST-NAME,
                    :HV-FIRST-NAME, :HV-MIDDLE-INIT,
                    :HV-SSN, :HV-STATUS,
                    :HV-PHONE,
                    :HV-EMAIL :HV-NI-EMAIL
             FROM   TBCUST
             WHERE  CUST_ID = :HV-CUST-ID
           END-EXEC

           PERFORM 9000-CHECK-SQLCODE

           IF SQLCODE = 0
              PERFORM 8100-MAP-HV-TO-OUTPUT
              WRITE OUTPUT-RECORD FROM WS-REQUEST
           END-IF.

      *================================================================*
      *  2500 - LIST BY NAME (CURSOR PROCESSING)                      *
      *================================================================*
       2500-LIST-BY-NAME.
           PERFORM 8000-MAP-INPUT-TO-HV
           STRING HV-LAST-NAME DELIMITED BY SPACES
                  '%' DELIMITED BY SIZE
                  INTO HV-LAST-NAME
           END-STRING

           EXEC SQL OPEN CSR-BY-NAME END-EXEC

           IF SQLCODE = 0
              PERFORM 2510-FETCH-NAME-CURSOR
                 UNTIL SQLCODE NOT = 0
              EXEC SQL CLOSE CSR-BY-NAME END-EXEC
           END-IF.

       2510-FETCH-NAME-CURSOR.
           EXEC SQL
             FETCH CSR-BY-NAME
               INTO :HV-CUST-ID, :HV-LAST-NAME,
                    :HV-FIRST-NAME, :HV-STATUS,
                    :HV-PHONE,
                    :HV-EMAIL :HV-NI-EMAIL
           END-EXEC

           IF SQLCODE = 0
              PERFORM 8100-MAP-HV-TO-OUTPUT
              WRITE OUTPUT-RECORD FROM WS-REQUEST
              ADD 1 TO WS-TOTAL-SUCCESS
           END-IF.

      *================================================================*
      *  8000 - MAP INPUT TO HOST VARIABLES                            *
      *================================================================*
       8000-MAP-INPUT-TO-HV.
           MOVE WS-REQ-DATA(1:10)   TO HV-CUST-ID
           MOVE WS-REQ-DATA(11:30)  TO HV-LAST-NAME
           MOVE WS-REQ-DATA(41:20)  TO HV-FIRST-NAME
           MOVE WS-REQ-DATA(61:9)   TO HV-SSN
           MOVE WS-REQ-DATA(70:10)  TO HV-PHONE
           MOVE WS-REQ-DATA(80:50)  TO HV-EMAIL
           MOVE 0 TO HV-NI-DOB HV-NI-ADDR1
                      HV-NI-CITY HV-NI-EMAIL
                      HV-NI-CREDIT.

      *================================================================*
      *  8100 - MAP HOST VARIABLES TO OUTPUT                           *
      *================================================================*
       8100-MAP-HV-TO-OUTPUT.
           INITIALIZE WS-REQUEST
           MOVE HV-CUST-ID         TO WS-REQ-DATA(1:10)
           MOVE HV-LAST-NAME       TO WS-REQ-DATA(11:30)
           MOVE HV-FIRST-NAME      TO WS-REQ-DATA(41:20)
           MOVE HV-STATUS          TO WS-REQ-DATA(61:1).

      *================================================================*
      *  9000 - SQLCODE CHECK WITH DEADLOCK RETRY                      *
      *  HANDLES: 0, +100, -803, -805, -811, -904, -911, -913         *
      *================================================================*
       9000-CHECK-SQLCODE.
           MOVE 'N' TO WS-RETRY-FLAG

           EVALUATE SQLCODE
             WHEN 0
                ADD 1 TO WS-TOTAL-SUCCESS
                EXEC SQL COMMIT END-EXEC
             WHEN +100
                DISPLAY 'NOT FOUND: CUSTID='
                        HV-CUST-ID
             WHEN -803
                DISPLAY 'DUPLICATE KEY: CUSTID='
                        HV-CUST-ID
                ADD 1 TO WS-TOTAL-ERRORS
                EXEC SQL ROLLBACK END-EXEC
             WHEN -805
                DISPLAY 'PACKAGE NOT FOUND - CHECK BIND'
                MOVE 12 TO WS-RETURN-CODE
                ADD 1 TO WS-TOTAL-ERRORS
             WHEN -811
                DISPLAY 'MULTIPLE ROWS RETURNED'
                ADD 1 TO WS-TOTAL-ERRORS
             WHEN -904
                DISPLAY 'RESOURCE UNAVAILABLE -'
                        ' CHECK PENDING STATUS'
                MOVE 12 TO WS-RETURN-CODE
                ADD 1 TO WS-TOTAL-ERRORS
             WHEN -911
                ADD 1 TO WS-RETRY-COUNT
                ADD 1 TO WS-TOTAL-DEADLOCKS
                IF WS-RETRY-COUNT <= WS-MAX-RETRIES
                   DISPLAY 'DEADLOCK RETRY '
                           WS-RETRY-COUNT ' OF '
                           WS-MAX-RETRIES
                   EXEC SQL ROLLBACK END-EXEC
                   MOVE 'Y' TO WS-RETRY-FLAG
                ELSE
                   DISPLAY 'MAX RETRIES EXCEEDED'
                   ADD 1 TO WS-TOTAL-ERRORS
                   EXEC SQL ROLLBACK END-EXEC
                END-IF
             WHEN -913
                DISPLAY 'TIMEOUT - LOCK ESCALATION'
                ADD 1 TO WS-TOTAL-ERRORS
                EXEC SQL ROLLBACK END-EXEC
             WHEN OTHER
                DISPLAY 'UNEXPECTED SQLCODE=' SQLCODE
                DISPLAY 'SQLERRM=' SQLERRMC
                ADD 1 TO WS-TOTAL-ERRORS
                EXEC SQL ROLLBACK END-EXEC
                IF SQLCODE < -900
                   MOVE 16 TO WS-RETURN-CODE
                END-IF
           END-EVALUATE.

       3000-FINALIZE.
           CLOSE INPUT-FILE
           CLOSE OUTPUT-FILE

           DISPLAY '======================================='
           DISPLAY WS-PROGRAM-NAME ' COMPLETE'
           DISPLAY 'TOTAL PROCESSED : ' WS-TOTAL-PROCESSED
           DISPLAY 'SUCCESSFUL      : ' WS-TOTAL-SUCCESS
           DISPLAY 'ERRORS          : ' WS-TOTAL-ERRORS
           DISPLAY 'DEADLOCKS HIT   : ' WS-TOTAL-DEADLOCKS
           DISPLAY 'RETURN CODE     : ' WS-RETURN-CODE
           DISPLAY '======================================='.
