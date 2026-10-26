-- ============================================================
-- TechMarket SpA | BDY1103 | EP2 - PRUEBAS Y EVIDENCIAS
-- Orden: script_maestro.sql -> script_EP2_completo.sql -> este archivo.
-- Ejecute E00 primero (crea un utilitario de reinicio). Luego cada
-- seccion por separado (seleccionar bloque + F5) y capturar.
-- Cada seccion arranca desde un estado limpio: es re-ejecutable.
-- REPARTO DE CAPTURAS (carpeta 02_Evidencias/<nombre>/)
--   Pablo : E01, E02, E03, E07, E08            (funciones y package)
--   Danyer: E09, E10, E11, E12, E13, E14       (triggers y excepciones)
--   Max   : E00, E04, E05, E06, E15 + C01, C02 (procedimientos, integracion, EP1)
-- ============================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 220 PAGESIZE 100;

-- ------------------------------------------------------------
-- EVIDENCIA E00 | Max | Objetos VALID y sin errores de compilacion
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_demo_reiniciar(p_cargar IN VARCHAR2 DEFAULT 'N')
IS  -- utilitario SOLO de pruebas: limpia bitacora/auditoria (sin ruido de DBMS_OUTPUT)
BEGIN
    DBMS_OUTPUT.DISABLE;
    DELETE FROM bitacora_beneficios;
    DELETE FROM auditoria_beneficios;
    IF UPPER(p_cargar) = 'S' THEN
        techmarket_beneficios.procesar_beneficios(10, DATE '2026-08-01', DATE '2026-08-31');
    END IF;
    COMMIT;
    DBMS_OUTPUT.ENABLE(NULL);
END pr_demo_reiniciar;
/

SELECT object_type, object_name, status
  FROM user_objects
 WHERE object_type IN ('FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER')
 ORDER BY object_type, object_name;

SELECT * FROM user_errors;   -- debe salir "no rows selected"

-- ------------------------------------------------------------
-- EVIDENCIA E01 | Pablo | Funciones SIN parametros (en SELECT)
-- Esperado: 4 clientes activos | ventas totales 4389640
-- ------------------------------------------------------------
SELECT fn_clientes_activos AS clientes_activos,
       fn_ventas_totales   AS ventas_totales
  FROM dual;

-- ------------------------------------------------------------
-- EVIDENCIA E02 | Pablo | Funciones CON parametros en SELECT masivo
-- Esperado (6 filas): S10: 101 GOLD 1339950, 102 GOLD 759960,
--   103 BRONZE 219980, 104 PLATINUM 1599800 | S20: 101 BRONZE 109990, 103 SILVER 319970
-- ------------------------------------------------------------
SELECT x.sucursal, x.id_cliente, x.cliente, x.total,
       calcular_categoria(x.total) AS categoria,
       calcular_beneficio(x.total) AS beneficio_pct
  FROM (SELECT s.id_sucursal, s.nombre AS sucursal, c.id_cliente, c.nombre AS cliente,
               fn_total_cliente(c.id_cliente, s.id_sucursal,
                                DATE '2026-08-01', DATE '2026-08-31') AS total
          FROM cliente c CROSS JOIN sucursal s) x
 WHERE x.total > 0
 ORDER BY x.id_sucursal, x.id_cliente;

-- Valores limite (funcion standalone vs. funcion del package)
-- Esperado: 250000 BRONZE 5 | 300000 SILVER 10 | 700000 GOLD 15 | 850000 GOLD | 1500000 PLATINUM 20
SELECT m.monto,
       calcular_categoria(m.monto)                AS categoria,
       calcular_beneficio(m.monto)                AS pct,
       techmarket_beneficios.calcular_categoria(m.monto) AS categoria_package
  FROM (SELECT 250000 monto FROM dual UNION ALL SELECT 299999 FROM dual
        UNION ALL SELECT 300000 FROM dual UNION ALL SELECT 699999 FROM dual
        UNION ALL SELECT 700000 FROM dual UNION ALL SELECT 850000 FROM dual
        UNION ALL SELECT 1499999 FROM dual UNION ALL SELECT 1500000 FROM dual) m
 ORDER BY m.monto;

-- ------------------------------------------------------------
-- EVIDENCIA E03 | Pablo | Funciones usadas desde OTRO bloque PL/SQL
-- Esperado (todas las sucursales, agosto): 101 GOLD 1449940 | 102 GOLD 759960
--   | 103 SILVER 539950 | 104 PLATINUM 1599800
-- ------------------------------------------------------------
DECLARE
    v_desde DATE := DATE '2026-08-01';
    v_hasta DATE := DATE '2026-08-31';
    v_total NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('Activos: ' || fn_clientes_activos
                         || ' | Ventas totales: ' || fn_ventas_totales);
    FOR c IN (SELECT id_cliente, nombre FROM cliente WHERE estado = 'ACTIVO' ORDER BY id_cliente) LOOP
        v_total := fn_total_cliente(c.id_cliente, NULL, v_desde, v_hasta);  -- NULL = todas las sucursales
        DBMS_OUTPUT.PUT_LINE(RPAD(c.nombre, 14) || '| ' || LPAD(v_total, 8)
            || ' | ' || techmarket_beneficios.calcular_categoria(v_total)
            || ' | ' || techmarket_beneficios.calcular_beneficio(v_total) || '%');
    END LOOP;
END;
/

-- ------------------------------------------------------------
-- EVIDENCIA E04 | Max | Procedimiento CON parametros, MASIVO (todas las sucursales)
-- Esperado: S10 = 4 filas, S20 = 2, S30 = 0 -> bitacora con 6 filas; 6 filas de auditoria
-- ------------------------------------------------------------
EXEC pr_demo_reiniciar;
BEGIN
    pr_procesar_todas_sucursales(DATE '2026-08-01', DATE '2026-08-31');
END;
/
SELECT id_bitacora, id_cliente, id_sucursal, total_compras, categoria_cliente, porcentaje_beneficio
  FROM bitacora_beneficios ORDER BY id_sucursal, id_cliente;

-- ------------------------------------------------------------
-- EVIDENCIA E05 | Max | Procedimiento SIN parametros
-- Esperado (solo S10): BRONZE 1 | GOLD 2 | PLATINUM 1
-- ------------------------------------------------------------
EXEC pr_demo_reiniciar('S');
EXEC pr_resumen_general;

-- ------------------------------------------------------------
-- EVIDENCIA E06 | Max | Procedimiento con IN/OUT llamado desde otro PL/SQL
-- ------------------------------------------------------------
DECLARE
    v_cant NUMBER; v_total NUMBER; v_cat VARCHAR2(20); v_ben NUMBER;
BEGIN
    FOR c IN (SELECT id_cliente FROM cliente WHERE estado = 'ACTIVO' ORDER BY id_cliente) LOOP
        pr_obtener_resumen_cliente(c.id_cliente, 10, DATE '2026-08-01', DATE '2026-08-31',
                                   v_cant, v_total, v_cat, v_ben);
        DBMS_OUTPUT.PUT_LINE('Cliente ' || c.id_cliente || ' | compras: ' || v_cant
            || ' | total: ' || v_total || ' | ' || v_cat || ' | ' || v_ben || '%');
    END LOOP;
END;
/

-- ------------------------------------------------------------
-- EVIDENCIA E07 | Pablo | PACKAGE: elementos PUBLICOS
-- Esperado: DESC lista solo 4 subprogramas; el resumen sale con "$1.339.950"
-- ------------------------------------------------------------
DESC techmarket_beneficios
BEGIN
    DBMS_OUTPUT.PUT_LINE('Umbrales publicos: SILVER>=' || techmarket_beneficios.c_umbral_silver
        || ' | GOLD>=' || techmarket_beneficios.c_umbral_gold
        || ' | PLATINUM>=' || techmarket_beneficios.c_umbral_platinum);
    DBMS_OUTPUT.PUT_LINE('Categoria de 850000: ' || techmarket_beneficios.calcular_categoria(850000));
    techmarket_beneficios.mostrar_resumen_cliente(101, 10, DATE '2026-08-01', DATE '2026-08-31');
    techmarket_beneficios.mostrar_resumen_cliente(104, 10, DATE '2026-08-01', DATE '2026-08-31');
END;
/

-- ------------------------------------------------------------
-- EVIDENCIA E08 | Pablo | PACKAGE: elemento PRIVADO inaccesible
-- Esperado: error ORA-06550 / PLS-00302 y luego solo "PACKAGE BODY"
-- ------------------------------------------------------------
BEGIN
    EXECUTE IMMEDIATE
      'BEGIN DBMS_OUTPUT.PUT_LINE(techmarket_beneficios.fn_formatear_monto_privado(1000)); END;';
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error esperado (privado): ' || SQLERRM);
END;
/
SELECT CASE WHEN UPPER(text) LIKE '%FN_FORMATEAR_MONTO_PRIVADO%'
            THEN 'FN_FORMATEAR_MONTO_PRIVADO' ELSE 'PR_VALIDAR_PERIODO' END AS elemento,
       type AS aparece_en, COUNT(*) AS lineas
  FROM user_source
 WHERE name = 'TECHMARKET_BENEFICIOS'
   AND (UPPER(text) LIKE '%FN_FORMATEAR_MONTO_PRIVADO%' OR UPPER(text) LIKE '%PR_VALIDAR_PERIODO%')
 GROUP BY CASE WHEN UPPER(text) LIKE '%FN_FORMATEAR_MONTO_PRIVADO%'
               THEN 'FN_FORMATEAR_MONTO_PRIVADO' ELSE 'PR_VALIDAR_PERIODO' END, type
 ORDER BY 1, 2;

-- ------------------------------------------------------------
-- EVIDENCIA E09 | Danyer | COMPOUND TRIGGER: INSERT masivo (1 sentencia, 4 filas)
-- Esperado: 1 INICIO + 4 FILA + 1 FIN "4 fila(s)"; auditoria con 4 INSERT
-- ------------------------------------------------------------
SELECT trigger_name, trigger_type, triggering_event, status
  FROM user_triggers WHERE table_name = 'BITACORA_BENEFICIOS';
EXEC pr_demo_reiniciar;
BEGIN
    techmarket_beneficios.procesar_beneficios(10, DATE '2026-08-01', DATE '2026-08-31');
END;
/
SELECT id_auditoria, id_bitacora, operacion, usuario_bd, categoria_nueva, total_nuevo
  FROM auditoria_beneficios ORDER BY id_auditoria;

-- ------------------------------------------------------------
-- EVIDENCIA E10 | Danyer | Contraste: procedimiento con LOOP = 4 sentencias
-- Esperado: el par INICIO/FIN aparece 4 veces (1 fila cada vez)
-- ------------------------------------------------------------
EXEC pr_demo_reiniciar;
BEGIN
    procesar_beneficios(10, DATE '2026-08-01', DATE '2026-08-31');
END;
/

-- ------------------------------------------------------------
-- EVIDENCIA E11 | Danyer | UPDATE multi-fila (+20% por ventas tardias)
-- Esperado: 101 pasa de GOLD a PLATINUM (1339950 -> 1607940); 4 filas UPDATE
-- ------------------------------------------------------------
EXEC pr_demo_reiniciar('S');
UPDATE bitacora_beneficios
   SET total_compras        = total_compras * 1.2,
       categoria_cliente    = calcular_categoria(total_compras * 1.2),
       porcentaje_beneficio = calcular_beneficio(total_compras * 1.2),
       fecha_actualizacion  = SYSDATE
 WHERE id_sucursal = 10;
SELECT id_auditoria, id_bitacora, operacion, categoria_anterior, categoria_nueva,
       total_anterior, total_nuevo
  FROM auditoria_beneficios ORDER BY id_auditoria;
ROLLBACK;

-- ------------------------------------------------------------
-- EVIDENCIA E12 | Danyer | UPDATE de 0 filas: la SENTENCIA dispara, la FILA no
-- Esperado: INICIO + FIN "0 fila(s)", sin lineas [FILA]; auditoria sigue con 4
-- ------------------------------------------------------------
EXEC pr_demo_reiniciar('S');
UPDATE bitacora_beneficios SET fecha_actualizacion = SYSDATE WHERE id_sucursal = 999;
SELECT COUNT(*) AS filas_auditoria FROM auditoria_beneficios;
ROLLBACK;

-- ------------------------------------------------------------
-- EVIDENCIA E13 | Danyer | Trigger de SENTENCIA simple: DELETE de 4 filas = 1 marca
-- Esperado: 1 mensaje y 1 fila 'DELETE' en auditoria
-- ------------------------------------------------------------
EXEC pr_demo_reiniciar('S');
DELETE FROM bitacora_beneficios WHERE id_sucursal = 10;
SELECT id_auditoria, id_bitacora, operacion, usuario_bd
  FROM auditoria_beneficios WHERE operacion = 'DELETE';
ROLLBACK;

-- ------------------------------------------------------------
-- EVIDENCIA E14 | Danyer | Excepciones: publica del package y ORA-20002
-- ------------------------------------------------------------
BEGIN
    pr_procesar_todas_sucursales(DATE '2026-08-31', DATE '2026-08-01');  -- fechas invertidas
EXCEPTION
    WHEN techmarket_beneficios.ex_periodo_invalido THEN
        DBMS_OUTPUT.PUT_LINE('Capturada ex_periodo_invalido: ' || SQLERRM);
END;
/
DECLARE
    v_c NUMBER; v_t NUMBER; v_cat VARCHAR2(20); v_b NUMBER;
BEGIN
    pr_obtener_resumen_cliente(999, 10, DATE '2026-08-01', DATE '2026-08-31', v_c, v_t, v_cat, v_b);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Cliente inexistente -> ' || SQLERRM);
END;
/

-- ------------------------------------------------------------
-- EVIDENCIA E15 | Max | Integracion extremo a extremo
-- Esperado: 6 filas, cada una con 1 registro de auditoria; resumen con
--   BRONZE 2 / SILVER 1 / GOLD 2 / PLATINUM 1
-- ------------------------------------------------------------
EXEC pr_demo_reiniciar;
EXEC pr_procesar_todas_sucursales(DATE '2026-08-01', DATE '2026-08-31');
SELECT s.nombre AS sucursal, c.nombre AS cliente, b.total_compras,
       b.categoria_cliente, b.porcentaje_beneficio,
       (SELECT COUNT(*) FROM auditoria_beneficios a WHERE a.id_bitacora = b.id_bitacora) AS filas_auditoria
  FROM bitacora_beneficios b
  JOIN cliente  c ON c.id_cliente  = b.id_cliente
  JOIN sucursal s ON s.id_sucursal = b.id_sucursal
 ORDER BY s.id_sucursal, c.id_cliente;
EXEC pr_resumen_general;
