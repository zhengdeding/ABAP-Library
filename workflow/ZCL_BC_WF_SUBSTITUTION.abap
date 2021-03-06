CLASS zcl_bc_wf_substitution DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    TYPES: BEGIN OF t_param,
             main_user TYPE xubname,
             sub_user  TYPE xubname,
             from_date TYPE objec-begda,
             to_date   TYPE objec-endda,
             reppr     TYPE padd2-reppr,
             active    TYPE padd2-active,
           END OF t_param,

           tt_profile_rng TYPE RANGE OF hr_rep_prf.

    CLASS-METHODS check_foreign_sub_auth
      RAISING
        zcx_bc_authorization.

    CLASS-METHODS get_substitudes
      IMPORTING
        !iv_main_user         TYPE hrus_d2-us_name
        !it_profile_rng       TYPE tt_profile_rng OPTIONAL
      RETURNING
        VALUE(rt_substitudes) TYPE rsec_t_users.

    CLASS-METHODS is_substitude
      IMPORTING
        !iv_main_user           TYPE xubname
        !iv_substitude          TYPE xubname
      RETURNING
        VALUE(rv_is_substitude) TYPE abap_bool.

    CLASS-METHODS validate_reppr_usability
      IMPORTING
        !iv_reppr TYPE t77ro-reppr
      RAISING
        zcx_bc_reppr.

    METHODS send_mail
      RAISING
        zcx_bc_method_parameter
        zcx_bc_mail_send
        zcx_bc_table_content.

    METHODS set_auth_to_substitudes
      CHANGING
        co_log TYPE REF TO zcl_bc_applog_facade
      RAISING
        zcx_bc_table_content.

    METHODS set_substitude
      IMPORTING
        !is_param TYPE t_param
      RAISING
        zcx_bc_wf_substitution.

  PROTECTED SECTION.
  PRIVATE SECTION.

    TYPES: BEGIN OF t_agr_users,
             agr_name TYPE agr_users-agr_name,
             uname    TYPE agr_users-uname,
             from_dat TYPE agr_users-from_dat,
             to_dat   TYPE agr_users-to_dat,
           END OF t_agr_users,

           BEGIN OF t_sub_role,
             tclass       TYPE zbct_wf_sub_role-tclass,
             agr_name_rng TYPE RANGE OF zbct_wf_sub_role-agr_name,
           END OF t_sub_role,

           tt_agr_users TYPE STANDARD TABLE OF t_agr_users WITH DEFAULT KEY,
           tt_bapiagr   TYPE STANDARD TABLE OF bapiagr WITH DEFAULT KEY,
           tt_sub_role  TYPE STANDARD TABLE OF t_sub_role WITH DEFAULT KEY.

    CONSTANTS: c_clsname            TYPE seoclsname         VALUE 'ZCL_BC_WF_SUBSTITUTION',
               c_meth_mail          TYPE seocpdname         VALUE 'SEND_MAIL',
               c_msgid_zbc          TYPE symsgid            VALUE 'ZBC',
               c_otype_user         TYPE otype              VALUE 'US',
               c_param_wf_mail_from TYPE zbct_par_val-pname VALUE 'WF_MAIL_FROM',
               c_plvar              TYPE plvar              VALUE '01',
               c_sign_i             TYPE ddsign             VALUE 'I'.

    DATA: gs_param   TYPE t_param,
          gv_sub_set TYPE abap_bool.

    METHODS append_agr_to_user
      IMPORTING
        !iv_uname TYPE bapibname-bapibname
        !it_agr   TYPE tt_bapiagr
      EXPORTING
        !et_ret   TYPE bapiret2_tab.

    METHODS get_recipients
      RETURNING
        VALUE(rt_user) TYPE rke_userid
      RAISING
        zcx_bc_table_content.
ENDCLASS.



CLASS zcl_bc_wf_substitution IMPLEMENTATION.


  METHOD append_agr_to_user.

    DATA lt_agr TYPE tt_bapiagr.

*   Ön kontroller
    CHECK it_agr[] IS NOT INITIAL.
    CLEAR et_ret[].

*   İletilen roller
    lt_agr[] = it_agr[].

*   Kullanıcının mevcut rolleri
    SELECT agr_name from_dat to_dat org_flag
      APPENDING CORRESPONDING FIELDS OF TABLE lt_agr
      FROM agr_users
      WHERE uname EQ iv_uname
      ##TOO_MANY_ITAB_FIELDS.

    SORT lt_agr BY agr_name from_dat to_dat.
    DELETE ADJACENT DUPLICATES FROM lt_agr COMPARING agr_name from_dat to_dat.

*   Metinleri tamamla
    LOOP AT lt_agr ASSIGNING FIELD-SYMBOL(<ls_agr>) WHERE agr_text IS INITIAL.

      SELECT SINGLE text
        INTO <ls_agr>-agr_text
        FROM agr_texts
        WHERE
          agr_name EQ <ls_agr>-agr_name AND
          spras    EQ sy-langu
        ##WARN_OK.

    ENDLOOP.

*   Kayıt
    CALL FUNCTION 'BAPI_USER_ACTGROUPS_ASSIGN'
      EXPORTING
        username       = iv_uname
      TABLES
        activitygroups = lt_agr
        return         = et_ret.

    COMMIT WORK AND WAIT.

  ENDMETHOD.


  METHOD check_foreign_sub_auth.

    AUTHORITY-CHECK OBJECT 'ZBCAO_WFSO' ID 'ACTVT' FIELD '78'.
    CHECK sy-subrc NE 0.

    RAISE EXCEPTION TYPE zcx_bc_authorization
      EXPORTING
        textid = zcx_bc_authorization=>no_auth.

  ENDMETHOD.


  METHOD get_recipients.

    SELECT uname INTO TABLE rt_user FROM zbct_wf_sub_rcpt.

    LOOP AT rt_user ASSIGNING FIELD-SYMBOL(<lv_user>).

      TRY.
          zcl_bc_sap_user=>get_instance( <lv_user> ).
        CATCH cx_root.
          DELETE rt_user.
          CONTINUE.
      ENDTRY.

    ENDLOOP.

    CHECK rt_user[] IS INITIAL.

    RAISE EXCEPTION TYPE zcx_bc_table_content
      EXPORTING
        objectid = 'UNAME'
        tabname  = 'ZBCT_WF_SUB_RCPT'
        textid   = zcx_bc_table_content=>entry_missing.

  ENDMETHOD.


  METHOD get_substitudes.
    SELECT DISTINCT rep_name
           FROM hrus_d2
           WHERE us_name EQ @iv_main_user   AND
                 begda   LE @sy-datum       AND
                 endda   GE @sy-datum       AND
                 reppr   IN @it_profile_rng AND
                 active  EQ @abap_true
           INTO TABLE @rt_substitudes.
  ENDMETHOD.


  METHOD is_substitude.
    SELECT SINGLE mandt FROM hrus_d2
           WHERE us_name  EQ @iv_main_user  AND
                 rep_name EQ @iv_substitude AND
                 begda    LE @sy-datum      AND
                 endda    GE @sy-datum      AND
                 active   EQ @abap_true
           INTO @DATA(lv_mandt).

    rv_is_substitude = xsdbool( sy-subrc EQ 0 ).
  ENDMETHOD.


  METHOD send_mail.

    DATA lv_rtext TYPE t77rq-rtext.

    IF gv_sub_set EQ abap_false.
      RAISE EXCEPTION TYPE zcx_bc_method_parameter
        EXPORTING
          class_name  = c_clsname
          method_name = c_meth_mail
          textid      = zcx_bc_method_parameter=>param_error.
    ENDIF.

    SELECT SINGLE rtext INTO lv_rtext
           FROM t77rq
           WHERE langu EQ sy-langu
             AND reppr EQ gs_param-reppr.

    zcl_bc_mail_facade=>send_email( iv_from    = CONV #( zcl_bc_par_master=>get_val_single( c_param_wf_mail_from ) )
                                    it_to      = get_recipients( )
                                    iv_subject = TEXT-954
                                    it_body    = VALUE #( ( zcl_bc_toolkit=>get_symsg_as_text( VALUE symsg( msgid = c_msgid_zbc
                                                                                                            msgno = SWITCH #( gs_param-active WHEN abap_true THEN 098 ELSE 101 )
                                                                                                            msgty = zcl_bc_applog_facade=>c_msgty_s
                                                                                                            msgv1 = gs_param-main_user
                                                                                                            msgv2 = gs_param-sub_user
                                                                                                            msgv3 = gs_param-from_date
                                                                                                            msgv4 = gs_param-to_date ) ) )

                                                          ( zcl_bc_toolkit=>get_symsg_as_text( VALUE symsg( msgid = c_msgid_zbc
                                                                                                            msgno = 099
                                                                                                            msgty = zcl_bc_applog_facade=>c_msgty_s
                                                                                                            msgv1 = gs_param-reppr
                                                                                                            msgv2 = lv_rtext ) ) ) ) ).

  ENDMETHOD.


  METHOD set_auth_to_substitudes.

    DATA: lt_agr         TYPE tt_bapiagr,
          lt_bapiret2    TYPE bapiret2_tab,
          lt_cust        TYPE STANDARD TABLE OF zbct_wf_sub_role,
          lt_cust_rng    TYPE tt_sub_role,
          lt_master_role TYPE tt_agr_users,
          lt_sub_role    TYPE tt_agr_users,
          lt_hrus_d2     TYPE STANDARD TABLE OF hrus_d2,
          lt_t77ro       TYPE STANDARD TABLE OF t77ro.

*   Verilmiş vekaletleri tespit et
    SELECT * INTO TABLE lt_hrus_d2
           FROM hrus_d2
           WHERE begda  LE sy-datum
             AND endda  GE sy-datum
             AND active EQ abap_true.

    CHECK sy-subrc EQ 0.

*   Vekalet verenlerin ve alanın var olan rollerini tespit et
    SELECT agr_name uname from_dat to_dat
           INTO CORRESPONDING FIELDS OF TABLE: lt_sub_role FROM agr_users
                                               FOR ALL ENTRIES IN lt_hrus_d2
                                               WHERE uname EQ lt_hrus_d2-rep_name,

                                               lt_master_role FROM agr_users
                                               FOR ALL ENTRIES IN lt_hrus_d2
                                               WHERE uname    EQ lt_hrus_d2-us_name
                                                 AND from_dat LE lt_hrus_d2-endda
                                                 AND to_dat   GE lt_hrus_d2-begda.

*   Vekil profillerinin tanımlarını al
    SELECT * INTO TABLE lt_t77ro
           FROM t77ro
           WHERE EXISTS ( SELECT tclass FROM zbct_wf_sub_role WHERE tclass EQ t77ro~tclass ).

*   Uyarlamayı oku
    SELECT * INTO TABLE lt_cust FROM zbct_wf_sub_role.

    IF sy-subrc NE 0.
      RAISE EXCEPTION TYPE zcx_bc_table_content
        EXPORTING
          objectid = 'ROLE'
          tabname  = 'ZBCT_WF_SUB_ROLE'
          textid   = zcx_bc_table_content=>entry_missing.
    ENDIF.

    lt_cust_rng = CORRESPONDING #( lt_cust ).
    SORT lt_cust_rng BY tclass.
    DELETE ADJACENT DUPLICATES FROM lt_cust_rng COMPARING tclass.

    LOOP AT lt_cust_rng ASSIGNING FIELD-SYMBOL(<ls_cust_rng>).
      LOOP AT lt_cust ASSIGNING FIELD-SYMBOL(<ls_cust>) WHERE tclass EQ <ls_cust_rng>-tclass.
        APPEND VALUE #( option = <ls_cust>-ddoption
                        sign   = c_sign_i
                        low    = <ls_cust>-agr_name ) TO <ls_cust_rng>-agr_name_rng.

      ENDLOOP.
    ENDLOOP.

*   Her bir vekalet kaydı için inceleme yapıp BAPI verilerini hazırla ve çağır

    LOOP AT lt_hrus_d2 ASSIGNING FIELD-SYMBOL(<ls_hrus_d2>).

      CLEAR lt_agr[].

      LOOP AT lt_cust_rng ASSIGNING <ls_cust_rng>.

        CHECK line_exists( lt_t77ro[ KEY primary_key COMPONENTS reppr  = <ls_hrus_d2>-reppr
                                                                tclass = <ls_cust_rng>-tclass ] ).

        LOOP AT lt_master_role ASSIGNING FIELD-SYMBOL(<ls_master_role>) WHERE agr_name IN <ls_cust_rng>-agr_name_rng
                                                                          AND uname    EQ <ls_hrus_d2>-us_name.

          LOOP AT lt_agr TRANSPORTING NO FIELDS WHERE agr_name EQ <ls_master_role>-agr_name
                                                  AND from_dat LE <ls_hrus_d2>-endda
                                                  AND to_dat   GE <ls_hrus_d2>-begda.
            EXIT.
          ENDLOOP.

          CHECK sy-subrc NE 0.

          MESSAGE s107(zbc) WITH <ls_hrus_d2>-us_name <ls_hrus_d2>-rep_name <ls_master_role>-agr_name.
          co_log->add_sy_msg( ).

          APPEND VALUE #( agr_name = <ls_master_role>-agr_name
                          from_dat = <ls_hrus_d2>-begda
                          to_dat   = <ls_hrus_d2>-endda ) TO lt_agr.

        ENDLOOP.

      ENDLOOP.

      CHECK lt_agr[] IS NOT INITIAL.

      LOOP AT lt_sub_role ASSIGNING FIELD-SYMBOL(<ls_sub_role>) WHERE uname EQ <ls_hrus_d2>-rep_name.

        APPEND VALUE #( agr_name = <ls_sub_role>-agr_name
                        from_dat = <ls_sub_role>-from_dat
                        to_dat   = <ls_sub_role>-to_dat ) TO lt_agr.
      ENDLOOP.

      append_agr_to_user( EXPORTING iv_uname = <ls_hrus_d2>-rep_name
                                    it_agr   = lt_agr
                          IMPORTING et_ret   = lt_bapiret2 ).

      co_log->add_bapiret2( lt_bapiret2 ).

    ENDLOOP.

  ENDMETHOD.


  METHOD set_substitude.

    TRY.

        gv_sub_set = abap_false.
        gs_param   = is_param.

        zcl_bc_sap_user=>get_instance(:
          is_param-main_user ),
          is_param-sub_user
        ).

        validate_reppr_usability( is_param-reppr ).

        CALL FUNCTION 'RH_SUBSTITUTION_MAINTAIN'
          EXPORTING
            act_plvar               = c_plvar
            act_otype               = c_otype_user
            act_objid               = is_param-main_user
            act_begda               = is_param-from_date
            act_endda               = is_param-to_date
            act_sclas               = c_otype_user
            act_sobid               = is_param-sub_user
            act_reppr               = is_param-reppr
            act_active              = is_param-active
            authority_check         = abap_false
            no_popup                = abap_true
          EXCEPTIONS
            source_object_not_valid = 1
            drain_object_not_valid  = 2
            time_interval_not_valid = 3
            exit_command            = 4
            enqueue_failed          = 5
            source_equal_drain      = 6
            subst_not_saved         = 7
            OTHERS                  = 8.

        IF sy-subrc NE 0.
          DATA(lo_cx_sy) = zcx_bc_symsg=>get_instance( ).
          RAISE EXCEPTION lo_cx_sy.
        ENDIF.

        gv_sub_set = abap_true.

      CATCH cx_root INTO DATA(lo_cx_root).

        RAISE EXCEPTION TYPE zcx_bc_wf_substitution
          EXPORTING
            main_user = is_param-main_user
            previous  = lo_cx_root
            sub_user  = is_param-sub_user
            textid    = zcx_bc_wf_substitution=>cant_set_substitude.

    ENDTRY.

  ENDMETHOD.


  METHOD validate_reppr_usability.

    SELECT SINGLE mandt
      INTO sy-mandt
      FROM t77ro
      WHERE
        reppr EQ iv_reppr AND
        EXISTS ( SELECT mandt FROM zbct_wf_sub_role WHERE tclass EQ t77ro~tclass )
      ##WARN_OK
      ##WRITE_OK.

    CHECK sy-subrc NE 0.

    RAISE EXCEPTION TYPE zcx_bc_reppr
      EXPORTING
        textid = zcx_bc_reppr=>not_in_zsubrole
        reppr  = iv_reppr.

  ENDMETHOD.
ENDCLASS.