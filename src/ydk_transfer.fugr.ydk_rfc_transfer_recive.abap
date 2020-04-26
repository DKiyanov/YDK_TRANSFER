FUNCTION ydk_rfc_transfer_recive.
*"----------------------------------------------------------------------
*"*"Локальный интерфейс:
*"  IMPORTING
*"     VALUE(CLUSTER) TYPE  XSTRING
*"----------------------------------------------------------------------

  IMPORT tab TO <rtab> FROM DATA BUFFER cluster.

  IF equally IS INITIAL.
    REFRESH <stab>.
    LOOP AT <rtab> ASSIGNING <rwa>.
      APPEND INITIAL LINE TO <stab> ASSIGNING <swa>.
      MOVE-CORRESPONDING <rwa> TO <swa>.
    ENDLOOP.
  ENDIF.

  LOOP AT itconv_fld.
    PERFORM (itconv_fld-convform) IN PROGRAM (sy-repid) TABLES <stab> USING itconv_fld-fieldname.
  ENDLOOP.

  DATA: ct_row TYPE i.
  ct_row = lines( <stab> ).
  ADD ct_row TO gct_key_recived.

  CASE mode.
    WHEN 'I'.
      INSERT (g_tabname) FROM TABLE <stab>.
    WHEN 'S'.
      INSERT (g_tabname) FROM TABLE <stab> ACCEPTING DUPLICATE KEYS.
    WHEN 'M'.
      PERFORM modify_from_tab.
    WHEN 'H'.
      PERFORM key_hash_store.
      PERFORM modify_from_tab.
  ENDCASE.
ENDFUNCTION.

FORM conv_logsys TABLES tab USING fieldname.
  DATA: where_str TYPE string.
  FIELD-SYMBOLS <logsys>.

  ASSIGN COMPONENT fieldname OF STRUCTURE tab TO <logsys>.
  <logsys> = g_dst_logsys.

  where_str = |{ fieldname } = '{ g_src_logsys }'|.

  MODIFY tab TRANSPORTING (fieldname) WHERE (where_str).
ENDFORM.
