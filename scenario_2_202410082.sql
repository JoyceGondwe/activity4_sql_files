
DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;

-- 1. Tables and sample data
CREATE TABLE lab_sessions (
    session_id              SERIAL PRIMARY KEY,
    session_name            VARCHAR(100) NOT NULL,
    available_workstations  INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id  SERIAL PRIMARY KEY,
    session_id      INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer        VARCHAR(100) NOT NULL,
    workstations    INT NOT NULL CHECK (workstations > 0),
    status          VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
                    CHECK (status IN ('RESERVED','CANCELLED'))
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
 ('Monday 08:00 - Programming Lab', 30),
 ('Tuesday 10:00 - Networks Lab', 4),
 ('Wednesday 14:00 - Databases Lab', 0),
 ('Thursday 09:00 - Web Lab', 12);

SELECT * FROM lab_sessions ORDER BY session_id;

-- 2. IF / ELSIF / ELSE session status
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '%: FULL', rec.session_name;
        ELSIF rec.available_workstations <= 5 THEN
            RAISE NOTICE '%: NEARLY FULL (% left)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '%: has ENOUGH workstations (%)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_counter INT := 1;
BEGIN
    WHILE v_counter <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', v_counter;
        v_counter := v_counter + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', i;
    END LOOP;
END $$;

-- 4. reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(p_session_id INT, p_lecturer VARCHAR, p_workstations INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_workstations IS NULL OR p_workstations <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_workstations;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_available < p_workstations THEN
        RAISE EXCEPTION 'Capacity exceeded: requested %, available %', p_workstations, v_available;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_workstations
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations, status)
    VALUES (p_session_id, p_lecturer, p_workstations, 'RESERVED');

    RAISE NOTICE 'Reservation recorded: % reserved % workstation(s) in session %',
                 p_lecturer, p_workstations, p_session_id;
END $$;

-- 5. Two valid reservations and one exceeding capacity
CALL reserve_workstations(1, 'Dr. Banda', 10);
CALL reserve_workstations(4, 'Mr. Phiri', 5);

DO $$
BEGIN
    CALL reserve_workstations(2, 'Ms. Mwansa', 8);   -- only 4 available
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Reservation rejected: %', SQLERRM;
END $$;

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 6. cancel_reservation procedure (idempotent)
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_count      INT;
    v_status     VARCHAR(20);
BEGIN
    SELECT session_id, workstations, status INTO v_session_id, v_count, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % already cancelled; nothing released', p_reservation_id;
        RETURN;
    END IF;

    UPDATE lab_sessions SET available_workstations = available_workstations + v_count
    WHERE session_id = v_session_id;
    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    RAISE NOTICE 'Reservation % cancelled; % workstation(s) released', p_reservation_id, v_count;
END $$;

CALL cancel_reservation(1);   -- releases workstations
CALL cancel_reservation(1);   -- releases nothing

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 7. Explicit cursor: sessions with few workstations remaining (<= 5)
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_name, available_workstations FROM lab_sessions
        WHERE available_workstations <= 5 ORDER BY available_workstations, session_name;
    v_name  lab_sessions.session_name%TYPE;
    v_avail lab_sessions.available_workstations%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_name, v_avail;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations remaining: % (% left)', v_name, v_avail;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. Zero workstations handled with EXCEPTION block
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Banda', 0);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final results
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;