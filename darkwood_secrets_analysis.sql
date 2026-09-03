/*
Project: Darkwood Secrets — monetization and in-game purchase analysis
DBMS: PostgreSQL
Author: Alexey Efimov

Goal:
- estimate the share of paying players;
- evaluate whether monetization differs by character race;
- analyze in-game purchases made with "Paradise Petals";
- compare purchase activity across character races.
*/

-- =========================================================
-- 1. EXPLORATORY DATA ANALYSIS
-- =========================================================

-- ---------------------------------------------------------
-- 1.1. Overall share of paying players
-- ---------------------------------------------------------
SELECT
    COUNT(u.id) AS total_players,
    SUM(u.payer) AS paying_players,
    ROUND(AVG(u.payer::numeric), 4) AS paying_share
FROM fantasy.users AS u;


-- ---------------------------------------------------------
-- 1.2. Share of paying players by character race
-- ---------------------------------------------------------
SELECT
    r.race,
    COUNT(u.id) AS total_players,
    SUM(u.payer) AS paying_players,
    ROUND(AVG(u.payer::numeric), 4) AS paying_share
FROM fantasy.users AS u
LEFT JOIN fantasy.race AS r
    ON u.race_id = r.race_id
GROUP BY r.race
ORDER BY paying_share DESC, total_players DESC;


-- =========================================================
-- 2. IN-GAME PURCHASE ANALYSIS
-- =========================================================

-- ---------------------------------------------------------
-- 2.1. Descriptive statistics for purchase amount
-- ---------------------------------------------------------
SELECT
    COUNT(e.transaction_id) AS total_purchases,
    ROUND(SUM(e.amount::numeric), 2) AS total_amount,
    ROUND(MIN(e.amount::numeric), 2) AS min_amount,
    ROUND(MAX(e.amount::numeric), 2) AS max_amount,
    ROUND(AVG(e.amount::numeric), 2) AS avg_amount,
    ROUND(
        (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY e.amount))::numeric,
        2
    ) AS median_amount,
    ROUND(STDDEV(e.amount::numeric), 2) AS stddev_amount
FROM fantasy.events AS e;


-- ---------------------------------------------------------
-- 2.2. Zero-value purchases
-- ---------------------------------------------------------
SELECT
    COUNT(*) FILTER (WHERE e.amount = 0) AS zero_amount_purchases,
    COUNT(e.transaction_id) AS total_purchases,
    ROUND(
        (COUNT(*) FILTER (WHERE e.amount = 0))::numeric
        / NULLIF(COUNT(e.transaction_id), 0),
        4
    ) AS zero_amount_share
FROM fantasy.events AS e;


-- ---------------------------------------------------------
-- 2.3. Descriptive statistics excluding zero-value purchases
-- Supplemental check used to evaluate the effect of zeroes.
-- ---------------------------------------------------------
SELECT
    COUNT(e.transaction_id) AS total_purchases_non_zero,
    ROUND(SUM(e.amount::numeric), 2) AS total_amount_non_zero,
    ROUND(MIN(e.amount::numeric), 2) AS min_amount_non_zero,
    ROUND(MAX(e.amount::numeric), 2) AS max_amount_non_zero,
    ROUND(AVG(e.amount::numeric), 2) AS avg_amount_non_zero,
    ROUND(
        (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY e.amount))::numeric,
        2
    ) AS median_amount_non_zero,
    ROUND(STDDEV(e.amount::numeric), 2) AS stddev_amount_non_zero
FROM fantasy.events AS e
WHERE e.amount > 0;


-- ---------------------------------------------------------
-- 2.4. Popularity of epic items
-- Zero-value purchases are excluded.
-- ---------------------------------------------------------
WITH valid_purchases AS (
    SELECT
        e.transaction_id,
        e.id,
        e.item_code,
        e.amount
    FROM fantasy.events AS e
    WHERE e.amount > 0
),
total_stats AS (
    SELECT
        COUNT(*) AS total_sales,
        COUNT(DISTINCT id) AS total_buyers
    FROM valid_purchases
)
SELECT
    vp.item_code,
    i.game_items,
    COUNT(*) AS sales_count,
    ROUND(
        COUNT(*)::numeric / NULLIF(ts.total_sales, 0),
        4
    ) AS sales_share,
    COUNT(DISTINCT vp.id) AS buyers_count,
    ROUND(
        COUNT(DISTINCT vp.id)::numeric / NULLIF(ts.total_buyers, 0),
        4
    ) AS buyers_share
FROM valid_purchases AS vp
LEFT JOIN fantasy.items AS i
    ON vp.item_code = i.item_code
CROSS JOIN total_stats AS ts
GROUP BY
    vp.item_code,
    i.game_items,
    ts.total_sales,
    ts.total_buyers
ORDER BY sales_count DESC, buyers_count DESC;


-- =========================================================
-- 3. AD HOC ANALYSIS: PURCHASE ACTIVITY BY RACE
-- =========================================================

WITH total_players AS (
    SELECT
        r.race_id,
        r.race,
        COUNT(u.id) AS total_players
    FROM fantasy.users AS u
    LEFT JOIN fantasy.race AS r
        ON u.race_id = r.race_id
    GROUP BY r.race_id, r.race
),
valid_purchases AS (
    SELECT
        e.transaction_id,
        e.id,
        e.amount
    FROM fantasy.events AS e
    WHERE e.amount > 0
),
player_activity AS (
    SELECT
        u.id AS player_id,
        u.race_id,
        u.payer,
        COUNT(vp.transaction_id) AS purchase_count,
        COALESCE(SUM(vp.amount), 0) AS total_spent
    FROM fantasy.users AS u
    LEFT JOIN valid_purchases AS vp
        ON u.id = vp.id
    GROUP BY
        u.id,
        u.race_id,
        u.payer
),
race_metrics AS (
    SELECT
        pa.race_id,
        COUNT(*) FILTER (
            WHERE pa.purchase_count > 0
        ) AS buyers_count,
        ROUND(
            (COUNT(*) FILTER (WHERE pa.purchase_count > 0))::numeric
            / NULLIF(COUNT(*), 0),
            4
        ) AS buyers_share,
        ROUND(
            (COUNT(*) FILTER (
                WHERE pa.purchase_count > 0
                  AND pa.payer = 1
            ))::numeric
            / NULLIF(
                COUNT(*) FILTER (WHERE pa.purchase_count > 0),
                0
            ),
            4
        ) AS paying_share_among_buyers,
        ROUND(
            AVG(pa.purchase_count) FILTER (
                WHERE pa.purchase_count > 0
            ),
            2
        ) AS avg_purchases_per_buyer,
        ROUND(
            (
                SUM(pa.total_spent) FILTER (
                    WHERE pa.purchase_count > 0
                )
            )::numeric
            / NULLIF(
                SUM(pa.purchase_count) FILTER (
                    WHERE pa.purchase_count > 0
                ),
                0
            ),
            2
        ) AS avg_purchase_amount,
        ROUND(
            AVG(pa.total_spent::numeric) FILTER (
                WHERE pa.purchase_count > 0
            ),
            2
        ) AS avg_total_spent_per_buyer
    FROM player_activity AS pa
    GROUP BY pa.race_id
)
SELECT
    tp.race,
    tp.total_players,
    COALESCE(rm.buyers_count, 0) AS buyers_count,
    COALESCE(rm.buyers_share, 0) AS buyers_share,
    COALESCE(rm.paying_share_among_buyers, 0) AS paying_share_among_buyers,
    COALESCE(rm.avg_purchases_per_buyer, 0) AS avg_purchases_per_buyer,
    COALESCE(rm.avg_purchase_amount, 0) AS avg_purchase_amount,
    COALESCE(rm.avg_total_spent_per_buyer, 0) AS avg_total_spent_per_buyer
FROM total_players AS tp
LEFT JOIN race_metrics AS rm
    ON tp.race_id = rm.race_id
ORDER BY buyers_share DESC, paying_share_among_buyers DESC;
