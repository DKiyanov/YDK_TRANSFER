*&---------------------------------------------------------------------*
*& Report  YDK_TAB_ROW_COUNT
*& Report with the number of entries in the tables
*&---------------------------------------------------------------------*
*& Developed by Kiyanov Dmitry in 2019 year.
*& MIT License
*&---------------------------------------------------------------------*

REPORT ydk_tab_row_count.

DATA: xtabname TYPE dd02l-tabname.
SELECT-OPTIONS tabname FOR xtabname NO INTERVALS.
PARAMETERS: where TYPE string LOWER CASE.

DATA: xfield TYPE dd03l-fieldname.
SELECT-OPTIONS sfield FOR xfield NO INTERVALS.

DATA: BEGIN OF ittab OCCURS 0,
        tabname TYPE dd02l-tabname,
        count   TYPE i,
      END   OF ittab.

START-OF-SELECTION.
  PERFORM get_data.
  PERFORM alv_show.

FORM get_data.
  FIELD-SYMBOLS <tab> LIKE LINE OF ittab.

  SELECT dd02l~tabname INTO CORRESPONDING FIELDS OF TABLE @ittab
    FROM dd02l
    JOIN tadir
      ON tadir~pgmid     = 'R3TR'
     AND tadir~object    = 'TABL'
     AND tadir~obj_name  = dd02l~tabname
   WHERE dd02l~tabname   IN @tabname
     AND dd02l~as4local  = 'A'
     AND dd02l~as4vers   = '0000'
     AND dd02l~tabclass  IN ('TRANSP', 'CLUSTER', 'POOL').
*     AND dd02l~clidep    = 'X'
*     AND tadir~devclass  <> '$TMP'.
  CHECK NOT ittab[] IS INITIAL.

  DATA: wfield_count TYPE i.
  DATA: tfield_count TYPE i.

  wfield_count = lines( sfield ).

  LOOP AT ittab ASSIGNING <tab>.
    IF wfield_count > 0.
      SELECT COUNT( * ) INTO tfield_count
        FROM dd03l
       WHERE tabname = <tab>-tabname
         AND fieldname IN sfield
         AND as4local = 'A'
         AND as4vers  = '0000'.

      IF tfield_count <> wfield_count.
        <tab>-count = -1.
        CONTINUE.
      ENDIF.
    ENDIF.

    IF where IS INITIAL.
      SELECT COUNT( * ) AS count INTO CORRESPONDING FIELDS OF <tab>
        FROM (<tab>-tabname).
    ELSE.
      SELECT COUNT( * ) AS count INTO CORRESPONDING FIELDS OF <tab>
        FROM (<tab>-tabname)
       WHERE (where).
    ENDIF.
  ENDLOOP.

  DELETE ittab WHERE count < 0.
ENDFORM.

FORM alv_show.
  DATA: fc TYPE lvc_t_fcat WITH HEADER LINE.
  DATA: repid TYPE sy-repid.

  CALL FUNCTION 'YDK_ALV_FCAT_BUILD'
    EXPORTING
      alv_strut_key = 'YDK_TAB_ROW_COUNT'
*     structures    = ''
    TABLES
      alv_tab       = ittab
      fcat          = fc.

  repid = sy-repid.
  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY_LVC'
    EXPORTING
*     I_INTERFACE_CHECK  = ' '
*     I_BYPASSING_BUFFER =
*     I_BUFFER_ACTIVE    =
      i_callback_program = repid
*     i_callback_pf_status_set = 'ALV_STATUS_SET'
*     i_callback_user_command  = 'ALV_USER_COMMAND'
*     I_CALLBACK_TOP_OF_PAGE   = ' '
*     I_CALLBACK_HTML_TOP_OF_PAGE       = ' '
*     I_CALLBACK_HTML_END_OF_LIST       = ' '
*     I_STRUCTURE_NAME   =
*     I_BACKGROUND_ID    = ' '
*     I_GRID_TITLE       =
*     I_GRID_SETTINGS    =
*     IS_LAYOUT_LVC      =
      it_fieldcat_lvc    = fc[]
*     IT_EXCLUDING       =
*     IT_SPECIAL_GROUPS_LVC    =
*     IT_SORT_LVC        =
*     IT_FILTER_LVC      =
*     IT_HYPERLINK       =
*     IS_SEL_HIDE        =
*     I_DEFAULT          = 'X'
      i_save             = 'A'
*     IS_VARIANT         =
*     IT_EVENTS          =
*     IT_EVENT_EXIT      =
*     IS_PRINT_LVC       =
*     IS_REPREP_ID_LVC   =
*     I_SCREEN_START_COLUMN    = 0
*     I_SCREEN_START_LINE      = 0
*     I_SCREEN_END_COLUMN      = 0
*     I_SCREEN_END_LINE  = 0
*     I_HTML_HEIGHT_TOP  =
*     I_HTML_HEIGHT_END  =
*     IT_ALV_GRAPHICS    =
*     IT_EXCEPT_QINFO_LVC      =
*     IR_SALV_FULLSCREEN_ADAPTER        =
    TABLES
      t_outtab           = ittab
    EXCEPTIONS
      program_error      = 1
      OTHERS             = 2.
ENDFORM.                    "alv_show
