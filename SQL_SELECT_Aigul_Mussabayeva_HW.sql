/*
================================================================================
 SQL SELECT homework
 Author:   Aigul Mussabayeva
 Database: dvdrental (PostgreSQL)
================================================================================

 Database analysis (done before solving the tasks)
 -------------------------------------------------
 Transactional data (events that happen over time):
     public.rental, public.payment
 Reference data (dictionaries / master data):
     public.film, public.actor, public.category, public.language,
     public.store, public.staff, public.customer,
     public.address, public.city, public.country
 Tables that connect entities (many-to-many bridges):
     public.film_actor     (film <-> actor)
     public.film_category  (film <-> category)
     public.inventory      (film <-> store; one row = one physical copy / disk)

 General assumptions used in all tasks
 -------------------------------------
 1. Categories and ratings are found by their NAME, never by a hardcoded ID.
    Names are compared with UPPER(...) so that 'Drama' / 'DRAMA' both match.
 2. "Store of a payment" = the store that owns the rented copy:
        payment -> rental -> inventory -> store_id
 3. Date ranges are written as  >= start AND < next_period_start
    instead of EXTRACT(YEAR ...) = ..., so that an index on the date column
    can be used and the last day of a period is never lost because of time.
 4. Top-N tasks use LIMIT N. If several rows share the N-th value, only N rows
    are shown (ties are cut). This is mentioned again in the tasks themselves.
 5. Window functions are not used (task requirement).
================================================================================
*/


/* =============================================================================
   PART 1
   ============================================================================= */

/* -----------------------------------------------------------------------------
   Task 1.1
   The marketing team needs a list of animation movies between 2017 and 2019
   to promote family-friendly content in an upcoming season in stores.
   Show all animation movies released during this period with rate more than 1,
   sorted alphabetically.

   Assumptions / interpretation:
   - "between 2017 and 2019" includes both 2017 and 2019.
   - "rate" = public.film.rental_rate, "more than 1" = strictly > 1.
   - A film belongs to Animation if it has the category 'Animation'
     in public.film_category (found by name, not by category_id).
----------------------------------------------------------------------------- */

-- 1.1 (a) JOIN solution
-- INNER JOIN keeps only films that have a category row AND whose category
-- exists; films without a category are dropped, which is what we need here.
SELECT f.title,
       f.release_year,
       f.rental_rate
FROM public.film AS f
INNER JOIN public.film_category AS fc
        ON fc.film_id = f.film_id
INNER JOIN public.category AS c
        ON c.category_id = fc.category_id
WHERE UPPER(c.name) = 'ANIMATION'
  AND f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
ORDER BY f.title;

-- 1.1 (b) Subquery solution
-- The subquery returns the list of film_id that are animations;
-- the outer query filters films by that list with IN.
-- INNER JOIN inside the subquery: only category rows that really exist.
SELECT f.title,
       f.release_year,
       f.rental_rate
FROM public.film AS f
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
  AND f.film_id IN (
        SELECT fc.film_id
        FROM public.film_category AS fc
        INNER JOIN public.category AS c
                ON c.category_id = fc.category_id
        WHERE UPPER(c.name) = 'ANIMATION'
      )
ORDER BY f.title;

-- 1.1 (c) CTE solution
-- Step 1 (CTE): list of animation film ids. Step 2: join it to films.
-- INNER JOIN with the CTE keeps only films present in the animation list.
WITH animation_films AS (
    SELECT fc.film_id
    FROM public.film_category AS fc
    INNER JOIN public.category AS c
            ON c.category_id = fc.category_id
    WHERE UPPER(c.name) = 'ANIMATION'
)
SELECT f.title,
       f.release_year,
       f.rental_rate
FROM public.film AS f
INNER JOIN animation_films AS af
        ON af.film_id = f.film_id
WHERE f.release_year BETWEEN 2017 AND 2019
  AND f.rental_rate > 1
ORDER BY f.title;

/*
   Comparison 1.1
   - JOIN: shortest and most direct; easy for the optimizer.
     Minus: if a film had the same category twice it could be duplicated
     (not possible here: film_category has PK (film_id, category_id)).
   - Subquery (IN): reads like the business question ("films that are in the
     animation list"); IN never duplicates rows. Minus: logic is split into
     an inner and outer part.
   - CTE: the "animation" filter gets a name, so the query is read top-down;
     handy if the list is reused. Minus: more lines for a simple task.
   Performance: PostgreSQL produces practically the same plan for all three.
   Production choice: JOIN - simplest and clear enough for a one-step filter.
*/


/* -----------------------------------------------------------------------------
   Task 1.2
   The finance department requires a report on store performance to assess
   profitability and plan resource allocation for stores after March 2017.
   Calculate the revenue earned by each rental store after March 2017
   (since April) (include columns: address and address2 - as one column,
   revenue).

   Assumptions / interpretation:
   - "after March 2017 (since April)" = payment_date >= 2017-04-01,
     with no upper limit (all later payments are included).
   - Revenue = SUM(public.payment.amount).
   - A payment belongs to the store that owns the rented copy:
     payment -> rental -> inventory -> store.
   - address and address2 are joined with a space; address2 is often NULL or
     an empty string, so NULLIF(...,'') + CONCAT_WS skips it without leaving
     a trailing space.
   - Stores without payments in the period are still shown with revenue 0.
----------------------------------------------------------------------------- */

-- 1.2 (a) JOIN solution
-- INNER JOIN store-address: every store has an address.
-- LEFT JOIN inventory/rental/payment: keeps stores even if they have no copies,
-- rentals or payments in the period (their revenue becomes 0 via COALESCE).
-- The date filter is placed in the ON clause of the payment join on purpose:
-- in WHERE it would remove the NULL rows and turn the LEFT JOIN into INNER.
SELECT CONCAT_WS(' ', a.address, NULLIF(a.address2, '')) AS store_address,
       COALESCE(SUM(p.amount), 0)                       AS revenue
FROM public.store AS s
INNER JOIN public.address AS a
        ON a.address_id = s.address_id
LEFT JOIN public.inventory AS i
       ON i.store_id = s.store_id
LEFT JOIN public.rental AS r
       ON r.inventory_id = i.inventory_id
LEFT JOIN public.payment AS p
       ON p.rental_id = r.rental_id
      AND p.payment_date >= DATE '2017-04-01'
GROUP BY s.store_id,
         a.address,
         a.address2
ORDER BY revenue DESC;

-- 1.2 (b) Subquery solution
-- Correlated scalar subquery: for every store it sums that store's payments.
-- INNER JOINs inside the subquery: only payments that have a rental and copy.
-- COALESCE turns NULL (store without payments) into 0.
SELECT CONCAT_WS(' ', a.address, NULLIF(a.address2, '')) AS store_address,
       COALESCE((
            SELECT SUM(p.amount)
            FROM public.payment AS p
            INNER JOIN public.rental AS r
                    ON r.rental_id = p.rental_id
            INNER JOIN public.inventory AS i
                    ON i.inventory_id = r.inventory_id
            WHERE i.store_id = s.store_id
              AND p.payment_date >= DATE '2017-04-01'
       ), 0)                                            AS revenue
FROM public.store AS s
INNER JOIN public.address AS a
        ON a.address_id = s.address_id
ORDER BY revenue DESC;

-- 1.2 (c) CTE solution
-- CTE: revenue per store_id (INNER JOINs: only real payments are summed).
-- Main query: LEFT JOIN from store to the CTE keeps stores without revenue.
WITH store_revenue AS (
    SELECT i.store_id,
           SUM(p.amount) AS revenue
    FROM public.payment AS p
    INNER JOIN public.rental AS r
            ON r.rental_id = p.rental_id
    INNER JOIN public.inventory AS i
            ON i.inventory_id = r.inventory_id
    WHERE p.payment_date >= DATE '2017-04-01'
    GROUP BY i.store_id
)
SELECT CONCAT_WS(' ', a.address, NULLIF(a.address2, '')) AS store_address,
       COALESCE(sr.revenue, 0)                          AS revenue
FROM public.store AS s
INNER JOIN public.address AS a
        ON a.address_id = s.address_id
LEFT JOIN store_revenue AS sr
       ON sr.store_id = s.store_id
ORDER BY revenue DESC;

/*
   Comparison 1.2
   - JOIN: one level, but a long LEFT JOIN chain; the filter must sit in ON,
     which is an easy place to make a mistake. Joins all copies and rentals
     of every store before aggregating - more rows in memory.
   - Subquery (correlated): very readable ("for each store, sum its payments").
     It is executed once per store; fine for 2-3 stores, slow for thousands.
   - CTE: first aggregates payments (small result), then attaches addresses.
     Clear two-step logic, easy to test the CTE alone.
   Production choice: CTE - clear, aggregates before joining, scales well.
*/


/* -----------------------------------------------------------------------------
   Task 1.3
   The marketing department in our stores aims to identify the most successful
   actors since 2015 to boost customer interest in their films.
   Show top-5 actors by number of movies (released since 2015) they took part
   in (columns: first_name, last_name, number_of_movies, sorted by
   number_of_movies in descending order).

   Assumptions / interpretation:
   - "since 2015" includes 2015: release_year >= 2015.
   - Top-5 = 5 rows (LIMIT 5). If several actors share the 5th place, only
     some of them are shown; the secondary sort by last_name/first_name makes
     the result stable (always the same 5 rows).
----------------------------------------------------------------------------- */

-- 1.3 (a) JOIN solution
-- INNER JOINs: only actors that have at least one film released since 2015.
SELECT a.first_name,
       a.last_name,
       COUNT(DISTINCT f.film_id) AS number_of_movies
FROM public.actor AS a
INNER JOIN public.film_actor AS fa
        ON fa.actor_id = a.actor_id
INNER JOIN public.film AS f
        ON f.film_id = fa.film_id
WHERE f.release_year >= 2015
GROUP BY a.actor_id,
         a.first_name,
         a.last_name
ORDER BY number_of_movies DESC,
         a.last_name,
         a.first_name
LIMIT 5;

-- 1.3 (b) Subquery solution
-- Derived table (subquery in FROM) counts films per actor_id,
-- then INNER JOIN with actor adds the names.
SELECT a.first_name,
       a.last_name,
       am.number_of_movies
FROM (
        SELECT fa.actor_id,
               COUNT(DISTINCT f.film_id) AS number_of_movies
        FROM public.film_actor AS fa
        INNER JOIN public.film AS f
                ON f.film_id = fa.film_id
        WHERE f.release_year >= 2015
        GROUP BY fa.actor_id
     ) AS am
INNER JOIN public.actor AS a
        ON a.actor_id = am.actor_id
ORDER BY am.number_of_movies DESC,
         a.last_name,
         a.first_name
LIMIT 5;

-- 1.3 (c) CTE solution
-- Same logic as (b), but the counting step is named and placed on top.
WITH actor_movies AS (
    SELECT fa.actor_id,
           COUNT(DISTINCT f.film_id) AS number_of_movies
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f
            ON f.film_id = fa.film_id
    WHERE f.release_year >= 2015
    GROUP BY fa.actor_id
)
SELECT a.first_name,
       a.last_name,
       am.number_of_movies
FROM actor_movies AS am
INNER JOIN public.actor AS a
        ON a.actor_id = am.actor_id
ORDER BY am.number_of_movies DESC,
         a.last_name,
         a.first_name
LIMIT 5;

/*
   Comparison 1.3
   - JOIN: compact; names must be repeated in GROUP BY.
   - Subquery in FROM: aggregates on narrow data (ids only), then adds names;
     must be read "inside out".
   - CTE: same efficiency as the subquery, read top-down, easy to debug
     (run the CTE alone to see counts for every actor).
   Limitation of all three: LIMIT 5 cuts ties on the 5th place.
   Production choice: CTE - readable and the counting step can be reused.
*/


/* -----------------------------------------------------------------------------
   Task 1.4
   The marketing team needs to track the production trends of Drama, Travel,
   and Documentary films to inform genre-specific marketing strategies.
   Show number of Drama, Travel, Documentary per year (include columns:
   release_year, number_of_drama_movies, number_of_travel_movies,
   number_of_documentary_movies), sorted by release year in descending order.
   Dealing with NULL values is encouraged.

   Assumptions / interpretation:
   - Every release year that exists in public.film is shown, even if it has
     none of the three genres (then all counts are 0, not NULL).
   - Films with release_year IS NULL are excluded: a year is required to
     place a film on the timeline.
   - A film with two of these genres (e.g. Drama and Travel) is counted in
     both columns.
----------------------------------------------------------------------------- */

-- 1.4 (a) JOIN solution (conditional aggregation)
-- LEFT JOIN film_category / category: keeps every film, so every year appears.
-- The genre filter is in the ON clause: other categories become NULL instead
-- of removing the film. COUNT ignores NULL, so the result is 0, never NULL.
SELECT f.release_year,
       COUNT(DISTINCT CASE WHEN UPPER(c.name) = 'DRAMA'       THEN f.film_id END) AS number_of_drama_movies,
       COUNT(DISTINCT CASE WHEN UPPER(c.name) = 'TRAVEL'      THEN f.film_id END) AS number_of_travel_movies,
       COUNT(DISTINCT CASE WHEN UPPER(c.name) = 'DOCUMENTARY' THEN f.film_id END) AS number_of_documentary_movies
FROM public.film AS f
LEFT JOIN public.film_category AS fc
       ON fc.film_id = f.film_id
LEFT JOIN public.category AS c
       ON c.category_id = fc.category_id
      AND UPPER(c.name) IN ('DRAMA', 'TRAVEL', 'DOCUMENTARY')
WHERE f.release_year IS NOT NULL
GROUP BY f.release_year
ORDER BY f.release_year DESC;

-- 1.4 (b) Subquery solution
-- Outer derived table: list of distinct years.
-- Three correlated scalar subqueries count each genre for that year
-- (INNER JOINs inside: only films that really have this category).
-- COUNT returns 0 when nothing matches, so no NULLs appear.
SELECT y.release_year,
       (SELECT COUNT(DISTINCT f.film_id)
        FROM public.film AS f
        INNER JOIN public.film_category AS fc ON fc.film_id = f.film_id
        INNER JOIN public.category AS c       ON c.category_id = fc.category_id
        WHERE f.release_year = y.release_year
          AND UPPER(c.name) = 'DRAMA')       AS number_of_drama_movies,
       (SELECT COUNT(DISTINCT f.film_id)
        FROM public.film AS f
        INNER JOIN public.film_category AS fc ON fc.film_id = f.film_id
        INNER JOIN public.category AS c       ON c.category_id = fc.category_id
        WHERE f.release_year = y.release_year
          AND UPPER(c.name) = 'TRAVEL')      AS number_of_travel_movies,
       (SELECT COUNT(DISTINCT f.film_id)
        FROM public.film AS f
        INNER JOIN public.film_category AS fc ON fc.film_id = f.film_id
        INNER JOIN public.category AS c       ON c.category_id = fc.category_id
        WHERE f.release_year = y.release_year
          AND UPPER(c.name) = 'DOCUMENTARY') AS number_of_documentary_movies
FROM (
        SELECT DISTINCT f.release_year
        FROM public.film AS f
        WHERE f.release_year IS NOT NULL
     ) AS y
ORDER BY y.release_year DESC;

-- 1.4 (c) CTE solution
-- CTE years: all years. CTE genre_counts: counts only for years that have
-- these genres (INNER JOINs). LEFT JOIN years -> genre_counts keeps years
-- without these genres; their counts are NULL, and COALESCE replaces NULL by 0.
WITH years AS (
    SELECT DISTINCT f.release_year
    FROM public.film AS f
    WHERE f.release_year IS NOT NULL
),
genre_counts AS (
    SELECT f.release_year,
           COUNT(DISTINCT CASE WHEN UPPER(c.name) = 'DRAMA'       THEN f.film_id END) AS drama_cnt,
           COUNT(DISTINCT CASE WHEN UPPER(c.name) = 'TRAVEL'      THEN f.film_id END) AS travel_cnt,
           COUNT(DISTINCT CASE WHEN UPPER(c.name) = 'DOCUMENTARY' THEN f.film_id END) AS documentary_cnt
    FROM public.film AS f
    INNER JOIN public.film_category AS fc
            ON fc.film_id = f.film_id
    INNER JOIN public.category AS c
            ON c.category_id = fc.category_id
    WHERE UPPER(c.name) IN ('DRAMA', 'TRAVEL', 'DOCUMENTARY')
    GROUP BY f.release_year
)
SELECT y.release_year,
       COALESCE(gc.drama_cnt, 0)       AS number_of_drama_movies,
       COALESCE(gc.travel_cnt, 0)      AS number_of_travel_movies,
       COALESCE(gc.documentary_cnt, 0) AS number_of_documentary_movies
FROM years AS y
LEFT JOIN genre_counts AS gc
       ON gc.release_year = y.release_year
ORDER BY y.release_year DESC;

/*
   Comparison 1.4
   - JOIN: one pass over the data, conditional aggregation; the NULL
     handling relies on placing the filter in ON (subtle for readers).
   - Subquery: very explicit (one subquery = one column) but the same join
     is repeated 3 times and executed for every year - the slowest and the
     longest; adding a 4th genre means copying a whole block.
   - CTE: clear separation "all years" + "counts", explicit NULL handling with
     COALESCE; one pass over the data for counting.
   Production choice: JOIN (a) for performance, or CTE (c) if the team values
     explicit NULL handling; I would choose CTE for readability.
*/


/* =============================================================================
   PART 2
   ============================================================================= */

/* -----------------------------------------------------------------------------
   Task 2.1
   The HR department aims to reward top-performing employees in 2017 with
   bonuses to recognize their contribution to stores revenue.
   Show which three employees generated the most revenue in 2017?

   Assumptions (given in the task + my interpretation):
   - Staff could work in several stores in a year; show the LAST store.
   - If staff processed the payment, he worked in the store of that payment.
     Store of a payment = payment -> rental -> inventory -> store_id.
   - Only payment_date is used: payments from 2017-01-01 to 2017-12-31.
   - "Last store" = store of the staff member's latest payment in 2017.
     If two payments have exactly the same latest timestamp, the one with
     the bigger payment_id is treated as the last (deterministic tie-break).
   - Revenue = SUM(payment.amount) processed by the staff member in 2017.
   - Top-3 = 3 rows (LIMIT 3), ties on 3rd place are cut.
----------------------------------------------------------------------------- */

-- 2.1 (a) JOIN solution (no subqueries at all)
-- lp      = candidate "last payment" of the staff member in 2017.
-- later   = LEFT JOIN that looks for any payment of the same staff that is
--           later than lp. "WHERE later.payment_id IS NULL" keeps lp only if
--           no later payment exists (anti-join), so exactly one lp per staff.
-- p       = all 2017 payments of the staff (INNER JOIN), summed as revenue.
--           Because lp is unique per staff, joining it does not duplicate p.
-- INNER JOIN rental/inventory/store: needed to find the store of lp.
SELECT st.first_name,
       st.last_name,
       lst_i.store_id                                       AS last_store_id,
       CONCAT_WS(' ', lst_a.address, NULLIF(lst_a.address2, '')) AS last_store_address,
       SUM(p.amount)                                        AS revenue_2017
FROM public.staff AS st
INNER JOIN public.payment AS p
        ON p.staff_id = st.staff_id
       AND p.payment_date >= DATE '2017-01-01'
       AND p.payment_date <  DATE '2018-01-01'
INNER JOIN public.payment AS lp
        ON lp.staff_id = st.staff_id
       AND lp.payment_date >= DATE '2017-01-01'
       AND lp.payment_date <  DATE '2018-01-01'
LEFT JOIN public.payment AS later
       ON later.staff_id = lp.staff_id
      AND later.payment_date >= DATE '2017-01-01'
      AND later.payment_date <  DATE '2018-01-01'
      AND (later.payment_date > lp.payment_date
           OR (later.payment_date = lp.payment_date AND later.payment_id > lp.payment_id))
INNER JOIN public.rental AS lst_r
        ON lst_r.rental_id = lp.rental_id
INNER JOIN public.inventory AS lst_i
        ON lst_i.inventory_id = lst_r.inventory_id
INNER JOIN public.store AS lst_s
        ON lst_s.store_id = lst_i.store_id
INNER JOIN public.address AS lst_a
        ON lst_a.address_id = lst_s.address_id
WHERE later.payment_id IS NULL
GROUP BY st.staff_id,
         st.first_name,
         st.last_name,
         lst_i.store_id,
         lst_a.address,
         lst_a.address2
ORDER BY revenue_2017 DESC
LIMIT 3;

-- 2.1 (b) Subquery solution
-- Derived table "rev": revenue per staff in 2017.
-- Correlated subqueries find the last store: the store of the payment whose
-- payment_id is the latest one (ORDER BY date DESC, id DESC LIMIT 1).
-- INNER JOIN staff: only staff that actually have 2017 payments.
SELECT st.first_name,
       st.last_name,
       (SELECT i.store_id
        FROM public.payment AS p2
        INNER JOIN public.rental AS r     ON r.rental_id = p2.rental_id
        INNER JOIN public.inventory AS i  ON i.inventory_id = r.inventory_id
        WHERE p2.staff_id = st.staff_id
          AND p2.payment_date >= DATE '2017-01-01'
          AND p2.payment_date <  DATE '2018-01-01'
        ORDER BY p2.payment_date DESC, p2.payment_id DESC
        LIMIT 1)                                            AS last_store_id,
       (SELECT CONCAT_WS(' ', a.address, NULLIF(a.address2, ''))
        FROM public.payment AS p2
        INNER JOIN public.rental AS r     ON r.rental_id = p2.rental_id
        INNER JOIN public.inventory AS i  ON i.inventory_id = r.inventory_id
        INNER JOIN public.store AS s      ON s.store_id = i.store_id
        INNER JOIN public.address AS a    ON a.address_id = s.address_id
        WHERE p2.staff_id = st.staff_id
          AND p2.payment_date >= DATE '2017-01-01'
          AND p2.payment_date <  DATE '2018-01-01'
        ORDER BY p2.payment_date DESC, p2.payment_id DESC
        LIMIT 1)                                            AS last_store_address,
       rev.revenue_2017
FROM (
        SELECT p.staff_id,
               SUM(p.amount) AS revenue_2017
        FROM public.payment AS p
        WHERE p.payment_date >= DATE '2017-01-01'
          AND p.payment_date <  DATE '2018-01-01'
        GROUP BY p.staff_id
     ) AS rev
INNER JOIN public.staff AS st
        ON st.staff_id = rev.staff_id
ORDER BY rev.revenue_2017 DESC
LIMIT 3;

-- 2.1 (c) CTE solution
-- payments_2017 : all 2017 payments with the store of each payment.
-- staff_revenue : revenue per staff.
-- last_payment  : id of the latest payment per staff (MAX date, then MAX id).
-- Final query   : INNER JOINs connect revenue, staff and the last store.
WITH payments_2017 AS (
    SELECT p.payment_id,
           p.staff_id,
           p.amount,
           p.payment_date,
           i.store_id
    FROM public.payment AS p
    INNER JOIN public.rental AS r
            ON r.rental_id = p.rental_id
    INNER JOIN public.inventory AS i
            ON i.inventory_id = r.inventory_id
    WHERE p.payment_date >= DATE '2017-01-01'
      AND p.payment_date <  DATE '2018-01-01'
),
staff_revenue AS (
    SELECT p17.staff_id,
           SUM(p17.amount)       AS revenue_2017,
           MAX(p17.payment_date) AS last_payment_date
    FROM payments_2017 AS p17
    GROUP BY p17.staff_id
),
last_payment AS (
    SELECT p17.staff_id,
           MAX(p17.payment_id) AS last_payment_id
    FROM payments_2017 AS p17
    INNER JOIN staff_revenue AS sr
            ON sr.staff_id = p17.staff_id
           AND sr.last_payment_date = p17.payment_date
    GROUP BY p17.staff_id
)
SELECT st.first_name,
       st.last_name,
       p17.store_id                                      AS last_store_id,
       CONCAT_WS(' ', a.address, NULLIF(a.address2, '')) AS last_store_address,
       sr.revenue_2017
FROM staff_revenue AS sr
INNER JOIN public.staff AS st
        ON st.staff_id = sr.staff_id
INNER JOIN last_payment AS lp
        ON lp.staff_id = sr.staff_id
INNER JOIN payments_2017 AS p17
        ON p17.payment_id = lp.last_payment_id
INNER JOIN public.store AS s
        ON s.store_id = p17.store_id
INNER JOIN public.address AS a
        ON a.address_id = s.address_id
ORDER BY sr.revenue_2017 DESC
LIMIT 3;

/*
   Comparison 2.1
   - JOIN (anti-join "no later payment"): solves the task without any
     subquery, but the self-join of payment with itself compares every
     payment of a staff member with every other one (~N^2 rows) - the most
     expensive and the hardest to read/explain.
   - Subquery: revenue in a derived table + correlated subqueries with
     ORDER BY ... LIMIT 1 for the last store. Easy to understand, but the
     "last payment" search is repeated per column (twice per staff).
   - CTE: each step (2017 payments -> revenue -> last payment -> result) is
     named and can be checked separately; the 2017 filter is written once.
   Production choice: CTE - correct, readable, each step is testable,
     data is read in a predictable way.
*/


/* -----------------------------------------------------------------------------
   Task 2.2
   The management team wants to identify the most popular movies and their
   target audience age groups to optimize marketing efforts.
   Show which 5 movies were rented more than others (number of rentals), and
   what's the expected age of the audience for these movies?
   To determine expected age please use 'Motion Picture Association film
   rating system'.

   Assumptions / interpretation:
   - Popularity = number of rows in public.rental for all copies of the film.
   - Expected age by MPA rating (public.film.rating):
        G     -> all ages
        PG    -> all ages, parental guidance suggested (some material may
                 not be suitable for children)
        PG-13 -> 13+ (parents strongly cautioned for children under 13)
        R     -> 17+ (under 17 only with a parent or adult guardian)
        NC-17 -> 18+ (no one 17 and under admitted)
   - Top-5 = 5 rows (LIMIT 5); ties are broken alphabetically by title.
----------------------------------------------------------------------------- */

-- 2.2 (a) JOIN solution
-- INNER JOIN film -> inventory -> rental: only films that were rented at least
-- once (never-rented films cannot be in the top anyway).
SELECT f.title,
       f.rating,
       CASE f.rating
           WHEN 'G'     THEN 'All ages'
           WHEN 'PG'    THEN 'All ages, parental guidance suggested'
           WHEN 'PG-13' THEN '13+ (parents strongly cautioned under 13)'
           WHEN 'R'     THEN '17+ (under 17 with parent or adult guardian)'
           WHEN 'NC-17' THEN '18+ (no one 17 and under admitted)'
           ELSE 'Unknown rating'
       END                      AS expected_audience_age,
       COUNT(r.rental_id)       AS number_of_rentals
FROM public.film AS f
INNER JOIN public.inventory AS i
        ON i.film_id = f.film_id
INNER JOIN public.rental AS r
        ON r.inventory_id = i.inventory_id
GROUP BY f.film_id,
         f.title,
         f.rating
ORDER BY number_of_rentals DESC,
         f.title
LIMIT 5;

-- 2.2 (b) Subquery solution
-- Derived table counts rentals per film_id (INNER JOIN rental-inventory),
-- outer query adds title and translates the rating into an age group.
SELECT f.title,
       f.rating,
       CASE f.rating
           WHEN 'G'     THEN 'All ages'
           WHEN 'PG'    THEN 'All ages, parental guidance suggested'
           WHEN 'PG-13' THEN '13+ (parents strongly cautioned under 13)'
           WHEN 'R'     THEN '17+ (under 17 with parent or adult guardian)'
           WHEN 'NC-17' THEN '18+ (no one 17 and under admitted)'
           ELSE 'Unknown rating'
       END                      AS expected_audience_age,
       fr.number_of_rentals
FROM (
        SELECT i.film_id,
               COUNT(r.rental_id) AS number_of_rentals
        FROM public.rental AS r
        INNER JOIN public.inventory AS i
                ON i.inventory_id = r.inventory_id
        GROUP BY i.film_id
     ) AS fr
INNER JOIN public.film AS f
        ON f.film_id = fr.film_id
ORDER BY fr.number_of_rentals DESC,
         f.title
LIMIT 5;

-- 2.2 (c) CTE solution
-- film_rentals: rentals per film; main query: names + age group.
WITH film_rentals AS (
    SELECT i.film_id,
           COUNT(r.rental_id) AS number_of_rentals
    FROM public.rental AS r
    INNER JOIN public.inventory AS i
            ON i.inventory_id = r.inventory_id
    GROUP BY i.film_id
)
SELECT f.title,
       f.rating,
       CASE f.rating
           WHEN 'G'     THEN 'All ages'
           WHEN 'PG'    THEN 'All ages, parental guidance suggested'
           WHEN 'PG-13' THEN '13+ (parents strongly cautioned under 13)'
           WHEN 'R'     THEN '17+ (under 17 with parent or adult guardian)'
           WHEN 'NC-17' THEN '18+ (no one 17 and under admitted)'
           ELSE 'Unknown rating'
       END                      AS expected_audience_age,
       fr.number_of_rentals
FROM film_rentals AS fr
INNER JOIN public.film AS f
        ON f.film_id = fr.film_id
ORDER BY fr.number_of_rentals DESC,
         f.title
LIMIT 5;

/*
   Comparison 2.2
   - JOIN: shortest, one GROUP BY; text columns are carried through the
     aggregation.
   - Subquery / CTE: aggregate on ids only, then join film for names -
     slightly less work for GROUP BY; CTE reads top-down, subquery inside-out.
   All three have the same plan in practice; LIMIT 5 cuts ties.
   Production choice: CTE - the "rentals per film" step is reusable and the
     age mapping stays in one clear final SELECT.
*/


/* =============================================================================
   PART 3
   Which actors/actresses didn't act for a longer period of time than the
   others?
   The stores' marketing team wants to analyze actors' inactivity periods to
   select those with notable career breaks for targeted promotional campaigns.
   ============================================================================= */

/* -----------------------------------------------------------------------------
   Task 3 V1: gap between the latest release_year and the current year
   per each actor.

   Assumptions / interpretation:
   - Current year = EXTRACT(YEAR FROM CURRENT_DATE) (not hardcoded).
   - gap = current year - the latest release_year of the actor's films.
   - The answer shows the actor(s) with the biggest gap; if several actors
     share the maximum, all of them are shown.
   - Films with release_year IS NULL are ignored (MAX ignores NULL).
----------------------------------------------------------------------------- */

-- 3 V1 (a) JOIN solution
-- INNER JOINs: only actors that have films. FETCH FIRST 1 ROWS WITH TIES
-- (standard SQL, not a window function) returns every actor that shares
-- the biggest gap.
SELECT a.first_name,
       a.last_name,
       MAX(f.release_year)                                       AS latest_release_year,
       EXTRACT(YEAR FROM CURRENT_DATE)::INT - MAX(f.release_year) AS years_without_films
FROM public.actor AS a
INNER JOIN public.film_actor AS fa
        ON fa.actor_id = a.actor_id
INNER JOIN public.film AS f
        ON f.film_id = fa.film_id
GROUP BY a.actor_id,
         a.first_name,
         a.last_name
ORDER BY years_without_films DESC
FETCH FIRST 1 ROWS WITH TIES;

-- 3 V1 (b) Subquery solution
-- Derived table: latest year per actor.
-- WHERE ... = (SELECT MIN(...)): the biggest gap = the smallest "latest year",
-- so actors whose latest year equals the overall minimum are returned.
SELECT a.first_name,
       a.last_name,
       ly.latest_release_year,
       EXTRACT(YEAR FROM CURRENT_DATE)::INT - ly.latest_release_year AS years_without_films
FROM (
        SELECT fa.actor_id,
               MAX(f.release_year) AS latest_release_year
        FROM public.film_actor AS fa
        INNER JOIN public.film AS f
                ON f.film_id = fa.film_id
        GROUP BY fa.actor_id
     ) AS ly
INNER JOIN public.actor AS a
        ON a.actor_id = ly.actor_id
WHERE ly.latest_release_year = (
        SELECT MIN(x.latest_release_year)
        FROM (
                SELECT MAX(f2.release_year) AS latest_release_year
                FROM public.film_actor AS fa2
                INNER JOIN public.film AS f2
                        ON f2.film_id = fa2.film_id
                GROUP BY fa2.actor_id
             ) AS x
      )
ORDER BY a.last_name,
         a.first_name;

-- 3 V1 (c) CTE solution
-- actor_gap: gap per actor (computed once), then the CTE is reused twice:
-- in the main query and to find the maximum gap.
WITH actor_gap AS (
    SELECT fa.actor_id,
           MAX(f.release_year)                                       AS latest_release_year,
           EXTRACT(YEAR FROM CURRENT_DATE)::INT - MAX(f.release_year) AS years_without_films
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f
            ON f.film_id = fa.film_id
    GROUP BY fa.actor_id
)
SELECT a.first_name,
       a.last_name,
       ag.latest_release_year,
       ag.years_without_films
FROM actor_gap AS ag
INNER JOIN public.actor AS a
        ON a.actor_id = ag.actor_id
WHERE ag.years_without_films = (SELECT MAX(ag2.years_without_films) FROM actor_gap AS ag2)
ORDER BY a.last_name,
         a.first_name;

/*
   Comparison 3 V1
   - JOIN: shortest; ties handled with FETCH FIRST ... WITH TIES
     (PostgreSQL 13+), which not every DBMS supports.
   - Subquery: portable, but the aggregation "latest year per actor" is
     written and executed twice.
   - CTE: the aggregation is written once and reused - readable, no copy-paste.
   Production choice: CTE.
*/


/* -----------------------------------------------------------------------------
   Task 3 V2: gaps between sequential films per each actor.

   Assumptions / interpretation:
   - For each actor, release years are put in order; a gap is the difference
     between two neighbouring (consecutive) DIFFERENT release years.
     Example: films in 2001, 2001, 2005, 2006 -> gaps 4 and 1, max gap = 4.
   - For each actor the biggest gap is taken; the answer shows the actor(s)
     with the biggest gap overall (all of them if there is a tie).
   - Actors with films in only one year have no gap and are not shown.
   - Window functions (LAG/LEAD) are not allowed, so "next film year" is
     found as MIN(release_year) among the actor's films that are later.
----------------------------------------------------------------------------- */

-- 3 V2 (a) JOIN solution
-- y1 (fa1+f1) = a film year of the actor.
-- y2 (fa2+f2) = a LATER film year of the same actor (INNER JOIN: the pair
--               exists only if a later film exists).
-- y3 (fa3+f3) = LEFT JOIN that searches a film of the same actor whose year
--               lies strictly between y1 and y2. fa3 and f3 are joined
--               together in brackets, so the "between" condition is checked
--               for the pair as a whole. "WHERE fa3.actor_id IS NULL" keeps
--               only pairs with nothing in between = consecutive years
--               (anti-join).
-- MAX(y2 - y1) per actor = the longest break; WITH TIES keeps all winners.
SELECT a.first_name,
       a.last_name,
       MAX(f2.release_year - f1.release_year) AS max_gap_years
FROM public.actor AS a
INNER JOIN public.film_actor AS fa1
        ON fa1.actor_id = a.actor_id
INNER JOIN public.film AS f1
        ON f1.film_id = fa1.film_id
INNER JOIN public.film_actor AS fa2
        ON fa2.actor_id = a.actor_id
INNER JOIN public.film AS f2
        ON f2.film_id = fa2.film_id
       AND f2.release_year > f1.release_year
LEFT JOIN (public.film_actor AS fa3
           INNER JOIN public.film AS f3
                   ON f3.film_id = fa3.film_id)
       ON fa3.actor_id = a.actor_id
      AND f3.release_year > f1.release_year
      AND f3.release_year < f2.release_year
WHERE fa3.actor_id IS NULL
GROUP BY a.actor_id,
         a.first_name,
         a.last_name
ORDER BY max_gap_years DESC
FETCH FIRST 1 ROWS WITH TIES;

-- 3 V2 (b) Subquery solution
-- Innermost derived table "y": distinct film years per actor.
-- Correlated subquery: for each (actor, year) the next year =
--   MIN(year) of the same actor that is greater than the current year.
-- Outer level: biggest gap per actor; WHERE = (SELECT MAX ...) keeps winners.
-- (The same gap calculation is repeated inside the WHERE subquery.)
SELECT a.first_name,
       a.last_name,
       g.max_gap_years
FROM (
        SELECT y.actor_id,
               MAX((SELECT MIN(f.release_year)
                    FROM public.film_actor AS fa
                    INNER JOIN public.film AS f
                            ON f.film_id = fa.film_id
                    WHERE fa.actor_id = y.actor_id
                      AND f.release_year > y.release_year) - y.release_year) AS max_gap_years
        FROM (
                SELECT DISTINCT fa.actor_id,
                       f.release_year
                FROM public.film_actor AS fa
                INNER JOIN public.film AS f
                        ON f.film_id = fa.film_id
                WHERE f.release_year IS NOT NULL
             ) AS y
        GROUP BY y.actor_id
     ) AS g
INNER JOIN public.actor AS a
        ON a.actor_id = g.actor_id
WHERE g.max_gap_years = (
        SELECT MAX((SELECT MIN(f.release_year)
                    FROM public.film_actor AS fa
                    INNER JOIN public.film AS f
                            ON f.film_id = fa.film_id
                    WHERE fa.actor_id = y.actor_id
                      AND f.release_year > y.release_year) - y.release_year)
        FROM (
                SELECT DISTINCT fa.actor_id,
                       f.release_year
                FROM public.film_actor AS fa
                INNER JOIN public.film AS f
                        ON f.film_id = fa.film_id
                WHERE f.release_year IS NOT NULL
             ) AS y
      )
ORDER BY a.last_name,
         a.first_name;

-- 3 V2 (c) CTE solution
-- actor_years : distinct film years per actor.
-- year_pairs  : each year + the next year of the same actor
--               (INNER JOIN with a later year + MIN = the nearest later year;
--               the last year of an actor has no pair and drops out).
-- actor_gaps  : the biggest gap per actor.
-- Final query : actors whose biggest gap equals the overall maximum.
WITH actor_years AS (
    SELECT DISTINCT fa.actor_id,
           f.release_year
    FROM public.film_actor AS fa
    INNER JOIN public.film AS f
            ON f.film_id = fa.film_id
    WHERE f.release_year IS NOT NULL
),
year_pairs AS (
    SELECT cur.actor_id,
           cur.release_year       AS film_year,
           MIN(nxt.release_year)  AS next_film_year
    FROM actor_years AS cur
    INNER JOIN actor_years AS nxt
            ON nxt.actor_id = cur.actor_id
           AND nxt.release_year > cur.release_year
    GROUP BY cur.actor_id,
             cur.release_year
),
actor_gaps AS (
    SELECT yp.actor_id,
           MAX(yp.next_film_year - yp.film_year) AS max_gap_years
    FROM year_pairs AS yp
    GROUP BY yp.actor_id
)
SELECT a.first_name,
       a.last_name,
       ag.max_gap_years
FROM actor_gaps AS ag
INNER JOIN public.actor AS a
        ON a.actor_id = ag.actor_id
WHERE ag.max_gap_years = (SELECT MAX(ag2.max_gap_years) FROM actor_gaps AS ag2)
ORDER BY a.last_name,
         a.first_name;

/*
   Comparison 3 V2
   - JOIN: no subqueries, but a triple self-join with an anti-join - the
     number of intermediate rows grows roughly as (films per actor)^3;
     hard to read and to explain; relies on WITH TIES (PostgreSQL 13+).
   - Subquery: correlated MIN(...) per (actor, year) is easy to reason about,
     but the whole calculation is duplicated for the WHERE filter and is
     read inside-out - the hardest to maintain.
   - CTE: step by step (years -> pairs -> gaps -> winners); every step can be
     run and checked alone; distinct years reduce the data before self-join.
   Production choice: CTE - clearest logic and reasonable performance.
   (In real production LAG() would be used, but window functions are
   forbidden in this task.)
*/
