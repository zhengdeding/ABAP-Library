CLASS zcl_bc_sap_system DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    CONSTANTS:
      c_dest_dev   TYPE rfcdest VALUE 'TDECLNT100',
      c_dest_live  TYPE rfcdest VALUE 'TPECLNT100',
      c_dest_qa    TYPE rfcdest VALUE 'TQECLNT100',

      c_sysid_dev  TYPE sysysid VALUE 'TDE',
      c_sysid_live TYPE sysysid VALUE 'TPE',
      c_sysid_qa   TYPE sysysid VALUE 'TQE'.

    CLASS-METHODS:

      convert_dest_to_sysid
        IMPORTING !iv_dest        TYPE tmscsys-sysnam
        RETURNING VALUE(rv_sysid) TYPE sysysid,

      convert_sysid_to_dest
        IMPORTING !iv_sysid      TYPE sysysid
        RETURNING VALUE(rv_dest) TYPE tmscsys-sysnam,

      delete_user_session
        IMPORTING
          !iv_bname TYPE xubname
        RAISING
          zcx_bc_function_subrc,

      expel_everyone_from_tcode
        importing
          !iv_tcode type tcode
        raising
          cx_Ssi_no_auth
          zcx_bc_function_subrc,

      is_current_system_live RETURNING VALUE(rv_live) TYPE abap_bool.

  PROTECTED SECTION.
  PRIVATE SECTION.

    TYPES:
      tt_msxxlist TYPE STANDARD TABLE OF msxxlist WITH DEFAULT KEY,
      tt_uinfo    TYPE STANDARD TABLE OF uinfo    WITH DEFAULT KEY,
      tt_usrlist  TYPE STANDARD TABLE OF usrinfo  WITH DEFAULT KEY.

ENDCLASS.



CLASS zcl_bc_sap_system IMPLEMENTATION.

  METHOD convert_dest_to_sysid.

    rv_sysid = SWITCH #( iv_dest
        WHEN c_dest_dev  THEN c_sysid_dev
        WHEN c_dest_qa   THEN c_sysid_qa
        WHEN c_dest_live THEN c_sysid_live
    ).

    ASSERT rv_sysid IS NOT INITIAL.

  ENDMETHOD.

  METHOD convert_sysid_to_dest.

    rv_dest = SWITCH #( iv_sysid
        WHEN c_sysid_dev  THEN c_dest_dev
        WHEN c_sysid_qa   THEN c_dest_qa
        WHEN c_sysid_live THEN c_dest_live
    ).

    ASSERT rv_dest IS NOT INITIAL.

  ENDMETHOD.

  METHOD delete_user_session.

    DATA:
      lt_servers TYPE tt_msxxlist,
      lt_uinfo   TYPE tt_uinfo,
      lt_usrlist TYPE tt_usrlist.

    CALL FUNCTION 'TH_SERVER_LIST'
      TABLES
        list           = lt_servers
      EXCEPTIONS
        no_server_list = 1
        OTHERS         = 2
        ##FM_SUBRC_OK.
    zcx_bc_function_subrc=>raise_if_sysubrc_not_initial( 'TH_SERVER_LIST' ).

    CALL FUNCTION 'TH_USER_LIST'
      TABLES
        list          = lt_uinfo
        usrlist       = lt_usrlist
      EXCEPTIONS
        auth_misssing = 1
        OTHERS        = 2
        ##FM_SUBRC_OK.
    zcx_bc_function_subrc=>raise_if_sysubrc_not_initial( 'TH_SERVER_LIST' ).

    LOOP AT lt_servers ASSIGNING FIELD-SYMBOL(<ls_server>).
      LOOP AT lt_usrlist
        ASSIGNING FIELD-SYMBOL(<ls_user>)
        WHERE bname EQ iv_bname.

        CALL 'ThSndDelUser'
          ID 'MANDT'  FIELD sy-mandt
          ID 'BNAME'  FIELD <ls_user>-bname
          ID 'SERVER' FIELD <ls_server>-name
          ID 'TID'    FIELD <ls_user>-tid.

      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.

  method expel_everyone_from_tcode.

    datA(lt_sessions) = new cl_server_info( )->get_session_list( with_application_info = 1 ).

    loop at lt_sessions
      assigning field-symbol(<ls_session>)
      where tenant eq sy-mandt.

      data(lv_tcode) = conv sytcode( <ls_session>-application ).
      check lv_tcode eq iv_tcode.

      call function 'TH_DELETE_USER'
        EXPORTING
          user             = <ls_session>-user_name
          client           = <ls_session>-tenant
          tid              = <ls_session>-logon_hdl
          logon_id         = <ls_Session>-logon_id
        EXCEPTIONS
          authority_error  = 1
          others           = 2
        ##FM_SUBRC_OK .

      zcx_bc_function_subrc=>raise_if_sysubrc_not_initial( 'TH_DELETE_USER' ).

    endloop.

  endmethod.

  METHOD is_current_system_live.
    rv_live = xsdbool( sy-sysid EQ c_sysid_live ).
  ENDMETHOD.

ENDCLASS.