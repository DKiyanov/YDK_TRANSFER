FUNCTION ydk_rfc_transfer_postproc.
*"----------------------------------------------------------------------
*"*"Локальный интерфейс:
*"  IMPORTING
*"     VALUE(TABNAME) TYPE  TABNAME
*"     VALUE(TEST) TYPE  FLAG
*"  EXPORTING
*"     VALUE(OK) TYPE  FLAG
*"----------------------------------------------------------------------

  ok = 'X'.
  CASE tabname.
    WHEN 'NRIV'.
      CHECK test IS INITIAL.
      PERFORM reset_num_buffer.
    WHEN OTHERS.
      CLEAR ok.
  ENDCASE.
ENDFUNCTION.

FORM reset_num_buffer.
* скопировано и адаптировано из тр SM56 программа RSM56000 подпрограмма USER_COMMAND событие 'RSET'
  DATA: opcode     TYPE x.
  DATA: noselect   TYPE noselect.
  DATA: reset_mode TYPE x.

  noselect-norsetglob = 'X'.
  reset_mode = 2.
  opcode = 3.

  CALL 'ThNoCall' ID 'OPCODE' FIELD opcode
    ID 'BNRIV' FIELD noselect
    ID 'RESETMODE' FIELD reset_mode.
ENDFORM.
