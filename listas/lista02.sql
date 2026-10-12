-- Questão 01 - View de Performance da Equipe

DROP VIEW IF EXISTS v_staff_performance;
CREATE VIEW v_staff_performance AS
SELECT
    sta.staff_id AS "ID do Funcionário",
    sta.first_name || ' ' || sta.last_name AS "Nome Completo",
    ci.city || ', ' || co.country AS "Cidade - País",
    COALESCE(rentals.total_rentals, 0) AS "Locações Totais",
    COALESCE(payments.total_payments, 0) AS "Faturamento Total"
FROM staff AS sta
LEFT JOIN store AS sto
    ON sta.store_id = sto.store_id
LEFT JOIN address AS a
    ON sto.address_id = a.address_id
LEFT JOIN city AS ci
    ON a.city_id = ci.city_id
LEFT JOIN country AS co
    ON ci.country_id = co.country_id
LEFT JOIN (
    SELECT staff_id, COUNT(*) AS total_rentals
    FROM rental
    GROUP BY staff_id
) AS rentals
    ON sta.staff_id = rentals.staff_id
LEFT JOIN (
    SELECT staff_id, SUM(amount) AS total_payments
    FROM payment
    GROUP BY staff_id
) AS payments
    ON sta.staff_id = payments.staff_id;

-- Questão 02 - View Materializada de Receita por Categoria

DROP MATERIALIZED VIEW IF EXISTS mv_category_total_sales;
CREATE MATERIALIZED VIEW mv_category_total_sales AS
SELECT
    cat.category_id AS "ID da Categoria",
    cat.name AS "Categoria",
    COALESCE(SUM(pay.amount), 0) AS "Receita Total"
FROM category AS cat
LEFT JOIN film_category AS fc
    ON cat.category_id = fc.category_id
LEFT JOIN inventory AS inv
    ON fc.film_id = inv.film_id
LEFT JOIN rental AS ren
    ON inv.inventory_id = ren.inventory_id
LEFT JOIN payment AS pay
    ON ren.rental_id = pay.rental_id
GROUP BY cat.category_id, cat.name;

CREATE UNIQUE INDEX idx_mv_category_total_sales_category_id
    ON mv_category_total_sales ("ID da Categoria");

REFRESH MATERIALIZED VIEW CONCURRENTLY mv_category_total_sales;
-- select * from mv_category_total_sales;

-- Questão 03 - Otimizando Filmes Atrasados
CREATE INDEX IF NOT EXISTS idx_rental_open
    ON rental (rental_id)
    WHERE return_date IS NULL;

EXPLAIN ANALYZE
SELECT rental_id, rental_date, customer_id
FROM rental
WHERE return_date IS NULL;


-- Questão 04 - Busca Inteligente de Sinopses
CREATE INDEX IF NOT EXISTS idx_film_description_fts
    ON film
    USING GIN (to_tsvector('english', description));

EXPLAIN ANALYZE
SELECT film_id, title, description
FROM film
WHERE to_tsvector('english', description)
    @@ to_tsquery('english', 'documentary & drama');


-- Questão 05 - Histórico do Cliente
CREATE INDEX IF NOT EXISTS idx_payment_customer_date
    ON payment (customer_id, payment_date DESC);

-- customer_id vem primeiro porque a consulta filtra por igualdade nessa coluna;
-- payment_date entrega os pagamentos em ordem decrescente logo em seguida.
SELECT *
FROM payment
WHERE customer_id = 1
ORDER BY payment_date DESC;

-- Questão 06 - Login Case-Insensitive
CREATE INDEX IF NOT EXISTS idx_customer_email_lower
    ON customer (LOWER(email));

EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, email
FROM customer
WHERE LOWER(email) = LOWER('MARY.SMITH@SAKILACUSTOMER.ORG');

-- Questão 07 - Validação de Datas
CREATE OR REPLACE FUNCTION validate_rental_dates()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.return_date IS NOT NULL
       AND NEW.return_date < NEW.rental_date THEN
        RAISE EXCEPTION 'A data de devolução não pode ser anterior à data da locação.'
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_rental_dates ON rental;
CREATE TRIGGER trg_validate_rental_dates
    BEFORE INSERT OR UPDATE ON rental
    FOR EACH ROW
    EXECUTE FUNCTION validate_rental_dates();
-- Teste valido
BEGIN;
UPDATE rental
SET return_date = rental_date + INTERVAL '1 day'
WHERE rental_id = (SELECT MIN(rental_id) FROM rental);
ROLLBACK;

-- Teste inválido
DO $$
DECLARE
    invalid_date_rejected BOOLEAN := FALSE;
BEGIN
    BEGIN
        UPDATE rental
        SET return_date = rental_date - INTERVAL '1 day'
        WHERE rental_id = (SELECT MIN(rental_id) FROM rental);
    EXCEPTION
        WHEN check_violation THEN
            invalid_date_rejected := TRUE;
    END;

    IF NOT invalid_date_rejected THEN
        RAISE EXCEPTION 'Falha no teste: o trigger aceitou uma data inválida.';
    END IF;
END;
$$;


-- Questão 08 - Auditoria de Preços
CREATE TABLE IF NOT EXISTS film_cost_audit (
    film_id INTEGER NOT NULL,
    old_cost NUMERIC(5,2) NOT NULL,
    new_cost NUMERIC(5,2) NOT NULL,
    changed_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION audit_film_replacement_cost()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO film_cost_audit (film_id, old_cost, new_cost)
    VALUES (OLD.film_id, OLD.replacement_cost, NEW.replacement_cost);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_film_replacement_cost ON film;
CREATE TRIGGER trg_audit_film_replacement_cost
    AFTER UPDATE ON film
    FOR EACH ROW
    WHEN (OLD.replacement_cost IS DISTINCT FROM NEW.replacement_cost)
    EXECUTE FUNCTION audit_film_replacement_cost();

-- Questão 09 - Proteção de Catálogo
CREATE OR REPLACE FUNCTION prevent_language_delete_when_in_use()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM film
        WHERE language_id = OLD.language_id
           OR original_language_id = OLD.language_id
    ) THEN
        RAISE EXCEPTION 'Não é possível excluir o idioma: ele está associado a um ou mais filmes.'
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_language_delete_when_in_use ON language;
CREATE TRIGGER trg_prevent_language_delete_when_in_use
    BEFORE DELETE ON language
    FOR EACH ROW
    EXECUTE FUNCTION prevent_language_delete_when_in_use();

-- Questão 10 - Sincronização de Estatísticas
CREATE TABLE IF NOT EXISTS customer_rental_stats (
    customer_id SMALLINT PRIMARY KEY REFERENCES customer (customer_id),
    total_rentals INTEGER NOT NULL DEFAULT 0
);

INSERT INTO customer_rental_stats (customer_id, total_rentals)
SELECT customer.customer_id, COUNT(rental.rental_id)::INTEGER
FROM customer
LEFT JOIN rental
    ON rental.customer_id = customer.customer_id
GROUP BY customer.customer_id
ON CONFLICT (customer_id) DO UPDATE
SET total_rentals = EXCLUDED.total_rentals;

CREATE OR REPLACE FUNCTION increment_customer_rental_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO customer_rental_stats (customer_id, total_rentals)
    VALUES (NEW.customer_id, 1)
    ON CONFLICT (customer_id) DO UPDATE
    SET total_rentals = customer_rental_stats.total_rentals + 1;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_increment_customer_rental_stats ON rental;
CREATE TRIGGER trg_increment_customer_rental_stats
    AFTER INSERT ON rental
    FOR EACH ROW
    EXECUTE FUNCTION increment_customer_rental_stats();
