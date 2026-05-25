;WITH items_carnicos AS (
    -- Solo items clasificados como cárnicos en plan '002'
    SELECT DISTINCT 
        ic.f125_rowid_item,
        cat.f106_id          AS id_categoria,
        cat.f106_descripcion AS categoria
    FROM dbo.t125_mc_items_criterios ic
    INNER JOIN dbo.t106_mc_criterios_item_mayores cat 
            ON cat.f106_id_plan = ic.f125_id_plan
           AND cat.f106_id      = ic.f125_id_criterio_mayor
    WHERE ic.f125_id_plan = '002'
      AND cat.f106_id_cia = :id_cia
      AND cat.f106_id IN ('0001','0002','0003','0004','0005')
),
ventas AS (
    SELECT 
        m.f470_id_cia,
        m.f470_rowid_item_ext,
        m.f470_id_co_movto                                                      AS id_co,
        CAST(m.f470_id_fecha AS date)                                           AS fecha,
        m.f470_id_unidad_medida                                                 AS unidad,
        m.f470_cant_1                                                           AS cantidad,
        m.f470_vlr_bruto - m.f470_vlr_dscto_linea - m.f470_vlr_dscto_global     AS valor_subtotal,
        m.f470_vlr_imp                                                          AS valor_impuestos,
        m.f470_vlr_neto                                                         AS valor_neto,
        m.f470_costo_prom_tot                                                   AS costo_total
    FROM dbo.t470_cm_movto_invent m
    WHERE m.f470_ind_naturaleza = 2
      AND m.f470_id_fecha >= :fecha_inicio
      AND m.f470_id_fecha <  :fecha_fin
      AND (:id_cia IS NULL OR m.f470_id_cia = :id_cia)
)
SELECT 
    v.f470_id_cia                              AS id_cia,
    cia.f010_razon_social                      AS compania,
    co.f285_id                                 AS id_co,
    co.f285_descripcion                        AS desc_co,
    v.fecha                                    AS fecha,
    ic.id_categoria + ' - ' + ic.categoria     AS categoria,
    LTRIM(RTRIM(item.f120_referencia))         AS referencia,
    item.f120_descripcion                      AS descripcion_producto,
    v.unidad                                   AS unidad,
    COUNT(*)                                   AS lineas_vendidas,
    SUM(v.cantidad)                            AS total_cantidad,
    SUM(v.valor_subtotal)                      AS total_subtotal,
    SUM(v.valor_impuestos)                     AS total_impuestos,
    SUM(v.valor_neto)                          AS total_neto,
    SUM(v.costo_total)                         AS total_costo,
    SUM(v.valor_neto - v.costo_total)          AS utilidad_bruta,
    CAST(SUM(v.valor_neto) / NULLIF(SUM(v.cantidad), 0) AS decimal(18,2)) AS precio_promedio
FROM ventas v
INNER JOIN dbo.t121_mc_items_extensiones ext  ON v.f470_rowid_item_ext = ext.f121_rowid
INNER JOIN dbo.t120_mc_items             item ON ext.f121_rowid_item   = item.f120_rowid
INNER JOIN items_carnicos                ic   ON ic.f125_rowid_item    = item.f120_rowid
INNER JOIN dbo.t010_mm_companias         cia  ON v.f470_id_cia         = cia.f010_id
LEFT  JOIN dbo.t285_co_centro_op         co   ON co.f285_id_cia        = v.f470_id_cia 
                                             AND co.f285_id            = v.id_co
WHERE (:id_co      IS NULL OR LTRIM(RTRIM(co.f285_id))            = LTRIM(RTRIM(CAST(:id_co AS varchar(10)))))
  AND (:referencia IS NULL OR LTRIM(RTRIM(item.f120_referencia))  = LTRIM(RTRIM(CAST(:referencia AS varchar(20)))))
GROUP BY 
    v.f470_id_cia, cia.f010_razon_social,
    co.f285_id, co.f285_descripcion,
    v.fecha,
    ic.id_categoria, ic.categoria,
    item.f120_referencia, item.f120_descripcion,
    v.unidad
ORDER BY 
    v.f470_id_cia, co.f285_id, v.fecha, categoria, item.f120_descripcion;
