FUNCTION-POOL ydk_transfer.                 "MESSAGE-ID ..

* INCLUDE LYDK_TRANSFERD...                  " Local class definition

DATA: g_tabname TYPE dd03l-tabname.
DATA: equally TYPE c.
DATA: invalid_key_tab TYPE c.
DATA: modify_mode TYPE c. " Режим выполнения modify table - 'A' - без обновления не изменённых записей в БД
DATA: mode TYPE c.

FIELD-SYMBOLS <rwa>  TYPE any.
FIELD-SYMBOLS <rtab> TYPE STANDARD TABLE.

FIELD-SYMBOLS <swa>  TYPE any.
FIELD-SYMBOLS <stab> TYPE STANDARD TABLE.

FIELD-SYMBOLS <keytab> TYPE STANDARD TABLE.
FIELD-SYMBOLS <key_wa>  TYPE any.
FIELD-SYMBOLS <key>  TYPE any.
DATA: itkeyfld TYPE STANDARD TABLE OF dd03l-fieldname WITH HEADER LINE.

FIELD-SYMBOLS <mandt> TYPE c.

DATA: g_dst_logsys TYPE t000-logsys.
DATA: g_src_logsys TYPE t000-logsys.

DATA: BEGIN OF itconv_fld OCCURS 0,
        fieldname TYPE string,
        convform  TYPE string,
      END   OF itconv_fld.

DATA: ithkey TYPE STANDARD TABLE OF ydk_transfer_key_hash.

FIELD-SYMBOLS <mwa>  TYPE any.
FIELD-SYMBOLS <mtab> TYPE STANDARD TABLE.
DATA: m_db_where TYPE string.
DATA: m_it_where TYPE string.

DATA: gct_key_checked TYPE i. " Количество успешно провереных ключей в базе получателя
DATA: gct_key_recived TYPE i. " Количество полученных записей

FORM key_to_str USING key xstr TYPE xstring.
  ASSIGN COMPONENT 1 OF STRUCTURE key TO <mandt>.
  CLEAR <mandt>.

  EXPORT key TO DATA BUFFER xstr.
ENDFORM.

FORM calc_hash USING hashdata hash.
  DATA: hashx TYPE hash160x.

  CALL FUNCTION 'CALCULATE_HASH_FOR_RAW'
    EXPORTING
      alg            = 'MD5'
      data           = hashdata
*     LENGTH         = 0
    IMPORTING
*     HASH           =
*     HASHLEN        =
      hashx          = hashx
*     HASHXLEN       =
*     HASHSTRING     =
*     HASHXSTRING    =
*     HASHB64STRING  =
    EXCEPTIONS
      unknown_alg    = 1
      param_error    = 2
      internal_error = 3
      OTHERS         = 4.

  hash = hashx.
ENDFORM.

FORM move_key USING row key.
  IF invalid_key_tab IS INITIAL.
    MOVE-CORRESPONDING row TO key.
    RETURN.
  ENDIF.

  FIELD-SYMBOLS <src> TYPE any.
  FIELD-SYMBOLS <dst> TYPE any.

  CLEAR key.
  LOOP AT itkeyfld.
    ASSIGN COMPONENT itkeyfld OF STRUCTURE row TO <src>.
    ASSIGN COMPONENT itkeyfld OF STRUCTURE key TO <dst>.
    <dst> = <src>.
  ENDLOOP.
ENDFORM.

FORM key_hash_store.
  DATA: key_xstr TYPE xstring.
  DATA: hkey TYPE ydk_transfer_key_hash.

  LOOP AT <stab> ASSIGNING <swa>.
    PERFORM move_key USING <swa> <key_wa>.
    PERFORM key_to_str USING <key_wa> key_xstr.
    PERFORM calc_hash USING key_xstr hkey.

    READ TABLE ithkey WITH KEY table_line = hkey TRANSPORTING NO FIELDS BINARY SEARCH.
    IF sy-subrc <> 0.
      INSERT hkey INTO ithkey INDEX sy-tabix.
    ENDIF.
  ENDLOOP.
ENDFORM.

FORM key_hash_removal_of_excess.
  CHECK mode = 'H'.
* читаем ключи из таблицы и проверяем наличие их среди переданных
* лишние удаляем

  DATA: cur TYPE cursor.

  OPEN CURSOR WITH HOLD cur FOR
    SELECT (itkeyfld)
      FROM (g_tabname).
  DO.
    FETCH NEXT CURSOR cur INTO TABLE <keytab> PACKAGE SIZE 1000.
    IF sy-subrc <> 0. EXIT. ENDIF.

    PERFORM check_keys.
  ENDDO.
  CLOSE CURSOR cur.
ENDFORM.

FORM check_keys.
  DATA: key_xstr TYPE xstring.
  DATA: hkey TYPE ydk_transfer_key_hash.
  DATA: tabix TYPE sy-tabix.

  LOOP AT <keytab> ASSIGNING <key>.
    tabix = sy-tabix.

    PERFORM key_to_str USING <key> key_xstr.
    PERFORM calc_hash USING key_xstr hkey.

    READ TABLE ithkey WITH KEY table_line = hkey BINARY SEARCH TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      ADD 1 TO gct_key_checked.

      DELETE <keytab> INDEX tabix.
    ENDIF.
  ENDLOOP.

  IF NOT <keytab> IS INITIAL. " Остались записи ключи которые нужно удалить
    DELETE (g_tabname) FROM TABLE <keytab>.
    CALL FUNCTION 'DB_COMMIT'.
  ENDIF.
ENDFORM.

FORM modify_from_tab_prepare USING pmodify_mode.
  DATA: mtab_ref TYPE REF TO data.

  modify_mode = pmodify_mode.

  CHECK modify_mode = 'A'.

  CREATE DATA mtab_ref TYPE STANDARD TABLE OF (g_tabname).
  ASSIGN mtab_ref->* TO <mtab>.

  CHECK lines( itkeyfld ) > 1.

  LOOP AT itkeyfld FROM 2. " Первое поле mandt
    CONCATENATE m_db_where ` AND ` itkeyfld ` = <stab>-` itkeyfld INTO m_db_where.
    CONCATENATE m_it_where ` AND ` itkeyfld ` = <mwa>-`  itkeyfld INTO m_it_where.
  ENDLOOP.
  SHIFT m_db_where BY 5 PLACES.
  SHIFT m_it_where BY 5 PLACES.
ENDFORM.

FORM modify_from_tab.
  CHECK NOT <stab> IS INITIAL.

  IF modify_mode IS INITIAL.
    MODIFY (g_tabname) FROM TABLE <stab>.
    RETURN.
  ENDIF.

* выбираем записи таблицы g_tabname в таблицу <mtab> с такимеже ключами как в <stab> и с такимже содержимым
* проходим по <mtab> и удаляем идентичные записи из <stab>
* обновляем таблицу g_tabname из <mtab>

  SELECT * INTO TABLE <mtab>
    FROM (g_tabname)
     FOR ALL ENTRIES IN <stab>
   WHERE (m_db_where).

  LOOP AT <mtab> ASSIGNING <mwa>.
    LOOP AT <stab> ASSIGNING <swa> WHERE (m_it_where).
      ASSIGN COMPONENT 1 OF STRUCTURE <swa> TO <mandt>.
      <mandt> = sy-mandt.
      IF <swa> = <mwa>.
        DELETE <stab> INDEX sy-tabix.
      ENDIF.

      EXIT.
    ENDLOOP.
  ENDLOOP.

  CHECK NOT <stab> IS INITIAL.
  MODIFY (g_tabname) FROM TABLE <stab>.
ENDFORM.
