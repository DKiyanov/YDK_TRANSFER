*&---------------------------------------------------------------------*
*& Report  YDK_RFC_TABDATA_TRANSFER
*& Transferring the table contents to the target system
*&---------------------------------------------------------------------*
*& Developed by Kiyanov Dmitry in 2016 year.
*& MIT License
*&---------------------------------------------------------------------*

REPORT ydk_rfc_tabdata_transfer.

PARAMETERS: tabname  TYPE dd03l-tabname OBLIGATORY.
PARAMETERS: rfcdest  TYPE rfcdest OBLIGATORY.
PARAMETERS: clrdata  TYPE ydk_transfer_clr_mode.
PARAMETERS: logsys   TYPE logsys.
PARAMETERS: where    TYPE string LOWER CASE.

DATA: msg TYPE string.
DATA: rowsize TYPE i.
DATA: rowcount TYPE i.

START-OF-SELECTION.
  FREE MEMORY ID 'YDK_RFC_TABDATA_TRANSFER'.

  PERFORM process.

  IF msg IS INITIAL.
    msg = 'OK'.
  ENDIF.

  EXPORT msg rowsize rowcount TO MEMORY ID 'YDK_RFC_TABDATA_TRANSFER'.

FORM process.
  DATA: tab_ref TYPE REF TO data.
  FIELD-SYMBOLS <tab> TYPE STANDARD TABLE.

  FIELD-SYMBOLS <wa> TYPE any.
  DATA: psize TYPE i.

  DATA: itcomponent TYPE if_salv_bs_t_data=>t_type_component.

  DATA: xstr TYPE xstring.

  DATA: cur TYPE cursor.
  DATA: ok TYPE c.

  CREATE DATA tab_ref TYPE STANDARD TABLE OF (tabname).
  ASSIGN tab_ref->* TO <tab>.

  itcomponent = cl_salv_bs_ddic=>get_components_by_data( <tab> ).
  EXPORT itcomponent TO DATA BUFFER xstr.

  CALL FUNCTION 'YDK_RFC_TRANSFER_INIT'
    DESTINATION rfcdest
    EXPORTING
      tabname               = tabname
      cluster               = xstr
      clrdata               = clrdata
      logsys                = logsys
    EXCEPTIONS
      system_failure        = 1
      communication_failure = 2
      table_not_found       = 3
      err_on_create_struct  = 4
      OTHERS                = 5.

  IF sy-subrc <> 0.
    msg = |{ text-001 } { sy-subrc }|. " Error on transmission initialization
    EXIT.
  ENDIF.

  APPEND INITIAL LINE TO <tab> ASSIGNING <wa>.
  DESCRIBE FIELD <wa> LENGTH rowsize IN BYTE MODE.
  psize = 1000000 DIV rowsize.
  IF psize = 0.
    psize = 1.
  ENDIF.
  REFRESH <tab>.

  IF where IS INITIAL.
    OPEN CURSOR WITH HOLD cur FOR
      SELECT *
        FROM (tabname).
  ELSE.
    OPEN CURSOR WITH HOLD cur FOR
      SELECT *
        FROM (tabname)
       WHERE (where).
  ENDIF.
  DO.
    FETCH NEXT CURSOR cur INTO TABLE <tab> PACKAGE SIZE psize.
    IF sy-subrc <> 0. EXIT. ENDIF.
    CHECK NOT <tab> IS INITIAL.

    EXPORT tab FROM <tab> TO DATA BUFFER xstr.

    CALL FUNCTION 'YDK_RFC_TRANSFER_RECIVE'
      DESTINATION rfcdest
      KEEPING LOGICAL UNIT OF WORK " This addition is for internal use only. When this addition is used incorrectly, the worst case scenario may be a system shutdown.
      EXPORTING
        cluster               = xstr
      EXCEPTIONS
        system_failure        = 1
        communication_failure = 2
        OTHERS                = 5.
    IF sy-subrc <> 0.
      msg = |{ text-002 } { sy-subrc }|. " Error in data transmission
      EXIT.
    ENDIF.

    rowcount = rowcount + lines( <tab> ).
  ENDDO.
  CLOSE CURSOR cur.

  CHECK msg IS INITIAL.

  IF clrdata = 'H'.
    CALL FUNCTION 'YDK_RFC_TRANSFER_FINISH'
      DESTINATION rfcdest
      IMPORTING
        ok                    = ok
      EXCEPTIONS
        system_failure        = 1
        communication_failure = 2
        OTHERS                = 5.
    IF sy-subrc <> 0.
      msg = |{ text-003 } { sy-subrc }|. " Error at transmission completion
      EXIT.
    ENDIF.

    IF ok IS INITIAL.
      msg = 'Error during collision checking (metod H)'(004).
    ENDIF.
  ENDIF.
ENDFORM.
