-- =====================================================================
-- REPORTE GERENCIAL DE VENTAS (Grand Total Siesa) - Carnes Santa Cruz
-- Fuente: t461 (cabecera factura) + t470 (detalle facturado)
-- Jerarquia: C.O. -> Tipo item -> Especie -> Tipo comercial -> Item
--            -> Cliente -> Grupo ABC
-- Termina en CTE 'data'; el router agrega paginacion / CSV / ORDER BY.
-- Parametros: :id_cia, :id_co, :fecha_inicio, :fecha_fin, :referencia
-- NOTA: :fecha_fin es INCLUSIVA (usa DATEADD(DAY,1,...) internamente).
-- =====================================================================
;WITH data AS (
    SELECT
        -- ===== Jerarquia =====
        f.f461_id_co_docto                              AS CO_Id,
        co.f285_descripcion                             AS CentroOperacion,
        pTipo.f106_id                                   AS TipoItem_Id,
        pTipo.f106_descripcion                          AS TipoItem,
        pEsp.f106_id                                    AS Especie_Id,
        pEsp.f106_descripcion                           AS Especie,
        pCom.f106_id                                    AS TipoComercial_Id,
        pCom.f106_descripcion                           AS TipoComercial,
        it.f120_referencia                              AS Item_Ref,
        it.f120_descripcion                             AS Item_Desc,
        ter.f200_razon_social                           AS Cliente,
        pGru.f106_id                                    AS Grupo_Id,
        pGru.f106_descripcion                           AS Grupo,
        -- ===== Medidas (con signo: venta + / devolucion-NC -) =====
        SUM(s.signo * m.f470_cant_base)                                                   AS CantidadInv,
        SUM(s.signo * m.f470_vlr_bruto)                                                   AS ValorBruto,
        SUM(s.signo * (m.f470_vlr_bruto - m.f470_vlr_dscto_linea - m.f470_vlr_dscto_global)) AS ValorSubtotal,
        SUM(s.signo * (m.f470_vlr_dscto_linea + m.f470_vlr_dscto_global))                 AS Descuentos,
        SUM(s.signo * m.f470_cant_1)                                                      AS KilosTotal
    FROM dbo.t461_cm_docto_factura_venta f
    JOIN dbo.t470_cm_movto_invent m
           ON  m.f470_id_cia            = f.f461_id_cia
           AND m.f470_rowid_docto_fact  = f.f461_rowid_docto
    -- Centro de operacion (cabecera)
    LEFT JOIN dbo.t285_co_centro_op co
           ON  co.f285_id_cia = f.f461_id_cia
           AND co.f285_id     = f.f461_id_co_docto
    -- Item y su extension
    JOIN dbo.t121_mc_items_extensiones e
           ON  e.f121_id_cia = m.f470_id_cia
           AND e.f121_rowid  = m.f470_rowid_item_ext
    JOIN dbo.t120_mc_items it
           ON  it.f120_rowid = e.f121_rowid_item
    -- Cliente de la factura (tercero -> razon social)
    LEFT JOIN dbo.t200_mm_terceros ter
           ON  ter.f200_rowid = f.f461_rowid_tercero_fact
    -- ===== Criterios de item (planes) =====
    LEFT JOIN dbo.t125_mc_items_criterios crTipo
           ON crTipo.f125_id_cia = e.f121_id_cia AND crTipo.f125_rowid_item = e.f121_rowid_item AND crTipo.f125_id_plan = '001'
    LEFT JOIN dbo.t106_mc_criterios_item_mayores pTipo
           ON pTipo.f106_id_cia = :id_cia AND pTipo.f106_id_plan = '001' AND pTipo.f106_id = crTipo.f125_id_criterio_mayor
    LEFT JOIN dbo.t125_mc_items_criterios crEsp
           ON crEsp.f125_id_cia = e.f121_id_cia AND crEsp.f125_rowid_item = e.f121_rowid_item AND crEsp.f125_id_plan = '002'
    LEFT JOIN dbo.t106_mc_criterios_item_mayores pEsp
           ON pEsp.f106_id_cia = :id_cia AND pEsp.f106_id_plan = '002' AND pEsp.f106_id = crEsp.f125_id_criterio_mayor
    LEFT JOIN dbo.t125_mc_items_criterios crCom
           ON crCom.f125_id_cia = e.f121_id_cia AND crCom.f125_rowid_item = e.f121_rowid_item AND crCom.f125_id_plan = '003'
    LEFT JOIN dbo.t106_mc_criterios_item_mayores pCom
           ON pCom.f106_id_cia = :id_cia AND pCom.f106_id_plan = '003' AND pCom.f106_id = crCom.f125_id_criterio_mayor
    LEFT JOIN dbo.t125_mc_items_criterios crGru
           ON crGru.f125_id_cia = e.f121_id_cia AND crGru.f125_rowid_item = e.f121_rowid_item AND crGru.f125_id_plan = '004'
    LEFT JOIN dbo.t106_mc_criterios_item_mayores pGru
           ON pGru.f106_id_cia = :id_cia AND pGru.f106_id_plan = '004' AND pGru.f106_id = crGru.f125_id_criterio_mayor
    -- Signo: naturaleza 2 = venta (+), 1 = devolucion/NC (-)
    CROSS APPLY (SELECT CASE WHEN m.f470_ind_naturaleza = 2 THEN 1 ELSE -1 END) s(signo)
    WHERE f.f461_id_cia        = :id_cia
      AND f.f461_id_fecha      >= :fecha_inicio
      AND f.f461_id_fecha      <  DATEADD(DAY, 1, :fecha_fin)
      AND m.f470_ind_estado_cm  = 5                     -- lineas confirmadas
      AND (:id_co IS NULL OR f.f461_id_co_docto = :id_co)
      AND (:referencia IS NULL OR LTRIM(RTRIM(it.f120_referencia)) = LTRIM(RTRIM(CAST(:referencia AS varchar(20)))))
      AND it.f120_referencia NOT IN ('99086','99031')   -- excluir arriendo de canastillas
    GROUP BY
        f.f461_id_co_docto, co.f285_descripcion,
        pTipo.f106_id, pTipo.f106_descripcion,
        pEsp.f106_id,  pEsp.f106_descripcion,
        pCom.f106_id,  pCom.f106_descripcion,
        it.f120_referencia, it.f120_descripcion,
        ter.f200_razon_social,
        pGru.f106_id,  pGru.f106_descripcion
)
