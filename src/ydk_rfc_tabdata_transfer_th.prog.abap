*&---------------------------------------------------------------------*
*& Report  YDK_RFC_TABDATAS_TRANSFER
*& Table copy stream
*&---------------------------------------------------------------------*
*& The program runs in the background, planning is performed
*& by the program YDK_RFC_TABDATA_TRANSFER_RN
*&---------------------------------------------------------------------*
*& Developed by Kiyanov Dmitry in 2016 year.
*& MIT License
*&---------------------------------------------------------------------*

REPORT ydk_rfc_tabdata_transfer_th.

PARAMETERS: rfcdest TYPE ydk_transfer-rfcdest OBLIGATORY.
PARAMETERS: ldate   TYPE ydk_transfer-ldate   OBLIGATORY.
PARAMETERS: ltime   TYPE ydk_transfer-ltime   OBLIGATORY.

PARAMETERS: clrdata TYPE ydk_transfer_clr_mode.
PARAMETERS: ignmode AS CHECKBOX.
PARAMETERS: where   TYPE string LOWER CASE.

DATA: ittab   TYPE STANDARD TABLE OF dd02l-tabname WITH HEADER LINE.
DATA: itetab  TYPE STANDARD TABLE OF dd02l-tabname WITH HEADER LINE.

DATA: logsys TYPE logsys.

START-OF-SELECTION.
  PERFORM mainproc.

FORM process.
  DATA: cttab TYPE i.
  DATA: ok TYPE c.
  DATA: cterr TYPE i.

  cttab = lines( ittab ).
  WRITE: / 'Selected for processing'(001), cttab, 'tables'(002).

  LOOP AT ittab.
    PERFORM lock_tab USING ittab ok.
    IF ok <> 'X'.
      WRITE: / sy-uzeit, ittab, 'omitted - processed by another process'(003).
      CONTINUE.
    ENDIF.

    PERFORM transfer_tab USING ittab ok.

    PERFORM unlock_tab USING ittab.

    IF ok <> 'X'.
      ADD 1 TO cterr.
      APPEND ittab TO itetab.
    ELSE.
      CLEAR cterr.
    ENDIF.

    CASE cterr.
      WHEN 5 OR 10 OR 15. " может это временный лаг
        WAIT UP TO 120 SECONDS.
      WHEN 20.
        WRITE: / 'The execution was interrupted because'(004), cterr, 'errors were in a row'(005).
        STOP.
    ENDCASE.
  ENDLOOP.

  WRITE: / 'Processing completed'(006).
ENDFORM.

FORM mainproc.
  DATA: last_tab TYPE dd02l-tabname.

  SELECT SINGLE logsys INTO logsys
    FROM t000
   WHERE mandt = sy-mandt.

  SELECT tabname INTO TABLE ittab
    FROM ydk_transfer
   WHERE rfcdest = rfcdest
     AND ldate   = ldate
     AND ltime   = ltime.

  IF ittab[] IS INITIAL.
    WRITE: / 'No tables selected'(007).
    EXIT.
  ENDIF.

  SORT ittab.
  READ TABLE ittab INDEX lines( ittab ).
  last_tab = ittab.

  PERFORM process.

* ещё раз обрабатываем ошибочные
  IF ( NOT itetab[] IS INITIAL ) AND ( ittab[] <> itetab[] ) AND ( lines( itetab ) < 300 ).
    ittab[] = itetab[].
    WRITE: / 'Error handling of this thread'(008).
    PERFORM process.
  ENDIF.

* Определяем последний ли поток.
  DATA: dkt TYPE ydk_transfer.

  SELECT SINGLE FOR UPDATE * INTO dkt " Создаём блокировку БД на последней таблице
    FROM ydk_transfer
   WHERE tabname = last_tab
     AND rfcdest = rfcdest
     AND ldate   = ldate
     AND ltime   = ltime.

  DATA: jobname TYPE tbtco-jobname.
  DATA: ctact   TYPE i.

  jobname = 'YDK_TRANSFER' && '_' && ldate && '_' && ltime.
  SELECT COUNT( * ) INTO ctact " Считаем количество активных процессов
    FROM tbtco
   WHERE jobname = jobname
     AND status = 'R'.

  CHECK ctact = 1.

  COMMIT WORK. " Снимаем блокировку БД

* ещё раз обрабатываем все ошибочные (в результате всех процессов)
  SELECT tabname INTO TABLE ittab
    FROM ydk_transfer
   WHERE rfcdest = rfcdest
     AND ldate   = ldate
     AND ltime   = ltime
     AND status   = 'E'.

  IF NOT ittab[] IS INITIAL.
    WRITE: / 'Processing errors from all threads'(009).
    SORT ittab.
    PERFORM process.
  ENDIF.

* Выполняем пост обработку
  DATA: postproc TYPE flag.

  SELECT tabname INTO TABLE ittab
    FROM ydk_transfer
   WHERE rfcdest = rfcdest
     AND ldate   = ldate
     AND ltime   = ltime
     AND status   = 'Z'.

  LOOP AT ittab.
    WRITE: / 'Post-processing'(010), ittab.
    CALL FUNCTION 'YDK_RFC_TRANSFER_POSTPROC' DESTINATION rfcdest
      EXPORTING
        tabname = ittab
        test    = ' '
      IMPORTING
        ok      = postproc.

    WRITE: postproc.
  ENDLOOP.
ENDFORM.

FORM lock_tab USING tabname ok.
* Блокируем если получилось
* Считываем статус - если = I  - ok = 'X'
  CLEAR ok.

  CALL FUNCTION 'ENQUEUE_EYDK_TRANSFER'
    EXPORTING
*     MODE_YDK_TRANSFER       = 'E'
*     MANDT          = SY-MANDT
      tabname        = tabname
      rfcdest        = rfcdest
*     X_TABNAME      = ' '
*     X_RFCDEST      = ' '
*     _SCOPE         = '2'
*     _WAIT          = ' '
*     _COLLECT       = ' '
    EXCEPTIONS
      foreign_lock   = 1
      system_failure = 2
      OTHERS         = 3.
  CHECK sy-subrc = 0.

  DATA: status TYPE ydk_transfer-status.

  SELECT SINGLE status INTO status
    FROM ydk_transfer
   WHERE tabname = tabname
     AND rfcdest = rfcdest.
  IF status CA 'IE'.
    ok = 'X'.
    RETURN.
  ENDIF.

  PERFORM unlock_tab USING tabname.
ENDFORM.

FORM unlock_tab USING tabname.
  CALL FUNCTION 'DEQUEUE_EYDK_TRANSFER'
    EXPORTING
*     MODE_YDK_TRANSFER       = 'E'
*     MANDT   = SY-MANDT
      tabname = tabname
      rfcdest = rfcdest
*     X_TABNAME               = ' '
*     X_RFCDEST               = ' '
*     _SCOPE  = '3'
*     _SYNCHRON               = ' '
*     _COLLECT                = ' '
    .
ENDFORM.

FORM transfer_tab USING tabname ok.
  DATA: msg TYPE string.
  DATA: rowsize TYPE i.
  DATA: rowcount TYPE i.

  DATA: trtab TYPE ydk_transfer.
  DATA: tabop TYPE ydk_transfer_tab.

  DATA: xclrdata TYPE c.
  DATA: postproc TYPE flag.

  CLEAR ok.

  WRITE: / sy-uzeit, tabname, 'started'(011).

  SELECT SINGLE * INTO tabop
    FROM ydk_transfer_tab
   WHERE tabname = tabname.

  SELECT SINGLE * INTO trtab
    FROM ydk_transfer
   WHERE tabname = tabname
     AND rfcdest = rfcdest.

  trtab-lcount   = 0.
  trtab-err      = ''.
  trtab-status   = 'P'.
  trtab-sdate    = sy-datum.
  trtab-stime    = sy-uzeit.
  trtab-etime    = sy-uzeit.
  trtab-duration = 0.

  IF tabop-cmode = 'СС'. " Копировать если изменилось количество - проверяем количество
    SELECT COUNT( * ) INTO rowcount
      FROM (tabname).
    IF trtab-ocount = rowcount.
      trtab-lcount   = rowcount.
      trtab-status   = 'S'.

      MODIFY ydk_transfer FROM trtab.
      COMMIT WORK.
      EXIT.
    ENDIF.
  ENDIF.

  xclrdata = clrdata.
  IF tabop-cmode = 'СL' AND ignmode IS INITIAL. " Не отчищать таблицу
    CLEAR xclrdata.
  ENDIF.

  MODIFY ydk_transfer FROM trtab.
  COMMIT WORK.

  FREE MEMORY ID 'YDK_RFC_TABDATA_TRANSFER'.

  SUBMIT ydk_rfc_tabdata_transfer AND RETURN
    WITH tabname = tabname
    WITH rfcdest = rfcdest
    WITH clrdata = xclrdata
    WITH logsys  = logsys
    WITH where   = where.

  IMPORT msg rowsize rowcount FROM MEMORY ID 'YDK_RFC_TABDATA_TRANSFER'.
  FREE MEMORY ID 'YDK_RFC_TABDATA_TRANSFER'.

  IF msg IS INITIAL.
    msg = 'no result - there''s probably a dump'(012).
  ENDIF.

  IF xclrdata = 'H' AND msg CS '(metod H)'.
* Обнаружена коллизия при передачи, передаём таблицу с зачисткой данных
    SUBMIT ydk_rfc_tabdata_transfer AND RETURN
      WITH tabname = tabname
      WITH rfcdest = rfcdest
      WITH clrdata = 'X'
      WITH logsys  = logsys
      WITH where   = where.

    IMPORT msg rowsize rowcount FROM MEMORY ID 'YDK_RFC_TABDATA_TRANSFER'.
    FREE MEMORY ID 'YDK_RFC_TABDATA_TRANSFER'.
  ENDIF.

  GET TIME.

  trtab-rowsize  = rowsize.
  trtab-lcount   = rowcount.

  trtab-etime    = sy-uzeit.
  IF trtab-sdate = sy-datum.
    trtab-duration = trtab-etime - trtab-stime.
  ELSE.
    DATA: tb TYPE t.
    DATA: te TYPE t.
    te = '240000'.
    trtab-duration = ( te - trtab-stime ) + ( trtab-etime - tb ) + ( sy-datum - trtab-sdate - 1 ) * 24 * 60 * 60.
  ENDIF.

  IF msg = 'OK'.
    ok = 'X'.
    trtab-status = 'O'.
    IF trtab-ocount <> trtab-lcount OR trtab-odate CO ' 0'.
      trtab-ocount    = trtab-lcount.
      trtab-odate     = ldate.
      trtab-oduration = trtab-duration.
    ENDIF.
  ELSE.
    trtab-err      = msg.
    trtab-status   = 'E'.
  ENDIF.

  IF trtab-status = 'O'.
    CALL FUNCTION 'YDK_RFC_TRANSFER_POSTPROC' " Вызываем локально - чтоб узнать нужнали после этой таблицы постобработка
      EXPORTING
        tabname = tabname
        test    = 'X'
      IMPORTING
        ok      = postproc.

    IF postproc = 'X'.
      trtab-status = 'Z'.
    ENDIF.
  ENDIF.

  MODIFY ydk_transfer FROM trtab.
  COMMIT WORK.

  WRITE: / sy-uzeit, tabname, msg.
ENDFORM.
