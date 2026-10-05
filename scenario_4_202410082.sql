

DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;

-- 1. Tables and sample data
CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
                   CHECK (status IN ('DISPENSED','REVERSED'))
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
 ('Paracetamol 500mg', 100),
 ('Amoxicillin 250mg', 8),
 ('Ibuprofen 200mg', 0),
 ('Oral Rehydration Salts', 40);

SELECT * FROM medicines ORDER BY medicine_id;

-- 2. IF / ELSIF / ELSE stock status
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '%: OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity <= 10 THEN
            RAISE NOTICE '%: LOW on stock (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '%: SUFFICIENTLY stocked (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_day INT := 1;
BEGIN
    WHILE v_day <= 3 LOOP
        RAISE NOTICE 'Stock review day %', v_day;
        v_day := v_day + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', i;
    END LOOP;
END $$;

-- 4. dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INT, p_student_number VARCHAR, p_quantity INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: % (must be greater than zero)', p_quantity;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF v_stock < p_quantity THEN
        RAISE EXCEPTION 'Insufficient stock: requested %, in stock %', p_quantity, v_stock;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_quantity
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity, status)
    VALUES (p_medicine_id, p_student_number, p_quantity, 'DISPENSED');

    RAISE NOTICE 'Dispensed % unit(s) of medicine % to student %',
                 p_quantity, p_medicine_id, p_student_number;
END $$;

-- 5. Two valid dispensing actions and one exceeding stock
CALL dispense_medicine(1, '2021001', 20);
CALL dispense_medicine(4, '2021002', 10);

DO $$
BEGIN
    CALL dispense_medicine(2, '2021003', 15);   -- only 8 in stock
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Dispensing rejected: %', SQLERRM;
END $$;

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 6. reverse_dispensing procedure (idempotent)
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_qty         INT;
    v_status      VARCHAR(20);
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispensing record % does not exist', p_record_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed; stock not restored again', p_record_id;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_medicine_id;
    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    RAISE NOTICE 'Record % reversed; % unit(s) restored to stock', p_record_id, v_qty;
END $$;

CALL reverse_dispensing(1);   -- restores stock
CALL reverse_dispensing(1);   -- restores nothing

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 7. Explicit (parameterised) cursor: medicines below a low-stock threshold
DO $$
DECLARE
    cur_low CURSOR (p_threshold INT) FOR
        SELECT medicine_name, stock_quantity FROM medicines
        WHERE stock_quantity < p_threshold ORDER BY stock_quantity, medicine_name;
    v_name  medicines.medicine_name%TYPE;
    v_stock medicines.stock_quantity%TYPE;
BEGIN
    OPEN cur_low(10);
    LOOP
        FETCH cur_low INTO v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (10): % (% in stock)', v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. Negative quantity handled with EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, '2021004', -5);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final results
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;