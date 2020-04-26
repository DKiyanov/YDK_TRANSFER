FUNCTION ydk_rfc_transfer_init.
*"----------------------------------------------------------------------
*"*"Локальный интерфейс:
*"  IMPORTING
*"     VALUE(TABNAME) TYPE  TABNAME
*"     VALUE(CLUSTER) TYPE  XSTRING
*"     VALUE(CLRDATA) TYPE  YDK_TRANSFER_CLR_MODE
*"     VALUE(MODIFY_MODE) TYPE  YDK_TRANSFER_MODIFY_MODE DEFAULT ' '
*"     VALUE(LOGSYS) TYPE  LOGSYS
*"  EXCEPTIONS
*"      TABLE_NOT_FOUND
*"      ERR_ON_CREATE_STRUCT
*"----------------------------------------------------------------------

* clrdata = 'H'. modify_mode = 'A'. " Для отладки

  DATA: oref TYPE REF TO cx_root.
  DATA: stab_ref TYPE REF TO data.
  DATA: itscomp TYPE if_salv_bs_t_data=>t_type_component.
  DATA: itrcomp TYPE if_salv_bs_t_data=>t_type_component.
  DATA: rtab_ref TYPE REF TO data.

  g_tabname = tabname.
  g_src_logsys = logsys.

  CLEAR equally.
  REFRESH itconv_fld.
  mode = 'M'.

  TRY.
      CREATE DATA stab_ref TYPE STANDARD TABLE OF (tabname).
      ASSIGN stab_ref->* TO <stab>.
    CATCH cx_root INTO oref.
      RAISE table_not_found.
  ENDTRY.

  itscomp = cl_salv_bs_ddic=>get_components_by_data( <stab> ).

  IMPORT itcomponent TO itrcomp FROM DATA BUFFER cluster.

  IF itscomp = itrcomp.
    equally = 'X'.
    ASSIGN <stab> TO <rtab>.
  ENDIF.
  IF equally IS INITIAL.
    TRY.
        CALL METHOD cl_salv_bs_ddic=>create_data_from_components
          EXPORTING
            t_component = itrcomp
          IMPORTING
            r_data      = rtab_ref.
      CATCH cx_root INTO oref.
        RAISE err_on_create_struct.
    ENDTRY.

    ASSIGN rtab_ref->* TO <rtab>.
  ENDIF.

  PERFORM check_logsys USING itscomp.

  IF clrdata CA 'IX'.
    mode = 'I'.
    PERFORM clear_tab USING tabname itscomp.
  ENDIF.
  IF clrdata = 'H'.
    mode = 'H'.
    PERFORM build_keytab USING tabname itscomp.
  ENDIF.

  PERFORM modify_from_tab_prepare USING modify_mode.
ENDFUNCTION.

FORM build_keytab USING tabname itcomp TYPE if_salv_bs_t_data=>t_type_component.
* Создаём ключевую таблицу
  DATA: ltcomp TYPE if_salv_bs_t_data=>t_type_component.
  DATA: ctkf TYPE i.
  DATA: tabix TYPE i.
  DATA: ktab_ref TYPE REF TO data.
  DATA: key_ref TYPE REF TO data.
  DATA: oref TYPE REF TO cx_root.

  SELECT fieldname INTO TABLE itkeyfld
    FROM dd03l
   WHERE tabname  = tabname
     AND as4local = 'A'
     AND as4vers  = '0000'
     AND keyflag  = 'X'
     AND datatype <> '' " Исключаем .Include ...
   ORDER BY position.

* из структуры таблицы удаляем  все поля ниже последнего ключевого поля
* у несколких таблиц почемуто изменяются имена полей (похоже обрезаются), поэтому просто отсчитываем
* заданное количество ключевых полней в структуре, остальные обрезаем
  ctkf = lines( itkeyfld ).
  ltcomp = itcomp.
  LOOP AT ltcomp ASSIGNING FIELD-SYMBOL(<comp>).
    CHECK <comp>-kind = cl_abap_typedescr=>kind_elem. " include и т.п.
    SUBTRACT 1 FROM ctkf.
    IF ctkf = 0.
      tabix = sy-tabix + 1.
      EXIT.
    ENDIF.
  ENDLOOP.
  DELETE ltcomp FROM tabix.

  TRY.
      CALL METHOD cl_salv_bs_ddic=>create_data_from_components
        EXPORTING
          t_component = ltcomp
        IMPORTING
          r_data      = ktab_ref.

    CATCH cx_root INTO oref.
*      RAISE err_on_create_struct. " проблемных таблиц не много, и они в основном пустые
      CREATE DATA ktab_ref LIKE <stab>.
      invalid_key_tab = 'X'.
  ENDTRY.

  ASSIGN ktab_ref->* TO <keytab>.

  CREATE DATA key_ref LIKE LINE OF <keytab>.
  ASSIGN key_ref->* TO <key_wa>.
ENDFORM.

* Отчистка таблицы перед загрузкой
FORM clear_tab USING tabname itcomp TYPE if_salv_bs_t_data=>t_type_component.
* Некоторые таблицы очень большие, поэтому не возможно выполнить удаление данных
* просто написав Delete from (tabname) - не хватает roll back сегмента для отката транзакции
* поэтому приходится извращаться

  PERFORM build_keytab USING tabname itcomp.

* Читаем ключи удаляем записи
  DATA: cur TYPE cursor.

  OPEN CURSOR WITH HOLD cur FOR
    SELECT (itkeyfld)
      FROM (tabname).
  DO.
    FETCH NEXT CURSOR cur INTO TABLE <keytab> PACKAGE SIZE 1000.
    IF sy-subrc <> 0. EXIT. ENDIF.
    DELETE (tabname) FROM TABLE <keytab>.
    CALL FUNCTION 'DB_COMMIT'.
  ENDDO.
  CLOSE CURSOR cur.
ENDFORM.

FORM check_logsys USING itcomp TYPE if_salv_bs_t_data=>t_type_component.
  LOOP AT itcomp ASSIGNING FIELD-SYMBOL(<comp>) WHERE s_elem-domain = 'LOGSYS'.
    itconv_fld-fieldname = <comp>-name.
    itconv_fld-convform  = 'CONV_LOGSYS'.
    APPEND itconv_fld.

    IF g_dst_logsys IS INITIAL.
      SELECT SINGLE logsys INTO g_dst_logsys
        FROM t000
       WHERE mandt = sy-mandt.
    ENDIF.
  ENDLOOP.
ENDFORM.
