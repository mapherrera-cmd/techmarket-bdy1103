-- ============================================================
-- TechMarket SpA | BDY1103 | EP2 - script_EP2_completo.sql
-- Requisito: haber ejecutado antes 05_Entrega/script_maestro.sql
-- Re-ejecutable: todo es CREATE OR REPLACE (+ DROP protegido).
-- Orden: funciones -> package -> procedimientos -> triggers.
-- Autores: Pablo (secciones 1-3), Danyer (4), Max (revision)
-- ============================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;

-- Verificacion de requisitos (tablas y objetos de EP1)
DECLARE
    v NUMBER;
BEGIN
    SELECT COUNT(*) INTO v FROM user_objects
     WHERE object_name IN ('CALCULAR_CATEGORIA','PROCESAR_BENEFICIOS','BITACORA_BENEFICIOS','AUDITORIA_BENEFICIOS');
    IF v < 4 THEN
        RAISE_APPLICATION_ERROR(-20999, 'Ejecute primero script_maestro.sql');
    END IF;
END;
/

-- ============================================================
-- 1. FUNCIONES ALMACENADAS NUEVAS (usables en SELECT y en PL/SQL)
-- ============================================================

-- 1.1 SIN parametros
CREATE OR REPLACE FUNCTION fn_clientes_activos
RETURN NUMBER
IS
    v_cantidad NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_cantidad
      FROM cliente
     WHERE estado = 'ACTIVO';
    RETURN v_cantidad;
END fn_clientes_activos;
/

CREATE OR REPLACE FUNCTION fn_ventas_totales
RETURN NUMBER
IS
    v_total NUMBER;
BEGIN
    SELECT NVL(SUM(total), 0) INTO v_total FROM venta;
    RETURN v_total;
END fn_ventas_totales;
/

-- 1.2 CON parametros. p_id_sucursal NULL = todas las sucursales.
CREATE OR REPLACE FUNCTION fn_total_cliente(
    p_id_cliente  IN NUMBER,
    p_id_sucursal IN NUMBER,
    p_fecha_desde IN DATE,
    p_fecha_hasta IN DATE
)
RETURN NUMBER
IS
    v_total NUMBER;
BEGIN
    SELECT NVL(SUM(total), 0)
      INTO v_total
      FROM venta
     WHERE id_cliente = p_id_cliente
       AND (p_id_sucursal IS NULL OR id_sucursal = p_id_sucursal)
       AND fecha_venta BETWEEN p_fecha_desde AND p_fecha_hasta;
    RETURN v_total;
END fn_total_cliente;
/

-- ============================================================
-- 2. PACKAGE techmarket_beneficios (reemplaza el de EP1)
--    PUBLICO : constantes, excepcion, 2 funciones, 2 procedimientos
--    PRIVADO : fn_formatear_monto_privado, pr_validar_periodo
--    (los privados NO se nombran en la especificacion)
-- ============================================================
CREATE OR REPLACE PACKAGE techmarket_beneficios AS

    -- Constantes publicas: umbrales de gasto por categoria
    c_umbral_silver     CONSTANT NUMBER := 300000;
    c_umbral_gold       CONSTANT NUMBER := 700000;
    c_umbral_platinum   CONSTANT NUMBER := 1500000;

    -- Excepcion publica: otros bloques pueden capturarla por nombre
    ex_periodo_invalido EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_periodo_invalido, -20001);

    FUNCTION calcular_categoria(
        p_total_comprado IN NUMBER
    ) RETURN VARCHAR2;

    FUNCTION calcular_beneficio(
        p_total_comprado IN NUMBER
    ) RETURN NUMBER;

    PROCEDURE procesar_beneficios(
        p_id_sucursal IN NUMBER,
        p_fecha_desde IN DATE,
        p_fecha_hasta IN DATE
    );

    PROCEDURE mostrar_resumen_cliente(
        p_id_cliente  IN NUMBER,
        p_id_sucursal IN NUMBER,
        p_fecha_desde IN DATE,
        p_fecha_hasta IN DATE
    );

END techmarket_beneficios;
/

CREATE OR REPLACE PACKAGE BODY techmarket_beneficios AS

    ---------------- ELEMENTOS PRIVADOS ----------------
    -- Solo visibles dentro del body (no estan en la especificacion)

    FUNCTION fn_formatear_monto_privado(p_monto IN NUMBER)
    RETURN VARCHAR2
    IS
    BEGIN
        -- Formato chileno: $1.339.950
        RETURN '$' || TO_CHAR(p_monto, 'FM999G999G999G990',
                              'NLS_NUMERIC_CHARACTERS='',.''');
    END fn_formatear_monto_privado;

    PROCEDURE pr_validar_periodo(
        p_fecha_desde IN DATE,
        p_fecha_hasta IN DATE
    )
    IS
    BEGIN
        IF p_fecha_desde IS NULL
           OR p_fecha_hasta IS NULL
           OR p_fecha_desde > p_fecha_hasta THEN
            RAISE_APPLICATION_ERROR(-20001,
                'Periodo invalido: la fecha de inicio no puede ser posterior a la de fin.');
        END IF;
    END pr_validar_periodo;

    ---------------- ELEMENTOS PUBLICOS ----------------

    FUNCTION calcular_categoria(p_total_comprado IN NUMBER)
    RETURN VARCHAR2
    IS
    BEGIN
        IF p_total_comprado < c_umbral_silver THEN
            RETURN 'BRONZE';
        ELSIF p_total_comprado < c_umbral_gold THEN
            RETURN 'SILVER';
        ELSIF p_total_comprado < c_umbral_platinum THEN
            RETURN 'GOLD';
        ELSE
            RETURN 'PLATINUM';
        END IF;
    END calcular_categoria;

    FUNCTION calcular_beneficio(p_total_comprado IN NUMBER)
    RETURN NUMBER
    IS
    BEGIN
        IF p_total_comprado < c_umbral_silver THEN
            RETURN 5;
        ELSIF p_total_comprado < c_umbral_gold THEN
            RETURN 10;
        ELSIF p_total_comprado < c_umbral_platinum THEN
            RETURN 15;
        ELSE
            RETURN 20;
        END IF;
    END calcular_beneficio;

    -- Procesamiento MASIVO: un solo INSERT ... SELECT para toda la sucursal.
    -- (Una sentencia -> el trigger de sentencia se dispara 1 vez, el de fila N veces)
    PROCEDURE procesar_beneficios(
        p_id_sucursal IN NUMBER,
        p_fecha_desde IN DATE,
        p_fecha_hasta IN DATE
    )
    IS
        v_filas NUMBER;
    BEGIN
        pr_validar_periodo(p_fecha_desde, p_fecha_hasta);

        INSERT INTO bitacora_beneficios (
            id_cliente, id_sucursal, periodo_desde, periodo_hasta,
            cantidad_compras, total_compras, categoria_cliente,
            porcentaje_beneficio, fecha_proceso, usuario_bd, fecha_actualizacion
        )
        SELECT v.id_cliente,
               p_id_sucursal,
               p_fecha_desde,
               p_fecha_hasta,
               COUNT(*),
               SUM(v.total),
               techmarket_beneficios.calcular_categoria(SUM(v.total)),
               techmarket_beneficios.calcular_beneficio(SUM(v.total)),
               SYSDATE,
               USER,
               SYSDATE
          FROM venta v
         WHERE v.id_sucursal = p_id_sucursal
           AND v.fecha_venta BETWEEN p_fecha_desde AND p_fecha_hasta
         GROUP BY v.id_cliente
         ORDER BY v.id_cliente;

        v_filas := SQL%ROWCOUNT;
        DBMS_OUTPUT.PUT_LINE('PACKAGE: sucursal ' || p_id_sucursal || ' -> '
                             || v_filas || ' cliente(s) registrados en bitacora.');
    END procesar_beneficios;

    -- Usa fn_total_cliente (standalone) + funciones del package + formateador PRIVADO
    PROCEDURE mostrar_resumen_cliente(
        p_id_cliente  IN NUMBER,
        p_id_sucursal IN NUMBER,
        p_fecha_desde IN DATE,
        p_fecha_hasta IN DATE
    )
    IS
        v_total NUMBER;
    BEGIN
        pr_validar_periodo(p_fecha_desde, p_fecha_hasta);
        v_total := fn_total_cliente(p_id_cliente, p_id_sucursal,
                                    p_fecha_desde, p_fecha_hasta);
        DBMS_OUTPUT.PUT_LINE('Cliente ' || p_id_cliente
            || ' | Total: ' || fn_formatear_monto_privado(v_total)
            || ' | ' || calcular_categoria(v_total)
            || ' | ' || calcular_beneficio(v_total) || '%');
    END mostrar_resumen_cliente;

END techmarket_beneficios;
/

-- ============================================================
-- 3. PROCEDIMIENTOS NUEVOS
-- ============================================================

-- 3.1 SIN parametros: resumen de la bitacora (BULK COLLECT)
CREATE OR REPLACE PROCEDURE pr_resumen_general
IS
    TYPE t_fila  IS RECORD (
        categoria VARCHAR2(20),
        clientes  NUMBER,
        total     NUMBER
    );
    TYPE t_tabla IS TABLE OF t_fila;
    v_tabla t_tabla;
BEGIN
    SELECT categoria_cliente, COUNT(*), SUM(total_compras)
      BULK COLLECT INTO v_tabla
      FROM bitacora_beneficios
     GROUP BY categoria_cliente
     ORDER BY MIN(porcentaje_beneficio);

    IF v_tabla.COUNT = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Bitacora vacia: ejecute primero el procesamiento de beneficios.');
        RETURN;
    END IF;

    DBMS_OUTPUT.PUT_LINE('=== RESUMEN GENERAL DE BENEFICIOS ===');
    FOR i IN 1 .. v_tabla.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(RPAD(v_tabla(i).categoria, 10)
            || ' | Clientes: ' || v_tabla(i).clientes
            || ' | Total: $' || TO_CHAR(v_tabla(i).total, 'FM999G999G999G990',
                                        'NLS_NUMERIC_CHARACTERS='',.'''));
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Clientes activos en el sistema: ' || fn_clientes_activos);
    DBMS_OUTPUT.PUT_LINE('Ventas totales registradas: $'
        || TO_CHAR(fn_ventas_totales, 'FM999G999G999G990',
                   'NLS_NUMERIC_CHARACTERS='',.'''));
END pr_resumen_general;
/

-- 3.2 CON parametros IN y OUT: resumen de un cliente
CREATE OR REPLACE PROCEDURE pr_obtener_resumen_cliente(
    p_id_cliente  IN  NUMBER,
    p_id_sucursal IN  NUMBER,
    p_fecha_desde IN  DATE,
    p_fecha_hasta IN  DATE,
    p_cantidad    OUT NUMBER,
    p_total       OUT NUMBER,
    p_categoria   OUT VARCHAR2,
    p_beneficio   OUT NUMBER
)
IS
    v_existe NUMBER;
BEGIN
    BEGIN
        SELECT 1 INTO v_existe FROM cliente WHERE id_cliente = p_id_cliente;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20002, 'Cliente ' || p_id_cliente || ' no existe.');
    END;

    SELECT COUNT(*) INTO p_cantidad
      FROM venta
     WHERE id_cliente = p_id_cliente
       AND id_sucursal = p_id_sucursal
       AND fecha_venta BETWEEN p_fecha_desde AND p_fecha_hasta;

    p_total     := fn_total_cliente(p_id_cliente, p_id_sucursal, p_fecha_desde, p_fecha_hasta);
    p_categoria := calcular_categoria(p_total);
    p_beneficio := calcular_beneficio(p_total);
END pr_obtener_resumen_cliente;
/

-- 3.3 CON parametros, MASIVO: recorre TODAS las sucursales y delega en el package
CREATE OR REPLACE PROCEDURE pr_procesar_todas_sucursales(
    p_fecha_desde IN DATE,
    p_fecha_hasta IN DATE
)
IS
    v_sucursales NUMBER := 0;
BEGIN
    FOR s IN (SELECT id_sucursal, nombre FROM sucursal ORDER BY id_sucursal) LOOP
        techmarket_beneficios.procesar_beneficios(s.id_sucursal, p_fecha_desde, p_fecha_hasta);
        v_sucursales := v_sucursales + 1;
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Sucursales procesadas: ' || v_sucursales);
END pr_procesar_todas_sucursales;
/

-- ============================================================
-- 4. TRIGGERS
--    Decision: el compound REEMPLAZA al trigger de solo-fila de EP1
--    (mismo nombre trg_auditoria_beneficios) para no auditar doble.
-- ============================================================
BEGIN
    EXECUTE IMMEDIATE 'DROP TRIGGER trg_auditoria_beneficios';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- 4.1 COMPOUND TRIGGER: nivel SENTENCIA (antes/despues) + nivel FILA, en un objeto
CREATE OR REPLACE TRIGGER trg_auditoria_beneficios
FOR INSERT OR UPDATE ON bitacora_beneficios
COMPOUND TRIGGER

    -- Estado compartido entre las secciones (vive durante UNA sentencia)
    g_operacion VARCHAR2(10);
    g_filas     NUMBER := 0;

    BEFORE STATEMENT IS
    BEGIN
        g_filas := 0;
        IF INSERTING THEN
            g_operacion := 'INSERT';
        ELSE
            g_operacion := 'UPDATE';
        END IF;
        DBMS_OUTPUT.PUT_LINE('[SENTENCIA - INICIO] ' || g_operacion
                             || ' sobre BITACORA_BENEFICIOS por ' || USER);
    END BEFORE STATEMENT;

    AFTER EACH ROW IS
    BEGIN
        INSERT INTO auditoria_beneficios (
            id_bitacora, operacion, usuario_bd, fecha_evento,
            categoria_anterior, categoria_nueva, total_anterior, total_nuevo
        )
        VALUES (
            :NEW.id_bitacora, g_operacion, USER, SYSDATE,
            :OLD.categoria_cliente, :NEW.categoria_cliente,
            :OLD.total_compras, :NEW.total_compras
        );
        g_filas := g_filas + 1;
        DBMS_OUTPUT.PUT_LINE('   [FILA] auditada bitacora ' || :NEW.id_bitacora
                             || ' (' || g_operacion || ')');
    END AFTER EACH ROW;

    AFTER STATEMENT IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('[SENTENCIA - FIN] ' || g_operacion || ': '
                             || g_filas || ' fila(s) auditada(s).');
    END AFTER STATEMENT;

END trg_auditoria_beneficios;
/

-- 4.2 Trigger de SENTENCIA simple: un DELETE masivo deja UNA sola marca
--     (contraste con el de fila: N filas borradas -> 1 registro)
CREATE OR REPLACE TRIGGER trg_bitacora_delete_stmt
AFTER DELETE ON bitacora_beneficios
BEGIN
    INSERT INTO auditoria_beneficios (id_bitacora, operacion, usuario_bd, fecha_evento)
    VALUES (NULL, 'DELETE', USER, SYSDATE);
    DBMS_OUTPUT.PUT_LINE('[SENTENCIA] DELETE sobre BITACORA_BENEFICIOS registrado 1 vez.');
END trg_bitacora_delete_stmt;
/

-- ============================================================
-- 5. VERIFICACION FINAL (no debe aparecer ningun error)
-- ============================================================
SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;

COMMIT;
