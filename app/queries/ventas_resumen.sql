;WITH ventas AS (
    SELECT 
        v.f9930_id_cia,
        v.f9930_rowid_bodega,
        v.f9930_rowid_item_ext,
        CAST(v.f9930_id_fecha_factura AS date)                                  AS fecha,
        v.f9930_id_unidad_medida                                                AS unidad,
        v.f9930_cant_1                                                          AS cantidad,
        v.f9930_vlr_bruto - v.f9930_vlr_dscto_linea - v.f9930_vlr_dscto_global  AS valor_subtotal,
        v.f9930_vlr_imp                                                         AS valor_impuestos,
        v.f9930_vlr_neto                                                        AS valor_neto,
        v.f9930_costo_prom_tot                                                  AS costo_total
    FROM dbo.t9930_pdv_a_movto_venta v
    WHERE v.f9930_ind_naturaleza = 2
      AND v.f9930_id_fecha_factura >= :fecha_inicio
      AND v.f9930_id_fecha_factura <  :fecha_fin
      AND (:id_cia IS NULL OR v.f9930_id_cia = :id_cia)
),
data AS (
    SELECT 
        v.f9930_id_cia                                  AS id_cia,
        cia.f010_razon_social                           AS compania,
        co.f285_id                                      AS id_co,
        co.f285_descripcion                             AS desc_co,
        v.fecha                                         AS fecha,
        LTRIM(RTRIM(item.f120_referencia))              AS referencia,
        item.f120_descripcion                           AS descripcion_producto,
        v.unidad                                        AS unidad,
        COUNT(*)                                        AS lineas_vendidas,
        SUM(v.cantidad)                                 AS total_cantidad,
        SUM(v.valor_subtotal)                           AS total_subtotal,
        SUM(v.valor_impuestos)                          AS total_impuestos,
        SUM(v.valor_neto)                               AS total_neto,
        SUM(v.costo_total)                              AS total_costo,
        SUM(v.valor_neto - v.costo_total)               AS utilidad_bruta,
        CAST(SUM(v.valor_neto) / NULLIF(SUM(v.cantidad), 0) AS decimal(18,2)) AS precio_promedio
    FROM ventas v
    INNER JOIN dbo.t010_mm_companias         cia  ON v.f9930_id_cia        = cia.f010_id
    INNER JOIN dbo.t121_mc_items_extensiones ext  ON v.f9930_rowid_item_ext = ext.f121_rowid
    INNER JOIN dbo.t120_mc_items             item ON ext.f121_rowid_item   = item.f120_rowid
    LEFT  JOIN dbo.t150_mc_bodegas           bod  ON bod.f150_rowid        = v.f9930_rowid_bodega
    LEFT  JOIN dbo.t285_co_centro_op         co   ON co.f285_id_cia        = v.f9930_id_cia 
                                                 AND co.f285_id            = bod.f150_id_co
    WHERE (:id_co       IS NULL OR LTRIM(RTRIM(co.f285_id))            = LTRIM(RTRIM(CAST(:id_co AS varchar(10)))))
      AND (:referencia  IS NULL OR LTRIM(RTRIM(item.f120_referencia))  = LTRIM(RTRIM(CAST(:referencia AS varchar(20)))))
    GROUP BY 
        v.f9930_id_cia, cia.f010_razon_social,
        co.f285_id, co.f285_descripcion,
        v.fecha,
        item.f120_referencia, item.f120_descripcion,
        v.unidad
)
