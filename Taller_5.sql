

--Actualizar la información del cliente

CREATE OR REPLACE PROCEDURE actualizar_informacion_cliente(
    IN p_cliente_id INT,
    IN p_direccion TEXT,
    IN p_telefono VARCHAR(15),
    IN p_correo_electronico VARCHAR(255)
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Verificar que el cliente existe
    IF NOT EXISTS (SELECT 1 FROM Clientes WHERE cliente_id = p_cliente_id) THEN
        RAISE EXCEPTION 'Cliente con el ID % no existe', p_cliente_id;
    END IF;

    -- Actualizar la información del cliente
    UPDATE Clientes
    SET direccion = p_direccion,
        telefono = p_telefono,
        correo_electronico = p_correo_electronico
    WHERE cliente_id = p_cliente_id;

    RAISE NOTICE 'Información del cliente con ID % actualizada con éxito.', p_cliente_id;
END;
$$;

CALL actualizar_informacion_cliente(
    1, -- Reemplaza con un ID de cliente válido
    'Prueba',
    '555-1234',
    'juan.perez@clientes.com'
);


--Eliminar una cuenta bancaria
CREATE OR REPLACE PROCEDURE eliminar_cuenta_bancaria(
    IN p_numero_cuenta CHAR(9)
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Verificar que la cuenta bancaria existe
    IF NOT EXISTS (SELECT 1 FROM Cuentas_bancarias WHERE numero_cuenta = p_numero_cuenta) THEN
        RAISE EXCEPTION 'Cuenta bancaria con el número % no existe', p_numero_cuenta;
    END IF;

    -- Eliminar las transacciones asociadas a la cuenta bancaria
    DELETE FROM Transacciones
    WHERE numero_cuenta = (SELECT numero_cuenta FROM Cuentas_bancarias WHERE numero_cuenta = p_numero_cuenta);

	-- Eliminar Prestamos asociados a la cuenta bancaria
    DELETE FROM prestamos
    WHERE numero_cuenta = (SELECT numero_cuenta FROM Cuentas_bancarias WHERE numero_cuenta = p_numero_cuenta);

	-- Eliminar TC asociados a la cuenta bancaria
    DELETE FROM tarjetas_credito
    WHERE numero_cuenta = (SELECT numero_cuenta FROM Cuentas_bancarias WHERE numero_cuenta = p_numero_cuenta);

    -- Eliminar la cuenta bancaria
    DELETE FROM Cuentas_bancarias
    WHERE numero_cuenta = p_numero_cuenta;

    RAISE NOTICE 'Cuenta bancaria con el número % eliminada con éxito.', p_numero_cuenta;
END;
$$;

CALL eliminar_cuenta_bancaria('1234567890');

--Transferir fondos entre cuentas

CREATE OR REPLACE PROCEDURE transferir_fondos(
    IN p_cuenta_origen_id character varying(50),
    IN p_cuenta_destino_id character varying(50),
    IN p_monto NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cuenta_origen_id INTEGER;
    v_cuenta_destino_id INTEGER;
BEGIN
    -- Verificar que la cuenta de origen existe
    IF NOT EXISTS (SELECT 1 FROM Cuentas_bancarias WHERE numero_cuenta = p_cuenta_origen_id) THEN
        RAISE EXCEPTION 'Cuenta de origen con el ID % no existe', p_cuenta_origen_id;
    END IF;

    -- Verificar que la cuenta de destino existe
    IF NOT EXISTS (SELECT 1 FROM Cuentas_bancarias WHERE numero_cuenta = p_cuenta_destino_id) THEN
        RAISE EXCEPTION 'Cuenta de destino con el ID % no existe', p_cuenta_destino_id;
    END IF;

    -- Verificar que la cuenta de origen tiene suficiente saldo
    IF (SELECT saldo FROM Cuentas_bancarias WHERE numero_cuenta = p_cuenta_origen_id) < p_monto THEN
        RAISE EXCEPTION 'Saldo insuficiente en la cuenta de origen con el ID %', p_cuenta_origen_id;
    END IF;

    -- Iniciar la transferencia de fondos
    BEGIN
        -- Reducir el saldo en la cuenta de origen
        UPDATE Cuentas_bancarias
        SET saldo = saldo - p_monto
        WHERE numero_cuenta = p_cuenta_origen_id;

        -- Aumentar el saldo en la cuenta de destino
        UPDATE Cuentas_bancarias
        SET saldo = saldo + p_monto
        WHERE numero_cuenta = p_cuenta_destino_id;

        -- Obtener los IDs de las cuentas
        SELECT cuenta_id 
        INTO v_cuenta_origen_id
        FROM Cuentas_bancarias 
        WHERE numero_cuenta = p_cuenta_origen_id;

        SELECT cuenta_id 
        INTO v_cuenta_destino_id
        FROM Cuentas_bancarias 
        WHERE numero_cuenta = p_cuenta_destino_id;

        -- Registrar la transacción en la tabla de transacciones
        INSERT INTO Transacciones (cuenta_id, monto, tipo_transaccion, fecha_transaccion)
        VALUES (v_cuenta_origen_id, -p_monto, 'retiro', NOW());

        INSERT INTO Transacciones (cuenta_id, monto, tipo_transaccion, fecha_transaccion)
        VALUES (v_cuenta_destino_id, p_monto, 'transferencia', NOW());

    EXCEPTION
        -- Manejo de errores en caso de que la transacción falle
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Error en la transferencia de fondos: %', SQLERRM;
    END;

    RAISE NOTICE 'Transferencia de % desde la cuenta % a la cuenta % completada con éxito',
        p_monto, p_cuenta_origen_id, p_cuenta_destino_id;
END;
$$;

CALL transferir_fondos('2345678901', '3456789012', 100.00);

--Agregar una nueva transacción

CREATE OR REPLACE PROCEDURE agregar_transaccion(
    IN p_numero_cuenta character varying(50),
    IN p_monto NUMERIC,
    IN p_tipo_transaccion character varying(20) -- 'depósito' o 'retiro'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_cuenta_id INTEGER;
BEGIN
    -- Verificar que la cuenta existe
    IF NOT EXISTS (SELECT 1 FROM Cuentas_bancarias WHERE numero_cuenta = p_numero_cuenta) THEN
        RAISE EXCEPTION 'Cuenta con el número de cuenta % no existe', p_numero_cuenta;
    END IF;

    -- Obtener el ID de la cuenta
    SELECT cuenta_id
    INTO v_cuenta_id
    FROM Cuentas_bancarias
    WHERE numero_cuenta = p_numero_cuenta;

    -- Actualizar el saldo basado en el tipo de transacción
    IF p_tipo_transaccion = 'depósito' THEN
        -- Aumentar el saldo
        UPDATE Cuentas_bancarias
        SET saldo = saldo + p_monto
        WHERE cuenta_id = v_cuenta_id;
    ELSIF p_tipo_transaccion = 'retiro' THEN
        -- Verificar que hay suficiente saldo
        IF (SELECT saldo FROM Cuentas_bancarias WHERE cuenta_id = v_cuenta_id) < p_monto THEN
            RAISE EXCEPTION 'Saldo insuficiente en la cuenta con el número de cuenta %', p_numero_cuenta;
        END IF;
        -- Disminuir el saldo
        UPDATE Cuentas_bancarias
        SET saldo = saldo - p_monto
        WHERE cuenta_id = v_cuenta_id;
    ELSE
        RAISE EXCEPTION 'Tipo de transacción % no válido. Debe ser "depósito" o "retiro".', p_tipo_transaccion;
    END IF;

    -- Registrar la transacción en la tabla de transacciones
    INSERT INTO Transacciones (cuenta_id, monto, tipo_transaccion, fecha_transaccion)
    VALUES (v_cuenta_id, p_monto, p_tipo_transaccion, NOW());

    RAISE NOTICE 'Transacción de % con éxito en la cuenta %', p_tipo_transaccion, p_numero_cuenta;
END;
$$;


CALL agregar_transaccion('2345678901', 100.00, 'depósito');

CALL agregar_transaccion('3456789012', 100.00, 'retiro');

--Calcular el saldo total de todas las cuentas de un cliente

CREATE OR REPLACE PROCEDURE calcular_saldo_total_cliente(
    IN p_cliente_id INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_saldo_total NUMERIC;
BEGIN
    -- Verificar que el cliente existe
    IF NOT EXISTS (SELECT 1 FROM Clientes WHERE cliente_id = p_cliente_id) THEN
        RAISE EXCEPTION 'Cliente con el ID % no existe', p_cliente_id;
    END IF;

    -- Calcular el saldo total de todas las cuentas del cliente
    SELECT COALESCE(SUM(saldo), 0)
    INTO v_saldo_total
    FROM Cuentas_bancarias
    WHERE cliente_id = p_cliente_id;

    -- Mostrar el saldo total
    RAISE NOTICE 'El saldo total para el cliente % es %', p_cliente_id, v_saldo_total;
END;
$$;

CALL calcular_saldo_total_cliente(2);

--Generar un reporte de transacciones para un rango de fechas
CREATE OR REPLACE PROCEDURE generar_reporte_transacciones(
    IN p_fecha_inicio DATE,
    IN p_fecha_fin DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    record RECORD;
BEGIN
    -- Verificar que el rango de fechas es válido
    IF p_fecha_inicio > p_fecha_fin THEN
        RAISE EXCEPTION 'La fecha de inicio % no puede ser mayor que la fecha de fin %', p_fecha_inicio, p_fecha_fin;
    END IF;

    -- Mostrar el reporte de transacciones
    RAISE NOTICE 'Reporte de transacciones desde % hasta %', p_fecha_inicio, p_fecha_fin;
    
    -- Consultar las transacciones en el rango de fechas
    FOR record IN
        SELECT transaccion_id, cuenta_id, tipo_transaccion, monto, fecha_transaccion::DATE AS fecha_transaccion, descripcion
        FROM Transacciones
        WHERE fecha_transaccion::DATE BETWEEN p_fecha_inicio AND p_fecha_fin
    LOOP
        RAISE NOTICE 'ID: %, Cuenta ID: %, Tipo: %, Monto: %, Fecha: %, Descripción: %',
            record.transaccion_id, record.cuenta_id, record.tipo_transaccion, record.monto, record.fecha_transaccion, record.descripcion;
    END LOOP;
END;
$$;


DO $$
BEGIN
    -- Llamar al procedimiento con el rango de fechas deseado
    CALL generar_reporte_transacciones('2024-01-01', '2024-08-01');
END;
$$;