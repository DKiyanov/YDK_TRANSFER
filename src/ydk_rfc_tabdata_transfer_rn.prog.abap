*&---------------------------------------------------------------------*
*& Report  YDK_RFC_TABDATAS_TRANSFER
*& Copying mandant data to another system by RFC
*&---------------------------------------------------------------------*
*& Developed by Kiyanov Dmitry in 2016 year.
*& MIT License
*&---------------------------------------------------------------------*

REPORT ydk_rfc_tabdata_transfer_rn.

TABLES: sscrfields.

DATA: xtabname TYPE dd02l-tabname.
DATA: xlabl    TYPE ydk_transfer_tab-labl.
DATA: xcmode   TYPE ydk_transfer_tab-cmode.
DATA: xydktr   TYPE ydk_transfer.

SELECT-OPTIONS tabname FOR xtabname NO INTERVALS.
PARAMETERS: rfcdest  TYPE rfcdest OBLIGATORY.
PARAMETERS: thcount  TYPE i OBLIGATORY DEFAULT 1.

SELECTION-SCREEN SKIP.
PARAMETERS: clrdata TYPE ydk_transfer_clr_mode DEFAULT 'H'.
PARAMETERS: ignmode AS CHECKBOX.

SELECTION-SCREEN SKIP.
SELECT-OPTIONS labl      FOR xlabl            NO INTERVALS.
SELECT-OPTIONS cmode     FOR xcmode           NO INTERVALS.
SELECT-OPTIONS status    FOR xydktr-status    NO INTERVALS.
SELECT-OPTIONS odate     FOR xydktr-odate     NO INTERVALS.
SELECT-OPTIONS ocount    FOR xydktr-ocount    NO INTERVALS.
SELECT-OPTIONS odrtion   FOR xydktr-oduration NO INTERVALS.

SELECTION-SCREEN SKIP.
PARAMETERS: where    TYPE string LOWER CASE.

SELECTION-SCREEN FUNCTION KEY: 1, 2.
DATA: ucomm TYPE sscrfields-ucomm.

AT SELECTION-SCREEN OUTPUT.
  sscrfields-functxt_01 = 'Test'(001).
  sscrfields-functxt_02 = 'Processing status'(002).

AT SELECTION-SCREEN.
  ucomm = sscrfields-ucomm.
  CASE sscrfields-ucomm.
    WHEN 'FC01'.
      sscrfields-ucomm = 'ONLI'.
    WHEN 'FC02'.
      SUBMIT ydk_rfc_tabdata_transfer_rp VIA SELECTION-SCREEN AND RETURN
        WITH srfcdest = rfcdest.
  ENDCASE.

START-OF-SELECTION.
  PERFORM process.

FORM process.
  DATA: ittab TYPE STANDARD TABLE OF dd02l-tabname WITH HEADER LINE.

  SELECT dd02l~tabname INTO TABLE @ittab
    FROM dd02l
    JOIN tadir
      ON tadir~pgmid     = 'R3TR'
     AND tadir~object    = 'TABL'
     AND tadir~obj_name  = dd02l~tabname
    LEFT JOIN ydk_transfer_tab AS ydktt
      ON ydktt~tabname   = dd02l~tabname
    LEFT JOIN ydk_transfer AS ydktr
      ON ydktr~tabname   = dd02l~tabname
     AND ydktr~rfcdest   = @rfcdest
   WHERE dd02l~tabname   IN @tabname
     AND dd02l~as4local  = 'A'
     AND dd02l~as4vers   = '0000'
     AND dd02l~tabclass  IN ('TRANSP', 'CLUSTER', 'POOL')
     AND dd02l~clidep    = 'X'
     AND tadir~devclass  <> '$TMP'
     AND ydktt~labl      IN @labl
     AND ydktt~cmode     IN @cmode
     AND ydktr~status    IN @status
     AND ydktr~odate     IN @odate
     AND ydktr~ocount    IN @ocount
     AND ydktr~oduration IN @odrtion.
  CHECK NOT ittab[] IS INITIAL.

*  SELECT tabname INTO TABLE @ittab
*    FROM dd03l
*     FOR ALL ENTRIES IN @ittab
*   WHERE tabname   = @ittab-table_line
*     AND as4local  = 'A'
*     AND as4vers   = '0000'
*     AND fieldname IN ('MANDT', 'CLIENT')
**    AND position  = 1 " Бывает что инклюды раньше манданта
*     AND keyflag   = 'X'.
*  CHECK NOT ittab[] IS INITIAL.

  IF ignmode IS INITIAL.
    DATA: itskip TYPE STANDARD TABLE OF ydk_transfer_tab-tabname WITH HEADER LINE.
    SELECT tabname INTO TABLE itskip
      FROM ydk_transfer_tab
     WHERE tabname IN tabname
       AND cmode = 'SK'. " Не копировать.

    LOOP AT itskip.
      DELETE ittab WHERE table_line = itskip.
    ENDLOOP.
  ENDIF.

  DATA: ittrtab TYPE STANDARD TABLE OF ydk_transfer.
  FIELD-SYMBOLS <trtab> LIKE LINE OF ittrtab.

  SELECT * INTO TABLE ittrtab
    FROM ydk_transfer
     FOR ALL ENTRIES IN ittab
   WHERE tabname = ittab-table_line
     AND rfcdest = rfcdest.

  DATA: ldate TYPE ydk_transfer-ldate.
  DATA: ltime TYPE ydk_transfer-ltime.

  ldate = sy-datum.
  ltime = sy-uzeit.

  SORT ittrtab BY tabname.
  LOOP AT ittab.
    READ TABLE ittrtab ASSIGNING <trtab> WITH KEY tabname = ittab BINARY SEARCH.
    IF sy-subrc <> 0.
      INSERT INITIAL LINE INTO ittrtab ASSIGNING <trtab> INDEX sy-tabix.
      <trtab>-tabname = ittab.
      <trtab>-rfcdest = rfcdest.
    ENDIF.

    <trtab>-ldate  = ldate.
    <trtab>-ltime  = ltime.
    <trtab>-status = 'I'. " Предстоит обработка
  ENDLOOP.

  IF ucomm = 'FC01'. " test
    DATA: cttab TYPE i.
    cttab = lines( ittrtab ).
    WRITE: / 'Selecte'(003), cttab, 'tables'(004).
    LOOP AT ittrtab ASSIGNING <trtab>.
      WRITE: / <trtab>-tabname.
    ENDLOOP.

    EXIT.
  ENDIF.

  MODIFY ydk_transfer FROM TABLE ittrtab.
  COMMIT WORK.

  DATA: jobnumber TYPE tbtcjob-jobcount.
  DATA: jobname   TYPE tbtcjob-jobname.

  DO thcount TIMES.
    jobname = 'YDK_TRANSFER' && '_' && ldate && '_' && ltime.

    CALL FUNCTION 'JOB_OPEN'
      EXPORTING
        jobname  = jobname
      IMPORTING
        jobcount = jobnumber
      EXCEPTIONS
        OTHERS   = 0.

    SUBMIT ydk_rfc_tabdata_transfer_th
      USER           sy-uname
      VIA JOB        jobname
      NUMBER         jobnumber
      WITH rfcdest = rfcdest
      WITH ldate   = ldate
      WITH ltime   = ltime
      WITH clrdata = clrdata
      WITH where   = where
      AND RETURN.

    CALL FUNCTION 'JOB_CLOSE'
      EXPORTING
        jobcount  = jobnumber
        jobname   = jobname
        strtimmed = 'X'
      EXCEPTIONS
        OTHERS    = 0.
  ENDDO.
  COMMIT WORK.

  SUBMIT ydk_rfc_tabdata_transfer_rp AND RETURN
    WITH sldate   EQ ldate
    WITH sltime   EQ ltime
    WITH srfcdest EQ rfcdest.
ENDFORM.
