CLASS zcl_bc_wf_toolkit DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    CONSTANTS:
      c_wi_type_w TYPE sww_witype VALUE 'W'.

    CLASS-METHODS:
      cancel_old_active_workflows
        IMPORTING
          !iv_catid  TYPE sww_wi2obj-catid
          !iv_instid TYPE sww_wi2obj-instid
          !iv_typeid TYPE sww_wi2obj-typeid,

      get_first_agent_from_history
        IMPORTING
          !iv_task        TYPE sww_wi2obj-wi_rh_task
          !iv_instid      TYPE sww_wi2obj-instid
          !iv_typeid      TYPE sww_wi2obj-typeid
        RETURNING
          VALUE(rv_agent) TYPE SWW_AAGENT
        RAISING
          zcx_bc_wf_approver,

      refresh_buffer EXPORTING et_msg TYPE tab_bdcmsgcoll.

  PROTECTED SECTION.
  PRIVATE SECTION.

    TYPES tt_status_range TYPE RANGE OF sww_wistat.

    CONSTANTS:
      BEGIN OF c_status,
        waiting    TYPE sww_wistat VALUE 'WAITING',
        ready      TYPE sww_wistat VALUE 'READY',
        selected   TYPE sww_wistat VALUE 'SELECTED',
        started    TYPE sww_wistat VALUE 'STARTED',
        error      TYPE sww_wistat VALUE 'ERROR',
        committed  TYPE sww_wistat VALUE 'COMMITTED',
        completed  TYPE sww_wistat VALUE 'COMPLETED',
        cancelled  TYPE sww_wistat VALUE 'CANCELLED',
        checked    TYPE sww_wistat VALUE 'CHECKED',
        excpcaught TYPE sww_wistat VALUE 'EXCPCAUGHT',
        excphandlr TYPE sww_wistat VALUE 'EXCPHANDLR',
      END OF c_status,

      c_tcode_buff_refr TYPE sytcode VALUE 'SWU_OBUF'.

    CLASS-METHODS:
      get_active_status_range RETURNING VALUE(rt_range) TYPE tt_status_range,

      get_active_wiids_of_sap_object
        IMPORTING
                  !iv_catid       TYPE sww_wi2obj-catid
                  !iv_instid      TYPE sww_wi2obj-instid
                  !iv_typeid      TYPE sww_wi2obj-typeid
        RETURNING VALUE(rt_wiids) TYPE usmd_t_wi.

ENDCLASS.



CLASS zcl_bc_wf_toolkit IMPLEMENTATION.


  METHOD cancel_old_active_workflows.

    DATA(lt_active_wiids) = get_active_wiids_of_sap_object( iv_catid  = iv_catid
                                                            iv_instid = iv_instid
                                                            iv_typeid = iv_typeid ).

    IF lines( lt_active_wiids ) LE 1.
      RETURN.
    ENDIF.

    SORT lt_active_wiids DESCENDING.
    DELETE lt_active_wiids INDEX 1.

    LOOP AT lt_active_wiids ASSIGNING FIELD-SYMBOL(<lv_obsolete_wiid>).
      CALL FUNCTION 'SAP_WAPI_ADM_WORKFLOW_CANCEL'
        EXPORTING
          workitem_id = <lv_obsolete_wiid>.
    ENDLOOP.

  ENDMETHOD.


  METHOD get_active_status_range.
    rt_range = VALUE #( sign   = zcl_bc_ddic_toolkit=>c_sign_e
                        option = zcl_bc_ddic_toolkit=>c_option_eq
                        ( low = c_status-cancelled )
                        ( low = c_status-completed ) ).
  ENDMETHOD.


  METHOD get_active_wiids_of_sap_object.
    DATA(lt_active_status_range) = get_active_status_range( ).

    SELECT _obj~wi_id
           FROM sww_wi2obj AS _obj
                INNER JOIN swwwihead AS _head ON _head~wi_id EQ _obj~wi_id
           WHERE _obj~catid    EQ @iv_catid  AND
                 _obj~instid   EQ @iv_instid AND
                 _obj~typeid   EQ @iv_typeid AND
                 _head~wi_stat IN @lt_active_status_range
           INTO TABLE @rt_wiids.
  ENDMETHOD.


  METHOD get_first_agent_from_history.

    SELECT DISTINCT wi_id
           FROM sww_wi2obj
           WHERE wi_rh_task EQ @iv_task   AND
                 instid     EQ @iv_instid AND
                 typeid     EQ @iv_typeid
           INTO TABLE @DATA(lt_tasks).

    IF lt_tasks IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bc_wf_approver
        EXPORTING
          textid   = zcx_bc_wf_approver=>cant_find_any_approver
          objectid = CONV #( iv_instid ).
    ENDIF.

    SELECT DISTINCT _outbox~wi_id, _outbox~wi_cd, _outbox~wi_ct, _outbox~wi_aagent, _head~top_wi_id
           FROM sww_outbox           AS _outbox
                INNER JOIN swwwihead AS _head ON _head~wi_id EQ _outbox~wi_id
           FOR ALL ENTRIES IN @lt_tasks
           WHERE _outbox~wi_id   EQ @lt_tasks-wi_id AND
                 _outbox~wi_stat EQ @c_status-completed
           INTO TABLE @DATA(lt_approvers).

    IF lt_approvers IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bc_wf_approver
        EXPORTING
          textid   = zcx_bc_wf_approver=>cant_find_any_approver
          objectid = CONV #( iv_instid ).
    ENDIF.

    SORT lt_approvers BY top_wi_id DESCENDING
                         wi_cd     ASCENDING
                         wi_ct     ASCENDING.

    rv_agent = lt_approvers[ 1 ]-wi_aagent.
  ENDMETHOD.


  METHOD refresh_buffer.
    CLEAR et_msg.

    DATA(lo_bdc) = NEW zcl_bc_bdc( ).
    lo_bdc->add_scr( iv_prg = 'SAPLSWUO'   iv_dyn = '0100' ).
    lo_bdc->add_fld( iv_nam = 'BDC_OKCODE' iv_val = '=REFR' ).

    lo_bdc->submit( EXPORTING iv_tcode  = c_tcode_buff_refr
                              is_option = VALUE #( dismode = 'N'
                                                   updmode = 'S' )
                    IMPORTING et_msg    = et_msg ).
  ENDMETHOD.
ENDCLASS.