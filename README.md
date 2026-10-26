# TechMarket SpA – Sistema de fidelización de clientes
**Asignatura:** BDY1103 – Taller de Base de Datos (Duoc UC)
**Profesor:** Leonel Octavio Garay Burgos
**Evaluación:** EP2 – Procedimientos, funciones, packages y triggers (Oracle PL/SQL)

## Integrantes y responsabilidades
| Integrante | Responsabilidad | Evidencias |
|---|---|---|
| Max Herrera | Procedimientos, integración, base EP1, diagramas e informe | E00, E04, E05, E06, E15, C01, C02 |
| Pablo Quintino | Funciones y package | E01, E02, E03, E07, E08 |
| Danyer Cordova | Triggers y excepciones | E09, E10, E11, E12, E13, E14 |

## Orden de ejecución (Oracle SQL Developer, F5 Run Script)
1. `02_SQL/script_maestro.sql` (crea tablas, datos y objetos EP1)
2. `02_SQL/script_EP2_completo.sql` (al final, `SELECT * FROM user_errors` debe salir vacío)
3. `02_SQL/test_EP2_evidencias.sql` (ejecutar E00 primero, luego cada sección por separado)

## Estructura
- `02_SQL/`: scripts maestro, EP2 y de pruebas
- `03_Diagramas/`: modelo de datos y dependencias de objetos
- `04_Evidencias/EP2/`: capturas E00 a E15, C01 y C02
- `05_Entrega/`: informe en Word
- `docs/`: entregables y notas de la Fase 1

## Objetos EP2
- **Funciones:** `fn_clientes_activos`, `fn_ventas_totales`, `fn_total_cliente`
- **Procedimientos:** `pr_resumen_general`, `pr_obtener_resumen_cliente`, `pr_procesar_todas_sucursales`
- **Package:** `techmarket_beneficios` (público: constantes, `ex_periodo_invalido`, `calcular_categoria`, `calcular_beneficio`, `procesar_beneficios`, `mostrar_resumen_cliente`; privado: `fn_formatear_monto_privado`, `pr_validar_periodo`)
- **Triggers:** `trg_auditoria_beneficios` (compound) y `trg_bitacora_delete_stmt` (sentencia)
