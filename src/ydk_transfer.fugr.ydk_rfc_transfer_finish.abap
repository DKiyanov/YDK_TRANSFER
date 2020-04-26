FUNCTION ydk_rfc_transfer_finish.
*"----------------------------------------------------------------------
*"*"Локальный интерфейс:
*"  EXPORTING
*"     VALUE(OK) TYPE  FLAG
*"----------------------------------------------------------------------
  PERFORM key_hash_removal_of_excess.

  IF gct_key_checked = gct_key_recived.
    ok = 'X'.
  ENDIF.
ENDFUNCTION.
