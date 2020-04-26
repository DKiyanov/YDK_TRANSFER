*&---------------------------------------------------------------------*
*& Report  YDK_RFC_TABDATA_TRANSFER_RP
*& Transferring table contents to the target system (report)
*&---------------------------------------------------------------------*
*& Developed by Kiyanov Dmitry in 2016 year.
*& MIT License
*&---------------------------------------------------------------------*

REPORT ydk_rfc_tabdata_transfer_rp.


DATA: BEGIN OF itd OCCURS 0,
        ldate    TYPE ydk_transfer-ldate,
        ltime    TYPE ydk_transfer-ltime,
        rfcdest  TYPE ydk_transfer-rfcdest,
        total    TYPE i,
        ok       TYPE i,
        skip     TYPE i,
        err      TYPE i,
        inproc   TYPE i,
        rest     TYPE i,
        thct     TYPE i,
        thact    TYPE i,
        duration TYPE i,
      END   OF itd.

SELECT-OPTIONS: sldate   FOR itd-ldate DEFAULT sy-datum.
SELECT-OPTIONS: sltime   FOR itd-ltime.
SELECT-OPTIONS: srfcdest FOR itd-rfcdest.


START-OF-SELECTION.
  PERFORM get_data.
  PERFORM alv_show.

FORM get_data.
  DATA: BEGIN OF itdx OCCURS 0,
          ldate   TYPE ydk_transfer-ldate,
          ltime   TYPE ydk_transfer-ltime,
          rfcdest TYPE ydk_transfer-rfcdest,
          status  TYPE ydk_transfer-status,
          sdate   TYPE ydk_transfer-sdate,
          stime   TYPE ydk_transfer-stime,
          etime   TYPE ydk_transfer-etime,
          count   TYPE i,
        END   OF itdx.

  DATA: duration TYPE i.

  DATA: jobname TYPE tbtco-jobname.
  DATA: BEGIN OF itjb OCCURS 0,
          status TYPE tbtco-status,
          count  TYPE i,
        END   OF itjb.

  REFRESH itd.
  CLEAR itd.

  SELECT ldate ltime rfcdest status sdate MIN( stime ) MAX( etime ) COUNT( * ) INTO TABLE itdx
    FROM ydk_transfer
   WHERE ldate   IN sldate
     AND ltime   IN sltime
     AND rfcdest IN srfcdest
   GROUP BY ldate ltime rfcdest status sdate.

  SORT itdx.
  LOOP AT itdx.
    CASE itdx-status.
      WHEN 'I'. ADD itdx-count TO itd-rest.
      WHEN 'O' OR 'Z'. ADD itdx-count TO itd-ok.
      WHEN 'E'. ADD itdx-count TO itd-err.
      WHEN 'P'. ADD itdx-count TO itd-inproc.
      WHEN 'S'. ADD itdx-count TO itd-skip.
    ENDCASE.

    ADD itdx-count TO itd-total.

    duration = itdx-etime - itdx-stime.
    ADD duration TO itd-duration.

    AT END OF rfcdest.
      itd-ldate   = itdx-ldate.
      itd-ltime   = itdx-ltime.
      itd-rfcdest = itdx-rfcdest.

      jobname = 'YDK_TRANSFER' && '_' && itd-ldate && '_' && itd-ltime.
      SELECT status COUNT( * ) INTO TABLE itjb
        FROM tbtco
       WHERE jobname = jobname
       GROUP BY status.

      LOOP AT itjb.
        IF itjb-status = 'R'.
          ADD itjb-count TO itd-thact.
        ENDIF.
        ADD itjb-count TO itd-thct.
      ENDLOOP.

      APPEND itd.
      CLEAR itd.
    ENDAT.
  ENDLOOP.
ENDFORM.


FORM alv_show.
  DATA: fc TYPE lvc_t_fcat WITH HEADER LINE.
  DATA: repid TYPE sy-repid.

  CALL FUNCTION 'YDK_ALV_FCAT_BUILD'
    EXPORTING
      alv_strut_key = 'YDK_RFC_TABD_TRANS'
*     structures    = ''
    TABLES
      alv_tab       = itd
      fcat          = fc.

  repid = sy-repid.
  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY_LVC'
    EXPORTING
*     I_INTERFACE_CHECK        = ' '
*     I_BYPASSING_BUFFER       =
*     I_BUFFER_ACTIVE          =
      i_callback_program       = repid
      i_callback_pf_status_set = 'ALV_STATUS_SET'
      i_callback_user_command  = 'ALV_USER_COMMAND'
*     I_CALLBACK_TOP_OF_PAGE   = ' '
*     I_CALLBACK_HTML_TOP_OF_PAGE       = ' '
*     I_CALLBACK_HTML_END_OF_LIST       = ' '
*     I_STRUCTURE_NAME         =
*     I_BACKGROUND_ID          = ' '
*     I_GRID_TITLE             =
*     I_GRID_SETTINGS          =
*     IS_LAYOUT_LVC            =
      it_fieldcat_lvc          = fc[]
*     IT_EXCLUDING             =
*     IT_SPECIAL_GROUPS_LVC    =
*     IT_SORT_LVC              =
*     IT_FILTER_LVC            =
*     IT_HYPERLINK             =
*     IS_SEL_HIDE              =
*     I_DEFAULT                = 'X'
      i_save                   = 'A'
*     IS_VARIANT               =
*     IT_EVENTS                =
*     IT_EVENT_EXIT            =
*     IS_PRINT_LVC             =
*     IS_REPREP_ID_LVC         =
*     I_SCREEN_START_COLUMN    = 0
*     I_SCREEN_START_LINE      = 0
*     I_SCREEN_END_COLUMN      = 0
*     I_SCREEN_END_LINE        = 0
*     I_HTML_HEIGHT_TOP        =
*     I_HTML_HEIGHT_END        =
*     IT_ALV_GRAPHICS          =
*     IT_EXCEPT_QINFO_LVC      =
*     IR_SALV_FULLSCREEN_ADAPTER        =
    TABLES
      t_outtab                 = itd
    EXCEPTIONS
      program_error            = 1
      OTHERS                   = 2.
ENDFORM.                    "alv_show

FORM alv_status_set USING extab TYPE slis_t_extab.
  SET PF-STATUS 'ALV' EXCLUDING extab.
ENDFORM.                    "ALV_STATUS

FORM add_seltab TABLES seltab TYPE se16n_or_seltab_t USING field.
  FIELD-SYMBOLS <sl> LIKE LINE OF seltab.
  FIELD-SYMBOLS <fs> TYPE any.
  ASSIGN COMPONENT field OF STRUCTURE itd TO <fs>.
  APPEND INITIAL LINE TO seltab ASSIGNING <sl>.
  <sl>-field  = field.
  <sl>-sign   = 'I'.
  <sl>-option = 'EQ'.
  <sl>-low    = <fs>.
ENDFORM.

FORM alv_user_command USING ucomm    TYPE sy-ucomm
                            selfield TYPE slis_selfield.

  DATA: itsel TYPE se16n_or_t.
  FIELD-SYMBOLS <sel> LIKE LINE OF itsel.
  FIELD-SYMBOLS <sl> LIKE LINE OF <sel>-seltab.

  DATA: status TYPE ydk_transfer-status.

  DATA: btcselect TYPE btcselect.
  DATA: itjlist TYPE STANDARD TABLE OF tbtcjob.


  READ TABLE itd INDEX selfield-tabindex.

  CASE ucomm.
    WHEN 'REFR'.
      PERFORM get_data.
      selfield-refresh    = 'X'.
      selfield-col_stable = 'X'.
      selfield-row_stable = 'X'.
    WHEN '&IC1'. " Double click
      CASE selfield-fieldname.
        WHEN 'THCT'
          OR 'THACT'
          OR 'DURATION'.

          btcselect-jobname = 'YDK_TRANSFER' && '_' && itd-ldate && '_' && itd-ltime.

          CALL FUNCTION 'BP_JOB_SELECT'
            EXPORTING
              jobselect_dialog    = 'N'
              jobsel_param_in     = btcselect
            TABLES
              jobselect_joblist   = itjlist
            EXCEPTIONS
              invalid_dialog_type = 1
              jobname_missing     = 2
              no_jobs_found       = 3
              selection_canceled  = 4
              username_missing    = 5
              OTHERS              = 6.
          CHECK NOT itjlist[] IS INITIAL.

          CALL FUNCTION 'BP_JOBLIST_PROCESSOR_SM37B'
            EXPORTING
              joblist_opcode             = 22 " btc_joblist_show
            TABLES
              joblist                    = itjlist
            EXCEPTIONS
              invalid_opcode             = 1
              joblist_is_empty           = 2
              joblist_processor_canceled = 3
              OTHERS                     = 4.
          EXIT.
      ENDCASE.

      APPEND INITIAL LINE TO itsel ASSIGNING <sel>.
      PERFORM add_seltab TABLES <sel>-seltab USING: 'LDATE', 'LTIME', 'RFCDEST'.

      CASE selfield-fieldname.
        WHEN 'OK'.     status = 'O'.
        WHEN 'SKIP'.   status = 'S'.
        WHEN 'ERR'.    status = 'E'.
        WHEN 'INPROC'. status = 'P'.
        WHEN 'REST'.   status = 'I'.
      ENDCASE.

      IF NOT status IS INITIAL.
        APPEND INITIAL LINE TO <sel>-seltab ASSIGNING <sl>.
        <sl>-field  = 'STATUS'.
        <sl>-sign   = 'I'.
        <sl>-option = 'EQ'.
        <sl>-low    = status.
      ENDIF.

      CALL FUNCTION 'SE16N_INTERFACE'
        EXPORTING
          i_tab           = 'YDK_TRANSFER'
*         I_EDIT          = ' '
*         I_SAPEDIT       = ' '
*         I_NO_TXT        = ' '
          i_max_lines     = 100000
*         I_LINE_DET      = ' '
*         I_DISPLAY       = 'X'
*         I_CLNT_SPEZ     = ' '
*         I_CLNT_DEP      = ' '
*         I_VARIANT       = ' '
*         I_OLD_ALV       = ' '
*         I_CHECKKEY      = ' '
*         I_TECH_NAMES    = ' '
*         I_CWIDTH_OPT_OFF            = ' '
*         I_SCROLL        = ' '
*         I_NO_CONVEXIT   = ' '
*         I_LAYOUT_GET    = ' '
*         I_ADD_FIELD     =
*         I_ADD_FIELDS_ON =
*         I_UNAME         =
*         I_HANA_ACTIVE   = ' '
*         I_DBCON         = ' '
*         I_OJKEY         = ' '
*         I_DISPLAY_ALL   = ' '
*       IMPORTING
*         E_LINE_NR       =
*         E_DREF          =
*         ET_FIELDCAT     =
        TABLES
*         IT_SELFIELDS    =
*         IT_OUTPUT_FIELDS            =
          it_or_selfields = itsel
*         IT_CALLBACK_EVENTS          =
*         IT_ADD_UP_CURR_FIELDS       =
*         IT_ADD_UP_QUAN_FIELDS       =
*         IT_SUM_UP_FIELDS            =
*         IT_GROUP_BY_FIELDS          =
*         IT_ORDER_BY_FIELDS          =
*         IT_AGGREGATE_FIELDS         =
*         IT_TOPLOW_FIELDS            =
*         IT_SORTORDER_FIELDS         =
*       CHANGING
*         IT_AND_SELFIELDS            =
        EXCEPTIONS
          no_values       = 1
          OTHERS          = 2.
  ENDCASE.
ENDFORM.                    "ALV_COMMAND
