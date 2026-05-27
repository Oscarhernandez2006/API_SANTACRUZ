;WITH 
items_especie AS (
    SELECT DISTINCT ic.f125_rowid_item, cat.f106_id AS id_especie, cat.f106_descripcion AS especie
    FROM dbo.t125_mc_items_criterios ic
    INNER JOIN dbo.t106_mc_criterios_item_mayores cat 
            ON cat.f106_id_plan = ic.f125_id_plan AND cat.f106_id = ic.f125_id_criterio_mayor
    WHERE ic.f125_id_plan = '002' AND cat.f106_id_cia = :id_cia
      AND cat.f106_id IN ('0001','0002','0003','0004','0005')
),
items_proceso AS (
    SELECT DISTINCT ic.f125_rowid_item, cat.f106_id AS id_proceso, cat.f106_descripcion AS proceso
    FROM dbo.t125_mc_items_criterios ic
    INNER JOIN dbo.t106_mc_criterios_item_mayores cat 
            ON cat.f106_id_plan = ic.f125_id_plan AND cat.f106_id = ic.f125_id_criterio_mayor
    WHERE ic.f125_id_plan = '003' AND cat.f106_id_cia = :id_cia
),
items_grupo AS (
    SELECT DISTINCT ic.f125_rowid_item, cat.f106_id AS id_grupo, cat.f106_descripcion AS grupo
    FROM dbo.t125_mc_items_criterios ic
    INNER JOIN dbo.t106_mc_criterios_item_mayores cat 
            ON cat.f106_id_plan = ic.f125_id_plan AND cat.f106_id = ic.f125_id_criterio_mayor
    WHERE ic.f125_id_plan = '001' AND cat.f106_id_cia = :id_cia
),
ventas AS (
    SELECT 
        m.f470_id_cia,
        m.f470_rowid_item_ext,
        m.f470_id_co_movto                  AS id_co,
        m.f470_rowid_tercero_vend           AS rowid_vendedor,
        m.f470_rowid_docto                  AS rowid_docto,
        m.f470_rowid_docto_fact             AS rowid_docto_fact,
        CAST(m.f470_id_fecha AS date)       AS fecha,
        UPPER(LTRIM(RTRIM(m.f470_id_unidad_medida))) AS unidad,
        m.f470_cant_1                       AS cantidad,
        m.f470_vlr_bruto - m.f470_vlr_dscto_linea - m.f470_vlr_dscto_global AS valor_subtotal,
        m.f470_vlr_imp                      AS valor_impuestos,
        m.f470_vlr_neto                     AS valor_neto,
        m.f470_costo_prom_tot               AS costo_total
    FROM dbo.t470_cm_movto_invent m
    WHERE m.f470_ind_naturaleza = 2
      AND m.f470_id_fecha >= :fecha_inicio
      AND m.f470_id_fecha <  :fecha_fin
      AND (:id_cia IS NULL OR m.f470_id_cia = :id_cia)
),
data AS (
    SELECT 
        v.f470_id_cia                                              AS id_cia,
        cia.f010_razon_social                                      AS compania,
        co.f285_id                                                 AS id_co,
        co.f285_descripcion                                        AS desc_co,
        v.fecha                                                    AS fecha,
        YEAR(v.fecha)                                              AS anio,
        MONTH(v.fecha)                                             AS mes,
        LTRIM(RTRIM(item.f120_referencia))                         AS referencia,
        item.f120_descripcion                                      AS descripcion_producto,
        CASE WHEN ig.id_grupo = '0001' THEN 'BIENES'
             WHEN ig.id_grupo = '0002' THEN 'SERVICIOS'
             ELSE ig.grupo END                                     AS tipo_bien_servicio,
        COALESCE(ie.id_especie + ' - ' + ie.especie, 'SIN ESPECIE') AS especie,
        COALESCE(ip.id_proceso + ' - ' + ip.proceso, 'SIN PROCESO') AS proceso,
        tv.f200_id                                                 AS codigo_vendedor,
        tv.f200_razon_social                                       AS nombre_vendedor,
        tc.f200_id                                                 AS codigo_cliente,
        tc.f200_nit                                                AS nit_cliente,
        tc.f200_razon_social                                       AS nombre_cliente,
        SUM(CASE WHEN v.unidad IN ('KG','KL','LB') THEN v.cantidad ELSE 0 END) AS kilos_vendidos,
        SUM(CASE WHEN v.unidad IN ('U','UN','PK')  THEN v.cantidad ELSE 0 END) AS unidades_vendidas,
        SUM(CASE WHEN v.unidad NOT IN ('KG','KL','LB','U','UN','PK') THEN v.cantidad ELSE 0 END) AS otras_cantidades,
        COUNT(*)                                                   AS lineas_facturadas,
        SUM(v.valor_subtotal)                                      AS total_subtotal,
        SUM(v.valor_impuestos)                                     AS total_impuestos,
        SUM(v.valor_neto)                                          AS total_neto,
        SUM(v.costo_total)                                         AS total_costo,
        SUM(v.valor_neto - v.costo_total)                          AS utilidad_bruta,
        CAST(
            CASE WHEN SUM(CASE WHEN v.unidad IN ('KG','KL','LB') THEN v.cantidad ELSE 0 END) > 0
                 THEN SUM(CASE WHEN v.unidad IN ('KG','KL','LB') THEN v.valor_neto ELSE 0 END)
                      / SUM(CASE WHEN v.unidad IN ('KG','KL','LB') THEN v.cantidad ELSE 0 END)
                 ELSE 0 END
            AS decimal(18,2)
        )                                                          AS precio_promedio_kilo
    FROM ventas v
    INNER JOIN dbo.t121_mc_items_extensiones ext  ON v.f470_rowid_item_ext = ext.f121_rowid
    INNER JOIN dbo.t120_mc_items             item ON ext.f121_rowid_item   = item.f120_rowid
    INNER JOIN items_grupo                   ig   ON ig.f125_rowid_item    = item.f120_rowid
    LEFT  JOIN items_especie                 ie   ON ie.f125_rowid_item    = item.f120_rowid
    LEFT  JOIN items_proceso                 ip   ON ip.f125_rowid_item    = item.f120_rowid
    INNER JOIN dbo.t010_mm_companias         cia  ON v.f470_id_cia         = cia.f010_id
    LEFT  JOIN dbo.t285_co_centro_op         co   ON co.f285_id_cia = v.f470_id_cia AND co.f285_id = v.id_co
    LEFT  JOIN dbo.t200_mm_terceros          tv   ON tv.f200_rowid = v.rowid_vendedor AND tv.f200_id_cia = v.f470_id_cia
    -- Cliente desde cabecera de factura de venta (t461)
    LEFT  JOIN dbo.t461_cm_docto_factura_venta fact ON fact.f461_rowid_docto = v.rowid_docto_fact 
                                                    AND fact.f461_id_cia      = v.f470_id_cia
    LEFT  JOIN dbo.t200_mm_terceros          tc   ON tc.f200_rowid   = fact.f461_rowid_tercero_fact 
                                                  AND tc.f200_id_cia = v.f470_id_cia
    WHERE (:id_co      IS NULL OR LTRIM(RTRIM(co.f285_id))           = LTRIM(RTRIM(CAST(:id_co AS varchar(10)))))
      AND (:referencia IS NULL OR LTRIM(RTRIM(item.f120_referencia)) = LTRIM(RTRIM(CAST(:referencia AS varchar(20)))))
    GROUP BY 
        v.f470_id_cia, cia.f010_razon_social,
        co.f285_id, co.f285_descripcion,
        v.fecha,
        item.f120_referencia, item.f120_descripcion,
        ig.id_grupo, ig.grupo,
        ie.id_especie, ie.especie,
        ip.id_proceso, ip.proceso,
        tv.f200_id, tv.f200_razon_social,
        tc.f200_id, tc.f200_nit, tc.f200_razon_social
)
