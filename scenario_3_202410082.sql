

DROP TABLE IF EXISTS allocations CASCADE;
DROP TABLE IF EXISTS hostel_rooms CASCADE;

-- 1. Tables and sample data
CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_name        VARCHAR(20) NOT NULL,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(20) NOT NULL DEFAULT 'ALLOCATED'
                   CHECK (status IN ('ALLOCATED','COMPLETE'))
);

INSERT INTO hostel_rooms (room_name, available_spaces) VALUES
 ('Room A101', 4),
 ('Room A102', 1),
 ('Room B201', 0),
 ('Room B202', 3);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- 2. IF / ELSIF / ELSE room status
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_name, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE '%: FULL', rec.room_name;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE '%: has ONE space left', rec.room_name;
        ELSE
            RAISE NOTICE '%: has SEVERAL spaces (%)', rec.room_name, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_day INT := 1;
BEGIN
    WHILE v_day <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', v_day;
        v_day := v_day + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', i;
    END LOOP;
END $$;

-- 4. allocate_room procedure
CREATE OR REPLACE PROCEDURE allocate_room(p_student_number VARCHAR, p_room_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_student_number IS NULL OR btrim(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank';
    END IF;

    SELECT available_spaces INTO v_available
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_available < 1 THEN
        RAISE EXCEPTION 'Room % is full; no bed space available', p_room_id;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id, status)
    VALUES (btrim(p_student_number), p_room_id, 'ALLOCATED');

    RAISE NOTICE 'Student % allocated to room %', p_student_number, p_room_id;
END $$;

-- 5. Two valid allocations and one to a full room
CALL allocate_room('2021001', 1);
CALL allocate_room('2021002', 2);

DO $$
BEGIN
    CALL allocate_room('2021003', 3);   -- Room B201 is full
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Allocation rejected: %', SQLERRM;
END $$;

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 6. check_out procedure (idempotent)
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT room_id, status INTO v_room_id, v_status
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation % does not exist', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % already checked out; no space freed', p_allocation_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room_id;
    UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
    RAISE NOTICE 'Allocation % checked out; one bed space freed in room %', p_allocation_id, v_room_id;
END $$;

CALL check_out(1);   -- frees a space
CALL check_out(1);   -- frees nothing

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 7. Explicit cursor: full or nearly full rooms (<= 1 space)
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_name, available_spaces FROM hostel_rooms
        WHERE available_spaces <= 1 ORDER BY available_spaces, room_name;
    v_name   hostel_rooms.room_name%TYPE;
    v_spaces hostel_rooms.available_spaces%TYPE;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_name, v_spaces;
        EXIT WHEN NOT FOUND;
        IF v_spaces = 0 THEN
            RAISE NOTICE '%: FULL', v_name;
        ELSE
            RAISE NOTICE '%: NEARLY FULL (% space left)', v_name, v_spaces;
        END IF;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- 8. Blank student number handled with EXCEPTION block
DO $$
BEGIN
    CALL allocate_room('   ', 1);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final results
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;