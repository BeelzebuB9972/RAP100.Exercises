CLASS lhc_zrap100_r_traveltp_9972 DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR Travel
        RESULT result,
      earlynumbering_create FOR NUMBERING
       entities FOR CREATE Travel,
      setOverallStatus FOR DETERMINE ON SAVE
       keys FOR Travel~setOverallStatus,
      validateDate FOR VALIDATE ON SAVE
       keys FOR Travel~validateDate,
      DeductDiscount FOR MODIFY
       keys FOR ACTION Travel~DeductDiscount RESULT result,
      copyTravel FOR MODIFY
       keys FOR ACTION Travel~copyTravel,
      acceptTravel FOR MODIFY
       keys FOR ACTION Travel~acceptTravel RESULT result.

    METHODS rejectTravel FOR MODIFY
       keys FOR ACTION Travel~rejectTravel RESULT result.
    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR Travel RESULT result.
ENDCLASS.

CLASS lhc_zrap100_r_traveltp_9972 IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.
  METHOD earlynumbering_create.

    SELECT MAX( travel_id )
    FROM zrap100_trav9972
    INTO @DATA(lv_max_travel_id).

    mapped-travel = VALUE #( FOR entity IN entities
                             WHERE ( travelid IS NOT INITIAL )
                             ( CORRESPONDING #( DEEP entity )  ) ).

    IF entities IS NOT INITIAL.
      LOOP AT entities INTO DATA(lw_entity) WHERE travelid IS INITIAL.
        IF lv_max_travel_id IS NOT INITIAL.
          DATA(lv_new_travel_id) = lv_max_travel_id + 1.
          lw_entity-%key-TravelID = lv_new_travel_id.
          lv_new_travel_id += 1.
          APPEND CORRESPONDING #( lw_entity ) TO mapped-travel.
        ENDIF.
      ENDLOOP.

    ENDIF.

  ENDMETHOD.

  METHOD setOverallStatus.
    READ ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    FIELDS ( OverallStatus )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_travels)
    FAILED DATA(lt_failed).

    DELETE lt_travels WHERE overallstatus IS NOT INITIAL.
    CHECK lt_travels IS NOT INITIAL.

    MODIFY ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    UPDATE
    FIELDS ( OverallStatus )
    WITH VALUE #( FOR wa IN lt_travels ( %tky = wa-%tky
                                         OverallStatus = 'O' ) )
    REPORTED DATA(lt_reported_update).

    reported = CORRESPONDING #( DEEP lt_reported_update ).
  ENDMETHOD.

  METHOD validateDate.

    READ ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    FIELDS ( BeginDate EndDate )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_travels).

    LOOP AT lt_travels ASSIGNING FIELD-SYMBOL(<lw_travel>).
      APPEND VALUE #(  %tky = <lw_travel>-%tky
                       %state_area = 'VALIDATE_DATE' ) TO reported-travel.
      IF <lw_travel>-BeginDate < cl_abap_context_info=>get_system_date( ).
        APPEND VALUE #( %tky = <lw_travel>-%tky
                        %state_area = 'VALIDATE_DATE'
                        %element-BeginDate = if_abap_behv=>mk-on
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = 'Begin Date must not be in the past'
                               ) ) TO reported-travel.
      ENDIF.
      IF <lw_travel>-EndDate < <lw_travel>-BeginDate.
        APPEND VALUE #( %tky = <lw_travel>-%tky
                        %state_area = 'VALIDATE_DATE'
                        %element-EndDate = if_abap_behv=>mk-on
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = 'End Date must not be before Begin date'
                               ) ) TO reported-travel.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD DeductDiscount.
    DATA lt_travels_for_update TYPE TABLE FOR UPDATE zrap100_r_traveltp_9972.

    DATA(lt_keys_with_discount) = keys.

    LOOP AT lt_keys_with_discount INTO DATA(lw_key_with_discount)
        WHERE %param-discount_percent IS INITIAL OR
        %param-discount_percent > 100 OR %param-discount_percent <= 0.
      APPEND VALUE #( %tky = lw_key_with_discount-%tky ) TO failed-travel.
      APPEND VALUE #( %tky = lw_key_with_discount-%tky
                      %op-%action-deductDiscount = if_abap_behv=>mk-on
                      %msg = new_message_with_text(
                               severity = if_abap_behv_message=>severity-error
                               text     = 'Invalid discount amount, enter value between 1 and 99'
                             )
                       ) TO reported-travel.
      DELETE TABLE lt_keys_with_discount FROM lw_key_with_discount.
    ENDLOOP.
    READ ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    FIELDS ( BookingFee )
    WITH CORRESPONDING #( lt_keys_with_discount )
    RESULT DATA(lt_travel_entities).

    LOOP AT lt_travel_entities INTO DATA(lw_travel).
      lw_travel-BookingFee = COND #( WHEN lw_travel-BookingFee IS NOT INITIAL
                                     THEN lw_travel-BookingFee - ( lw_travel-BookingFee  * ( lt_keys_with_discount[ %tky = lw_travel-%tky ]-%param-discount_percent / 100 ) ) ).
      APPEND VALUE #( %tky = lw_travel-%tky
                      BookingFee = lw_travel-BookingFee ) TO lt_travels_for_update.

    ENDLOOP.

    MODIFY ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    UPDATE
    FIELDS ( BookingFee )
    WITH lt_travels_for_update.

    READ ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    ALL FIELDS
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_travels_with_discount).

    result = VALUE #( FOR wa IN lt_travels_with_discount
                      ( %tky = wa-%tky
                        %param = wa ) ).
  ENDMETHOD.

  METHOD copyTravel.
**************************************************************************
* Instance-bound factory action `copyTravel`:
* Copy an existing travel instance
**************************************************************************
    DATA:
      travels       TYPE TABLE FOR CREATE zrap100_r_traveltp_9972\\travel.

    " remove travel instances with initial %cid (i.e., not set by caller API)
    READ TABLE keys WITH KEY %cid = '' INTO DATA(key_with_inital_cid).
    ASSERT key_with_inital_cid IS INITIAL.

    " read the data from the travel instances to be copied
    READ ENTITIES OF zrap100_r_traveltp_9972 IN LOCAL MODE
      ENTITY travel
       ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travel_read_result)
    FAILED failed.

    LOOP AT travel_read_result ASSIGNING FIELD-SYMBOL(<lfs_travel>).
      " adjust the copied travel instance data
      "" BeginDate must be on or after system date
      <lfs_travel>-BeginDate     = cl_abap_context_info=>get_system_date( ).
      "" EndDate must be after BeginDate
      <lfs_travel>-EndDate       = cl_abap_context_info=>get_system_date( ) + 30.
      "" OverallStatus of new instances must be set to open ('O')
      <lfs_travel>-OverallStatus = 'O'.
      " fill in travel container for creating new travel instance
      APPEND VALUE #( %cid      = keys[ KEY entity %key = <lfs_travel>-%key ]-%cid
                      %is_draft = keys[ KEY entity %key = <lfs_travel>-%key ]-%param-%is_draft
                      %data     = CORRESPONDING #(  <lfs_travel> EXCEPT TravelID )
                   )
        TO travels.
    ENDLOOP.

    " create new BO instance
    MODIFY ENTITIES OF zrap100_r_traveltp_9972 IN LOCAL MODE
      ENTITY travel
        CREATE FIELDS ( AgencyID CustomerID BeginDate EndDate BookingFee
                        TotalPrice CurrencyCode OverallStatus Description )
          WITH travels
      MAPPED DATA(mapped_create).

    " set the new BO instances
    mapped-travel   =  mapped_create-travel .
  ENDMETHOD.

  METHOD acceptTravel.

    DATA lt_update_travel TYPE TABLE FOR UPDATE zrap100_r_traveltp_9972.

    READ ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    FIELDS ( OverallStatus )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_travels).

    lt_update_travel = VALUE #( FOR travel IN lt_travels
                              ( %tky = travel-%tky
                                OverallStatus = 'A' ) ).

    MODIFY ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    UPDATE
    FIELDS ( OverallStatus )
    WITH lt_update_travel
    MAPPED DATA(lt_accepted_travels).

    READ ENTITY IN LOCAL MODE
  zrap100_r_traveltp_9972
  ALL FIELDS
  WITH CORRESPONDING #( keys )
  RESULT DATA(lt_updated_travels).

    result = VALUE #( FOR wa IN lt_updated_travels
                    ( %tky = wa-%tky
                      %param = wa ) ).

  ENDMETHOD.

  METHOD rejectTravel.
    MODIFY ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    UPDATE
    FIELDS ( OverallStatus )
    WITH VALUE #( FOR wa IN keys
                 ( %tky = wa-%tky
                   OverallStatus = 'X' ) )
    FAILED failed
    REPORTED reported.

    READ ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    ALL FIELDS
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_rejected_travels).

    result = VALUE #( FOR lw_travel IN lt_rejected_travels
                    ( %tky = lw_travel-%tky
                      %param = lw_travel ) ).
  ENDMETHOD.

  METHOD get_instance_features.

    READ ENTITY IN LOCAL MODE
    zrap100_r_traveltp_9972
    FIELDS ( TravelID OverallStatus )
    WITH CORRESPONDING #( keys )
    RESULT DATA(lt_travels).

    result = VALUE #( FOR travel IN lt_travels
                    ( %tky = travel-%tky
                      %features-%update = COND #( WHEN travel-OverallStatus = 'A'
                                                  THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
                      %features-%delete = COND #( WHEN travel-OverallStatus = 'A'
                                                  THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
                      %features-%action-Edit = COND #( WHEN travel-OverallStatus = 'A'
                                                       THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
                      %features-%action-acceptTravel = COND #( WHEN travel-OverallStatus = 'A'
                                                               THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
                      %features-%action-rejectTravel = COND #( WHEN travel-OverallStatus = 'X'
                                                               THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled ) ) ).
  ENDMETHOD.

ENDCLASS.
