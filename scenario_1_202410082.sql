

DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;

-- 1. Tables and sample data
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED','RETURNED'))
);

INSERT INTO books (title, available_copies) VALUES
 ('Database Systems', 5),
 ('Operating Systems', 3),
 ('Computer Networks', 0),
 ('Software Engineering', 1);

SELECT * FROM books ORDER BY book_id;

-- 2. IF / ELSIF / ELSE stock status
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '%: UNAVAILABLE (0 copies)', rec.title;
        ELSIF rec.available_copies <= 2 THEN
            RAISE NOTICE '%: LOW on copies (% left)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '%: SUFFICIENTLY stocked (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    v_counter INT := 1;
BEGIN
    WHILE v_counter <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number: %', v_counter;
        v_counter := v_counter + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number: %', i;
    END LOOP;
END $$;

-- 4. borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(p_book_id INT, p_student_number VARCHAR, p_quantity INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_quantity;
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE EXCEPTION 'Insufficient copies: requested %, available %', p_quantity, v_available;
    END IF;

    UPDATE books SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student_number, p_quantity, 'BORROWED');

    RAISE NOTICE 'Loan recorded: student % borrowed % copy/copies of book %',
                 p_student_number, p_quantity, p_book_id;
END $$;

-- 5. Two valid loans and one request exceeding available copies
CALL borrow_book(1, '2021001', 2);
CALL borrow_book(2, '2021002', 1);

DO $$
BEGIN
    CALL borrow_book(4, '2021003', 3);   -- only 1 copy available
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Loan rejected: %', SQLERRM;
END $$;

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 6. return_book procedure (idempotent)
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty     INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT book_id, quantity, loan_status INTO v_book_id, v_qty, v_status
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan % does not exist', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned; no copies restored', p_loan_id;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book_id;
    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    RAISE NOTICE 'Loan % returned; % copy/copies restored', p_loan_id, v_qty;
END $$;

CALL return_book(1);   -- first call restores copies
CALL return_book(1);   -- second call restores nothing

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 7. Explicit cursor: books with few copies remaining (threshold <= 2)
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT title, available_copies FROM books
        WHERE available_copies <= 2 ORDER BY available_copies, title;
    v_title  books.title%TYPE;
    v_copies books.available_copies%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies remaining: % (% left)', v_title, v_copies;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. Invalid quantity (zero) handled with EXCEPTION block
DO $$
BEGIN
    CALL borrow_book(1, '2021004', 0);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final results
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;