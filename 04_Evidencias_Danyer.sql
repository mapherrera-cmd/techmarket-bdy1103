-- este es el mismo codigo solo que actualizado para que funcionara en one compiller

-- =========================================================================
-- EVIDENCIAS EP2 - TECHMARKET SpA (Danyer Córdoba)
-- =========================================================================

SET SERVEROUTPUT ON;

-- E09: Prueba de Inserción
INSERT INTO bitacora_beneficios (
    id_bitacora, id_cliente, id_sucursal, periodo_desde, periodo_hasta,
    cantidad_compras, total_compras, categoria_cliente,
    porcentaje_beneficio, fecha_proceso, usuario_bd, fecha_actualizacion
) VALUES (
    1, 101, 1, TO_DATE('2026-01-01','YYYY-MM-DD'), TO_DATE('2026-03-31','YYYY-MM-DD'),
    3, 250000, 'BRONZE', 5, SYSDATE, USER, SYSDATE
);
COMMIT;

-- E11: Prueba de Update
UPDATE bitacora_beneficios 
SET total_compras = 350000, categoria_cliente = 'SILVER' 
WHERE id_bitacora = 1;
COMMIT;

-- E14: Bloque de Excepciones controlado
DECLARE
    v_error_test NUMBER;
BEGIN
    SELECT total_compras / 0 INTO v_error_test 
    FROM bitacora_beneficios 
    WHERE id_bitacora = 1;
EXCEPTION
    WHEN ZERO_DIVIDE THEN
        DBMS_OUTPUT.PUT_LINE('EXCEPCIÓN CAPTURADA: ORA-01476: divisor es igual a cero.');
END;
/
